import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

//! Collects the signals the deep-work engine needs: wrist motion
//! (accelerometer at 25 Hz), steps, heart rate and beat intervals.
class SensorManager {

    private var _engine      as DeepWorkEngine?;
    private var _hrvAnalyzer as HrvAnalyzer;
    private var _sensorsEnabled as Boolean = false;

    // While paused, HR keeps updating but the engine is not fed,
    // so paused time can't pollute depth/zone/trend stats
    private var _paused as Boolean = false;
    private var _pauseStartMs as Number = 0;

    // High-rate accelerometer via the sensor data listener
    private const ACCEL_SAMPLE_RATE = 25;
    private var _hasHighRateAccel as Boolean = false;

    // Current sensor values
    private var _heartRate as Number = 0;
    private var _motion    as Number = 0;  // Per-second motion intensity (mg)

    // Previous 1 Hz accel vector (fallback when no high-rate data)
    private var _lastX as Number = 0;
    private var _lastY as Number = 0;
    private var _lastZ as Number = 0;
    private var _hasLastAccel as Boolean = false;

    function initialize(engine as DeepWorkEngine?) {
        _engine      = engine;
        _hrvAnalyzer = new HrvAnalyzer();
    }

    //! Start sensor data collection
    function startSensors() as Void {
        if (_sensorsEnabled) {
            return;
        }

        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<SensorType>);
            Sensor.enableSensorEvents(method(:onSensorData));
            _sensorsEnabled = true;
        } catch (ex) {
            System.println("Error enabling sensors: " + ex.getErrorMessage());
            return;
        }

        registerListener();

        _paused = false;
        _motion = 0;
        _hasLastAccel = false;
        _hrvAnalyzer.reset();
    }

    //! Register for beat intervals + 25 Hz accelerometer. Falls back to
    //! beat intervals only if the device rejects the accelerometer rate.
    private function registerListener() as Void {
        _hasHighRateAccel = false;
        if (!(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
            Sensor.registerSensorDataListener(method(:onSensorDataListener), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => ACCEL_SAMPLE_RATE
                },
                :heartBeatIntervals => {
                    :enabled => true
                }
            });
            _hasHighRateAccel = true;
        } catch (ex) {
            try {
                Sensor.registerSensorDataListener(method(:onSensorDataListener), {
                    :period => 1,
                    :heartBeatIntervals => {
                        :enabled => true
                    }
                });
            } catch (ex2) {
                System.println("Error registering listener: " + ex2.getErrorMessage());
            }
        }
    }

    //! Stop sensor data collection
    function stopSensors() as Void {
        if (!_sensorsEnabled) {
            return;
        }

        try {
            Sensor.enableSensorEvents(null);

            if (Sensor has :unregisterSensorDataListener) {
                Sensor.unregisterSensorDataListener();
            }

            _sensorsEnabled = false;
        } catch (ex) {
            System.println("Error disabling sensors: " + ex.getErrorMessage());
        }
    }

    //! Sensor event callback (1 Hz) — drives the engine's per-second update
    function onSensorData(sensorInfo as Sensor.Info) as Void {
        if (sensorInfo has :heartRate && sensorInfo.heartRate != null) {
            _heartRate = sensorInfo.heartRate as Number;
        }

        // Without high-rate data, estimate motion from how far the 1 Hz
        // gravity vector moved since the last second (wrist re-orientation)
        if (!_hasHighRateAccel && sensorInfo has :accel && sensorInfo.accel != null) {
            var accel = sensorInfo.accel as Array<Number>;
            if (accel.size() >= 3) {
                if (_hasLastAccel) {
                    var dx = accel[0] - _lastX;
                    var dy = accel[1] - _lastY;
                    var dz = accel[2] - _lastZ;
                    _motion = Math.sqrt(dx * dx + dy * dy + dz * dz).toNumber();
                }
                _lastX = accel[0];
                _lastY = accel[1];
                _lastZ = accel[2];
                _hasLastAccel = true;
            }
        }

        if (!_paused) {
            updateEngine();
        }
    }

    //! Pause/resume feeding the engine (sensors stay on for HR display)
    function setPaused(paused as Boolean) as Void {
        if (paused && !_paused) {
            _pauseStartMs = System.getTimer();
        } else if (!paused && _paused) {
            var engine = _engine;
            if (engine != null) {
                engine.onResume(System.getTimer() - _pauseStartMs);
            }
        }
        _paused = paused;
    }

    //! Sensor data listener callback: beat intervals + accelerometer batch
    function onSensorDataListener(sensorData as Sensor.SensorData) as Void {
        if (sensorData has :heartBeatIntervals && sensorData.heartBeatIntervals != null) {
            var intervals = sensorData.heartBeatIntervals;
            if (intervals has :data && intervals.data != null) {
                var idata = intervals.data as Array<Number>;
                for (var i = 0; i < idata.size(); i++) {
                    _hrvAnalyzer.addInterval(idata[i]);
                }
            }
        }

        if (sensorData has :accelerometerData && sensorData.accelerometerData != null) {
            var ad = sensorData.accelerometerData as Sensor.AccelerometerData;
            if (ad.x != null && ad.y != null && ad.z != null) {
                _motion = motionIntensity(ad.x as Array<Number>,
                                          ad.y as Array<Number>,
                                          ad.z as Array<Number>);
            }
        }
    }

    //! Motion intensity for one second of samples (mg):
    //! vibration (std-dev around the mean) + re-orientation (how far the
    //! mean gravity vector moved since last second). Typing produces small
    //! values; reaching, lifting a phone or walking produce large ones.
    private function motionIntensity(xs as Array<Number>, ys as Array<Number>,
                                     zs as Array<Number>) as Number {
        var n = xs.size();
        if (ys.size() < n) { n = ys.size(); }
        if (zs.size() < n) { n = zs.size(); }
        if (n == 0) {
            return _motion;
        }

        var sx = 0; var sy = 0; var sz = 0;
        for (var i = 0; i < n; i++) {
            sx += xs[i];
            sy += ys[i];
            sz += zs[i];
        }
        var mx = sx / n;
        var my = sy / n;
        var mz = sz / n;

        // Float accumulator: a vigorous shake can overflow a 32-bit sum
        var variance = 0.0;
        for (var i = 0; i < n; i++) {
            var dx = xs[i] - mx;
            var dy = ys[i] - my;
            var dz = zs[i] - mz;
            variance += ((dx * dx) + (dy * dy) + (dz * dz)).toFloat();
        }
        var vibration = Math.sqrt(variance / n).toNumber();

        var reorientation = 0;
        if (_hasLastAccel) {
            var ox = mx - _lastX;
            var oy = my - _lastY;
            var oz = mz - _lastZ;
            reorientation = Math.sqrt(ox * ox + oy * oy + oz * oz).toNumber();
        }
        _lastX = mx;
        _lastY = my;
        _lastZ = mz;
        _hasLastAccel = true;

        return vibration + (reorientation / 2);
    }

    //! Cumulative steps today, or -1 when unavailable
    private function currentSteps() as Number {
        var info = ActivityMonitor.getInfo();
        if (info has :steps && info.steps != null) {
            return info.steps as Number;
        }
        return -1;
    }

    //! HRV counts as valid only while clean beat intervals are arriving —
    //! otherwise dropouts would be scored as a real physiological change.
    private function updateEngine() as Void {
        var engine = _engine;
        if (engine == null) {
            return;
        }
        engine.update(
            _hrvAnalyzer.getRmssd(),
            _hrvAnalyzer.isFresh(),
            _heartRate,
            _motion,
            currentSteps()
        );
    }

    function getHeartRate() as Number {
        return _heartRate;
    }

    function getRmssd() as Float {
        return _hrvAnalyzer.getRmssd();
    }

    function areSensorsEnabled() as Boolean {
        return _sensorsEnabled;
    }
}
