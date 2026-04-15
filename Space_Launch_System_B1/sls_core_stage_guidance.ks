// SLS core-stage ascent guidance.
// Boost stage remains a fixed passive profile. Keep the vehicle straight up
// until 50 m/s, then use the heuristic handoff controller for the ICPS cutoff.

GLOBAL FUNCTION FlyAscentGuidance {
    PARAMETER missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest.

    LOCAL guidanceInterval TO ascentSettings["guidance_update_interval"].
    LOCAL boostersSeparated TO FALSE.
    LOCAL coreEngineCount TO resolvedManifest["core_engines"]["parts"]:LENGTH.
    LOCAL previousPitchCommand TO launchSettings["post_liftoff_pitch_hold"].
    LOCAL stageOneCutoffReason TO "CORE STAGE DEPLETED".
    LOCAL boosterPeakThrusts TO InitializeBoosterPeakThrusts(resolvedManifest).
    LOCAL lastDisplayMode TO "".
    LOCAL abortJettisonComplete TO FALSE.
    LOCAL fairingPanelsDeployed TO FALSE.
    LOCAL fairingPanelsTelemetryText TO "FAIRING PANELS: PENDING".

    UNTIL FALSE {
    // The first stage follows a shallow, shuttle-like ascent:
    // hold nearly vertical through ignition, pitchover cleanly once the
    // vehicle is actually moving, then keep building horizontal speed while
    // the solids and core stage are still available.
        UpdateBoosterPeakThrusts(resolvedManifest, boosterPeakThrusts).

        IF NOT boostersSeparated AND ShouldSeparateBoosters(stagingSettings, resolvedManifest, boosterPeakThrusts) {
            ExecuteBoosterSeparationSequence(resolvedManifest).
            SET boostersSeparated TO TRUE.
            SET coreEngineCount TO GetActiveCoreEngineCount(resolvedManifest, stagingSettings).
        } ELSE IF boostersSeparated {
            SET coreEngineCount TO GetActiveCoreEngineCount(resolvedManifest, stagingSettings).
        }.

        IF boostersSeparated AND NOT abortJettisonComplete AND SHIP:ALTITUDE >= 140000 AND (TIME:SECONDS - launchClockStartSeconds) >= 198 {
            // Drop the Orion abort cover and light the jettison motor only
            // after the vehicle is high enough and late enough in ascent for a
            // safe jettison window.
            ExecuteAbortJettisonSequence(resolvedManifest).
            SET abortJettisonComplete TO TRUE.
        }.

        IF boostersSeparated AND NOT fairingPanelsDeployed AND SHIP:ALTITUDE >= 150000 {
            // Deploy the Orion fairing panels once we are above 150 km.
            // This is intentionally independent of the abort-jettison timing
            // so the deploy cannot be held up by a separate sequence.
            ExecuteManifestGroup(resolvedManifest["orion_fairing_panels"]).
            SET fairingPanelsDeployed TO TRUE.
            SET fairingPanelsTelemetryText TO "FAIRING PANELS: DEPLOYED".
        }.

        LOCAL completionStatus TO GetStageOneCompletionStatus(
            boostersSeparated,
            coreEngineCount,
            resolvedManifest,
            stagingSettings,
            ascentSettings,
            orbitSettings
        ).

        IF completionStatus["is_complete"] {
            SET stageOneCutoffReason TO completionStatus["reason"].
            BREAK.
        }.

        LOCAL targetHeading TO GetAscentHeading(ascentSettings, launchSettings).
        LOCAL targetThrottle TO ComputeAscentThrottle(ascentSettings, orbitSettings, boostersSeparated).
        LOCAL targetPitch TO ComputeAscentPitch(
            ascentSettings,
            orbitSettings,
            stagingSettings,
            boostersSeparated,
            SHIP:ALTITUDE,
            SHIP:VERTICALSPEED,
            SHIP:APOAPSIS,
            ETA:APOAPSIS,
            previousPitchCommand
        ).
        LOCAL phaseLabel TO "BOOST STAGE OLG".
        LOCAL guidanceText TO "BOOST STAGE OLG".

        IF boostersSeparated {
            SET phaseLabel TO "CORE STAGE GUIDANCE".
            SET guidanceText TO "CORE STAGE HEURISTIC".
        }.

        SET previousPitchCommand TO targetPitch.

        LOCAL launchRollCommand TO GetLaunchRollCommand(SHIP:VERTICALSPEED, launchSettings, ascentSettings).

        IF SHIP:VERTICALSPEED < ascentSettings["roll_program_start_vertical_speed"] {
            LOCK STEERING TO HEADING(
                launchSettings["post_liftoff_heading"],
                launchSettings["post_liftoff_pitch_hold"],
                launchRollCommand
            ).
        } ELSE {
            LOCK STEERING TO HEADING(targetHeading, targetPitch, launchRollCommand).
        }.
        LOCK THROTTLE TO targetThrottle.

        ClearScreenForMode("ASCENT GUIDANCE", lastDisplayMode).
        SET lastDisplayMode TO "ASCENT GUIDANCE".

        DisplayAscentStatus(
            missionSettings,
            phaseLabel,
            guidanceText,
            targetPitch,
            targetHeading,
            targetThrottle,
            orbitSettings["target_apoapsis"],
            GetStageOneMinimumHandoffEta(ascentSettings, stagingSettings),
            SHIP:APOAPSIS,
            coreEngineCount,
            fairingPanelsTelemetryText
        ).

        WriteVehicleBridgeStatus(
            missionSettings,
            launchSettings,
            "ASCENT_GUIDANCE",
            -1,
            TRUE,
            boostersSeparated,
            TRUE,
            TRUE,
            TRUE,
            FALSE,
            FALSE,
            guidanceText,
            FALSE,
            FALSE,
            FALSE
        ).

        WAIT guidanceInterval.
    }.

    LOCK THROTTLE TO 0.
    ShutdownCoreEngines(resolvedManifest).
    RunStageSeparation(missionSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest, stageOneCutoffReason).
}.

FUNCTION GetStageOneCompletionStatus {
    PARAMETER boostersSeparated, coreEngineCount, resolvedManifest, stagingSettings, ascentSettings, orbitSettings.

    IF coreEngineCount <= 0 {
        RETURN LEXICON("is_complete", TRUE, "reason", "CORE THRUST LOST").
    }.

    IF NOT boostersSeparated {
        RETURN LEXICON("is_complete", FALSE, "reason", "").
    }.

    LOCAL coreFuelFraction TO GetCoreStageFuelFraction(resolvedManifest).
    LOCAL targetApoapsisValue TO orbitSettings["target_apoapsis"].

    // Stage 1 now has a hard apoapsis ceiling: once the current apoapsis
    // reaches the mission target, we cut the stage instead of trying to
    // "save" the burn past the target.
    IF SHIP:APOAPSIS >= targetApoapsisValue {
        RETURN LEXICON("is_complete", TRUE, "reason", "CORE TARGET APOAPSIS REACHED").
    }.

    IF coreFuelFraction <= 0 {
        RETURN LEXICON("is_complete", TRUE, "reason", "CORE FUEL DEPLETED").
    }.

    IF ETA:APOAPSIS <= 0 {
        RETURN LEXICON("is_complete", TRUE, "reason", "APOAPSIS PASSED").
    }.

    RETURN LEXICON("is_complete", FALSE, "reason", "").
}.

FUNCTION ComputeBoostStagePitch {
    PARAMETER ascentSettings, currentAltitudeValue.

    // The booster phase is intentionally open loop.
    // We start vertical, then drive a shaped pitchover, and finally blend to
    // the core-stage entry attitude as the stack climbs out of the denser air.
    IF currentAltitudeValue <= ascentSettings["pitchover_start_altitude"] {
        RETURN ascentSettings["pitchover_start_pitch"].
    }.

    LOCAL altitudeFraction TO ClampValue(
        (currentAltitudeValue - ascentSettings["pitchover_start_altitude"]) /
        (ascentSettings["boost_guidance_end_altitude"] - ascentSettings["pitchover_start_altitude"]),
        0,
        1
    ).
    SET altitudeFraction TO ShapeAscentBlend(altitudeFraction, ascentSettings["boost_guidance_curve_exponent"]).

    RETURN LerpValue(
        ascentSettings["pitchover_start_pitch"],
        ascentSettings["boost_guidance_end_pitch"],
        altitudeFraction
    ).
}.

FUNCTION GetStageOneApoapsisSafetyBlend {
    PARAMETER ascentSettings, targetApoapsisValue, currentApoapsisValue.

    IF targetApoapsisValue <= 0 {
        RETURN 0.
    }.

    LOCAL apoapsisFraction TO ClampValue(currentApoapsisValue / targetApoapsisValue, 0, 1).
    IF apoapsisFraction <= ascentSettings["stage_one_apoapsis_safety_fraction"] {
        RETURN 0.
    }.

    RETURN ClampValue(
        (apoapsisFraction - ascentSettings["stage_one_apoapsis_safety_fraction"]) /
        MAX(0.0001, 1 - ascentSettings["stage_one_apoapsis_safety_fraction"]),
        0,
        1
    ).
}.

FUNCTION ComputeAscentThrottle {
    PARAMETER ascentSettings, orbitSettings, boostersSeparated.

    LOCAL throttleCommand TO ascentSettings["core_stage_max_throttle"].
    LOCAL currentAltitudeValue TO SHIP:ALTITUDE.
    LOCAL targetApoapsisValue TO orbitSettings["target_apoapsis"].
    LOCAL apoapsisErrorValue TO targetApoapsisValue - SHIP:APOAPSIS.
    LOCAL apoapsisSafetyBlend TO GetStageOneApoapsisSafetyBlend(ascentSettings, targetApoapsisValue, SHIP:APOAPSIS).

    IF NOT boostersSeparated {
        SET throttleCommand TO ascentSettings["solid_booster_min_throttle"].
    } ELSE {
        IF SHIP:APOAPSIS >= targetApoapsisValue {
            RETURN 0.
        }.

        IF apoapsisErrorValue <= 0 {
            SET throttleCommand TO MIN(throttleCommand, ascentSettings["core_stage_apoapsis_overshoot_throttle"]).
        } ELSE IF apoapsisErrorValue <= ascentSettings["apoapsis_fine_tune_margin"] {
            SET throttleCommand TO MIN(throttleCommand, ascentSettings["core_stage_apoapsis_hold_throttle"]).
        } ELSE IF apoapsisErrorValue <= ascentSettings["apoapsis_throttle_down_margin"] {
            LOCAL throttleBlendValue TO ClampValue(
                apoapsisErrorValue / ascentSettings["apoapsis_throttle_down_margin"],
                0,
                1
            ).

            SET throttleCommand TO LerpValue(
                ascentSettings["core_stage_min_throttle"],
                ascentSettings["core_stage_max_throttle"],
                throttleBlendValue
            ).
        }.

        // Start trimming throttle before we hit the target apoapsis so the
        // stack settles into the handoff instead of overshooting and then
        // trying to recover a bad trajectory.
        IF apoapsisSafetyBlend > 0 {
            LOCAL safetyThrottleBlend TO ClampValue(
                apoapsisSafetyBlend * ascentSettings["stage_one_apoapsis_safety_throttle_down_gain"],
                0,
                1
            ).

            SET throttleCommand TO MIN(
                throttleCommand,
                LerpValue(
                    ascentSettings["core_stage_max_throttle"],
                    ascentSettings["core_stage_apoapsis_overshoot_throttle"],
                    safetyThrottleBlend
                )
            ).
        }.
    }.

    IF currentAltitudeValue >= ascentSettings["max_q_start_altitude"] AND currentAltitudeValue <= ascentSettings["max_q_end_altitude"] {
        SET throttleCommand TO MIN(throttleCommand, ascentSettings["max_q_throttle_limit"]).
    }.

    RETURN ClampValue(throttleCommand, 0, 1).
}.

FUNCTION DisplayAscentStatus {
    PARAMETER missionSettings, phaseLabel, guidanceText, targetPitch, targetHeading, targetThrottle, targetApoapsisValue, handoffEtaTarget, guidanceApoapsisValue, coreEngineCount, fairingPanelsTelemetryText.

    DrawLine("SLS MAIN", 0).
    DrawLine("Mode: ASCENT GUIDANCE", 1).
    DrawLine("Phase: " + phaseLabel, 2).
    DrawLine("Guidance: " + guidanceText, 3).
    DrawLine("Mission: " + missionSettings["mission_name"], 4).
    DrawLine("Altitude: " + ROUND(SHIP:ALTITUDE, 0), 5).
    DrawLine("Orbital Speed: " + ROUND(SHIP:ORBIT:VELOCITY:ORBIT:MAG, 1), 6).
    DrawLine("Apoapsis: " + ROUND(SHIP:APOAPSIS, 0), 7).
    DrawLine("Periapsis: " + ROUND(SHIP:PERIAPSIS, 0), 8).
    DrawLine("Target Apo: " + ROUND(targetApoapsisValue, 0), 9).
    DrawLine("Min ETA Apo: " + ROUND(handoffEtaTarget, 1), 10).
    DrawLine("Tracked Apo: " + ROUND(guidanceApoapsisValue, 0), 11).
    DrawLine("Pitch Cmd: " + ROUND(targetPitch, 2), 12).
    DrawLine("Heading Cmd: " + ROUND(targetHeading, 2), 13).
    DrawLine("Throttle Cmd: " + ROUND(targetThrottle, 2), 14).
    DrawLine("ETA Apoapsis: " + ROUND(ETA:APOAPSIS, 1), 15).
    DrawLine("Core Engines Alive: " + coreEngineCount, 16).
    DrawLine("Guidance Mode: " + guidanceText, 17).
    DrawLine(fairingPanelsTelemetryText, 18).
}.

FUNCTION LimitPitchCommand {
    PARAMETER requestedPitch, previousPitch, ascentSettings.

    LOCAL pitchDelta TO requestedPitch - previousPitch.
    LOCAL limitedPitch TO requestedPitch.

    IF pitchDelta > ascentSettings["pitch_up_rate_limit"] {
        SET limitedPitch TO previousPitch + ascentSettings["pitch_up_rate_limit"].
    } ELSE IF pitchDelta < -ascentSettings["pitch_down_rate_limit"] {
        SET limitedPitch TO previousPitch - ascentSettings["pitch_down_rate_limit"].
    }.

    RETURN ClampValue(limitedPitch, ascentSettings["gravity_turn_min_pitch"], 90).
}.

FUNCTION GetAscentHeading {
    PARAMETER ascentSettings, launchSettings.

    // Keep the stack pointed at the planned launch azimuth, but do not let the
    // heading command depend on shuttle-only surface state that does not exist
    // in the SLS guidance runtime.
    IF SHIP:VERTICALSPEED < ascentSettings["roll_program_start_vertical_speed"] {
        RETURN launchSettings["post_liftoff_heading"].
    }.

    RETURN launchSettings["post_liftoff_heading"].
}.

FUNCTION ComputeAscentPitch {
    PARAMETER ascentSettings, orbitSettings, stagingSettings, boostersSeparated, currentAltitudeValue, currentVerticalSpeed, currentApoapsisValue, currentEtaToApoapsis, previousPitchCommand.

    // Shuttle-derived first stage guidance keeps the control law simple:
    // - stay vertical until the stack is clearly moving,
    // - use an open-loop pitch schedule while the boosters are attached,
    // - transition into a core-stage curve once the solids are gone,
    // - and apply only bounded pitch-rate changes so the vehicle does not
    //   chase its own steering noise.
    LOCAL targetApoapsisValue TO orbitSettings["target_apoapsis"].
    LOCAL apoapsisSafetyBlend TO GetStageOneApoapsisSafetyBlend(ascentSettings, targetApoapsisValue, currentApoapsisValue).

    IF NOT boostersSeparated {
        LOCAL boostPitchCommand TO ComputeBoostStagePitch(ascentSettings, currentAltitudeValue).

        // Ease the boost pitch down once the trajectory is already most of
        // the way to target. That gives the stack time to flatten smoothly
        // instead of holding a steeper attitude until the last moment.
        IF apoapsisSafetyBlend > 0 {
            SET boostPitchCommand TO boostPitchCommand - (
                apoapsisSafetyBlend * ascentSettings["stage_one_apoapsis_safety_pitch_down_gain"]
            ).
        }.

        IF currentVerticalSpeed < ascentSettings["roll_program_start_vertical_speed"] {
            SET boostPitchCommand TO 90.
        }.

        RETURN LimitPitchCommand(boostPitchCommand, previousPitchCommand, ascentSettings).
    }.

    LOCAL targetPitch TO ComputeCoreGuidancePitch(ascentSettings, currentAltitudeValue).
    LOCAL minimumHandoffEta TO GetStageOneMinimumHandoffEta(ascentSettings, stagingSettings).
    LOCAL pitchBias TO GetStageOneApoapsisMarginPitchBias(ascentSettings, targetApoapsisValue, currentApoapsisValue) +
        GetStageOneEtaPitchBias(ascentSettings, minimumHandoffEta, currentEtaToApoapsis) +
        GetStageOneVerticalSpeedPitchBias(ascentSettings, currentVerticalSpeed) +
        GetBoosterSeparationRecoveryPitchBias(ascentSettings, currentAltitudeValue).

    // Apply the same early flattening logic after booster sep so the core
    // stage does not wait until it is already at the target to start easing
    // off vertical energy.
    IF apoapsisSafetyBlend > 0 {
        SET pitchBias TO pitchBias - (
            apoapsisSafetyBlend * ascentSettings["stage_one_apoapsis_safety_pitch_down_gain"]
        ).
    }.

    // When the stack is a little too high, bias the pitch down instead of
    // cutting the engines. That lets the core stage trade a bit of vertical
    // energy for a more controlled apogee recovery.
    IF currentApoapsisValue > targetApoapsisValue {
        LOCAL overshootFraction TO ClampValue(
            (currentApoapsisValue - targetApoapsisValue) / ascentSettings["stage_one_handoff_apoapsis_control_band"],
            0,
            1
        ).

        SET pitchBias TO pitchBias - (overshootFraction * ascentSettings["stage_one_handoff_pitch_down_gain"]).
    }.

    IF currentApoapsisValue < ascentSettings["engine_cutoff_target_apoapsis"] - ascentSettings["apoapsis_pitch_up_shortfall"] {
        SET pitchBias TO pitchBias + ascentSettings["apoapsis_pitch_up_bias_max"].
    }.

    RETURN LimitPitchCommand(targetPitch + pitchBias, previousPitchCommand, ascentSettings).
}.

FUNCTION ComputeCoreGuidancePitch {
    PARAMETER ascentSettings, currentAltitudeValue.

    LOCAL pitchValue TO ascentSettings["boost_guidance_end_pitch"].

    // The core stage mirrors the booster pitch profile but with a slower,
    // lower terminal attitude so MECO happens near the handoff target.
    IF currentAltitudeValue <= ascentSettings["boost_guidance_end_altitude"] {
        RETURN pitchValue.
    }.

    IF currentAltitudeValue < ascentSettings["gravity_turn_start_altitude"] {
        LOCAL boostBlendValue TO ClampValue(
            (currentAltitudeValue - ascentSettings["boost_guidance_end_altitude"]) /
            MAX(1, ascentSettings["gravity_turn_start_altitude"] - ascentSettings["boost_guidance_end_altitude"]),
            0,
            1
        ).

        SET boostBlendValue TO ShapeAscentBlend(boostBlendValue, ascentSettings["boost_guidance_curve_exponent"]).
        RETURN LerpValue(
            ascentSettings["boost_guidance_end_pitch"],
            ascentSettings["pitchover_end_pitch"],
            boostBlendValue
        ).
    }.

    IF currentAltitudeValue < ascentSettings["gravity_turn_end_altitude"] {
        LOCAL gravityBlendValue TO ClampValue(
            (currentAltitudeValue - ascentSettings["gravity_turn_start_altitude"]) /
            MAX(1, ascentSettings["gravity_turn_end_altitude"] - ascentSettings["gravity_turn_start_altitude"]),
            0,
            1
        ).

        SET gravityBlendValue TO ShapeAscentBlend(gravityBlendValue, ascentSettings["gravity_turn_curve_exponent"]).
        SET pitchValue TO LerpValue(
            ascentSettings["pitchover_end_pitch"],
            ascentSettings["gravity_turn_final_pitch"],
            gravityBlendValue
        ).
    } ELSE IF currentAltitudeValue < ascentSettings["core_guidance_end_altitude"] {
        LOCAL coreBlendValue TO ClampValue(
            (currentAltitudeValue - ascentSettings["core_guidance_start_altitude"]) /
            MAX(1, ascentSettings["core_guidance_end_altitude"] - ascentSettings["core_guidance_start_altitude"]),
            0,
            1
        ).

        SET coreBlendValue TO ShapeAscentBlend(coreBlendValue, ascentSettings["core_guidance_curve_exponent"]).
        SET pitchValue TO LerpValue(
            ascentSettings["gravity_turn_final_pitch"],
            ascentSettings["core_stage_terminal_pitch"],
            coreBlendValue
        ).
    } ELSE {
        SET pitchValue TO ascentSettings["core_stage_terminal_pitch"].
    }.

    RETURN ClampValue(pitchValue, ascentSettings["gravity_turn_min_pitch"], 90).
}.

FUNCTION GetStageOneApoapsisMarginPitchBias {
    PARAMETER ascentSettings, targetApoapsisValue, currentApoapsisValue.

    // Positive error means we are under the target trajectory and should hold
    // a little more nose-up attitude. Negative error means we are ahead of the
    // curve and can relax the pitch slightly.
    LOCAL errorFraction TO ClampValue(
        (targetApoapsisValue - currentApoapsisValue) / ascentSettings["stage_one_handoff_apoapsis_control_band"],
        -1,
        1
    ).

    IF errorFraction >= 0 {
        RETURN errorFraction * ascentSettings["stage_one_handoff_pitch_up_gain"].
    }.

    RETURN errorFraction * ascentSettings["stage_one_handoff_pitch_down_gain"].
}.

FUNCTION GetStageOneEtaPitchBias {
    PARAMETER ascentSettings, minimumHandoffEta, currentEtaToApoapsis.

    // If apoapsis is arriving too early, bias the stack a little higher so the
    // remaining core burn has time to shape the trajectory cleanly.
    LOCAL etaErrorFraction TO ClampValue(
        (minimumHandoffEta - currentEtaToApoapsis) / ascentSettings["stage_one_handoff_eta_control_band"],
        -1,
        1
    ).

    IF etaErrorFraction >= 0 {
        RETURN etaErrorFraction * ascentSettings["stage_one_handoff_eta_pitch_up_gain"].
    }.

    RETURN etaErrorFraction * ascentSettings["stage_one_handoff_eta_pitch_down_gain"].
}.

FUNCTION GetStageOneVerticalSpeedPitchBias {
    PARAMETER ascentSettings, currentVerticalSpeed.

    LOCAL verticalSpeedErrorFraction TO ClampValue(
        (ascentSettings["stage_one_vertical_speed_floor"] - currentVerticalSpeed) /
        ascentSettings["stage_one_vertical_speed_control_band"],
        0,
        1
    ).

    RETURN verticalSpeedErrorFraction * ascentSettings["stage_one_vertical_speed_pitch_gain"].
}.

FUNCTION GetBoosterSeparationRecoveryPitchBias {
    PARAMETER ascentSettings, currentAltitudeValue.

    // Booster sep often leaves a short transient where the stack needs a touch
    // more pitch-up to recover the trajectory before the core-stage curve takes over.
    IF currentAltitudeValue <= ascentSettings["boost_guidance_end_altitude"] {
        RETURN ascentSettings["stage_one_booster_sep_recovery_pitch_bias"].
    }.

    IF currentAltitudeValue >= ascentSettings["stage_one_booster_sep_recovery_end_altitude"] {
        RETURN 0.
    }.

    LOCAL decayFraction TO ClampValue(
        (currentAltitudeValue - ascentSettings["boost_guidance_end_altitude"]) /
        (ascentSettings["stage_one_booster_sep_recovery_end_altitude"] - ascentSettings["boost_guidance_end_altitude"]),
        0,
        1
    ).

    RETURN LerpValue(
        ascentSettings["stage_one_booster_sep_recovery_pitch_bias"],
        0,
        ShapeAscentBlend(decayFraction, ascentSettings["core_guidance_curve_exponent"])
    ).
}.

FUNCTION GetLaunchRollCommand {
    PARAMETER currentVerticalSpeed, launchSettings, ascentSettings.

    // Do not let the stack roll during the first vertical climb. Keep the
    // vehicle locked out until it is actually driving upward faster than the
    // configured liftoff threshold, then release the planned roll schedule.
    IF currentVerticalSpeed < ascentSettings["roll_program_start_vertical_speed"] {
        RETURN 0.
    }.

    RETURN launchSettings["post_liftoff_roll"].
}.

FUNCTION ShouldSeparateBoosters {
    PARAMETER stagingSettings, resolvedManifest, boosterPeakThrusts.

    LOCAL boosterEngineParts TO resolvedManifest["booster_engines"]["parts"].
    LOCAL minimumThrustRatio TO 1.
    LOCAL boosterIndex TO 0.

    // SRB sep is driven by both ascent energy and thrust tailoff.
    // We require a minimum vertical rate so the stack is not dumped too early.
    IF SHIP:VERTICALSPEED < stagingSettings["booster_separation_vertical_speed_min"] {
        RETURN FALSE.
    }.

    FOR boosterEnginePart IN boosterEngineParts {
        LOCAL peakThrustValue TO boosterPeakThrusts[boosterIndex].

        IF peakThrustValue > 0 {
            SET minimumThrustRatio TO MIN(minimumThrustRatio, boosterEnginePart:THRUST / peakThrustValue).
        }.

        SET boosterIndex TO boosterIndex + 1.
    }.

    RETURN minimumThrustRatio <= stagingSettings["booster_separation_thrust_ratio"].
}.

FUNCTION ExecuteBoosterSeparationSequence {
    PARAMETER resolvedManifest.

    ActivateBranchAuxiliaryMotors(resolvedManifest).
    ExecuteManifestGroup(resolvedManifest["booster_separation_motors"]).
    WAIT 0.
    ExecuteManifestGroup(resolvedManifest["booster_separation"]).
}.

FUNCTION ActivateBranchAuxiliaryMotors {
    PARAMETER resolvedManifest.

    LOCAL boosterDecouplers TO resolvedManifest["booster_separation"]["parts"].
    LOCAL boosterEngineParts TO resolvedManifest["booster_engines"]["parts"].

    FOR boosterDecoupler IN boosterDecouplers {
        FOR childPart IN boosterDecoupler:CHILDREN {
            ActivateAuxiliaryEnginesInTree(childPart, boosterEngineParts).
        }.
    }.
}.

FUNCTION ActivateAuxiliaryEnginesInTree {
    PARAMETER rootPart, excludedParts.

    IF NOT excludedParts:CONTAINS(rootPart) {
        ActivatePartEngines(rootPart).
    }.

    FOR childPart IN rootPart:CHILDREN {
        ActivateAuxiliaryEnginesInTree(childPart, excludedParts).
    }.
}.

FUNCTION GetPrimaryPropellantFraction {
    PARAMETER enginePart.

    LOCAL totalAmount TO 0.
    LOCAL totalCapacity TO 0.
    LOCAL resourceCount TO enginePart:RESOURCES:LENGTH.
    LOCAL resourceIndex TO 0.

    UNTIL resourceIndex >= resourceCount {
        LOCAL resourceItem TO enginePart:RESOURCES[resourceIndex].

        IF resourceItem:CAPACITY > 0 {
            SET totalAmount TO totalAmount + resourceItem:AMOUNT.
            SET totalCapacity TO totalCapacity + resourceItem:CAPACITY.
        }.

        SET resourceIndex TO resourceIndex + 1.
    }.

    IF totalCapacity <= 0 {
        RETURN 1.
    }.

    RETURN totalAmount / totalCapacity.
}.

FUNCTION InitializeBoosterPeakThrusts {
    PARAMETER resolvedManifest.

    LOCAL boosterPeakThrusts TO LIST().

    FOR boosterEnginePart IN resolvedManifest["booster_engines"]["parts"] {
        boosterPeakThrusts:ADD(MAX(boosterEnginePart:THRUST, 0)).
    }.

    RETURN boosterPeakThrusts.
}.

FUNCTION UpdateBoosterPeakThrusts {
    PARAMETER resolvedManifest, boosterPeakThrusts.

    LOCAL boosterIndex TO 0.

    FOR boosterEnginePart IN resolvedManifest["booster_engines"]["parts"] {
        IF boosterEnginePart:THRUST > boosterPeakThrusts[boosterIndex] {
            SET boosterPeakThrusts[boosterIndex] TO boosterEnginePart:THRUST.
        }.

        SET boosterIndex TO boosterIndex + 1.
    }.
}.

GLOBAL FUNCTION GetActiveCoreEngineCount {
    PARAMETER resolvedManifest, stagingSettings.

    LOCAL activeCoreEngines TO 0.

    FOR coreEnginePart IN resolvedManifest["core_engines"]["parts"] {
        IF coreEnginePart:THRUST >= stagingSettings["core_engine_min_operating_thrust"] {
            SET activeCoreEngines TO activeCoreEngines + 1.
        }.
    }.

    RETURN activeCoreEngines.
}.

FUNCTION GetCoreStageFuelFraction {
    PARAMETER resolvedManifest.

    LOCAL totalAmount TO 0.
    LOCAL totalCapacity TO 0.
    LOCAL corePropellantNames TO LIST().

    FOR coreEnginePart IN resolvedManifest["core_engines"]["parts"] {
        FOR resourceName IN coreEnginePart:CONSUMEDRESOURCES:KEYS {
            IF NOT corePropellantNames:CONTAINS(resourceName) {
                corePropellantNames:ADD(resourceName).
            }.
        }.
    }.

    IF resolvedManifest["core_stage_propellant_tanks"]["parts"]:LENGTH > 0 {
        FOR coreTankPart IN resolvedManifest["core_stage_propellant_tanks"]["parts"] {
            FOR resourceItem IN coreTankPart:RESOURCES {
                IF corePropellantNames:CONTAINS(resourceItem:NAME) {
                    SET totalAmount TO totalAmount + resourceItem:AMOUNT.
                    SET totalCapacity TO totalCapacity + resourceItem:CAPACITY.
                }.
            }.
        }.
    } ELSE {
        FOR coreEnginePart IN resolvedManifest["core_engines"]["parts"] {
            LOCAL enginePartFuelFraction TO GetPrimaryPropellantFraction(coreEnginePart).
            SET totalAmount TO totalAmount + enginePartFuelFraction.
            SET totalCapacity TO totalCapacity + 1.
        }.
    }.

    IF totalCapacity <= 0 {
        RETURN 0.
    }.

    RETURN totalAmount / totalCapacity.
}.

FUNCTION GetStageOneHandoffApoapsis {
    PARAMETER orbitSettings.

    IF orbitSettings:HASKEY("stage_one_handoff_apoapsis") {
        RETURN orbitSettings["stage_one_handoff_apoapsis"].
    }.

    RETURN orbitSettings["target_periapsis"].
}.

FUNCTION GetStageOneMinimumHandoffEta {
    PARAMETER ascentSettings, stagingSettings.

    LOCAL minimumHandoffEtaValue TO
        stagingSettings["upper_stage_ignition_delay"] +
        stagingSettings["upper_stage_settle_time"] +
        stagingSettings["upper_stage_perigee_raise_start_eta"] +
        ascentSettings["stage_one_handoff_eta_margin"].

    RETURN minimumHandoffEtaValue.
}.

FUNCTION ShutdownCoreEngines {
    PARAMETER resolvedManifest.

    // At stage one cutoff we do not guess which engines are still alive.
    // We explicitly send a shutdown request to every core engine part.
    FOR coreEnginePart IN resolvedManifest["core_engines"]["parts"] {
        ExecutePartTrigger(coreEnginePart, "module_action", "Shutdown Engine", "ModuleEnginesRF", TRUE).
    }.
}.

GLOBAL FUNCTION IgniteBoosterEngines {
    PARAMETER boosterEngineGroup.

    ExecuteManifestGroup(boosterEngineGroup).
}.

FUNCTION ExecuteAbortJettisonSequence {
    PARAMETER resolvedManifest.

    // The abort motor must be commanded while it still belongs to the active
    // vessel. Fire it first, then decouple the cover immediately after the
    // motor is live so the eject event happens as one sequence.
    ExecuteManifestGroup(resolvedManifest["abort_launch_motor"]).
    WAIT 0.
    ExecuteManifestGroup(resolvedManifest["abort_jettison_motor"]).
    WAIT 0.
    ExecuteManifestGroup(resolvedManifest["abort_protective_cover"]).
}.
