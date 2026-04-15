RUNPATH("0:/Libraries/maths_library").
RUNPATH("0:/Libraries/navigation_library").

RUNPATH("0:/NASA/Space_Launch_System_B1/mission_configuration.ks").
RUNPATH("0:/NASA/MCC_Interface/mcc_bridge.ks").

LOCAL missionConfig TO GetMissionConfiguration().
RunCountdown(missionConfig["mission"], missionConfig["launch"], missionConfig["ascent"]).

FUNCTION RunCountdown {
    PARAMETER missionSettings, launchSettings, ascentSettings.

    LOCAL launchBody TO SHIP:BODY.
    LOCAL selectedTargetBodyName TO missionSettings["target_body"].
    LOCAL selectedLaunchWindowMode TO missionSettings["launch_window_mode"].
    LOCAL targetBody TO BODY(selectedTargetBodyName).
    LOCAL countdownMode TO ResolveCountdownModeFromSelection(selectedLaunchWindowMode, selectedTargetBodyName, launchBody).
    LOCAL refreshRate TO missionSettings["countdown_refresh_rate"].
    LOCAL handoffTimeSeconds TO launchSettings["handoff_time_seconds"].
    LOCAL handoffComplete TO FALSE.
    LOCAL launchEpochSeconds TO 0.
    LOCAL windowLongitude TO SHIP:GEOPOSITION:LNG.
    LOCAL relativeInclination TO 0.
    LOCAL modeStatusText TO "".
    LOCAL cachedWindowSolution TO LEXICON().
    LOCAL hasCachedWindowSolution TO FALSE.
    LOCAL solutionRefreshTime TO 0.
    LOCAL siteLatitude TO SHIP:GEOPOSITION:LAT.
    LOCAL siteLongitude TO SHIP:GEOPOSITION:LNG.
    LOCAL secondsToWindow TO 0.
    LOCAL handoffSentAtSeconds TO -1.
    LOCAL operatorCommandRevision TO 0.
    LOCAL countdownHoldActive TO FALSE.
    LOCAL countdownArmed TO FALSE.
    LOCAL abortActive TO FALSE.
    LOCAL heldCountdownSeconds TO 0.
    LOCAL operatorStatusText TO "AWAITING START".
    LOCAL vehicleId TO launchSettings["vehicle_id"].
    LOCAL lastDisplayMode TO "".
    LOCAL useMccApp TO missionSettings["use_mcc_app"].
    LOCAL launchRuleGateRequired TO FALSE.

    CLEARSCREEN.

    IF NOT useMccApp {
        LOCAL countdownInitialization TO InitializeCountdownFromCommand(
            countdownMode,
            launchEpochSeconds,
            missionSettings,
            selectedTargetBodyName
        ).
        SET countdownMode TO countdownInitialization["countdown_mode"].
        SET launchEpochSeconds TO countdownInitialization["launch_epoch_seconds"].
        SET heldCountdownSeconds TO countdownInitialization["held_countdown_seconds"].
        SET countdownArmed TO countdownInitialization["countdown_armed"].
        SET launchRuleGateRequired TO (launchEpochSeconds - TIME:SECONDS) > 3600.
        SET countdownHoldActive TO FALSE.
        SET abortActive TO FALSE.
        SET operatorStatusText TO "LOCAL COUNTDOWN ACTIVE".
    }.

    UNTIL FALSE {
        SET siteLatitude TO SHIP:GEOPOSITION:LAT.
        SET siteLongitude TO SHIP:GEOPOSITION:LNG.

        IF useMccApp {
            LOCAL operatorCommand TO ReadMccCommand(vehicleId, operatorCommandRevision).

            IF operatorCommand["is_new_revision"] {
                LOCAL operatorUpdate TO ApplyTowerOperatorCommand(
                    operatorCommand,
                    countdownMode,
                    launchEpochSeconds,
                    countdownArmed,
                    countdownHoldActive,
                    abortActive,
                    heldCountdownSeconds,
                    missionSettings,
                    selectedTargetBodyName,
                    selectedLaunchWindowMode
                ).

                SET operatorCommandRevision TO operatorCommand["revision"].
                SET countdownMode TO operatorUpdate["countdown_mode"].
                SET launchEpochSeconds TO operatorUpdate["launch_epoch_seconds"].
                SET countdownArmed TO operatorUpdate["countdown_armed"].
                SET countdownHoldActive TO operatorUpdate["countdown_hold_active"].
                SET abortActive TO operatorUpdate["abort_active"].
                SET heldCountdownSeconds TO operatorUpdate["held_countdown_seconds"].
                SET operatorStatusText TO operatorUpdate["operator_status_text"].
                SET selectedTargetBodyName TO operatorUpdate["target_body"].
                SET selectedLaunchWindowMode TO operatorUpdate["launch_window_mode"].
                SET launchRuleGateRequired TO operatorUpdate["launch_rule_gate_required"].
                SET targetBody TO BODY(selectedTargetBodyName).
                SET hasCachedWindowSolution TO FALSE.
            }.
        }.

        IF abortActive {
            SET modeStatusText TO "ABORT".
            SET secondsToWindow TO heldCountdownSeconds.
            SET windowLongitude TO siteLongitude.
            SET relativeInclination TO 0.
        } ELSE IF NOT countdownArmed {
            SET modeStatusText TO "AWAITING START".
            SET secondsToWindow TO 0.
            SET windowLongitude TO siteLongitude.
            SET relativeInclination TO 0.
        } ELSE IF countdownHoldActive {
            SET modeStatusText TO "COUNTDOWN HOLD".
            SET secondsToWindow TO heldCountdownSeconds.
            SET windowLongitude TO siteLongitude.
            SET relativeInclination TO 0.
        } ELSE IF countdownMode = "MANUAL_COUNTDOWN" {
            SET modeStatusText TO "MANUAL COUNTDOWN".
            SET secondsToWindow TO launchEpochSeconds - TIME:SECONDS.
            SET windowLongitude TO siteLongitude.
            SET relativeInclination TO 0.
        } ELSE {
            IF (NOT hasCachedWindowSolution OR TIME:SECONDS >= solutionRefreshTime OR launchEpochSeconds <= TIME:SECONDS) AND NOT IsTimeWarpActive() {
                ShowWindowCalculationStatus(missionSettings, selectedTargetBodyName, launchBody, siteLatitude, siteLongitude).
                WAIT 0.
                SET cachedWindowSolution TO FindRelativeInclinationWindow(
                    targetBody,
                    launchBody,
                    ascentSettings["launch_heading"],
                    siteLatitude,
                    siteLongitude,
                    missionSettings
                ).
                SET launchEpochSeconds TO TIME:SECONDS + cachedWindowSolution["seconds_to_window"].
                SET windowLongitude TO cachedWindowSolution["window_longitude"].
                SET relativeInclination TO cachedWindowSolution["relative_inclination"].
                SET solutionRefreshTime TO TIME:SECONDS + missionSettings["window_solution_refresh_seconds"].
                SET hasCachedWindowSolution TO TRUE.
            }.

            SET secondsToWindow TO launchEpochSeconds - TIME:SECONDS.
            SET modeStatusText TO "REL INC WINDOW".
        }.

        // Publish the handoff in both modes. The vehicle waits for this
        // message before arming its own launch sequence, so the tower is the
        // source of truth for launch start.
        IF countdownArmed AND NOT abortActive AND NOT countdownHoldActive AND secondsToWindow > 3600 {
            SET launchRuleGateRequired TO TRUE.
        }.

        IF countdownArmed AND NOT abortActive AND NOT countdownHoldActive AND NOT handoffComplete AND secondsToWindow <= handoffTimeSeconds {
            IF SendTowerHandoff(launchSettings, launchEpochSeconds, windowLongitude) {
                SET handoffComplete TO TRUE.
                SET handoffSentAtSeconds TO secondsToWindow.
            } ELSE {
                ShowHandoffFailure(launchSettings).
                WAIT UNTIL FALSE.
            }.
        }.

        ClearScreenForMode(modeStatusText, lastDisplayMode).
        SET lastDisplayMode TO modeStatusText.

        DisplayTowerStatus(
            missionSettings,
            launchSettings,
            selectedTargetBodyName,
            countdownMode,
            modeStatusText,
            launchBody,
            siteLatitude,
            siteLongitude,
            windowLongitude,
            relativeInclination,
            secondsToWindow,
            handoffComplete,
            handoffSentAtSeconds,
            countdownHoldActive,
            operatorStatusText
        ).

        WriteTowerBridgeStatus(
            missionSettings,
            launchSettings,
            selectedTargetBodyName,
            countdownMode,
            modeStatusText,
            siteLatitude,
            siteLongitude,
            windowLongitude,
            relativeInclination,
            secondsToWindow,
            handoffComplete,
            countdownHoldActive,
            operatorStatusText,
            launchEpochSeconds,
            countdownArmed,
            abortActive,
            launchRuleGateRequired
        ).

        WAIT refreshRate.
    }.
}.

FUNCTION DisplayTowerStatus {
    PARAMETER missionSettings, launchSettings, selectedTargetBodyName, countdownMode, modeStatusText, launchBody, siteLatitude, siteLongitude, windowLongitude, relativeInclination, secondsToWindow, handoffComplete, handoffSentAtSeconds, countdownHoldActive, operatorStatusText.

    DrawLine("SLS LAUNCH TOWER", 0).
    DrawLine("Mode: " + modeStatusText, 1).
    DrawLine("Mission: " + missionSettings["mission_name"], 2).
    DrawLine("Launch Body: " + launchBody:NAME, 3).
    DrawLine("Target Body: " + selectedTargetBodyName, 4).
    DrawLine("Target Inclination: " + missionSettings["target_inclination"], 5).
    DrawLine("Target Apoapsis: " + missionSettings["target_body_apoapsis"], 6).
    DrawLine("Target Periapsis: " + missionSettings["target_body_periapsis"], 7).
    DrawLine("", 8).
    DrawLine("Site Latitude: " + ROUND(siteLatitude, 3), 9).
    DrawLine("Site Longitude: " + ROUND(siteLongitude, 3), 10).
    DrawLine("Window Longitude: " + ROUND(windowLongitude, 3), 11).

    IF countdownMode = "MANUAL_COUNTDOWN" {
        DrawLine("Manual Time: " + missionSettings["manual_countdown_time"], 12).
    } ELSE {
        DrawLine("Relative Inclination: " + ROUND(relativeInclination, 3), 12).
    }.

    DrawLine("", 13).
    DrawLine(FormatCountdown(secondsToWindow), 14).
    DrawLine(GetWindowStatus(countdownMode, relativeInclination, missionSettings["window_alignment_tolerance"]), 15).
    IF countdownHoldActive {
        DrawLine("Operator State: HOLD", 16).
    } ELSE IF NOT missionSettings["use_mcc_app"] {
        DrawLine("Operator State: LOCAL AG6 / BOOT", 16).
    } ELSE {
        DrawLine("Operator State: " + operatorStatusText, 16).
    }.

    IF NOT missionSettings["use_mcc_app"] {
        DrawLine("Vehicle Handoff: NOT REQUIRED", 17).
    } ELSE IF handoffComplete {
        DrawLine("Vehicle Handoff: SENT AT " + FormatCountdown(handoffSentAtSeconds), 17).
    } ELSE {
        DrawLine("Vehicle Handoff: T-" + launchSettings["handoff_time_seconds"], 17).
    }.
}.

FUNCTION ApplyTowerOperatorCommand {
    PARAMETER operatorCommand, countdownMode, launchEpochSeconds, countdownArmed, countdownHoldActive, abortActive, heldCountdownSeconds, missionSettings, currentTargetBodyName, currentLaunchWindowMode.

    LOCAL commandName TO operatorCommand["command_name"].
    LOCAL updatedCountdownMode TO countdownMode.
    LOCAL updatedLaunchEpochSeconds TO launchEpochSeconds.
    LOCAL updatedCountdownArmed TO countdownArmed.
    LOCAL updatedHoldActive TO countdownHoldActive.
    LOCAL updatedAbortActive TO abortActive.
    LOCAL updatedHeldCountdownSeconds TO heldCountdownSeconds.
    LOCAL updatedLaunchRuleGateRequired TO FALSE.
    LOCAL updatedTargetBodyName TO currentTargetBodyName.
    LOCAL updatedLaunchWindowMode TO currentLaunchWindowMode.
    LOCAL operatorStatusText TO "AWAITING START".

    IF operatorCommand["target_body"] <> "" {
        SET updatedTargetBodyName TO operatorCommand["target_body"].
    }.

    IF operatorCommand["launch_window_mode"] <> "" {
        SET updatedLaunchWindowMode TO operatorCommand["launch_window_mode"].
    }.

    IF commandName = "start_countdown" {
        SET updatedCountdownMode TO ResolveCountdownModeFromSelection(updatedLaunchWindowMode, updatedTargetBodyName, SHIP:BODY).
        LOCAL countdownInitialization TO InitializeCountdownFromCommand(updatedCountdownMode, updatedLaunchEpochSeconds, missionSettings, updatedTargetBodyName).
        SET updatedCountdownMode TO countdownInitialization["countdown_mode"].
        SET updatedLaunchEpochSeconds TO countdownInitialization["launch_epoch_seconds"].
        SET updatedHeldCountdownSeconds TO countdownInitialization["held_countdown_seconds"].
        SET updatedCountdownArmed TO countdownInitialization["countdown_armed"].
        SET updatedLaunchRuleGateRequired TO (updatedLaunchEpochSeconds - TIME:SECONDS) > 3600.
        SET updatedHoldActive TO FALSE.
        SET updatedAbortActive TO FALSE.
        SET operatorStatusText TO countdownInitialization["operator_status_text"].
    } ELSE IF commandName = "hold" {
        SET updatedHoldActive TO TRUE.
        SET updatedHeldCountdownSeconds TO MAX(0, launchEpochSeconds - TIME:SECONDS).
        SET operatorStatusText TO "HOLD ACCEPTED".
    } ELSE IF commandName = "resume" {
        IF countdownHoldActive {
            SET updatedLaunchEpochSeconds TO TIME:SECONDS + heldCountdownSeconds.
        }.
        SET updatedHoldActive TO FALSE.
        SET operatorStatusText TO "COUNT RESUMED".
    } ELSE IF commandName = "set_countdown" {
        IF operatorCommand["countdown_seconds"] < 0 {
            SET operatorStatusText TO "INVALID COUNT REQUEST".
        } ELSE {
            SET updatedCountdownMode TO ResolveCountdownModeFromSelection(updatedLaunchWindowMode, updatedTargetBodyName, SHIP:BODY).
            SET updatedCountdownArmed TO TRUE.
            SET updatedLaunchRuleGateRequired TO operatorCommand["countdown_seconds"] > 3600.
            SET updatedHoldActive TO FALSE.
            SET updatedAbortActive TO FALSE.

            IF updatedCountdownMode = "MANUAL_COUNTDOWN" {
                SET updatedLaunchEpochSeconds TO TIME:SECONDS + operatorCommand["countdown_seconds"].
                SET updatedHeldCountdownSeconds TO operatorCommand["countdown_seconds"].
                SET operatorStatusText TO "COUNTDOWN STARTED AT " + FormatCountdown(operatorCommand["countdown_seconds"]).
            } ELSE {
                LOCAL countdownInitialization TO InitializeCountdownFromCommand(updatedCountdownMode, updatedLaunchEpochSeconds, missionSettings, updatedTargetBodyName).
                SET updatedCountdownMode TO countdownInitialization["countdown_mode"].
                SET updatedLaunchEpochSeconds TO countdownInitialization["launch_epoch_seconds"].
                SET updatedHeldCountdownSeconds TO countdownInitialization["held_countdown_seconds"].
                SET operatorStatusText TO "WINDOWED COUNTDOWN ARMED FOR " + updatedTargetBodyName.
            }.
        }.
    } ELSE IF commandName = "abort" {
        SET updatedAbortActive TO TRUE.
        SET updatedHoldActive TO TRUE.
        SET updatedHeldCountdownSeconds TO MAX(0, launchEpochSeconds - TIME:SECONDS).
        SET operatorStatusText TO "ABORT ISSUED".
    }.

    RETURN LEXICON(
        "countdown_mode", updatedCountdownMode,
        "launch_epoch_seconds", updatedLaunchEpochSeconds,
        "countdown_armed", updatedCountdownArmed,
        "countdown_hold_active", updatedHoldActive,
        "abort_active", updatedAbortActive,
        "held_countdown_seconds", updatedHeldCountdownSeconds,
        "launch_rule_gate_required", updatedLaunchRuleGateRequired,
        "operator_status_text", operatorStatusText,
        "target_body", updatedTargetBodyName,
        "launch_window_mode", updatedLaunchWindowMode
    ).
}.

FUNCTION InitializeCountdownFromCommand {
    PARAMETER currentCountdownMode, launchEpochSeconds, missionSettings, selectedTargetBodyName.

    LOCAL initializedCountdownMode TO currentCountdownMode.
    LOCAL initializedLaunchEpochSeconds TO launchEpochSeconds.
    LOCAL initializedHeldCountdownSeconds TO 0.
    LOCAL operatorStatusText TO "COUNTDOWN STARTED".

    IF currentCountdownMode = "MANUAL_COUNTDOWN" OR selectedTargetBodyName = SHIP:BODY:NAME {
        LOCAL manualValidation TO ValidateManualCountdown(missionSettings["manual_countdown_time"], missionSettings).

        IF NOT manualValidation["is_valid"] {
            RETURN LEXICON(
                "countdown_mode", "MANUAL_COUNTDOWN",
                "launch_epoch_seconds", launchEpochSeconds,
                "held_countdown_seconds", 0,
                "countdown_armed", FALSE,
                "operator_status_text", manualValidation["message"]
            ).
        }.

        SET initializedCountdownMode TO "MANUAL_COUNTDOWN".
        SET initializedLaunchEpochSeconds TO TIME:SECONDS + manualValidation["countdown_seconds"].
        SET initializedHeldCountdownSeconds TO manualValidation["countdown_seconds"].
    } ELSE {
        IF NOT IsValidTargetBody(BODY(selectedTargetBodyName), SHIP:BODY) {
            RETURN LEXICON(
                "countdown_mode", currentCountdownMode,
                "launch_epoch_seconds", launchEpochSeconds,
                "held_countdown_seconds", 0,
                "countdown_armed", FALSE,
                "operator_status_text", "INVALID TARGET BODY FOR WINDOWED START"
            ).
        }.

        SET initializedHeldCountdownSeconds TO MAX(0, launchEpochSeconds - TIME:SECONDS).
    }.

    RETURN LEXICON(
        "countdown_mode", initializedCountdownMode,
        "launch_epoch_seconds", initializedLaunchEpochSeconds,
        "held_countdown_seconds", initializedHeldCountdownSeconds,
        "countdown_armed", TRUE,
        "operator_status_text", operatorStatusText
    ).
}.

FUNCTION WriteTowerBridgeStatus {
    PARAMETER missionSettings, launchSettings, selectedTargetBodyName, countdownMode, modeStatusText, siteLatitude, siteLongitude, windowLongitude, relativeInclination, secondsToWindow, handoffComplete, countdownHoldActive, operatorStatusText, launchEpochSeconds, countdownArmed, abortActive, launchRuleGateRequired.

    WriteMccTowerStatus(
        LEXICON(
            "source", "tower",
            "vehicle_id", launchSettings["vehicle_id"],
            "mission_name", missionSettings["mission_name"],
            "use_mcc_app", missionSettings["use_mcc_app"],
            "target_body", selectedTargetBodyName,
            "countdown_mode", countdownMode,
            "mode_status_text", modeStatusText,
            "countdown_armed", countdownArmed,
            "launch_rule_gate_required", launchRuleGateRequired,
            "countdown_hold_active", countdownHoldActive,
            "abort_active", abortActive,
            "operator_status_text", operatorStatusText,
            "seconds_to_window", ROUND(MAX(0, secondsToWindow), 1),
            "formatted_countdown", FormatCountdown(secondsToWindow),
            "handoff_complete", handoffComplete,
            "launch_epoch_seconds", launchEpochSeconds,
            "site_latitude", ROUND(siteLatitude, 4),
            "site_longitude", ROUND(siteLongitude, 4),
            "window_longitude", ROUND(windowLongitude, 4),
            "relative_inclination", ROUND(relativeInclination, 4),
            "updated_at", TIME:SECONDS
        )
    ).
}.

FUNCTION SendTowerHandoff {
    PARAMETER launchSettings, launchEpochSeconds, launchNodeLongitude.

    WriteMccCommand(
        LEXICON(
            "command_revision", ROUND(TIME:SECONDS, 0),
            "vehicle_id", launchSettings["vehicle_id"],
            "command", "tower_handoff",
            "countdown_seconds", MAX(0, launchEpochSeconds - TIME:SECONDS),
            "launch_epoch_seconds", launchEpochSeconds,
            "target_body", "",
            "launch_window_mode", "",
            "launch_node_longitude", launchNodeLongitude,
            "issued_at_utc", TIME:SECONDS
        )
    ).
    RETURN TRUE.
}.

FUNCTION ShowHandoffFailure {
    PARAMETER launchSettings.

    CLEARSCREEN.
    DrawLine("SLS LAUNCH TOWER", 0).
    DrawLine("Mode: HANDOFF FAILED", 1).
    DrawLine("Unable to publish tower handoff.", 2).
    DrawLine("Expected Vessel: " + launchSettings["vehicle_vessel_name"], 3).
    DrawLine("Expected CPU Tag: " + launchSettings["vehicle_cpu_tag"], 4).
    DrawLine("Launch is held pending valid handoff.", 5).
}.

FUNCTION ShowWindowCalculationStatus {
    PARAMETER missionSettings, selectedTargetBodyName, launchBody, siteLatitude, siteLongitude.

    CLEARSCREEN.
    DrawLine("SLS LAUNCH TOWER", 0).
    DrawLine("Mode: CALCULATING WINDOW", 1).
    DrawLine("Mission: " + missionSettings["mission_name"], 2).
    DrawLine("Launch Body: " + launchBody:NAME, 3).
    DrawLine("Target Body: " + selectedTargetBodyName, 4).
    DrawLine("Site Latitude: " + ROUND(siteLatitude, 3), 5).
    DrawLine("Site Longitude: " + ROUND(siteLongitude, 3), 6).
    DrawLine("Computing rel-inc launch time...", 7).
}.

FUNCTION IsTimeWarpActive {
    RETURN KUNIVERSE:TIMEWARP:RATE > 1.
}.

FUNCTION ResolveCountdownModeFromSelection {
    PARAMETER selectedLaunchWindowMode, selectedTargetBodyName, launchBody.

    IF selectedLaunchWindowMode = "MANUAL_COUNTDOWN" OR selectedLaunchWindowMode = "RELATIVE_INCLINATION" {
        RETURN selectedLaunchWindowMode.
    }.

    IF selectedTargetBodyName = launchBody:NAME {
        RETURN "MANUAL_COUNTDOWN".
    }.

    RETURN "RELATIVE_INCLINATION".
}.

FUNCTION ValidateManualCountdown {
    PARAMETER countdownString, missionSettings.

    LOCAL parts TO countdownString:SPLIT(":").

    IF parts:LENGTH <> 3 {
        RETURN LEXICON("is_valid", FALSE, "countdown_seconds", 0, "message", "Manual countdown must be HH:MM:SS.").
    }.

    LOCAL hoursValue TO parts[0]:TONUMBER.
    LOCAL minutesValue TO parts[1]:TONUMBER.
    LOCAL secondsValue TO parts[2]:TONUMBER.
    LOCAL totalSeconds TO (hoursValue * 3600) + (minutesValue * 60) + secondsValue.

    IF totalSeconds < missionSettings["manual_countdown_reject_seconds"] {
        RETURN LEXICON(
            "is_valid", FALSE,
            "countdown_seconds", 0,
            "message", "Manual countdown must be at least " + FormatCountdown(missionSettings["manual_countdown_min_seconds"]) + "."
        ).
    }.

    IF totalSeconds < missionSettings["manual_countdown_min_seconds"] {
        RETURN LEXICON(
            "is_valid", FALSE,
            "countdown_seconds", 0,
            "message", "Manual countdown must be at least " + FormatCountdown(missionSettings["manual_countdown_min_seconds"]) + "."
        ).
    }.

    RETURN LEXICON("is_valid", TRUE, "countdown_seconds", totalSeconds, "message", "").
}.

FUNCTION IsValidTargetBody {
    PARAMETER targetBody, launchBody.

    RETURN targetBody:ORBIT:BODY:NAME = launchBody:NAME.
}.

FUNCTION GetWindowStatus {
    PARAMETER countdownMode, relativeInclination, toleranceDegrees.

    IF countdownMode = "MANUAL_COUNTDOWN" {
        RETURN "GO FOR MANUAL COUNTDOWN".
    }.

    IF relativeInclination <= toleranceDegrees {
        RETURN "GO FOR REL INC WINDOW".
    }.

    RETURN "HOLD FOR WINDOW".
}.

FUNCTION FindRelativeInclinationWindow {
    PARAMETER targetBody, launchBody, launchHeading, siteLatitude, siteLongitude, missionSettings.

    LOCAL searchDuration TO launchBody:ROTATIONPERIOD.
    LOCAL coarseStep TO missionSettings["relative_inclination_search_step_seconds"].
    LOCAL refineStep TO missionSettings["relative_inclination_refine_step_seconds"].
    LOCAL bestSeconds TO 0.
    LOCAL bestRelativeInclination TO 999.
    LOCAL coarseSeconds TO 0.
    LOCAL fineStart TO 0.
    LOCAL fineEnd TO 0.
    LOCAL fineSeconds TO 0.

    UNTIL coarseSeconds > searchDuration {
        LOCAL sampledRelativeInclination TO GetRelativeInclinationAtTime(
            targetBody,
            launchBody,
            launchHeading,
            siteLatitude,
            siteLongitude,
            coarseSeconds
        ).

        IF sampledRelativeInclination < bestRelativeInclination {
            SET bestRelativeInclination TO sampledRelativeInclination.
            SET bestSeconds TO coarseSeconds.
        }.

        SET coarseSeconds TO coarseSeconds + coarseStep.
    }.

    SET fineStart TO MAX(0, bestSeconds - coarseStep).
    SET fineEnd TO MIN(searchDuration, bestSeconds + coarseStep).
    SET bestRelativeInclination TO 999.
    SET fineSeconds TO fineStart.

    UNTIL fineSeconds > fineEnd {
        LOCAL sampledRelativeInclination TO GetRelativeInclinationAtTime(
            targetBody,
            launchBody,
            launchHeading,
            siteLatitude,
            siteLongitude,
            fineSeconds
        ).

        IF sampledRelativeInclination < bestRelativeInclination {
            SET bestRelativeInclination TO sampledRelativeInclination.
            SET bestSeconds TO fineSeconds.
        }.

        SET fineSeconds TO fineSeconds + refineStep.
    }.

    RETURN LEXICON(
        "seconds_to_window", bestSeconds,
        "window_longitude", NormalizeLongitude(siteLongitude + (bestSeconds / searchDuration) * 360),
        "relative_inclination", bestRelativeInclination
    ).
}.

FUNCTION GetRelativeInclinationAtTime {
    PARAMETER targetBody, launchBody, launchHeading, siteLatitude, siteLongitude, secondsFromNow.

    LOCAL futureLongitude TO NormalizeLongitude(siteLongitude + (secondsFromNow / launchBody:ROTATIONPERIOD) * 360).
    LOCAL inertialLongitude TO NormalizeAngle(futureLongitude + launchBody:ROTATIONANGLE).
    LOCAL launchPlaneNormal TO GetLaunchPlaneNormal(siteLatitude, inertialLongitude, launchHeading).
    LOCAL targetPlaneNormal TO GetOrbitPlaneNormal(targetBody:ORBIT:INCLINATION, targetBody:ORBIT:LAN).
    LOCAL relativeInclination TO VANG(launchPlaneNormal, targetPlaneNormal).

    IF relativeInclination > 90 {
        SET relativeInclination TO 180 - relativeInclination.
    }.

    RETURN relativeInclination.
}.

FUNCTION GetLaunchPlaneNormal {
    PARAMETER latitudeDegrees, inertialLongitudeDegrees, headingDegrees.

    LOCAL latitudeCosine TO COS(latitudeDegrees).
    LOCAL latitudeSine TO SIN(latitudeDegrees).
    LOCAL longitudeCosine TO COS(inertialLongitudeDegrees).
    LOCAL longitudeSine TO SIN(inertialLongitudeDegrees).
    LOCAL headingCosine TO COS(headingDegrees).
    LOCAL headingSine TO SIN(headingDegrees).
    LOCAL launchPosition TO V(
        latitudeCosine * longitudeCosine,
        latitudeSine,
        latitudeCosine * longitudeSine
    ).
    LOCAL northVector TO V(
        -latitudeSine * longitudeCosine,
        latitudeCosine,
        -latitudeSine * longitudeSine
    ).
    LOCAL eastVector TO V(
        -longitudeSine,
        0,
        longitudeCosine
    ).
    LOCAL launchDirection TO (northVector * headingCosine) + (eastVector * headingSine).

    RETURN VCRS(launchPosition, launchDirection):NORMALIZED.
}.

FUNCTION GetOrbitPlaneNormal {
    PARAMETER inclinationDegrees, lanDegrees.

    LOCAL inclinationSine TO SIN(inclinationDegrees).
    LOCAL inclinationCosine TO COS(inclinationDegrees).
    LOCAL lanSine TO SIN(lanDegrees).
    LOCAL lanCosine TO COS(lanDegrees).

    RETURN V(
        inclinationSine * lanSine,
        inclinationCosine,
        -inclinationSine * lanCosine
    ):NORMALIZED.
}.

FUNCTION DrawLine {
    PARAMETER text, row.

    PRINT PadDisplayText(text) AT(0, row).
}.

FUNCTION FormatCountdown {
    PARAMETER totalSeconds.

    LOCAL roundedSeconds TO ROUND(MAX(0, totalSeconds), 0).
    LOCAL hours TO FLOOR(roundedSeconds / 3600).
    LOCAL remainingSeconds TO roundedSeconds - (hours * 3600).
    LOCAL minutes TO FLOOR(remainingSeconds / 60).
    LOCAL seconds TO remainingSeconds - (minutes * 60).

    RETURN "T-" + FormatTwoDigits(hours) + ":" + FormatTwoDigits(minutes) + ":" + FormatTwoDigits(seconds).
}.

FUNCTION FormatTwoDigits {
    PARAMETER value.

    LOCAL roundedValue TO ROUND(MAX(0, value), 0).

    IF roundedValue < 10 {
        RETURN "0" + roundedValue.
    }.

    RETURN "" + roundedValue.
}.

FUNCTION NormalizeAngle {
    PARAMETER angle.

    LOCAL normalizedAngle TO angle.

    UNTIL normalizedAngle >= 0 {
        SET normalizedAngle TO normalizedAngle + 360.
    }.

    UNTIL normalizedAngle < 360 {
        SET normalizedAngle TO normalizedAngle - 360.
    }.

    RETURN normalizedAngle.
}.

FUNCTION NormalizeLongitude {
    PARAMETER rawLongitude.

    LOCAL normalizedLongitude TO NormalizeAngle(rawLongitude).

    IF normalizedLongitude > 180 {
        SET normalizedLongitude TO normalizedLongitude - 360.
    }.

    RETURN normalizedLongitude.
}.

FUNCTION PadDisplayText {
    PARAMETER text.

    RETURN text + "                                                  ".
}.

FUNCTION ClearScreenForMode {
    PARAMETER currentMode, previousMode.

    IF currentMode <> previousMode {
        CLEARSCREEN.
    }.
}.
