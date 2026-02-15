using Toybox.Sensor;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Lang;
using Toybox.Math;

//! Manages sensor data collection for Flow Score calculation
class SensorManager {

    private var _flowCalculator as FlowScoreCalculator?;
    private var _hrvAnalyzer as HrvAnalyzer;
    private var _sensorsEnabled as Boolean = false;

    // Current sensor values
    private var _heartRate as Number = 0;
    private var _oxygenSaturation as Number = 0;
    private var _accelMagnitude as Number = 0;
    private var _stress as Number = 0;

    // HR history for stability calculation
    private var _hrHistory as Array<Number>;
    private const HR_HISTORY_SIZE = 30;  // 30 seconds of HR data

    //! Constructor
    function initialize(flowCalculator as FlowScoreCalculator?) {
        _flowCalculator = flowCalculator;
        _hrvAnalyzer = new HrvAnalyzer();
        _hrHistory = [] as Array<Number>;
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
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_PULSE_OXIMETRY] as Array<SensorType>);
            Sensor.enableSensorEvents(method(:onSensorData));

            // Register for heart beat intervals (HRV data)
            if (Sensor has :registerSensorDataListener) {
                Sensor.registerSensorDataListener(method(:onSensorDataListener), options);
            }

            _sensorsEnabled = true;
            _hrvAnalyzer.reset();
            _hrHistory = [] as Array<Number>;

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
        // Heart rate
        if (sensorInfo has :heartRate && sensorInfo.heartRate != null) {
            _heartRate = sensorInfo.heartRate;
            updateHrHistory(_heartRate);
        }

        // Oxygen saturation (SpO2)
        if (sensorInfo has :oxygenSaturation && sensorInfo.oxygenSaturation != null) {
            _oxygenSaturation = sensorInfo.oxygenSaturation;
        }

        // Accelerometer - calculate magnitude
        if (sensorInfo has :accel && sensorInfo.accel != null) {
            var accel = sensorInfo.accel;
            if (accel.size() >= 3) {
                // Calculate magnitude: sqrt(x^2 + y^2 + z^2)
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
        // Process heart beat intervals for HRV
        if (sensorData has :heartBeatIntervals && sensorData.heartBeatIntervals != null) {
            var intervals = sensorData.heartBeatIntervals;
            if (intervals has :data && intervals.data != null) {
                for (var i = 0; i < intervals.data.size(); i++) {
                    _hrvAnalyzer.addInterval(intervals.data[i]);
                }
            }
        }
    }

    //! Update heart rate history for stability calculation
    private function updateHrHistory(hr as Number) as Void {
        _hrHistory.add(hr);
        if (_hrHistory.size() > HR_HISTORY_SIZE) {
            _hrHistory = _hrHistory.slice(1, null) as Array<Number>;
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
                        _stress = sample.data;
                    }
                }
            }
        } catch (ex) {
            // Stress history may not be available
        }
    }

    //! Calculate HR standard deviation for stability
    function getHrStdDev() as Float {
        if (_hrHistory.size() < 2) {
            return 0.0;
        }

        // Calculate mean
        var sum = 0.0;
        for (var i = 0; i < _hrHistory.size(); i++) {
            sum += _hrHistory[i];
        }
        var mean = sum / _hrHistory.size();

        // Calculate variance
        var variance = 0.0;
        for (var i = 0; i < _hrHistory.size(); i++) {
            var diff = _hrHistory[i] - mean;
            variance += diff * diff;
        }
        variance = variance / _hrHistory.size();

        return Math.sqrt(variance).toFloat();
    }

    //! Update flow calculator with current sensor data
    private function updateFlowCalculator() as Void {
        if (_flowCalculator == null) {
            return;
        }

        _flowCalculator.updateSensorData(
            _hrvAnalyzer.getRmssd(),
            _heartRate,
            getHrStdDev(),
            _accelMagnitude,
            _stress,
            _oxygenSaturation
        );
    }

    //! Get current heart rate
    function getHeartRate() as Number {
        return _heartRate;
    }

    //! Get current SpO2
    function getOxygenSaturation() as Number {
        return _oxygenSaturation;
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
