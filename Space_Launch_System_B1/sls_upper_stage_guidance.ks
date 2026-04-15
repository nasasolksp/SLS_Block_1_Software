// Upper-stage guidance sequence.
// Loaded by SLS_Main.ks. This module covers the live upper-stage burn and coast logic.

GLOBAL FUNCTION FlyUpperStageGuidanceSequence {
    PARAMETER missionSettings, ascentSettings, orbitSettings, stagingSettings, resolvedManifest.
    LOCAL lastDisplayMode TO "".
    LOCAL coastStartTime TO TIME:SECONDS.
    LOCAL ignitionGraceDeadline TO 0.
    LOCAL upperStageTargetAchieved TO FALSE.
    LOCAL upperStageFailed TO FALSE.
    LOCAL sequenceComplete TO FALSE.
    LOCAL initialInsertionBurnPending TO TRUE.
    LOCAL ullagePrepTriggered TO FALSE.
    LOCAL ullageBurnReadyDeadline TO 0.
    LOCAL guidanceText TO "COAST TO APOAPSIS".
    LOCAL filteredVerticalSpeed TO 0.
    LOCAL previousPitchCommand TO 0.

    LOCK THROTTLE TO 0.
    LOCK STEERING TO PROGRADE.

    UNTIL sequenceComplete {
        LOCAL burnDirective TO GetUpperStageBurnDirective(
            orbitSettings,
            stagingSettings,
            initialInsertionBurnPending
        ).

        SET guidanceText TO burnDirective["guidance_text"].

        IF burnDirective["is_complete"] {
            SET upperStageTargetAchieved TO TRUE.
            SET sequenceComplete TO TRUE.
            BREAK.
        }.

        IF sequenceComplete {
            BREAK.
        }.

        IF NOT burnDirective["should_burn"] {
            LOCK THROTTLE TO 0.
            LOCK STEERING TO PROGRADE.

            IF
                NOT initialInsertionBurnPending AND
                NOT ullagePrepTriggered AND
                ETA:APOAPSIS <= stagingSettings["upper_stage_perigee_raise_start_eta"] AND
                ETA:APOAPSIS > stagingSettings["upper_stage_perigee_raise_start_eta"] - stagingSettings["upper_stage_ullage_prep_lead_time"]
            {
                // Pulse the ullage axes a little ahead of the next burn so the
                // RCS settles the propellant before ignition.
                SET SHIP:CONTROL:FORE TO 1.
                SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
                SET ullagePrepTriggered TO TRUE.
                SET ullageBurnReadyDeadline TO TIME:SECONDS + stagingSettings["upper_stage_settle_time"].
                SET guidanceText TO "ULLAGE PREP".
            }.

            ClearScreenForMode("UPPER STAGE COAST", lastDisplayMode).
            SET lastDisplayMode TO "UPPER STAGE COAST".
            SlsDisplayUpperStageGuidance(missionSettings, orbitSettings, 0, guidanceText).
            WAIT stagingSettings["upper_stage_guidance_interval"].
            SET initialInsertionBurnPending TO burnDirective["next_insertion_pending"].
        } ELSE {
            IF
                NOT initialInsertionBurnPending AND
                ullagePrepTriggered AND
                TIME:SECONDS < ullageBurnReadyDeadline
            {
                // Hold the stage in coast while the ullage pulse settles.
                // The engine should not be asked to ignite until this window
                // has elapsed, otherwise we just thrash the start sequence.
                LOCK THROTTLE TO 0.
                LOCK STEERING TO PROGRADE.

                ClearScreenForMode("UPPER STAGE COAST", lastDisplayMode).
                SET lastDisplayMode TO "UPPER STAGE COAST".
                SET guidanceText TO "ULLAGE SETTLING".
                SlsDisplayUpperStageGuidance(missionSettings, orbitSettings, 0, guidanceText).
                WAIT stagingSettings["upper_stage_guidance_interval"].
                SET initialInsertionBurnPending TO burnDirective["next_insertion_pending"].
            } ELSE {
                SET ullagePrepTriggered TO FALSE.

                // Latch the burn throttle once at ignition so the engine can
                // spool cleanly without the command being reissued every frame.
                LOCAL burnThrottleCommand TO burnDirective["throttle"].
                LOCK THROTTLE TO burnThrottleCommand.
                IgniteUpperStageEngines(resolvedManifest).
                SET ignitionGraceDeadline TO TIME:SECONDS + stagingSettings["upper_stage_ignition_grace_time"].

                LOCAL burnPassComplete TO FALSE.

                UNTIL burnPassComplete {
                    LOCAL activeUpperStageEngineCount TO GetActiveUpperStageEngineCount(resolvedManifest).
                    LOCAL upperStageFuelFraction TO GetUpperStageFuelFraction(resolvedManifest).
                    SET filteredVerticalSpeed TO LerpValue(
                        filteredVerticalSpeed,
                        SHIP:VERTICALSPEED,
                        stagingSettings["upper_stage_vertical_speed_filter_alpha"]
                    ).
                    LOCAL periapsisErrorValue TO orbitSettings["target_periapsis"] - SHIP:PERIAPSIS.
                    LOCAL apoapsisLimitReached TO SHIP:APOAPSIS >= orbitSettings["target_apoapsis"] - orbitSettings["apoapsis_tolerance"].
                    LOCAL passedApoapsisWindow TO ETA:APOAPSIS > stagingSettings["upper_stage_perigee_raise_start_eta"] AND SHIP:ALTITUDE < SHIP:APOAPSIS - orbitSettings["apoapsis_tolerance"].
                    LOCAL insertionApoapsisReady TO initialInsertionBurnPending AND apoapsisLimitReached.

                    IF activeUpperStageEngineCount <= 0 {
                        IF TIME:SECONDS < ignitionGraceDeadline {
                            SET guidanceText TO "ICPS IGNITION STABILIZING".
                            LOCK STEERING TO PROGRADE.
                            ClearScreenForMode("UPPER STAGE BURN", lastDisplayMode).
                            SET lastDisplayMode TO "UPPER STAGE BURN".
                            SlsDisplayUpperStageGuidance(missionSettings, orbitSettings, activeUpperStageEngineCount, guidanceText).
                            WAIT stagingSettings["upper_stage_guidance_interval"].
                        } ELSE {
                            SET guidanceText TO "UPPER STAGE THRUST LOST".
                            SET upperStageFailed TO TRUE.
                            SET sequenceComplete TO TRUE.
                            SET burnPassComplete TO TRUE.
                            BREAK.
                        }.
                    }.

                    IF initialInsertionBurnPending AND upperStageFuelFraction <= stagingSettings["upper_stage_min_fuel_fraction"] AND NOT apoapsisLimitReached {
                        // Do not abandon the first burn just because the tank is
                        // getting thin. Keep pushing until we actually reach the
                        // apoapsis target, or until the stage is truly empty.
                        SET guidanceText TO "LOW FUEL - CONTINUING INSERTION".
                    }.

                    IF upperStageFuelFraction <= 0 {
                        IF apoapsisLimitReached {
                            SET guidanceText TO "UPPER STAGE FUEL DEPLETED AT TARGET".
                            SET burnPassComplete TO TRUE.
                            BREAK.
                        } ELSE {
                            SET guidanceText TO "UPPER STAGE PROPULSION EXHAUSTED".
                            SET upperStageFailed TO TRUE.
                            SET sequenceComplete TO TRUE.
                            SET burnPassComplete TO TRUE.
                            BREAK.
                        }.
                    }.

                    IF insertionApoapsisReady {
                        SET guidanceText TO "INITIAL APOAPSIS TARGET REACHED".
                        SET burnPassComplete TO TRUE.
                        BREAK.
                    }.

                    IF periapsisErrorValue <= orbitSettings["periapsis_tolerance"] {
                        SET guidanceText TO "UPPER STAGE TARGET ACHIEVED".
                        SET upperStageTargetAchieved TO TRUE.
                        SET sequenceComplete TO TRUE.
                        SET burnPassComplete TO TRUE.
                        BREAK.
                    }.

                    IF apoapsisLimitReached {
                        SET guidanceText TO "APOAPSIS LIMIT REACHED - COAST".
                        SET burnPassComplete TO TRUE.
                        BREAK.
                    }.

                    IF NOT initialInsertionBurnPending AND passedApoapsisWindow {
                        SET guidanceText TO "COAST TO NEXT BURN WINDOW".
                        SET burnPassComplete TO TRUE.
                        BREAK.
                    }.

                    LOCAL targetPitch TO GetUpperStagePitchCommand(
                        orbitSettings,
                        stagingSettings,
                        initialInsertionBurnPending,
                        periapsisErrorValue,
                        ETA:APOAPSIS,
                        filteredVerticalSpeed,
                        previousPitchCommand
                    ).

                    SET previousPitchCommand TO targetPitch.

                    LOCK STEERING TO HEADING(SHIP:HEADING, targetPitch, 0).

                    ClearScreenForMode("UPPER STAGE BURN", lastDisplayMode).
                    SET lastDisplayMode TO "UPPER STAGE BURN".
                    SlsDisplayUpperStageGuidance(missionSettings, orbitSettings, activeUpperStageEngineCount, guidanceText).
                    WAIT stagingSettings["upper_stage_guidance_interval"].
                }.

                ShutdownUpperStageEngines(resolvedManifest).
                LOCK THROTTLE TO 0.
                SET initialInsertionBurnPending TO FALSE.
            }.
        }.
    }.

    CLEARSCREEN.

    UNTIL FALSE {
        DrawLine("SLS MAIN", 0).
        DrawLine("Mode: UPPER STAGE GUIDANCE", 1).
        DrawLine("Mission: " + missionSettings["mission_name"], 2).
        DrawLine("Guidance: " + guidanceText, 3).
        DrawLine("Completed: " + upperStageTargetAchieved, 4).
        DrawLine("Failed: " + upperStageFailed, 5).
        DrawLine("Apoapsis: " + ROUND(SHIP:APOAPSIS, 0), 6).
        DrawLine("Periapsis: " + ROUND(SHIP:PERIAPSIS, 0), 7).
        DrawLine("Target Apoapsis: " + ROUND(orbitSettings["target_apoapsis"], 0), 8).
        DrawLine("Target Periapsis: " + ROUND(orbitSettings["target_periapsis"], 0), 9).
        DrawLine("ETA Periapsis: " + ROUND(ETA:PERIAPSIS, 1), 10).
        WAIT 0.5.
    }.
}. 

FUNCTION GetActiveUpperStageEngineCount {
    PARAMETER resolvedManifest.

    LOCAL activeCount TO 0.

    // We count the engines that are actually producing thrust rather than
    // assuming the ignition command succeeded. That makes the ignition check
    // robust against parts that are staged but still spooling up.
    FOR upperStageEnginePart IN resolvedManifest["upper_stage_engines"]["parts"] {
        IF upperStageEnginePart:THRUST > 0 {
            SET activeCount TO activeCount + 1.
        }.
    }.

    RETURN activeCount.
}.

FUNCTION GetUpperStageBurnDirective {
    PARAMETER orbitSettings, stagingSettings, initialInsertionBurnPending.

    LOCAL apoapsisErrorValue TO orbitSettings["target_apoapsis"] - SHIP:APOAPSIS.
    LOCAL periapsisErrorValue TO orbitSettings["target_periapsis"] - SHIP:PERIAPSIS.
    LOCAL complete TO FALSE.
    LOCAL shouldBurn TO FALSE.
    LOCAL guidanceText TO "COAST TO APOAPSIS".
    LOCAL throttleCommand TO 0.
    LOCAL nextInsertionPending TO initialInsertionBurnPending.

    IF SlsUpperStageTargetAchieved(orbitSettings) {
        RETURN LEXICON(
            "is_complete", TRUE,
            "should_burn", FALSE,
            "guidance_text", "UPPER STAGE TARGET ACHIEVED",
            "throttle", 0,
            "next_insertion_pending", FALSE
        ).
    }.

    IF initialInsertionBurnPending {
        SET guidanceText TO "INITIAL INSERTION BURN".
        SET shouldBurn TO apoapsisErrorValue > orbitSettings["apoapsis_tolerance"].
        SET throttleCommand TO 1.

        IF NOT shouldBurn {
            SET guidanceText TO "COAST TO APOAPSIS".
            SET nextInsertionPending TO FALSE.
        }.
    } ELSE {
        IF periapsisErrorValue > orbitSettings["periapsis_tolerance"] {
            IF ETA:APOAPSIS <= stagingSettings["upper_stage_perigee_raise_start_eta"] {
                SET guidanceText TO "UPPER STAGE PERIGEE RAISE".
                SET shouldBurn TO TRUE.
                SET throttleCommand TO 1.
            } ELSE {
                SET guidanceText TO "COAST TO NEXT BURN WINDOW".
            }.
        } ELSE {
            SET complete TO TRUE.
            SET guidanceText TO "UPPER STAGE TARGET ACHIEVED".
        }.
    }.

    RETURN LEXICON(
        "is_complete", complete,
        "should_burn", shouldBurn,
        "guidance_text", guidanceText,
        "throttle", throttleCommand,
        "next_insertion_pending", nextInsertionPending
    ).
}.

FUNCTION GetUpperStageFuelFraction {
    PARAMETER resolvedManifest.

    LOCAL totalAmount TO 0.
    LOCAL totalCapacity TO 0.

    FOR upperStageEnginePart IN resolvedManifest["upper_stage_engines"]["parts"] {
        LOCAL resourceCount TO upperStageEnginePart:RESOURCES:LENGTH.
        LOCAL resourceIndex TO 0.

        UNTIL resourceIndex >= resourceCount {
            LOCAL resourceItem TO upperStageEnginePart:RESOURCES[resourceIndex].

            IF resourceItem:CAPACITY > 0 {
                SET totalAmount TO totalAmount + resourceItem:AMOUNT.
                SET totalCapacity TO totalCapacity + resourceItem:CAPACITY.
            }.

            SET resourceIndex TO resourceIndex + 1.
        }.
    }.

    IF totalCapacity <= 0 {
        RETURN 1.
    }.

    RETURN totalAmount / totalCapacity.
}.

FUNCTION GetUpperStagePitchCommand {
    PARAMETER orbitSettings, stagingSettings, initialInsertionBurnPending, periapsisErrorValue, etaToApoapsis, filteredVerticalSpeed, previousPitchCommand.

    LOCAL apoapsisShortfall TO MAX(0, orbitSettings["target_apoapsis"] - SHIP:APOAPSIS).
    LOCAL basePitch TO 0.
    LOCAL verticalSpeedBias TO 0.

    IF initialInsertionBurnPending {
        SET basePitch TO 3.
    }.

    IF apoapsisShortfall > 0 {
        SET basePitch TO MAX(
            basePitch,
            LerpValue(
                0,
                8,
                ClampValue(apoapsisShortfall / MAX(1, orbitSettings["target_apoapsis"]), 0, 1)
            )
        ).
    }.

    // Only use the vertical-speed recovery term during the later perigee-raise
    // burn. The initial insertion burn should stay conservative and coast to
    // apogee instead of trying to "help" the orbit loft upward.
    IF NOT initialInsertionBurnPending AND periapsisErrorValue > orbitSettings["periapsis_tolerance"] AND etaToApoapsis <= stagingSettings["upper_stage_perigee_raise_start_eta"] AND filteredVerticalSpeed < -stagingSettings["upper_stage_vertical_speed_deadband"] {
        SET verticalSpeedBias TO MIN(
            12,
            ABS(filteredVerticalSpeed) * stagingSettings["upper_stage_vertical_speed_pitch_gain"] +
            stagingSettings["upper_stage_vertical_speed_pitch_bias"]
        ).
    }.

    RETURN LimitUpperStagePitchCommand(
        ClampValue(basePitch + verticalSpeedBias, 0, 90),
        previousPitchCommand,
        stagingSettings
    ).
}.

FUNCTION LimitUpperStagePitchCommand {
    PARAMETER requestedPitch, previousPitch, stagingSettings.

    LOCAL pitchDelta TO requestedPitch - previousPitch.
    LOCAL limitedPitch TO requestedPitch.

    IF pitchDelta > stagingSettings["upper_stage_pitch_up_rate_limit"] {
        SET limitedPitch TO previousPitch + stagingSettings["upper_stage_pitch_up_rate_limit"].
    } ELSE IF pitchDelta < -stagingSettings["upper_stage_pitch_down_rate_limit"] {
        SET limitedPitch TO previousPitch - stagingSettings["upper_stage_pitch_down_rate_limit"].
    }.

    RETURN ClampValue(limitedPitch, 0, 90).
}.

FUNCTION SlsDisplayUpperStageGuidance {
    PARAMETER missionSettings, orbitSettings, activeUpperStageEngineCount, guidanceText.
    DrawLine("SLS MAIN", 0).
    DrawLine("Mode: UPPER STAGE BURN", 1).
    DrawLine("Mission: " + missionSettings["mission_name"], 2).
    DrawLine("Guidance: " + guidanceText, 3).
    DrawLine("Altitude: " + ROUND(SHIP:ALTITUDE, 0), 4).
    DrawLine("Apoapsis: " + ROUND(SHIP:APOAPSIS, 0), 5).
    DrawLine("Periapsis: " + ROUND(SHIP:PERIAPSIS, 0), 6).
    DrawLine("Target Apoapsis: " + ROUND(orbitSettings["target_apoapsis"], 0), 7).
    DrawLine("Target Periapsis: " + ROUND(orbitSettings["target_periapsis"], 0), 8).
    DrawLine("ETA Apoapsis: " + ROUND(ETA:APOAPSIS, 1), 9).
    DrawLine("ETA Periapsis: " + ROUND(ETA:PERIAPSIS, 1), 10).
    DrawLine("Active Engines: " + activeUpperStageEngineCount, 11).
}.

FUNCTION SlsComputeUpperStageThrottle {
    PARAMETER stagingSettings, orbitSettings.
    LOCAL throttleCommandValue TO stagingSettings["upper_stage_max_throttle"].
    LOCAL periapsisErrorValue TO orbitSettings["target_periapsis"] - SHIP:PERIAPSIS.
    LOCAL apoapsisOvershootValue TO SHIP:APOAPSIS - orbitSettings["target_apoapsis"].

    IF apoapsisOvershootValue >= 0 {
        RETURN 0.
    }.

    IF periapsisErrorValue <= stagingSettings["upper_stage_perigee_raise_throttle_down_band"] {
        LOCAL throttleBlendValue TO ClampValue(
            periapsisErrorValue / stagingSettings["upper_stage_perigee_raise_throttle_down_band"],
            0,
            1
        ).

        SET throttleCommandValue TO LerpValue(
            stagingSettings["upper_stage_min_throttle"],
            stagingSettings["upper_stage_max_throttle"],
            throttleBlendValue
        ).
    }.

    IF apoapsisOvershootValue > -stagingSettings["upper_stage_perigee_raise_apoapsis_guard_band"] {
        LOCAL apoapsisGuardBlendValue TO ClampValue(
            (stagingSettings["upper_stage_perigee_raise_apoapsis_guard_band"] + apoapsisOvershootValue) /
            stagingSettings["upper_stage_perigee_raise_apoapsis_guard_band"],
            0,
            1
        ).

        SET throttleCommandValue TO MIN(
            throttleCommandValue,
            LerpValue(
                stagingSettings["upper_stage_max_throttle"],
                stagingSettings["upper_stage_min_throttle"],
                apoapsisGuardBlendValue
            )
        ).
    }.

    RETURN ClampValue(throttleCommandValue, 0, stagingSettings["upper_stage_max_throttle"]).
}.

FUNCTION ShutdownUpperStageEngines {
    PARAMETER resolvedManifest.

    // Mirror the ignition helper: keep issuing the shutdown command for a
    // brief window so we catch any engine that is still spooling or not yet
    // responsive on the first frame after cutoff.
    LOCAL shutdownDeadline TO TIME:SECONDS + 3.

    UNTIL TIME:SECONDS >= shutdownDeadline {
        FOR upperStageEnginePart IN resolvedManifest["upper_stage_engines"]["parts"] {
            IF upperStageEnginePart:HASMODULE("ModuleEnginesRF") {
                LOCAL rfModule TO upperStageEnginePart:GETMODULE("ModuleEnginesRF").

                IF rfModule:HASEVENT("Shutdown Engine") {
                    rfModule:DOEVENT("Shutdown Engine").
                }.
            }.
        }.

        WAIT 0.2.

        IF GetActiveUpperStageEngineCount(resolvedManifest) <= 0 {
            RETURN.
        }.
    }.
}.

FUNCTION SlsUpperStageTargetAchieved {
    PARAMETER orbitSettings.
    RETURN ABS(SHIP:PERIAPSIS - orbitSettings["target_periapsis"]) <= orbitSettings["periapsis_tolerance"] AND ABS(SHIP:APOAPSIS - orbitSettings["target_apoapsis"]) <= orbitSettings["apoapsis_tolerance"].
}.
