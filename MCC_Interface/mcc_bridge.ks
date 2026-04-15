GLOBAL FUNCTION GetMccBridgePaths {
    RETURN LEXICON(
        "command_archive_path", "0:/NASA/MCC_Interface/command.txt",
        "tower_status_archive_path", "0:/NASA/MCC_Interface/tower_status.txt",
        "vehicle_status_archive_path", "0:/NASA/MCC_Interface/vehicle_status.txt",
        "vehicle_flight_status_archive_path", "0:/NASA/MCC_Interface/vehicle_flight.txt",
        "vehicle_flight_log_archive_path", "0:/NASA/MCC_Interface/vehicle_flight_log.csv",
        "vehicle_launch_forecast_archive_path", "0:/NASA/MCC_Interface/vehicle_launch_forecast.csv",
        "command_volume_path", "/NASA/MCC_Interface/command.txt",
        "tower_status_volume_path", "/NASA/MCC_Interface/tower_status.txt",
        "vehicle_status_volume_path", "/NASA/MCC_Interface/vehicle_status.txt",
        "vehicle_flight_status_volume_path", "/NASA/MCC_Interface/vehicle_flight.txt",
        "vehicle_flight_log_volume_path", "/NASA/MCC_Interface/vehicle_flight_log.csv",
        "vehicle_launch_forecast_volume_path", "/NASA/MCC_Interface/vehicle_launch_forecast.csv"
    ).
}.

GLOBAL FUNCTION ReadMccCommand {
    PARAMETER vehicleId, lastRevision.

    LOCAL bridgePaths TO GetMccBridgePaths().
    LOCAL commandData TO ReadBridgeRecord(bridgePaths["command_archive_path"], bridgePaths["command_volume_path"]).
    LOCAL revision TO 0.
    LOCAL targetVehicleId TO "".
    LOCAL commandName TO "noop".
    LOCAL countdownSeconds TO -1.
    LOCAL launchEpochSeconds TO -1.
    LOCAL targetBody TO "".
    LOCAL launchWindowMode TO "".

    IF commandData:HASKEY("command_revision") {
        SET revision TO commandData["command_revision"]:TONUMBER.
    }.

    IF commandData:HASKEY("vehicle_id") {
        SET targetVehicleId TO commandData["vehicle_id"].
    }.

    IF targetVehicleId <> "" AND targetVehicleId <> vehicleId {
        RETURN BuildMccCommandResult(TRUE, FALSE, revision, "noop", -1, targetVehicleId, "", "").
    }.

    IF commandData:HASKEY("command") {
        SET commandName TO commandData["command"].
    }.

    IF commandData:HASKEY("countdown_seconds") {
        SET countdownSeconds TO commandData["countdown_seconds"]:TONUMBER.
    }.

    IF commandData:HASKEY("launch_epoch_seconds") {
        SET launchEpochSeconds TO commandData["launch_epoch_seconds"]:TONUMBER.
    }.

    IF commandData:HASKEY("target_body") {
        SET targetBody TO commandData["target_body"].
    }.

    IF commandData:HASKEY("launch_window_mode") {
        SET launchWindowMode TO commandData["launch_window_mode"].
    }.

    RETURN BuildMccCommandResult(TRUE, revision > lastRevision, revision, commandName, countdownSeconds, launchEpochSeconds, targetVehicleId, targetBody, launchWindowMode).
}.

GLOBAL FUNCTION BuildMccCommandResult {
    PARAMETER isAvailable, isNewRevision, revision, commandName, countdownSeconds, launchEpochSeconds, targetVehicleId, targetBody, launchWindowMode.

    RETURN LEXICON(
        "is_available", isAvailable,
        "is_new_revision", isNewRevision,
        "revision", revision,
        "command_name", commandName,
        "countdown_seconds", countdownSeconds,
        "launch_epoch_seconds", launchEpochSeconds,
        "vehicle_id", targetVehicleId,
        "target_body", targetBody,
        "launch_window_mode", launchWindowMode
    ).
}.

GLOBAL FUNCTION WriteMccCommand {
    PARAMETER statusLexicon.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeRecord(statusLexicon, bridgePaths["command_archive_path"], bridgePaths["command_volume_path"]).
}.

GLOBAL FUNCTION WriteMccTowerStatus {
    PARAMETER statusLexicon.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeRecord(statusLexicon, bridgePaths["tower_status_archive_path"], bridgePaths["tower_status_volume_path"]).
}.

GLOBAL FUNCTION WriteMccVehicleStatus {
    PARAMETER statusLexicon.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeRecord(statusLexicon, bridgePaths["vehicle_status_archive_path"], bridgePaths["vehicle_status_volume_path"]).
}.

GLOBAL FUNCTION WriteMccVehicleFlightStatus {
    PARAMETER statusLexicon.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeRecord(statusLexicon, bridgePaths["vehicle_flight_status_archive_path"], bridgePaths["vehicle_flight_status_volume_path"]).
}.

GLOBAL FUNCTION WriteMccVehicleFlightLog {
    PARAMETER logLines.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeTextFile(logLines, bridgePaths["vehicle_flight_log_archive_path"], bridgePaths["vehicle_flight_log_volume_path"]).
}.

GLOBAL FUNCTION WriteMccVehicleLaunchForecast {
    PARAMETER logLines.

    LOCAL bridgePaths TO GetMccBridgePaths().
    WriteBridgeTextFile(logLines, bridgePaths["vehicle_launch_forecast_archive_path"], bridgePaths["vehicle_launch_forecast_volume_path"]).
}.

GLOBAL FUNCTION ReadBridgeRecord {
    PARAMETER archivePath, volumePath.

    LOCAL bridgeVolume TO VOLUME(0).
    LOCAL record TO LEXICON().
    LOCAL fileContents TO 0.

    IF NOT bridgeVolume:EXISTS(volumePath) {
        RETURN record.
    }.

    SET fileContents TO OPEN(archivePath):READALL.

    FOR rawLine IN fileContents {
        LOCAL lineText TO rawLine:TRIM.
        LOCAL lineParts TO lineText:SPLIT("=").

        IF lineParts:LENGTH < 2 {
            CONTINUE.
        }.

        LOCAL keyText TO lineParts[0]:TRIM.
        LOCAL valueText TO lineParts[1]:TRIM.
        record:ADD(keyText, valueText).
    }.

    RETURN record.
}.

GLOBAL FUNCTION WriteBridgeRecord {
    PARAMETER record, archivePath, volumePath.

    LOCAL bridgeVolume TO VOLUME(0).
    LOCAL fileHandle TO 0.

    IF NOT bridgeVolume:EXISTS(volumePath) {
        CREATE(archivePath).
    }.

    SET fileHandle TO OPEN(archivePath).
    fileHandle:CLEAR().

    FOR keyName IN record:KEYS {
        fileHandle:WRITELN(keyName + "=" + record[keyName]).
    }.
}.

GLOBAL FUNCTION WriteBridgeTextFile {
    PARAMETER lines, archivePath, volumePath.

    LOCAL bridgeVolume TO VOLUME(0).
    LOCAL fileHandle TO 0.

    IF NOT bridgeVolume:EXISTS(volumePath) {
        CREATE(archivePath).
    }.

    SET fileHandle TO OPEN(archivePath).
    fileHandle:CLEAR().

    FOR lineText IN lines {
        fileHandle:WRITELN(lineText).
    }.
}.
