import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.System;

//! Manages sensor data collection for focus quality calculation
class SensorManager {

    private var _flowCalculator as FlowScoreCalculator?;
    private var _hrvAnalyzer    as HrvAnalyzer;
    private var _sensorsEnabled as Boolean = false;

    // Current sensor values
    private var _heartRate     as Number = 0;
    private var _accelMagnitude as Number = 0;
    private var _stress        as Number = 0;

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

        // Enable sensor events
        var options = {
            :period => 1,  // 1 second sample rate
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

            // Register for heart beat intervals (HRV data)
            if (Sensor has :registerSensorDataListener) {
                Sensor.registerSensorDataListener(method(:onSensorDataListener), options);
            }

            _sensorsEnabled = true;
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
        // Heart rate (for display only)
        if (sensorInfo has :heartRate && sensorInfo.heartRate != null) {
            _heartRate = sensorInfo.heartRate as Number;
        }

        // Accelerometer — calculate magnitude
        if (sensorInfo has :accel && sensorInfo.accel != null) {
            var accel = sensorInfo.accel as Array<Number>;
            if (accel.size() >= 3) {
                var x = accel[0];
                var y = accel[1];
                var z = accel[2];
                _accelMagnitude = Math.sqrt(x * x + y * y + z * z).toNumber();
            }
        }

        // Query stress from sensor history
        updateStress();

        // Update flow calculator with new sensor data
        updateFlowCalculator();
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

    //! Query stress level from sensor history
    private function updateStress() as Void {
        try {
            if (SensorHistory has :getStressHistory) {
                var stressIter = SensorHistory.getStressHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });

                if (stressIter != null) {
                    var sample = stressIter.next();
                    if (sample != null && sample.data != null) {
                        _stress = (sample.data as Number);
                    }
                }
            }
        } catch (ex) {
            // Stress history may not be available on all firmware versions
        }
    }

    //! Update flow calculator with current sensor data
    private function updateFlowCalculator() as Void {
        if (_flowCalculator == null) {
            return;
        }

        _flowCalculator.updateSensorData(
            _hrvAnalyzer.getRmssd(),
            _accelMagnitude,
            _stress
        );
    }

    //! Get current heart rate (bpm) — used for quiet display in timer view
    function getHeartRate() as Number {
        return _heartRate;
    }

    //! Get current accelerometer magnitude
    function getAccelMagnitude() as Number {
        return _accelMagnitude;
    }

    //! Get current stress level
    function getStress() as Number {
        return _stress;
    }

    //! Get current RMSSD
    function getRmssd() as Float {
        return _hrvAnalyzer.getRmssd();
    }

    //! Check if sensors are enabled
    function areSensorsEnabled() as Boolean {
        return _sensorsEnabled;
    }
}
