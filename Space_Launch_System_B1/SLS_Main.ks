DECLARE PARAMETER startMode IS "standby".
DECLARE PARAMETER requestedLaunchEpochSeconds IS -1.

RUNPATH("0:/NASA/Space_Launch_System_B1/mission_configuration.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_parts_manifest.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_part_resolver.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_core_stage_guidance.ks").
RUNPATH("0:/NASA/Space_Launch_System_B1/sls_upper_stage_guidance.ks").
RUNPATH("0:/NASA/MCC_Interface/mcc_bridge.ks").

LOCAL missionConfig TO GetMissionConfiguration().
LOCAL missionSettings TO missionConfig["mission"].
LOCAL launchSettings TO missionConfig["launch"].
LOCAL ascentSettings TO missionConfig["ascent"].
LOCAL orbitSettings TO missionConfig["orbit"].
LOCAL stagingSettings TO missionConfig["staging"].
LOCAL readinessSettings TO missionConfig["readiness"].
LOCAL partsManifest TO GetSlsPartsManifest().
LOCAL resolvedManifest TO ResolveManifest(partsManifest).
LOCAL useMccApp TO missionSettings["use_mcc_app"].
GLOBAL launchClockStartSeconds TO -1.
GLOBAL launchReadinessSnapshot TO LEXICON(
    "readiness_state", "AWAITING_DIAGNOSTICS",
    "summary_text", "Awaiting countdown diagnostics.",
    "profile_text", "Awaiting countdown diagnostics.",
    "stage_breakdown_text", "Awaiting countdown diagnostics.",
    "available_delta_v_mps", 0,
    "required_delta_v_mps", 0,
    "delta_v_margin_mps", 0,
    "liftoff_twr", 0,
    "booster_delta_v_mps", 0,
    "core_delta_v_mps", 0,
    "upper_delta_v_mps", 0,
    "target_orbit_speed_mps", 0,
    "launch_losses_mps", 0
).

CLEARSCREEN.

LOCAL scheduledLaunchTime TO requestedLaunchEpochSeconds.

IF startMode = "standby" AND scheduledLaunchTime < 0 {
    // The vehicle does not self-arm its countdown. It stays in standby until
    // the tower publishes a valid handoff message, regardless of whether the
    // MCC app is enabled.
    LOCAL handoffData TO WaitForTowerHandoff(missionSettings, launchSettings).
    SET scheduledLaunchTime TO handoffData["launch_epoch_seconds"].
}.

IF scheduledLaunchTime < 0 {
    LOCAL handoffData TO WaitForTowerHandoff(missionSettings, launchSettings).
    SET scheduledLaunchTime TO handoffData["launch_epoch_seconds"].
}.

IF NOT ValidateResolvedManifest(resolvedManifest) {
    ShowManifestHold(resolvedManifest).
    WAIT UNTIL FALSE.
}.

RunTerminalSequence(
    missionSettings,
    launchSettings,
    ascentSettings,
    orbitSettings,
    stagingSettings,
    readinessSettings,
    resolvedManifest,
    scheduledLaunchTime
).

FUNCTION RunTerminalSequence {
    PARAMETER missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, readinessSettings, resolvedManifest, launchEpochSeconds.

    LOCAL countdownState TO InitializeCountdownState(launchSettings).
    LOCAL engineStarted TO countdownState["engine_started"].
    LOCAL boostersIgnited TO countdownState["boosters_ignited"].
    LOCAL releaseTriggered TO countdownState["release_triggered"].
    LOCAL padReleased TO countdownState["pad_released"].
    LOCAL commitTriggered TO countdownState["commit_triggered"].
    LOCAL throttleHold TO launchSettings["post_liftoff_throttle"].
    LOCAL nextReleaseRetryTime TO 0.
    LOCAL releaseAttemptTime TO -1.
    LOCAL liftoffValidationDeadline TO -1.
    LOCAL operatorCommandRevision TO 0.
    LOCAL countdownHoldActive TO FALSE.
    LOCAL abortActive TO FALSE.
    LOCAL heldCountdownSeconds TO 0.
    LOCAL operatorStatusText TO "READY".
    LOCAL wetDressEnabled TO launchSettings["wet_dress_enabled"].
    LOCAL wetDressStopSeconds TO launchSettings["wet_dress_stop_seconds"].
    LOCAL wetDressHoldActive TO FALSE.
    LOCAL launchRuleGateRequired TO (launchEpochSeconds - TIME:SECONDS) > 3600.
    LOCAL launchRuleGateTriggered TO FALSE.
    SET launchReadinessSnapshot TO BuildLaunchReadinessReport(
        missionSettings,
        launchSettings,
        ascentSettings,
        orbitSettings,
        stagingSettings,
        readinessSettings,
        resolvedManifest
    ).
    LOCAL lastDisplayMode TO "".
    ConfigureSteeringManager(ascentSettings).
    EnsureGuidanceAuthority().

    UNTIL SHIP:ALTITUDE >= launchSettings["tower_clear_altitude"] {
        IF missionSettings["use_mcc_app"] {
            LOCAL operatorCommand TO ReadMccCommand(launchSettings["vehicle_id"], operatorCommandRevision).

            IF operatorCommand["is_new_revision"] {
                LOCAL operatorUpdate TO ApplyVehicleOperatorCommand(
                    operatorCommand,
                    launchEpochSeconds,
                    countdownHoldActive,
                    abortActive,
                    heldCountdownSeconds,
                    engineStarted,
                    releaseTriggered
                ).

                SET operatorCommandRevision TO operatorCommand["revision"].
                SET launchEpochSeconds TO operatorUpdate["launch_epoch_seconds"].
                SET countdownHoldActive TO operatorUpdate["countdown_hold_active"].
                SET abortActive TO operatorUpdate["abort_active"].
                SET heldCountdownSeconds TO operatorUpdate["held_countdown_seconds"].
                SET operatorStatusText TO operatorUpdate["operator_status_text"].
                SET launchRuleGateRequired TO operatorUpdate["launch_rule_gate_required"].
            }.
        } ELSE {
            SET operatorStatusText TO "LOCAL COUNTDOWN ACTIVE".
        }.

        IF abortActive {
            AbortLaunch("Abort command received from MCC.").
            WAIT UNTIL FALSE.
        }.

        LOCAL secondsToLaunch TO launchEpochSeconds - TIME:SECONDS.

        IF countdownHoldActive {
            SET secondsToLaunch TO heldCountdownSeconds.
        }.

        IF wetDressEnabled AND NOT wetDressHoldActive AND secondsToLaunch <= wetDressStopSeconds {
            SET wetDressHoldActive TO TRUE.
            SET countdownHoldActive TO TRUE.
            SET heldCountdownSeconds TO MAX(0, secondsToLaunch).
            SET operatorStatusText TO "WET DRESS HOLD".
        }.

        IF wetDressHoldActive {
            SET countdownHoldActive TO TRUE.
            SET operatorStatusText TO "WET DRESS HOLD".
            SET secondsToLaunch TO heldCountdownSeconds.
        }.

        IF NOT countdownHoldActive AND NOT wetDressEnabled {
            IF NOT engineStarted AND secondsToLaunch <= launchSettings["engine_start_time_seconds"] {
                LOCK THROTTLE TO 1.
                ExecuteManifestGroup(resolvedManifest["core_engines"]).
                SET engineStarted TO TRUE.
            }.

            IF NOT releaseTriggered AND secondsToLaunch <= launchSettings["vehicle_release_time_seconds"] {
                ExecutePadRelease(resolvedManifest).
                SET releaseTriggered TO TRUE.
                SET releaseAttemptTime TO TIME:SECONDS.
                SET nextReleaseRetryTime TO TIME:SECONDS + 1.
            }.

            IF releaseTriggered AND secondsToLaunch <= launchSettings["vehicle_release_time_seconds"] AND NOT padReleased AND IsPadReleaseConfirmed(launchSettings) {
                SET padReleased TO TRUE.
            }.

            IF releaseTriggered AND NOT padReleased AND TIME:SECONDS >= nextReleaseRetryTime {
                ExecutePadRelease(resolvedManifest).
                SET nextReleaseRetryTime TO TIME:SECONDS + 1.
            }.

            IF releaseTriggered AND NOT padReleased AND TIME:SECONDS >= releaseAttemptTime + launchSettings["release_abort_timeout_seconds"] {
                AbortLaunch("Pad release failed. Throttle to zero.").
                WAIT UNTIL FALSE.
            }.

            IF padReleased AND secondsToLaunch <= launchSettings["vehicle_release_time_seconds"] AND NOT boostersIgnited {
                IgniteBoosterEngines(resolvedManifest["booster_engines"]).
                SET boostersIgnited TO TRUE.
                SET liftoffValidationDeadline TO TIME:SECONDS + launchSettings["liftoff_validation_seconds"].
                IF launchClockStartSeconds < 0 {
                    SET launchClockStartSeconds TO TIME:SECONDS.
                }.
            }.

            IF padReleased AND NOT commitTriggered AND secondsToLaunch <= launchSettings["liftoff_commit_time_seconds"] {
                LOCK THROTTLE TO throttleHold.
                LOCK STEERING TO HEADING(
                    launchSettings["post_liftoff_heading"],
                    launchSettings["post_liftoff_pitch_hold"],
                    GetLaunchRollCommand(SHIP:VERTICALSPEED, launchSettings, ascentSettings)
                ).
                SET commitTriggered TO TRUE.
                IF launchClockStartSeconds < 0 {
                    SET launchClockStartSeconds TO TIME:SECONDS.
                }.
            }.
        }.

        IF engineStarted AND NOT releaseTriggered AND NOT abortActive {
            LOCAL coreIgnitionStatus TO EvaluateCoreIgnitionHealth(resolvedManifest, stagingSettings, launchSettings).

            IF secondsToLaunch <= launchSettings["core_engine_ready_check_time_seconds"] AND NOT coreIgnitionStatus["is_nominal"] {
                AbortLaunch(coreIgnitionStatus["message"]).
                WAIT UNTIL FALSE.
            }.
        }.

        IF boostersIgnited AND padReleased AND NOT abortActive {
            LOCAL liftoffStatus TO EvaluateLiftoffHealth(resolvedManifest, stagingSettings, launchSettings).

            IF TIME:SECONDS >= liftoffValidationDeadline AND NOT liftoffStatus["is_nominal"] {
                AbortLaunch(liftoffStatus["message"]).
                WAIT UNTIL FALSE.
            }.
        }.

        SET launchReadinessSnapshot TO BuildLaunchReadinessReport(
            missionSettings,
            launchSettings,
            ascentSettings,
            orbitSettings,
            stagingSettings,
            readinessSettings,
            resolvedManifest
        ).

        IF countdownArmed AND NOT abortActive AND NOT countdownHoldActive AND secondsToLaunch > 3600 {
            SET launchRuleGateRequired TO TRUE.
        }.

        IF launchRuleGateRequired AND NOT launchRuleGateTriggered AND secondsToLaunch <= 3600 {
            WriteLaunchRuleCheckStatus(
                missionSettings,
                launchSettings,
                readinessSettings,
                resolvedManifest,
                secondsToLaunch,
                engineStarted,
                boostersIgnited,
                releaseTriggered,
                padReleased,
                commitTriggered,
                countdownHoldActive,
                abortActive,
                operatorStatusText,
                launchRuleGateRequired,
                TRUE
            ).
            SET launchRuleGateTriggered TO TRUE.
        }.

        ClearScreenForMode("TERMINAL COUNTDOWN", lastDisplayMode).
        SET lastDisplayMode TO "TERMINAL COUNTDOWN".

        DisplayVehicleStatus(
            missionSettings,
            launchSettings,
            secondsToLaunch,
            engineStarted,
            boostersIgnited,
            releaseTriggered,
            padReleased,
            commitTriggered,
            countdownHoldActive,
            operatorStatusText
        ).

        WriteVehicleBridgeStatus(
            missionSettings,
            launchSettings,
            "TERMINAL_COUNTDOWN",
            secondsToLaunch,
            engineStarted,
            boostersIgnited,
            releaseTriggered,
            padReleased,
            commitTriggered,
            countdownHoldActive,
            abortActive,
            operatorStatusText,
            wetDressEnabled,
            wetDressStopSeconds,
            wetDressHoldActive
        ).

        WAIT 0.1.
    }.

    IF launchClockStartSeconds < 0 {
        SET launchClockStartSeconds TO TIME:SECONDS.
    }.

    FlyAscentGuidance(missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest).
}.

FUNCTION WaitForTowerHandoff {
    PARAMETER missionSettings, launchSettings.

    LOCAL lastDisplayMode TO "".
    LOCAL lastRevision TO 0.

    UNTIL FALSE {
        LOCAL towerCommand TO ReadMccCommand(launchSettings["vehicle_id"], lastRevision).

        IF towerCommand["is_new_revision"] {
            SET lastRevision TO towerCommand["revision"].

            IF towerCommand["command_name"] = "tower_handoff" {
                LOCAL handoffContent TO BuildTowerHandoffContent(towerCommand, launchSettings).

                IF IsValidTowerHandoff(handoffContent) {
                    RETURN handoffContent.
                }.
            }.
        }.

        ClearScreenForMode("STANDBY", lastDisplayMode).
        SET lastDisplayMode TO "STANDBY".

        DrawLine("SLS MAIN", 0).
        DrawLine("Mode: STANDBY", 1).
        DrawLine("CPU Tag: " + CORE:TAG, 2).
        DrawLine("Expected Tag: " + launchSettings["vehicle_cpu_tag"], 3).
        DrawLine("Vehicle: " + SHIP:NAME, 4).
        DrawLine("Awaiting tower handoff message.          ", 5).
        WriteVehicleBridgeStatus(
            missionSettings,
            launchSettings,
            "STANDBY",
            -1,
            FALSE,
            FALSE,
            FALSE,
            FALSE,
            FALSE,
            FALSE,
            FALSE,
            "AWAITING TOWER HANDOFF",
            launchSettings["wet_dress_enabled"],
            launchSettings["wet_dress_stop_seconds"],
            FALSE
        ).
        WAIT 0.1.
    }.
}.

FUNCTION BuildTowerHandoffContent {
    PARAMETER towerCommand, launchSettings.

    LOCAL launchEpochSeconds TO -1.

    IF towerCommand["launch_epoch_seconds"] <> "" {
        SET launchEpochSeconds TO towerCommand["launch_epoch_seconds"].
    } ELSE IF towerCommand["countdown_seconds"] >= 0 {
        SET launchEpochSeconds TO TIME:SECONDS + towerCommand["countdown_seconds"].
    }.

    RETURN LEXICON(
        "message_type", "tower_handoff",
        "launch_epoch_seconds", launchEpochSeconds,
        "launch_node_longitude", 0
    ).
}.

FUNCTION IsValidTowerHandoff {
    PARAMETER handoffContent.

    IF NOT handoffContent:HASKEY("launch_epoch_seconds") {
        RETURN FALSE.
    }.

    // Ignore stale handoff messages left over from previous AG6/script runs,
    // but still allow a small catch-up window if the CPU starts slightly late.
    RETURN handoffContent["launch_epoch_seconds"] >= TIME:SECONDS - 2.
}.

FUNCTION DisplayVehicleStatus {
    PARAMETER missionSettings, launchSettings, secondsToLaunch, engineStarted, boostersIgnited, releaseTriggered, padReleased, commitTriggered, countdownHoldActive, operatorStatusText.

    LOCAL eventTimeDisplay TO ResolveVehicleEventTimeDisplay(secondsToLaunch, padReleased).
    LOCAL readinessSummaryText TO launchReadinessSnapshot["summary_text"].
    LOCAL readinessProfileText TO launchReadinessSnapshot["profile_text"].

    DrawLine("SLS MAIN", 0).
    DrawLine("Mode: TERMINAL COUNTDOWN", 1).
    DrawLine("Mission: " + missionSettings["mission_name"], 2).
    DrawLine("Target Body: " + missionSettings["target_body"], 3).
    DrawLine("Target Orbit: " + missionSettings["target_body_apoapsis"] + " / " + missionSettings["target_body_periapsis"], 4).
    DrawLine("Readiness: " + readinessSummaryText, 5).
    DrawLine("Delta-V Required: " + ROUND(launchReadinessSnapshot["required_delta_v_mps"], 0), 6).
    DrawLine("Delta-V Available: " + ROUND(launchReadinessSnapshot["available_delta_v_mps"], 0), 7).
    DrawLine("Profile: " + readinessProfileText, 8).
    DrawLine(eventTimeDisplay, 9).
    DrawLine("Engine Start At: T-" + launchSettings["engine_start_time_seconds"], 10).
    DrawLine("Release At: T-" + launchSettings["vehicle_release_time_seconds"], 11).
    DrawLine("Commit At: T-" + launchSettings["liftoff_commit_time_seconds"], 12).
    DrawLine("Engines Started: " + engineStarted, 13).
    DrawLine("Boosters Ignited: " + boostersIgnited, 14).
    DrawLine("Release Attempted: " + releaseTriggered, 15).
    DrawLine("Pad Released: " + padReleased, 16).
    DrawLine("Liftoff Commit: " + commitTriggered, 17).
    DrawLine("Count Hold: " + countdownHoldActive, 18).
    DrawLine("Operator: " + operatorStatusText, 19).
}. 

FUNCTION ValidateStandaloneCountdown {
    PARAMETER countdownString, missionSettings.

    LOCAL parts TO countdownString:SPLIT(":").

    IF parts:LENGTH <> 3 {
        RETURN LEXICON("is_valid", FALSE, "countdown_seconds", 0, "message", "Manual countdown must be HH:MM:SS.").
    }.

    LOCAL hoursValue TO parts[0]:TONUMBER.
    LOCAL minutesValue TO parts[1]:TONUMBER.
    LOCAL secondsValue TO parts[2]:TONUMBER.
    LOCAL totalSeconds TO (hoursValue * 3600) + (minutesValue * 60) + secondsValue.

    IF totalSeconds < missionSettings["manual_countdown_min_seconds"] {
        RETURN LEXICON(
            "is_valid", FALSE,
            "countdown_seconds", 0,
            "message", "Manual countdown must be at least " + FormatCountdown(missionSettings["manual_countdown_min_seconds"]) + "."
        ).
    }.

    RETURN LEXICON("is_valid", TRUE, "countdown_seconds", totalSeconds, "message", "").
}.

FUNCTION ShowStandaloneHold {
    PARAMETER messageText.

    CLEARSCREEN.
    DrawLine("SLS MAIN", 0).
    DrawLine("Mode: HOLD", 1).
    DrawLine(messageText, 2).
}.

FUNCTION ApplyVehicleOperatorCommand {
    PARAMETER operatorCommand, launchEpochSeconds, countdownHoldActive, abortActive, heldCountdownSeconds, engineStarted, releaseTriggered.

    LOCAL commandName TO operatorCommand["command_name"].
    LOCAL updatedLaunchEpochSeconds TO launchEpochSeconds.
    LOCAL updatedHoldActive TO countdownHoldActive.
    LOCAL updatedAbortActive TO abortActive.
    LOCAL updatedHeldCountdownSeconds TO heldCountdownSeconds.
    LOCAL operatorStatusText TO "READY".
    LOCAL isLockedOut TO engineStarted OR releaseTriggered.

    IF commandName = "hold" {
        IF isLockedOut {
            SET operatorStatusText TO "HOLD REJECTED AFTER ENGINE START".
        } ELSE {
            SET updatedHoldActive TO TRUE.
            SET updatedHeldCountdownSeconds TO MAX(0, launchEpochSeconds - TIME:SECONDS).
            SET operatorStatusText TO "HOLD ACCEPTED".
        }.
    } ELSE IF commandName = "resume" {
        IF countdownHoldActive {
            SET updatedLaunchEpochSeconds TO TIME:SECONDS + heldCountdownSeconds.
        }.
        SET updatedHoldActive TO FALSE.
        SET operatorStatusText TO "COUNT RESUMED".
    } ELSE IF commandName = "set_countdown" {
        IF isLockedOut {
            SET operatorStatusText TO "COUNT CHANGE REJECTED AFTER ENGINE START".
        } ELSE IF operatorCommand["countdown_seconds"] < 0 {
            SET operatorStatusText TO "INVALID COUNT REQUEST".
        } ELSE {
            IF countdownHoldActive {
                SET updatedHeldCountdownSeconds TO operatorCommand["countdown_seconds"].
            } ELSE {
                SET updatedLaunchEpochSeconds TO TIME:SECONDS + operatorCommand["countdown_seconds"].
            }.

            SET operatorStatusText TO "COUNT SET TO " + FormatCountdown(operatorCommand["countdown_seconds"]).
        }.
    } ELSE IF commandName = "abort" {
        SET updatedAbortActive TO TRUE.
        SET operatorStatusText TO "ABORT ISSUED".
    }.

    RETURN LEXICON(
        "launch_epoch_seconds", updatedLaunchEpochSeconds,
        "countdown_hold_active", updatedHoldActive,
        "abort_active", updatedAbortActive,
        "held_countdown_seconds", updatedHeldCountdownSeconds,
        "operator_status_text", operatorStatusText
    ).
}.

FUNCTION WriteVehicleBridgeStatus {
    PARAMETER missionSettings, launchSettings, modeName, secondsToLaunch, engineStarted, boostersIgnited, releaseTriggered, padReleased, commitTriggered, countdownHoldActive, abortActive, operatorStatusText, wetDressEnabled, wetDressStopSeconds, wetDressHoldActive.

    LOCAL eventTimeDisplay TO ResolveVehicleEventTimeDisplay(secondsToLaunch, padReleased).
    LOCAL missionElapsedSeconds TO GetLaunchElapsedSeconds().
    LOCAL wetDressStatusText TO "DISABLED".

    IF wetDressEnabled {
        IF wetDressHoldActive {
            SET wetDressStatusText TO "WET DRESS HOLD".
        } ELSE {
            SET wetDressStatusText TO "WET DRESS ARMED TO T-" + FormatCountdown(wetDressStopSeconds).
        }.
    }.

    WriteMccVehicleStatus(
        LEXICON(
            "source", "vehicle",
            "vehicle_id", launchSettings["vehicle_id"],
            "mission_name", missionSettings["mission_name"],
            "mode", modeName,
            "ship_name", SHIP:NAME,
            "altitude", ROUND(SHIP:ALTITUDE, 2),
            "vertical_speed", ROUND(SHIP:VERTICALSPEED, 2),
            "apoapsis", ROUND(SHIP:APOAPSIS, 2),
            "periapsis", ROUND(SHIP:PERIAPSIS, 2),
            "current_thrust", ROUND(SHIP:THRUST, 2),
            "available_thrust", ROUND(SHIP:AVAILABLETHRUST, 2),
            "countdown_seconds", ROUND(MAX(0, secondsToLaunch), 1),
            "formatted_countdown", FormatCountdown(secondsToLaunch),
            "mission_elapsed_seconds", ROUND(missionElapsedSeconds, 1),
            "formatted_event_time", eventTimeDisplay,
            "engine_started", engineStarted,
            "boosters_ignited", boostersIgnited,
            "release_attempted", releaseTriggered,
            "pad_released", padReleased,
            "liftoff_commit", commitTriggered,
            "countdown_hold_active", countdownHoldActive,
            "abort_active", abortActive,
            "operator_status_text", operatorStatusText,
            "wet_dress_enabled", wetDressEnabled,
            "wet_dress_stop_seconds", wetDressStopSeconds,
            "wet_dress_stop_time", FormatCountdown(wetDressStopSeconds),
            "wet_dress_hold_active", wetDressHoldActive,
            "wet_dress_status_text", wetDressStatusText,
            "readiness_status_text", launchReadinessSnapshot["readiness_state"],
            "readiness_summary_text", launchReadinessSnapshot["summary_text"],
            "readiness_profile_text", launchReadinessSnapshot["profile_text"],
            "readiness_stage_breakdown_text", launchReadinessSnapshot["stage_breakdown_text"],
            "readiness_available_delta_v_mps", ROUND(launchReadinessSnapshot["available_delta_v_mps"], 1),
            "readiness_required_delta_v_mps", ROUND(launchReadinessSnapshot["required_delta_v_mps"], 1),
            "readiness_delta_v_margin_mps", ROUND(launchReadinessSnapshot["delta_v_margin_mps"], 1),
            "readiness_liftoff_twr", ROUND(launchReadinessSnapshot["liftoff_twr"], 2),
            "readiness_target_orbit_speed_mps", ROUND(launchReadinessSnapshot["target_orbit_speed_mps"], 1),
            "readiness_launch_losses_mps", ROUND(launchReadinessSnapshot["launch_losses_mps"], 1),
            "updated_at", TIME:SECONDS
        )
    ).
}.

FUNCTION WriteLaunchRuleCheckStatus {
    PARAMETER missionSettings, launchSettings, readinessSettings, resolvedManifest, secondsToLaunch, engineStarted, boostersIgnited, releaseTriggered, padReleased, commitTriggered, countdownHoldActive, abortActive, operatorStatusText, gateRequired, gateTriggered.

    LOCAL readinessState TO launchReadinessSnapshot["readiness_state"].
    LOCAL manifestValid TO ValidateResolvedManifest(resolvedManifest).
    LOCAL deltaVMarginOk TO launchReadinessSnapshot["delta_v_margin_mps"] >= 0.
    LOCAL liftoffTwrOk TO launchReadinessSnapshot["liftoff_twr"] >= readinessSettings["minimum_liftoff_twr"].
    LOCAL vehicleReady TO readinessState = "GO".
    LOCAL allRulesMet TO manifestValid AND vehicleReady AND deltaVMarginOk AND liftoffTwrOk AND NOT countdownHoldActive AND NOT abortActive.
    LOCAL gateStatus TO "NOT_REQUIRED".
    LOCAL gateResultText TO "T-60 launch rule check is not required for this countdown.".

    IF gateRequired {
        IF gateTriggered {
            SET gateStatus TO "PASS".
            SET gateResultText TO "T-60 launch rules met.".
            IF NOT allRulesMet {
                SET gateStatus TO "FAIL".
                SET gateResultText TO "T-60 launch rules not fully met.".
            }.
        } ELSE {
            SET gateStatus TO "PENDING".
            SET gateResultText TO "Awaiting the T-60 launch rule check.".
        }.
    }.

    WriteMccLaunchRuleCheck(
        LEXICON(
            "source", "launch_rule_check",
            "vehicle_id", launchSettings["vehicle_id"],
            "mission_name", missionSettings["mission_name"],
            "status", gateStatus,
            "gate_required", gateRequired,
            "gate_triggered", gateTriggered,
            "countdown_seconds", ROUND(MAX(0, secondsToLaunch), 1),
            "formatted_countdown", FormatCountdown(secondsToLaunch),
            "gate_result_text", gateResultText,
            "readiness_status_text", readinessState,
            "readiness_summary_text", launchReadinessSnapshot["summary_text"],
            "readiness_profile_text", launchReadinessSnapshot["profile_text"],
            "readiness_stage_breakdown_text", launchReadinessSnapshot["stage_breakdown_text"],
            "readiness_available_delta_v_mps", ROUND(launchReadinessSnapshot["available_delta_v_mps"], 1),
            "readiness_required_delta_v_mps", ROUND(launchReadinessSnapshot["required_delta_v_mps"], 1),
            "readiness_delta_v_margin_mps", ROUND(launchReadinessSnapshot["delta_v_margin_mps"], 1),
            "readiness_liftoff_twr", ROUND(launchReadinessSnapshot["liftoff_twr"], 2),
            "readiness_target_orbit_speed_mps", ROUND(launchReadinessSnapshot["target_orbit_speed_mps"], 1),
            "readiness_launch_losses_mps", ROUND(launchReadinessSnapshot["launch_losses_mps"], 1),
            "manifest_valid", manifestValid,
            "countdown_hold_active", countdownHoldActive,
            "abort_active", abortActive,
            "engine_started", engineStarted,
            "boosters_ignited", boostersIgnited,
            "release_attempted", releaseTriggered,
            "pad_released", padReleased,
            "liftoff_commit", commitTriggered,
            "readiness_go", vehicleReady,
            "delta_v_margin_ok", deltaVMarginOk,
            "liftoff_twr_ok", liftoffTwrOk,
            "all_rules_met", allRulesMet,
            "operator_status_text", operatorStatusText,
            "updated_at", TIME:SECONDS
        )
    ).
}.

FUNCTION ResolveVehicleEventTimeDisplay {
    PARAMETER secondsToLaunch, padReleased.

    IF padReleased AND launchClockStartSeconds >= 0 {
        RETURN FormatMissionTime(GetLaunchElapsedSeconds()).
    }.

    RETURN FormatCountdown(secondsToLaunch).
}.

FUNCTION GetLaunchElapsedSeconds {
    IF launchClockStartSeconds < 0 {
        RETURN 0.
    }.

    RETURN MAX(0, TIME:SECONDS - launchClockStartSeconds).
}.

FUNCTION InitializeCountdownState {
    PARAMETER launchSettings.

    LOCAL vehicleAirborne TO SHIP:ALTITUDE > launchSettings["tower_clear_altitude"] OR SHIP:VERTICALSPEED > 5.
    LOCAL engineStarted TO SHIP:THRUST > 1.
    LOCAL padReleased TO vehicleAirborne.
    LOCAL releaseTriggered TO vehicleAirborne.
    LOCAL boostersIgnited TO vehicleAirborne.
    LOCAL commitTriggered TO vehicleAirborne.

    RETURN LEXICON(
        "engine_started", engineStarted,
        "boosters_ignited", boostersIgnited,
        "release_triggered", releaseTriggered,
        "pad_released", padReleased,
        "commit_triggered", commitTriggered,
        "vehicle_airborne", vehicleAirborne
    ).
}.

FUNCTION ConfigureSteeringManager {
    PARAMETER ascentSettings.

    SET STEERINGMANAGER:ROLLTS TO ascentSettings["steering_roll_ts"].
    SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.
}.

FUNCTION EnsureGuidanceAuthority {
    ApplyPreferredGuidanceControlReference().
    SAS OFF.
    RCS OFF.
}.

FUNCTION ApplyPreferredGuidanceControlReference {
    IF TrySetBestGuidanceControlReference() {
        RETURN.
    }.

    IF TrySetGuidanceControlReference(SHIP:CONTROLPART) {
        RETURN.
    }.

    IF TrySetGuidanceControlReference(CORE:PART) {
        RETURN.
    }.
}.

FUNCTION TrySetBestGuidanceControlReference {
    LOCAL bestPriority TO -1.
    LOCAL bestScore TO -999999999.
    LOCAL bestPart TO SHIP:ROOTPART.
    LOCAL foundBestPart TO FALSE.

    FOR candidatePart IN SHIP:PARTS {
        LOCAL candidatePriority TO GetGuidanceControlPriority(candidatePart).

        IF candidatePriority >= 0 {
            LOCAL candidateScore TO VDOT(candidatePart:POSITION, UP:VECTOR).

            IF NOT foundBestPart OR candidatePriority > bestPriority OR (candidatePriority = bestPriority AND candidateScore > bestScore) {
                SET bestPart TO candidatePart.
                SET bestPriority TO candidatePriority.
                SET bestScore TO candidateScore.
                SET foundBestPart TO TRUE.
            }.
        }.
    }.

    IF foundBestPart {
        bestPart:CONTROLFROM.
        RETURN TRUE.
    }.

    RETURN FALSE.
}.

FUNCTION GetGuidanceControlPriority {
    PARAMETER candidatePart.

    IF candidatePart:TITLE = "Orion Capsule" OR candidatePart:TITLE = "Orion Crew Module" {
        RETURN 4.
    }.

    IF candidatePart:TITLE = "Orion Docking Port" OR candidatePart:TITLE = "Orion Service Module" {
        RETURN 3.
    }.

    IF candidatePart:HASMODULE("ModuleCommand") {
        RETURN 2.
    }.

    IF candidatePart:HASMODULE("ModuleDockingNode") {
        RETURN 1.
    }.

    RETURN -1.
}.

FUNCTION TrySetGuidanceControlReference {
    PARAMETER candidatePart.

    IF candidatePart:HASMODULE("ModuleCommand") OR candidatePart:HASMODULE("ModuleDockingNode") {
        candidatePart:CONTROLFROM.
        RETURN TRUE.
    }.

    RETURN FALSE.
}.

FUNCTION ExecutePadRelease {
    PARAMETER resolvedManifest.

    ExecuteManifestGroup(resolvedManifest["launch_clamps"]).
    ExecuteManifestGroup(resolvedManifest["hold_down_release"]).
}.

FUNCTION IsPadReleaseConfirmed {
    PARAMETER launchSettings.

    RETURN SHIP:VERTICALSPEED >= launchSettings["release_confirm_vertical_speed"] OR SHIP:ALTITUDE > 1.
}.

FUNCTION AbortLaunch {
    PARAMETER messageText.

    LOCK THROTTLE TO 0.
    UNLOCK STEERING.
    SAS ON.
    CLEARSCREEN.

    UNTIL FALSE {
        DrawLine("SLS MAIN", 0).
        DrawLine("Mode: ABORT", 1).
        DrawLine(messageText, 2).
        DrawLine("Altitude: " + ROUND(SHIP:ALTITUDE, 1), 3).
        DrawLine("Vertical Speed: " + ROUND(SHIP:VERTICALSPEED, 2), 4).
        WAIT 0.5.
    }.
}.

FUNCTION RunStageSeparation {
    PARAMETER missionSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest, stageOneCutoffReason.

    LOCAL separationDelay TO stagingSettings["upper_stage_ignition_delay"].
    LOCAL settleTime TO stagingSettings["upper_stage_settle_time"].
    LOCAL upperStageEngineCount TO resolvedManifest["upper_stage_engines"]["parts"]:LENGTH.
    LOCAL lastDisplayMode TO "".
    LOCAL separationTime TO TIME:SECONDS + separationDelay.
    LOCAL ignitionTime TO separationTime + settleTime.
    LOCAL preSeparationAttitude TO SHIP:FACING.

    LOCK STEERING TO preSeparationAttitude.

    UNTIL TIME:SECONDS >= separationTime {
        ClearScreenForMode("STAGE SEPARATION", lastDisplayMode).
        SET lastDisplayMode TO "STAGE SEPARATION".

        DrawLine("SLS MAIN", 0).
        DrawLine("Mode: STAGE SEPARATION", 1).
        DrawLine("Mission: " + missionSettings["mission_name"], 2).
        DrawLine("Target Body: " + missionSettings["target_body"], 3).
        DrawLine("Stage 1 Complete: TRUE", 4).
        DrawLine("Reason: " + stageOneCutoffReason, 5).
        DrawLine("Attitude: PRE-SEP HOLD", 6).
        DrawLine("Interstage Sep In: " + ROUND(separationTime - TIME:SECONDS, 1), 7).
        DrawLine("Upper Stage Engines: " + upperStageEngineCount, 8).
        DrawLine("Ignition In: T+" + ROUND(ignitionTime - TIME:SECONDS, 1), 9).
        DrawLine("Apoapsis: " + ROUND(SHIP:APOAPSIS, 0), 10).
        DrawLine("Periapsis: " + ROUND(SHIP:PERIAPSIS, 0), 11).
        WAIT 0.1.
    }.

    ActivateUpperStageRcs(resolvedManifest).
    ExecuteManifestGroup(resolvedManifest["core_stage_separation_motors"]).
    WAIT 0.25.
    ExecuteManifestGroup(resolvedManifest["core_stage_separation"]).
    ActivateUpperStageRcs(resolvedManifest).
    ApplyPreferredGuidanceControlReference().
    RCS ON.
    LOCK STEERING TO PROGRADE.

    UNTIL TIME:SECONDS >= ignitionTime {
        ClearScreenForMode("STAGE SEPARATION", lastDisplayMode).
        SET lastDisplayMode TO "STAGE SEPARATION".

        DrawLine("SLS MAIN", 0).
        DrawLine("Mode: STAGE SEPARATION", 1).
        DrawLine("Mission: " + missionSettings["mission_name"], 2).
        DrawLine("Target Body: " + missionSettings["target_body"], 3).
        DrawLine("Stage 1 Complete: TRUE", 4).
        DrawLine("Reason: " + stageOneCutoffReason, 5).
        DrawLine("Attitude: PROGRADE", 6).
        DrawLine("Interstage: SEPARATED", 7).
        DrawLine("Upper Stage RCS: ON", 8).
        DrawLine("Ignition In: T+" + ROUND(ignitionTime - TIME:SECONDS, 1), 9).
        DrawLine("Apoapsis: " + ROUND(SHIP:APOAPSIS, 0), 10).
        DrawLine("Periapsis: " + ROUND(SHIP:PERIAPSIS, 0), 11).
        WAIT 0.1.
    }.

    FlyUpperStageGuidanceSequence(missionSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest).
}.

FUNCTION ActivateUpperStageRcs {
    PARAMETER resolvedManifest.

    // Re-apply the module-level RCS enable path around separation so the
    // upper stage has working jets as soon as it becomes the active vessel.
    FOR upperStagePart IN resolvedManifest["upper_stage_rcs_hardware"]["parts"] {
        EnablePartRcsModules(upperStagePart).
    }.
}.

FUNCTION EnablePartRcsModules {
    PARAMETER part.

    FOR availableModuleName IN part:MODULES {
        IF availableModuleName = "ModuleRCS" OR availableModuleName = "ModuleRCSFX" {
            LOCAL availableModule TO part:GETMODULE(availableModuleName).

            // Prefer the tweakable field path exposed by the module. This matches
            // the live module interface the vehicle exposes in flight.
            IF availableModule:HASFIELD("rcs") {
                availableModule:SETFIELD("rcs", TRUE).
            } ELSE IF availableModule:HASFIELD("RCS") {
                availableModule:SETFIELD("RCS", TRUE).
            }.

            IF availableModule:HASACTION("toggle rcs thrust") {
                availableModule:DOACTION("toggle rcs thrust", TRUE).
            } ELSE IF availableModule:HASACTION("Toggle RCS Thrust") {
                availableModule:DOACTION("Toggle RCS Thrust", TRUE).
            } ELSE IF availableModule:HASACTION("RCS") {
                availableModule:DOACTION("RCS", TRUE).
            } ELSE IF availableModule:HASEVENT("RCS") {
                availableModule:DOEVENT("RCS").
            } ELSE IF availableModule:HASEVENT("Activate") {
                availableModule:DOEVENT("Activate").
            } ELSE IF availableModule:HASEVENT("Enable") {
                availableModule:DOEVENT("Enable").
            } ELSE IF availableModule:HASACTION("Activate") {
                availableModule:DOACTION("Activate", TRUE).
            } ELSE IF availableModule:HASACTION("ToggleAction") {
                availableModule:DOACTION("ToggleAction", TRUE).
            }.
        }.
    }.
}.

FUNCTION EvaluateCoreIgnitionHealth {
    PARAMETER resolvedManifest, stagingSettings, launchSettings.

    LOCAL nominalCoreEngines TO resolvedManifest["core_engines"]["parts"]:LENGTH.
    LOCAL activeCoreEngines TO GetActiveCoreEngineCount(resolvedManifest, stagingSettings).
    LOCAL thrustRatio TO GetShipThrustRatio().
    LOCAL ignitionNominal TO activeCoreEngines >= nominalCoreEngines AND thrustRatio >= launchSettings["core_engine_start_min_thrust_ratio"].
    LOCAL statusMessage TO "CORE ENGINES NOMINAL".

    IF activeCoreEngines < nominalCoreEngines {
        SET statusMessage TO "ABORT: CORE IGNITION FAIL " + activeCoreEngines + "/" + nominalCoreEngines.
    } ELSE IF thrustRatio < launchSettings["core_engine_start_min_thrust_ratio"] {
        SET statusMessage TO "ABORT: CORE THRUST LOW " + ROUND(thrustRatio * 100, 0) + "%".
    }.

    RETURN LEXICON(
        "is_nominal", ignitionNominal,
        "message", statusMessage,
        "active_core_engines", activeCoreEngines,
        "thrust_ratio", thrustRatio
    ).
}.

FUNCTION EvaluateLiftoffHealth {
    PARAMETER resolvedManifest, stagingSettings, launchSettings.

    LOCAL nominalCoreEngines TO resolvedManifest["core_engines"]["parts"]:LENGTH.
    LOCAL activeCoreEngines TO GetActiveCoreEngineCount(resolvedManifest, stagingSettings).
    LOCAL thrustRatio TO GetShipThrustRatio().
    LOCAL liftoffNominal TO activeCoreEngines >= nominalCoreEngines AND thrustRatio >= launchSettings["liftoff_min_thrust_ratio"].
    LOCAL statusMessage TO "LIFTOFF THRUST NOMINAL".

    IF activeCoreEngines < nominalCoreEngines {
        SET statusMessage TO "ABORT: CORE ENGINE OUT AT LIFTOFF".
    } ELSE IF thrustRatio < launchSettings["liftoff_min_thrust_ratio"] {
        SET statusMessage TO "ABORT: LIFTOFF THRUST LOW " + ROUND(thrustRatio * 100, 0) + "%".
    }.

    RETURN LEXICON(
        "is_nominal", liftoffNominal,
        "message", statusMessage,
        "active_core_engines", activeCoreEngines,
        "thrust_ratio", thrustRatio
    ).
}.

FUNCTION GetShipThrustRatio {
    IF SHIP:MAXTHRUST <= 0 {
        RETURN 0.
    }.

    RETURN ClampValue(SHIP:THRUST / SHIP:MAXTHRUST, 0, 1.25).
}.

FUNCTION BuildLaunchReadinessReport {
    PARAMETER missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, readinessSettings, resolvedManifest.

    LOCAL stageBreakdown TO BuildLaunchStageDeltaVBreakdown(resolvedManifest).
    LOCAL orbitEstimate TO EstimateOrbitInsertionDeltaV(missionSettings, orbitSettings, readinessSettings).
    LOCAL availableDeltaV TO stageBreakdown["total_delta_v_mps"].
    LOCAL requiredDeltaV TO orbitEstimate["required_delta_v_mps"].
    LOCAL deltaVMargin TO availableDeltaV - requiredDeltaV.
    LOCAL liftoffTwr TO EstimateLaunchTwr(resolvedManifest).
    LOCAL readinessState TO "GO".
    LOCAL readinessSummary TO "GO: " + ROUND(deltaVMargin, 0) + " m/s Δv margin, liftoff TWR " + ROUND(liftoffTwr, 2) + ".".

    IF liftoffTwr < readinessSettings["minimum_liftoff_twr"] {
        SET readinessState TO "NO-GO".
        SET readinessSummary TO "NO-GO: liftoff TWR " + ROUND(liftoffTwr, 2) + " below " + readinessSettings["minimum_liftoff_twr"] + ".".
    } ELSE IF deltaVMargin < 0 {
        SET readinessState TO "NO-GO".
        SET readinessSummary TO "NO-GO: Δv short by " + ROUND(ABS(deltaVMargin), 0) + " m/s.".
    } ELSE IF deltaVMargin < readinessSettings["watch_delta_v_margin_mps"] {
        SET readinessState TO "WATCH".
        SET readinessSummary TO "WATCH: only " + ROUND(deltaVMargin, 0) + " m/s Δv margin, liftoff TWR " + ROUND(liftoffTwr, 2) + ".".
    }.

    RETURN LEXICON(
        "readiness_state", readinessState,
        "summary_text", readinessSummary,
        "profile_text", BuildFlightProfileSummary(launchSettings, ascentSettings, orbitSettings, stagingSettings),
        "stage_breakdown_text", stageBreakdown["stage_breakdown_text"],
        "available_delta_v_mps", availableDeltaV,
        "required_delta_v_mps", requiredDeltaV,
        "delta_v_margin_mps", deltaVMargin,
        "liftoff_twr", liftoffTwr,
        "booster_delta_v_mps", stageBreakdown["booster_delta_v_mps"],
        "core_delta_v_mps", stageBreakdown["core_delta_v_mps"],
        "upper_delta_v_mps", stageBreakdown["upper_delta_v_mps"],
        "target_orbit_speed_mps", orbitEstimate["target_orbit_speed_mps"],
        "launch_losses_mps", orbitEstimate["launch_losses_mps"]
    ).
}.

FUNCTION BuildLaunchStageDeltaVBreakdown {
    PARAMETER resolvedManifest.

    LOCAL remainingMassKg TO SHIP:MASS * 1000.
    LOCAL boosterParts TO resolvedManifest["booster_engines"]["parts"].
    LOCAL coreParts TO LIST().
    LOCAL upperParts TO LIST().

    AppendPartList(coreParts, resolvedManifest["core_engines"]["parts"]).
    AppendPartList(coreParts, resolvedManifest["core_stage_propellant_tanks"]["parts"]).
    AppendPartList(upperParts, resolvedManifest["upper_stage_engines"]["parts"]).
    AppendPartList(upperParts, resolvedManifest["upper_stage_rcs_hardware"]["parts"]).

    LOCAL boosterReport TO BuildStageReadinessReport("BOOSTERS", boosterParts, resolvedManifest["booster_engines"]["parts"], remainingMassKg, 0.92).
    SET remainingMassKg TO boosterReport["post_stage_mass_kg"].

    LOCAL coreReport TO BuildStageReadinessReport("CORE", coreParts, resolvedManifest["core_engines"]["parts"], remainingMassKg, 0.96).
    SET remainingMassKg TO coreReport["post_stage_mass_kg"].

    LOCAL upperReport TO BuildStageReadinessReport("UPPER", upperParts, resolvedManifest["upper_stage_engines"]["parts"], remainingMassKg, 1.0).

    RETURN LEXICON(
        "booster_delta_v_mps", boosterReport["delta_v_mps"],
        "core_delta_v_mps", coreReport["delta_v_mps"],
        "upper_delta_v_mps", upperReport["delta_v_mps"],
        "total_delta_v_mps", boosterReport["delta_v_mps"] + coreReport["delta_v_mps"] + upperReport["delta_v_mps"],
        "stage_breakdown_text", boosterReport["summary_text"] + " | " + coreReport["summary_text"] + " | " + upperReport["summary_text"]
    ).
}.

FUNCTION BuildStageReadinessReport {
    PARAMETER stageName, stageParts, engineParts, stageStartMassKg, stageEfficiencyFactor.

    LOCAL massSummary TO GetStageMassSummary(stageParts, engineParts).
    LOCAL effectiveIspSeconds TO GetStageEffectiveIsp(engineParts) * stageEfficiencyFactor.
    LOCAL stageBurnTimeSeconds TO GetStageBurnTimeEstimate(engineParts, massSummary["propellant_mass_kg"]).
    LOCAL stageEndMassKg TO stageStartMassKg - massSummary["propellant_mass_kg"].
    LOCAL stageDeltaV TO 0.

    IF stageStartMassKg > 0 AND stageEndMassKg > 0 AND stageStartMassKg > stageEndMassKg {
        SET stageDeltaV TO effectiveIspSeconds * CONSTANT:g0 * LN(stageStartMassKg / stageEndMassKg).
    }.

    RETURN LEXICON(
        "stage_name", stageName,
        "delta_v_mps", stageDeltaV,
        "burn_time_seconds", stageBurnTimeSeconds,
        "total_mass_kg", massSummary["total_mass_kg"],
        "propellant_mass_kg", massSummary["propellant_mass_kg"],
        "dry_mass_kg", massSummary["dry_mass_kg"],
        "post_stage_mass_kg", MAX(0, stageEndMassKg - massSummary["dry_mass_kg"]),
        "summary_text", stageName + ": " + ROUND(stageDeltaV, 0) + " m/s / " + ROUND(stageBurnTimeSeconds, 0) + " s burn"
    ).
}.

FUNCTION GetStageMassSummary {
    PARAMETER stageParts, engineParts.

    LOCAL totalMassKg TO 0.
    LOCAL propellantMassKg TO 0.
    LOCAL propellantNames TO GetPropellantNamesFromParts(engineParts).

    FOR stagePart IN stageParts {
        SET totalMassKg TO totalMassKg + (stagePart:MASS * 1000).

        FOR resourceItem IN stagePart:RESOURCES {
            IF propellantNames:CONTAINS(resourceItem:NAME) {
                SET propellantMassKg TO propellantMassKg + (resourceItem:AMOUNT * resourceItem:DENSITY * 1000).
            }.
        }.
    }.

    IF propellantMassKg > totalMassKg {
        SET propellantMassKg TO totalMassKg.
    }.

    RETURN LEXICON(
        "total_mass_kg", totalMassKg,
        "propellant_mass_kg", propellantMassKg,
        "dry_mass_kg", MAX(0, totalMassKg - propellantMassKg)
    ).
}.

FUNCTION GetStageEffectiveIsp {
    PARAMETER engineParts.

    LOCAL totalThrustN TO 0.
    LOCAL totalMassFlowKgPerSec TO 0.

    FOR enginePart IN engineParts {
        LOCAL partMassFlowKgPerSec TO enginePart:MAXMASSFLOW * 1000.

        IF partMassFlowKgPerSec > 0 {
            SET totalMassFlowKgPerSec TO totalMassFlowKgPerSec + partMassFlowKgPerSec.
            SET totalThrustN TO totalThrustN + (enginePart:AVAILABLETHRUSTAT(0) * 1000).
        }.
    }.

    IF totalMassFlowKgPerSec <= 0 {
        RETURN 0.
    }.

    RETURN totalThrustN / (totalMassFlowKgPerSec * CONSTANT:g0).
}.

FUNCTION GetStageBurnTimeEstimate {
    PARAMETER engineParts, propellantMassKg.

    LOCAL totalMassFlowKgPerSec TO 0.

    FOR enginePart IN engineParts {
        SET totalMassFlowKgPerSec TO totalMassFlowKgPerSec + (enginePart:MAXMASSFLOW * 1000).
    }.

    IF totalMassFlowKgPerSec <= 0 {
        RETURN 0.
    }.

    RETURN propellantMassKg / totalMassFlowKgPerSec.
}.

FUNCTION GetPropellantNamesFromParts {
    PARAMETER engineParts.

    LOCAL propellantNames TO LIST().

    FOR enginePart IN engineParts {
        FOR resourceName IN enginePart:CONSUMEDRESOURCES:KEYS {
            IF NOT propellantNames:CONTAINS(resourceName) {
                propellantNames:ADD(resourceName).
            }.
        }.
    }.

    RETURN propellantNames.
}.

FUNCTION AppendPartList {
    PARAMETER destinationParts, sourceParts.

    FOR sourcePart IN sourceParts {
        destinationParts:ADD(sourcePart).
    }.
}.

FUNCTION EstimateOrbitInsertionDeltaV {
    PARAMETER missionSettings, orbitSettings, readinessSettings.

    LOCAL launchBody TO SHIP:BODY.
    LOCAL targetPeriapsisRadius TO launchBody:RADIUS + orbitSettings["target_periapsis"].
    LOCAL targetApoapsisRadius TO launchBody:RADIUS + orbitSettings["target_apoapsis"].
    LOCAL targetSemiMajorAxis TO (targetPeriapsisRadius + targetApoapsisRadius) / 2.
    LOCAL targetOrbitSpeed TO SQRT(launchBody:MU * (2 / targetPeriapsisRadius - 1 / targetSemiMajorAxis)).
    LOCAL launchLosses TO EstimateLaunchLosses(missionSettings, readinessSettings).

    RETURN LEXICON(
        "target_orbit_speed_mps", targetOrbitSpeed,
        "launch_losses_mps", launchLosses,
        "required_delta_v_mps", targetOrbitSpeed + launchLosses
    ).
}.

FUNCTION EstimateLaunchLosses {
    PARAMETER missionSettings, readinessSettings.

    LOCAL atmosphereFraction TO 0.

    IF readinessSettings["launch_loss_atmosphere_reference_height_m"] > 0 {
        SET atmosphereFraction TO ClampValue(
            SHIP:BODY:ATM:HEIGHT / readinessSettings["launch_loss_atmosphere_reference_height_m"],
            0,
            1
        ).
    }.

    LOCAL launchLosses TO LerpValue(
        readinessSettings["launch_loss_floor_mps"],
        readinessSettings["launch_loss_ceiling_mps"],
        atmosphereFraction
    ).

    RETURN launchLosses + (ABS(missionSettings["target_inclination"]) * 2).
}.

FUNCTION EstimateLaunchTwr {
    PARAMETER resolvedManifest.

    LOCAL launchThrustN TO GetLaunchThrustEstimate(resolvedManifest) * 0.92.
    LOCAL shipWeightN TO (SHIP:MASS * 1000) * CONSTANT:g0.

    IF shipWeightN <= 0 {
        RETURN 0.
    }.

    RETURN launchThrustN / shipWeightN.
}.

FUNCTION GetLaunchThrustEstimate {
    PARAMETER resolvedManifest.

    LOCAL thrustN TO 0.

    FOR boosterEnginePart IN resolvedManifest["booster_engines"]["parts"] {
        SET thrustN TO thrustN + (boosterEnginePart:AVAILABLETHRUSTAT(0) * 1000).
    }.

    FOR coreEnginePart IN resolvedManifest["core_engines"]["parts"] {
        SET thrustN TO thrustN + (coreEnginePart:AVAILABLETHRUSTAT(0) * 1000).
    }.

    RETURN thrustN.
}.

FUNCTION BuildFlightProfileSummary {
    PARAMETER launchSettings, ascentSettings, orbitSettings, stagingSettings.

    RETURN "Vertical hold to " + launchSettings["post_liftoff_pitch_hold"] + " deg, pitchover " +
        ascentSettings["pitchover_start_altitude"] + "-" + ascentSettings["pitchover_end_altitude"] +
        " m, gravity turn to " + ascentSettings["gravity_turn_final_pitch"] + " deg by " +
        ascentSettings["gravity_turn_end_altitude"] + " m, max-Q cap " +
        ROUND(ascentSettings["max_q_throttle_limit"] * 100, 0) + "%, handoff near " +
        ROUND(GetStageOneHandoffApoapsis(orbitSettings), 0) + " m, upper-stage settle " +
        stagingSettings["upper_stage_settle_time"] + " s, circularization to " +
        ROUND(orbitSettings["target_apoapsis"], 0) + " x " + ROUND(orbitSettings["target_periapsis"], 0) + " m.".
}.

FUNCTION LerpValue {
    PARAMETER startValue, endValue, blendFraction.

    RETURN startValue + ((endValue - startValue) * ClampValue(blendFraction, 0, 1)).
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

FUNCTION ShapeAscentBlend {
    PARAMETER rawFraction, curveExponent.

    LOCAL clampedFraction TO ClampValue(rawFraction, 0, 1).

    IF clampedFraction <= 0 {
        RETURN 0.
    }.

    IF clampedFraction >= 1 {
        RETURN 1.
    }.

    RETURN clampedFraction ^ curveExponent.
}.

FUNCTION IgniteUpperStageEngines {
    PARAMETER resolvedManifest.

    IF GetActiveUpperStageEngineCount(resolvedManifest) > 0 {
        RETURN.
    }.

    FOR upperStageEnginePart IN resolvedManifest["upper_stage_engines"]["parts"] {
        ActivateEnginePart(upperStageEnginePart).
    }.
}.

FUNCTION ActivateEnginePart {
    PARAMETER enginePart.

    IF enginePart:HASMODULE("ModuleEnginesRF") {
        LOCAL rfModule TO enginePart:GETMODULE("ModuleEnginesRF").

        IF rfModule:HASEVENT("Activate Engine") {
            rfModule:DOEVENT("Activate Engine").
            RETURN.
        } ELSE IF rfModule:HASEVENT("Activate") {
            rfModule:DOEVENT("Activate").
            RETURN.
        } ELSE IF rfModule:HASACTION("Activate Engine") {
            rfModule:DOACTION("Activate Engine", TRUE).
            RETURN.
        } ELSE IF rfModule:HASACTION("Activate") {
            rfModule:DOACTION("Activate", TRUE).
            RETURN.
        }.
    }.

    IF enginePart:HASMODULE("ModuleEngines") {
        LOCAL engineModule TO enginePart:GETMODULE("ModuleEngines").

        IF engineModule:HASEVENT("Activate Engine") {
            engineModule:DOEVENT("Activate Engine").
            RETURN.
        } ELSE IF engineModule:HASEVENT("Activate") {
            engineModule:DOEVENT("Activate").
            RETURN.
        } ELSE IF engineModule:HASACTION("Activate Engine") {
            engineModule:DOACTION("Activate Engine", TRUE).
            RETURN.
        } ELSE IF engineModule:HASACTION("Activate") {
            engineModule:DOACTION("Activate", TRUE).
            RETURN.
        }.
    }.

    FOR availableModuleName IN enginePart:MODULES {
        LOCAL availableModule TO enginePart:GETMODULE(availableModuleName).

        IF availableModule:HASEVENT("Activate Engine") {
            availableModule:DOEVENT("Activate Engine").
            RETURN.
        } ELSE IF availableModule:HASEVENT("Activate") {
            availableModule:DOEVENT("Activate").
            RETURN.
        } ELSE IF availableModule:HASACTION("Activate Engine") {
            availableModule:DOACTION("Activate Engine", TRUE).
            RETURN.
        } ELSE IF availableModule:HASACTION("Activate") {
            availableModule:DOACTION("Activate", TRUE).
            RETURN.
        }.
    }.
}.

FUNCTION ActivatePartEngines {
    PARAMETER part.

    FOR moduleName IN part:MODULES {
        LOCAL availableModule TO part:GETMODULE(moduleName).

        IF availableModule:HASACTION("Activate Engine") {
            availableModule:DOACTION("Activate Engine", TRUE).
        }.
    }.
}.

FUNCTION ValidateResolvedManifest {
    PARAMETER resolvedManifest.

    FOR groupName IN resolvedManifest:KEYS {
        IF NOT resolvedManifest[groupName]["is_valid"] {
            RETURN FALSE.
        }.
    }.

    RETURN TRUE.
}.

FUNCTION ShowManifestHold {
    PARAMETER resolvedManifest.

    DrawLine("SLS MAIN", 0).
    DrawLine("Mode: HOLD", 1).
    DrawLine("Parts manifest validation failed.", 2).

    LOCAL row TO 4.

    FOR groupName IN resolvedManifest:KEYS {
        LOCAL resolvedGroup TO resolvedManifest[groupName].
        LOCAL requiredCount TO 0.

        IF resolvedGroup["definition"]:HASKEY("required_count") {
            SET requiredCount TO resolvedGroup["definition"]["required_count"].
        }.

        DrawLine(
            groupName + ": " + resolvedGroup["parts"]:LENGTH + "/" + requiredCount + " resolved",
            row
        ).
        SET row TO row + 1.
    }.
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

FUNCTION FormatMissionTime {
    PARAMETER totalSeconds.

    LOCAL roundedSeconds TO ROUND(MAX(0, totalSeconds), 0).
    LOCAL hours TO FLOOR(roundedSeconds / 3600).
    LOCAL remainingSeconds TO roundedSeconds - (hours * 3600).
    LOCAL minutes TO FLOOR(remainingSeconds / 60).
    LOCAL seconds TO remainingSeconds - (minutes * 60).

    RETURN "T+" + FormatTwoDigits(hours) + ":" + FormatTwoDigits(minutes) + ":" + FormatTwoDigits(seconds).
}.

FUNCTION FormatTwoDigits {
    PARAMETER value.

    LOCAL roundedValue TO ROUND(MAX(0, value), 0).

    IF roundedValue < 10 {
        RETURN "0" + roundedValue.
    }.

    RETURN "" + roundedValue.
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
