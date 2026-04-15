// Intended for the processor named SLS_Data_CPU.
// Keep this core separate from the main guidance CPU so flight logging stays isolated.

WAIT UNTIL SHIP:UNPACKED.

RUNPATH("0:/NASA/Space_Launch_System_B1/mission_configuration.ks").
RUNPATH("0:/NASA/MCC_Interface/mcc_bridge.ks").

LOCAL missionConfig TO GetMissionConfiguration().
LOCAL missionSettings TO missionConfig["mission"].
LOCAL launchSettings TO missionConfig["launch"].

LOCAL flightLogIntervalSeconds TO 0.25.
LOCAL standbyIntervalSeconds TO 1.
LOCAL flightStarted TO FALSE.
LOCAL flightSampleIndex TO 0.
LOCAL flightStartSeconds TO 0.
LOCAL launchReferenceLatitude TO 0.
LOCAL launchReferenceLongitude TO 0.
LOCAL flightLogLines TO LIST().
LOCAL flightLogHeader TO "sample_index,mission_elapsed_seconds,altitude_m,downrange_m,vertical_speed_mps,surface_speed_mps,apoapsis_m,periapsis_m,latitude_deg,longitude_deg".

UNTIL FALSE {
    IF NOT IsFlightLoggingActive() {
        IF flightStarted {
            SET flightStarted TO FALSE.
            SET flightSampleIndex TO 0.
            SET flightLogLines TO LIST().
        }.

        WAIT standbyIntervalSeconds.
        CONTINUE.
    }.

    IF NOT flightStarted {
        SET flightStarted TO TRUE.
        SET flightSampleIndex TO 0.
        SET flightStartSeconds TO TIME:SECONDS.
        SET launchReferenceLatitude TO SHIP:GEOPOSITION:LAT.
        SET launchReferenceLongitude TO SHIP:GEOPOSITION:LNG.
        SET flightLogLines TO LIST().
        flightLogLines:ADD(flightLogHeader).
    }.

    LOCAL missionElapsedSeconds TO TIME:SECONDS - flightStartSeconds.
    LOCAL downrangeMeters TO ComputeDownrangeDistanceMeters(launchReferenceLatitude, launchReferenceLongitude).
    LOCAL statusRecord TO BuildFlightStatusRecord(
        missionSettings,
        launchSettings,
        TRUE,
        "logging",
        missionElapsedSeconds,
        downrangeMeters,
        flightSampleIndex,
        launchReferenceLatitude,
        launchReferenceLongitude,
        SHIP:GEOPOSITION:LAT,
        SHIP:GEOPOSITION:LNG,
        SHIP:ALTITUDE,
        SHIP:VERTICALSPEED,
        SHIP:GROUNDSPEED,
        SHIP:APOAPSIS,
        SHIP:PERIAPSIS
    ).

    WriteMccVehicleFlightStatus(statusRecord).

    flightLogLines:ADD(
        BuildFlightLogRow(
            flightSampleIndex,
            missionElapsedSeconds,
            SHIP:ALTITUDE,
            downrangeMeters,
            SHIP:VERTICALSPEED,
            SHIP:GROUNDSPEED,
            SHIP:APOAPSIS,
            SHIP:PERIAPSIS,
            SHIP:GEOPOSITION:LAT,
            SHIP:GEOPOSITION:LNG
        )
    ).

    WriteMccVehicleFlightLog(flightLogLines).

    SET flightSampleIndex TO flightSampleIndex + 1.
    WAIT flightLogIntervalSeconds.
}.

FUNCTION IsFlightLoggingActive {
    RETURN SHIP:ALTITUDE > 0 OR SHIP:GROUNDSPEED > 0.5 OR ABS(SHIP:VERTICALSPEED) > 0.5.
}.

FUNCTION BuildFlightStatusRecord {
    PARAMETER missionSettings, launchSettings, loggingActive, statusText, missionElapsedSeconds, downrangeMeters, sampleIndex, launchLatitude, launchLongitude, currentLatitude, currentLongitude, altitudeMeters, verticalSpeedMetersPerSecond, surfaceSpeedMetersPerSecond, apoapsisMeters, periapsisMeters.

    LOCAL modeText TO "STANDBY".
    IF loggingActive {
        SET modeText TO "FLIGHT_LOGGING".
    }.

    RETURN LEXICON(
        "source", "vehicle_flight",
        "vehicle_id", launchSettings["vehicle_id"],
        "mission_name", missionSettings["mission_name"],
        "mode", modeText,
        "status", statusText,
        "ship_name", SHIP:NAME,
        "altitude", ROUND(altitudeMeters, 2),
        "downrange_distance_m", ROUND(downrangeMeters, 2),
        "vertical_speed", ROUND(verticalSpeedMetersPerSecond, 2),
        "surface_speed", ROUND(surfaceSpeedMetersPerSecond, 2),
        "apoapsis", ROUND(apoapsisMeters, 2),
        "periapsis", ROUND(periapsisMeters, 2),
        "mission_elapsed_seconds", ROUND(missionElapsedSeconds, 1),
        "formatted_event_time", FormatMissionElapsedTime(missionElapsedSeconds),
        "launch_reference_latitude", ROUND(launchLatitude, 4),
        "launch_reference_longitude", ROUND(launchLongitude, 4),
        "current_latitude", ROUND(currentLatitude, 4),
        "current_longitude", ROUND(currentLongitude, 4),
        "logging_active", loggingActive,
        "sample_index", sampleIndex,
        "updated_at", TIME:SECONDS
    ).
}.

FUNCTION BuildFlightLogRow {
    PARAMETER sampleIndex, missionElapsedSeconds, altitudeMeters, downrangeMeters, verticalSpeedMetersPerSecond, surfaceSpeedMetersPerSecond, apoapsisMeters, periapsisMeters, latitudeDegrees, longitudeDegrees.

    RETURN sampleIndex + "," +
        ROUND(missionElapsedSeconds, 1) + "," +
        ROUND(altitudeMeters, 2) + "," +
        ROUND(downrangeMeters, 2) + "," +
        ROUND(verticalSpeedMetersPerSecond, 2) + "," +
        ROUND(surfaceSpeedMetersPerSecond, 2) + "," +
        ROUND(apoapsisMeters, 2) + "," +
        ROUND(periapsisMeters, 2) + "," +
        ROUND(latitudeDegrees, 4) + "," +
        ROUND(longitudeDegrees, 4).
}.

FUNCTION ComputeDownrangeDistanceMeters {
    PARAMETER launchLatitude, launchLongitude.

    LOCAL currentLatitude TO SHIP:GEOPOSITION:LAT.
    LOCAL currentLongitude TO SHIP:GEOPOSITION:LNG.
    LOCAL cosineAngle TO SIN(launchLatitude) * SIN(currentLatitude) + COS(launchLatitude) * COS(currentLatitude) * COS(currentLongitude - launchLongitude).
    LOCAL clampedCosine TO ClampValue(cosineAngle, -1, 1).
    LOCAL centralAngleDegrees TO ARCCOS(clampedCosine).

    RETURN SHIP:BODY:RADIUS * (centralAngleDegrees * 3.141592653589793 / 180).
}.

FUNCTION FormatMissionElapsedTime {
    PARAMETER elapsedSeconds.

    RETURN "T+" + ROUND(MAX(0, elapsedSeconds), 1).
}.

FUNCTION ClampValue {
    PARAMETER value, minimumValue, maximumValue.

    IF value < minimumValue {
        RETURN minimumValue.
    }.

    IF value > maximumValue {
        RETURN maximumValue.
    }.

    RETURN value.
}.
