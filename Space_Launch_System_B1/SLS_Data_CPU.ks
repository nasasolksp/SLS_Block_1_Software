// Intended for the processor named SLS_Data_CPU.
// Keep this core separate from the main guidance CPU so flight logging stays isolated.

WAIT UNTIL SHIP:UNPACKED.

RUNPATH("0:/NASA/Space_Launch_System_B1/mission_configuration.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_parts_manifest.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_part_resolver.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_launch_forecast.ks").
RUNPATH("0:/NASA/MCC_Interface/mcc_bridge.ks").

LOCAL bridgePaths TO GetMccBridgePaths().
LOCAL missionConfig TO GetMissionConfiguration().
LOCAL missionSettings TO missionConfig["mission"].
LOCAL launchSettings TO missionConfig["launch"].
LOCAL ascentSettings TO missionConfig["ascent"].
LOCAL orbitSettings TO missionConfig["orbit"].
LOCAL stagingSettings TO missionConfig["staging"].
LOCAL readinessSettings TO missionConfig["readiness"].
LOCAL partsManifest TO GetSlsPartsManifest().
LOCAL resolvedManifest TO ResolveManifest(partsManifest).

LOCAL flightLogIntervalSeconds TO 0.25.
LOCAL standbyIntervalSeconds TO 1.
LOCAL flightStarted TO FALSE.
LOCAL flightSampleIndex TO 0.
LOCAL flightStartSeconds TO 0.
LOCAL launchReferenceLatitude TO 0.
LOCAL launchReferenceLongitude TO 0.
LOCAL flightLogLines TO LIST().
LOCAL flightLogHeader TO "sample_index,mission_elapsed_seconds,altitude_m,downrange_m,vertical_speed_mps,surface_speed_mps,apoapsis_m,periapsis_m,latitude_deg,longitude_deg".

LOCAL forecastState TO InitializeLaunchForecastState().
LOCAL forecastSnapshotIndex TO 0.

LOCAL forecastHeaderLines TO LIST().
forecastHeaderLines:ADD("sample_index,checkpoint_seconds_to_launch,checkpoint_label,mission_elapsed_seconds,route_name,route_status,launch_heading_deg,pitchover_start_altitude_m,pitchover_end_altitude_m,gravity_turn_final_pitch_deg,gravity_turn_end_altitude_m,estimated_delta_v_mps,predicted_downrange_m,predicted_altitude_m,predicted_apoapsis_m,predicted_periapsis_m,route_points").
WriteMccVehicleLaunchForecast(forecastHeaderLines).

UNTIL FALSE {
    IF IsFlightLoggingActive() {
        IF forecastState["rows"]:LENGTH > 0 OR forecastState["forecast_active"] {
            ResetLaunchForecastState(forecastState).
            SET forecastSnapshotIndex TO 0.
            WriteMccVehicleLaunchForecast(BuildLaunchForecastCsvRows(forecastState["rows"])).
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
        CONTINUE.
    }.

    IF flightStarted {
        SET flightStarted TO FALSE.
        SET flightSampleIndex TO 0.
        SET flightStartSeconds TO 0.
        SET flightLogLines TO LIST().
    }.

    LOCAL towerStatus TO ReadBridgeRecord(bridgePaths["tower_status_archive_path"], bridgePaths["tower_status_volume_path"]).

    IF IsLaunchForecastCountdownActive(towerStatus) AND IsResolvedManifestValid(resolvedManifest) {
        LOCAL currentSeconds TO GetTowerCountdownSeconds(towerStatus).

        IF NOT forecastState["forecast_active"] {
            SET forecastState["forecast_active"] TO TRUE.
            SET forecastState["forecast_complete"] TO FALSE.
            SET forecastState["next_checkpoint_seconds"] TO currentSeconds.
            SET forecastState["last_checkpoint_seconds"] TO -1.
            SET forecastState["rows"] TO LIST().
            SET forecastSnapshotIndex TO 0.
        }.

        IF ShouldCaptureLaunchForecastSnapshot(towerStatus, forecastState) {
            LOCAL forecastCheckpointSeconds TO currentSeconds.
            IF forecastState["next_checkpoint_seconds"] >= 0 {
                SET forecastCheckpointSeconds TO forecastState["next_checkpoint_seconds"].
            }.

            LOCAL snapshot TO BuildLaunchForecastSnapshot(
                missionSettings,
                launchSettings,
                ascentSettings,
                orbitSettings,
                stagingSettings,
                readinessSettings,
                resolvedManifest,
                forecastCheckpointSeconds,
                forecastSnapshotIndex
            ).

            forecastState["rows"]:ADD(snapshot).
            SET forecastState["last_checkpoint_seconds"] TO forecastCheckpointSeconds.
            SET forecastSnapshotIndex TO forecastSnapshotIndex + 1.
            UpdateLaunchForecastSchedule(forecastState, forecastCheckpointSeconds).
            WriteMccVehicleLaunchForecast(BuildLaunchForecastCsvRows(forecastState["rows"])).
        }.
    } ELSE {
        IF forecastState["rows"]:LENGTH > 0 OR forecastState["forecast_active"] {
            ResetLaunchForecastState(forecastState).
            SET forecastSnapshotIndex TO 0.
            WriteMccVehicleLaunchForecast(BuildLaunchForecastCsvRows(forecastState["rows"])).
        }.
    }.

    WAIT standbyIntervalSeconds.
}.

FUNCTION IsFlightLoggingActive {
    RETURN SHIP:ALTITUDE > 0 OR SHIP:GROUNDSPEED > 0.5 OR ABS(SHIP:VERTICALSPEED) > 0.5.
}.

FUNCTION IsResolvedManifestValid {
    PARAMETER resolvedManifest.

    FOR groupName IN resolvedManifest:KEYS {
        IF NOT resolvedManifest[groupName]["is_valid"] {
            RETURN FALSE.
        }.
    }.

    RETURN TRUE.
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
