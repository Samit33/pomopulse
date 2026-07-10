import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

//! Manages sensor data collection for focus quality calculation
class SensorManager {

    private var _flowCalculator as FlowScoreCalculator?;
    private var _hrvAnalyzer    as HrvAnalyzer;
    private var _sensorsEnabled as Boolean = false;

    // While paused, HR keeps displaying but the flow calculator is not fed,
    // so paused time can't pollute zone/trend/streak stats
    private var _paused as Boolean = false;

    // Current sensor values
    private var _heartRate      as Number = 0;
    private var _accelMagnitude as Number = 0;

    //! Constructor
    function initialize(flowCalculator as FlowScoreCalculator?) {
        _flowCalculator = flowCalculator;
        _hrvAnalyzer    = new HrvAnalyzer();
    }

    //! Start sensor data collection
    function startSensors() as Void {
        if (_sensorsEnabled) {
            return;
        }

        var options = {
            :period => 1,
            :accelerometer => {
                :enabled => true,
                :sampleRate => 1
            },
            :heartBeatIntervals => {
                :enabled => true
            }
        };

        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<SensorType>);
            Sensor.enableSensorEvents(method(:onSensorData));

            if (Sensor has :registerSensorDataListener) {
                Sensor.registerSensorDataListener(method(:onSensorDataListener), options);
            }

            _sensorsEnabled = true;
            _paused = false;
            _hrvAnalyzer.reset();

        } catch (ex) {
            System.println("Error enabling sensors: " + ex.getErrorMessage());
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

    //! Sensor event callback (1Hz)
    function onSensorData(sensorInfo as Sensor.Info) as Void {
        if (sensorInfo has :heartRate && sensorInfo.heartRate != null) {
            _heartRate = sensorInfo.heartRate as Number;
        }

        if (sensorInfo has :accel && sensorInfo.accel != null) {
            var accel = sensorInfo.accel as Array<Number>;
            if (accel.size() >= 3) {
                var x = accel[0];
                var y = accel[1];
                var z = accel[2];
                _accelMagnitude = Math.sqrt(x * x + y * y + z * z).toNumber();
            }
        }

        if (!_paused) {
            updateFlowCalculator();
        }
    }

    //! Pause/resume feeding the flow calculator (sensors stay on for HR display)
    function setPaused(paused as Boolean) as Void {
        _paused = paused;
    }

    //! Sensor data listener callback for HRV data
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
    }

    //! Update flow calculator with current sensor data.
    //! HRV is only considered valid once enough clean beat intervals have
    //! accumulated — otherwise dropouts would be scored as low HRV.
    private function updateFlowCalculator() as Void {
        if (_flowCalculator == null) {
            return;
        }
        var hrvValid = _hrvAnalyzer.getIntervalCount() >= 10;
        _flowCalculator.updateSensorData(
            _hrvAnalyzer.getRmssd(),
            _accelMagnitude,
            hrvValid
        );
    }

    function getHeartRate() as Number {
        return _heartRate;
    }

    function getAccelMagnitude() as Number {
        return _accelMagnitude;
    }

    function getRmssd() as Float {
        return _hrvAnalyzer.getRmssd();
    }

    function areSensorsEnabled() as Boolean {
        return _sensorsEnabled;
    }
}
