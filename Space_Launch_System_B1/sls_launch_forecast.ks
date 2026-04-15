// Launch forecast planner for countdown operations.
// This module is loaded by the data CPU so it can read the live ship state,
// sweep candidate ascent profiles, and publish a compact forecast CSV before
// liftoff.

GLOBAL FUNCTION InitializeLaunchForecastState {
    RETURN LEXICON(
        "forecast_active", FALSE,
        "forecast_complete", FALSE,
        "next_checkpoint_seconds", -1,
        "last_checkpoint_seconds", -1,
        "rows", LIST()
    ).
}.

GLOBAL FUNCTION ResetLaunchForecastState {
    PARAMETER state.

    SET state["forecast_active"] TO FALSE.
    SET state["forecast_complete"] TO FALSE.
    SET state["next_checkpoint_seconds"] TO -1.
    SET state["last_checkpoint_seconds"] TO -1.
    SET state["rows"] TO LIST().
}.

GLOBAL FUNCTION IsLaunchForecastCountdownActive {
    PARAMETER towerStatus.

    IF NOT towerStatus:HASKEY("countdown_armed") {
        RETURN FALSE.
    }.

    IF towerStatus:HASKEY("abort_active") AND towerStatus["abort_active"] {
        RETURN FALSE.
    }.

    IF towerStatus:HASKEY("formatted_countdown") {
        LOCAL formattedCountdown TO towerStatus["formatted_countdown"].
        IF formattedCountdown <> "" AND formattedCountdown <> "T-00:00:00" {
            RETURN TRUE.
        }.
    }.

    IF towerStatus:HASKEY("seconds_to_window") {
        RETURN towerStatus["seconds_to_window"]:TONUMBER > 0.
    }.

    RETURN towerStatus["countdown_armed"].
}.

GLOBAL FUNCTION ShouldCaptureLaunchForecastSnapshot {
    PARAMETER towerStatus, state.

    IF state["forecast_complete"] {
        RETURN FALSE.
    }.

    IF NOT IsLaunchForecastCountdownActive(towerStatus) {
        RETURN FALSE.
    }.

    LOCAL currentSeconds TO GetTowerCountdownSeconds(towerStatus).
    IF currentSeconds < 0 {
        RETURN FALSE.
    }.

    IF state["next_checkpoint_seconds"] < 0 {
        RETURN TRUE.
    }.

    RETURN currentSeconds <= state["next_checkpoint_seconds"].
}.

GLOBAL FUNCTION UpdateLaunchForecastSchedule {
    PARAMETER state, currentSeconds.

    IF currentSeconds < 0 {
        SET state["next_checkpoint_seconds"] TO -1.
        RETURN.
    }.

    IF currentSeconds <= 20 {
        SET state["next_checkpoint_seconds"] TO -1.
        SET state["forecast_complete"] TO TRUE.
        RETURN.
    }.

    LOCAL nextCheckpoint TO currentSeconds - 300.
    IF nextCheckpoint < 20 {
        SET nextCheckpoint TO 20.
    }.
    SET state["next_checkpoint_seconds"] TO nextCheckpoint.
}.

GLOBAL FUNCTION GetTowerCountdownSeconds {
    PARAMETER towerStatus.

    IF towerStatus:HASKEY("seconds_to_window") {
        RETURN towerStatus["seconds_to_window"]:TONUMBER.
    }.

    IF towerStatus:HASKEY("countdown_seconds") {
        RETURN towerStatus["countdown_seconds"]:TONUMBER.
    }.

    RETURN -1.
}.

GLOBAL FUNCTION BuildLaunchForecastSnapshot {
    PARAMETER missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, readinessSettings, resolvedManifest, checkpointSecondsToLaunch, sampleIndex.

    LOCAL bestRoute TO SelectBestLaunchForecastRoute(
        missionSettings,
        launchSettings,
        ascentSettings,
        orbitSettings,
        stagingSettings,
        readinessSettings,
        resolvedManifest
    ).

    LOCAL routePoints TO BuildLaunchForecastTrajectorySamples(bestRoute, orbitSettings, sampleIndex).

    RETURN LEXICON(
        "sample_index", sampleIndex,
        "checkpoint_seconds_to_launch", ROUND(MAX(0, checkpointSecondsToLaunch), 1),
        "checkpoint_label", FormatLaunchForecastCountdown(checkpointSecondsToLaunch),
        "mission_elapsed_seconds", ROUND(GetLaunchForecastMissionElapsedSeconds(), 1),
        "route_name", bestRoute["route_name"],
        "route_status", bestRoute["route_status"],
        "launch_heading_deg", ROUND(bestRoute["launch_heading_deg"], 2),
        "pitchover_start_altitude_m", ROUND(bestRoute["pitchover_start_altitude_m"], 0),
        "pitchover_end_altitude_m", ROUND(bestRoute["pitchover_end_altitude_m"], 0),
        "gravity_turn_final_pitch_deg", ROUND(bestRoute["gravity_turn_final_pitch_deg"], 2),
        "gravity_turn_end_altitude_m", ROUND(bestRoute["gravity_turn_end_altitude_m"], 0),
        "estimated_delta_v_mps", ROUND(bestRoute["estimated_delta_v_mps"], 1),
        "predicted_downrange_m", ROUND(bestRoute["predicted_downrange_m"], 0),
        "predicted_altitude_m", ROUND(bestRoute["predicted_altitude_m"], 0),
        "predicted_apoapsis_m", ROUND(bestRoute["predicted_apoapsis_m"], 0),
        "predicted_periapsis_m", ROUND(bestRoute["predicted_periapsis_m"], 0),
        "route_points", routePoints
    ).
}.

GLOBAL FUNCTION BuildLaunchForecastCsvRows {
    PARAMETER snapshotRows.

    LOCAL lines TO LIST().
    lines:ADD("sample_index,checkpoint_seconds_to_launch,checkpoint_label,mission_elapsed_seconds,route_name,route_status,launch_heading_deg,pitchover_start_altitude_m,pitchover_end_altitude_m,gravity_turn_final_pitch_deg,gravity_turn_end_altitude_m,estimated_delta_v_mps,predicted_downrange_m,predicted_altitude_m,predicted_apoapsis_m,predicted_periapsis_m,route_points").

    FOR snapshotRow IN snapshotRows {
        lines:ADD(
            snapshotRow["sample_index"] + "," +
            RoundCsvValue(snapshotRow["checkpoint_seconds_to_launch"]) + "," +
            snapshotRow["checkpoint_label"] + "," +
            RoundCsvValue(snapshotRow["mission_elapsed_seconds"]) + "," +
            snapshotRow["route_name"] + "," +
            snapshotRow["route_status"] + "," +
            RoundCsvValue(snapshotRow["launch_heading_deg"]) + "," +
            RoundCsvValue(snapshotRow["pitchover_start_altitude_m"]) + "," +
            RoundCsvValue(snapshotRow["pitchover_end_altitude_m"]) + "," +
            RoundCsvValue(snapshotRow["gravity_turn_final_pitch_deg"]) + "," +
            RoundCsvValue(snapshotRow["gravity_turn_end_altitude_m"]) + "," +
            RoundCsvValue(snapshotRow["estimated_delta_v_mps"]) + "," +
            RoundCsvValue(snapshotRow["predicted_downrange_m"]) + "," +
            RoundCsvValue(snapshotRow["predicted_altitude_m"]) + "," +
            RoundCsvValue(snapshotRow["predicted_apoapsis_m"]) + "," +
            RoundCsvValue(snapshotRow["predicted_periapsis_m"]) + "," +
            snapshotRow["route_points"]
        ).
    }.

    RETURN lines.
}.

GLOBAL FUNCTION RoundCsvValue {
    PARAMETER value.

    RETURN ROUND(value, 2).
}.

GLOBAL FUNCTION GetLaunchForecastMissionElapsedSeconds {
    RETURN TIME:SECONDS.
}.

GLOBAL FUNCTION FormatLaunchForecastCountdown {
    PARAMETER totalSeconds.

    LOCAL roundedSeconds TO ROUND(MAX(0, totalSeconds), 0).
    LOCAL hours TO FLOOR(roundedSeconds / 3600).
    LOCAL remainingSeconds TO roundedSeconds - (hours * 3600).
    LOCAL minutes TO FLOOR(remainingSeconds / 60).
    LOCAL seconds TO remainingSeconds - (minutes * 60).

    RETURN "T-" + FormatTwoDigits(hours) + ":" + FormatTwoDigits(minutes) + ":" + FormatTwoDigits(seconds).
}.

GLOBAL FUNCTION SelectBestLaunchForecastRoute {
    PARAMETER missionSettings, launchSettings, ascentSettings, orbitSettings, stagingSettings, readinessSettings, resolvedManifest.

    LOCAL stageBreakdown TO BuildLaunchStageDeltaVBreakdown(resolvedManifest).
    LOCAL availableDeltaV TO stageBreakdown["total_delta_v_mps"].
    LOCAL baseRequiredDeltaV TO EstimateOrbitInsertionDeltaV(missionSettings, orbitSettings, readinessSettings)["required_delta_v_mps"].
    LOCAL baseHeading TO launchSettings["post_liftoff_heading"].
    LOCAL basePitchoverStart TO ascentSettings["pitchover_start_altitude"].
    LOCAL basePitchoverEnd TO ascentSettings["pitchover_end_altitude"].
    LOCAL baseGravityTurnEnd TO ascentSettings["gravity_turn_end_altitude"].
    LOCAL baseFinalPitch TO ascentSettings["gravity_turn_final_pitch"].
    LOCAL desiredMixFactor TO ClampValue(orbitSettings["target_periapsis"] / MAX(1, orbitSettings["target_apoapsis"]), 0, 1).
    LOCAL bestCandidate TO LEXICON(
        "route_status", "UNSET",
        "route_name", "UNSET",
        "launch_heading_deg", baseHeading,
        "pitchover_start_altitude_m", basePitchoverStart,
        "pitchover_end_altitude_m", basePitchoverEnd,
        "gravity_turn_final_pitch_deg", baseFinalPitch,
        "gravity_turn_end_altitude_m", baseGravityTurnEnd,
        "estimated_delta_v_mps", 1e20,
        "predicted_downrange_m", 0,
        "predicted_altitude_m", 0,
        "predicted_apoapsis_m", 0,
        "predicted_periapsis_m", 0,
        "score_mps", 1e20,
        "meets_band", FALSE
    ).

    LOCAL headingIndex TO 0.
    UNTIL headingIndex >= 3 {
        LOCAL headingOffset TO -1.5 + (headingIndex * 1.5).

        LOCAL pitchoverStartIndex TO 0.
        UNTIL pitchoverStartIndex >= 3 {
            LOCAL pitchoverStartOffset TO -500 + (pitchoverStartIndex * 500).

            LOCAL pitchoverEndIndex TO 0.
            UNTIL pitchoverEndIndex >= 3 {
                LOCAL pitchoverEndOffset TO -2000 + (pitchoverEndIndex * 2000).

                LOCAL finalPitchIndex TO 0.
                UNTIL finalPitchIndex >= 3 {
                    LOCAL finalPitchOffset TO -4 + (finalPitchIndex * 4).

                    LOCAL gravityEndIndex TO 0.
                    UNTIL gravityEndIndex >= 3 {
                        LOCAL gravityTurnEndOffset TO -5000 + (gravityEndIndex * 5000).

                        LOCAL candidateHeading TO baseHeading + headingOffset.
                        LOCAL candidatePitchoverStart TO MAX(50, basePitchoverStart + pitchoverStartOffset).
                        LOCAL candidatePitchoverEnd TO MAX(candidatePitchoverStart + 500, basePitchoverEnd + pitchoverEndOffset).
                        LOCAL candidateFinalPitch TO ClampValue(baseFinalPitch + finalPitchOffset, 5, 60).
                        LOCAL candidateGravityTurnEnd TO MAX(candidatePitchoverEnd + 1000, baseGravityTurnEnd + gravityTurnEndOffset).
                        LOCAL candidateRouteName TO BuildForecastRouteName(
                            candidateHeading,
                            candidatePitchoverStart,
                            candidatePitchoverEnd,
                            candidateFinalPitch,
                            candidateGravityTurnEnd
                        ).

                        LOCAL routeAssessment TO EstimateForecastRoute(
                            missionSettings,
                            orbitSettings,
                            availableDeltaV,
                            baseRequiredDeltaV,
                            candidateHeading,
                            candidatePitchoverStart,
                            candidatePitchoverEnd,
                            candidateFinalPitch,
                            candidateGravityTurnEnd,
                            baseHeading,
                            desiredMixFactor
                        ).

                        IF routeAssessment["score_mps"] < bestCandidate["score_mps"] {
                            SET bestCandidate TO routeAssessment.
                            SET bestCandidate["route_name"] TO candidateRouteName.
                        }.

                        SET gravityEndIndex TO gravityEndIndex + 1.
                    }.

                    SET finalPitchIndex TO finalPitchIndex + 1.
                }.

                SET pitchoverEndIndex TO pitchoverEndIndex + 1.
            }.

            SET pitchoverStartIndex TO pitchoverStartIndex + 1.
        }.

        SET headingIndex TO headingIndex + 1.
    }.

    IF bestCandidate["route_status"] = "UNSET" {
        SET bestCandidate["route_status"] TO "FALLBACK".
        SET bestCandidate["route_name"] TO BuildForecastRouteName(baseHeading, basePitchoverStart, basePitchoverEnd, baseFinalPitch, baseGravityTurnEnd).
        SET bestCandidate["launch_heading_deg"] TO baseHeading.
        SET bestCandidate["pitchover_start_altitude_m"] TO basePitchoverStart.
        SET bestCandidate["pitchover_end_altitude_m"] TO basePitchoverEnd.
        SET bestCandidate["gravity_turn_final_pitch_deg"] TO baseFinalPitch.
        SET bestCandidate["gravity_turn_end_altitude_m"] TO baseGravityTurnEnd.
        SET bestCandidate["estimated_delta_v_mps"] TO baseRequiredDeltaV.
        SET bestCandidate["predicted_downrange_m"] TO 0.
        SET bestCandidate["predicted_altitude_m"] TO orbitSettings["stage_one_handoff_apoapsis"].
        SET bestCandidate["predicted_apoapsis_m"] TO orbitSettings["target_apoapsis"].
        SET bestCandidate["predicted_periapsis_m"] TO orbitSettings["target_periapsis"].
        SET bestCandidate["score_mps"] TO baseRequiredDeltaV.
        SET bestCandidate["meets_band"] TO TRUE.
    }.

    IF bestCandidate["meets_band"] {
        SET bestCandidate["route_status"] TO "LOCKED".
    } ELSE {
        SET bestCandidate["route_status"] TO "ESTIMATED".
    }.

    RETURN bestCandidate.
}.

GLOBAL FUNCTION IsResolvedManifestValid {
    PARAMETER resolvedManifest.

    FOR groupName IN resolvedManifest:KEYS {
        IF NOT resolvedManifest[groupName]["is_valid"] {
            RETURN FALSE.
        }.
    }.

    RETURN TRUE.
}.

GLOBAL FUNCTION EstimateForecastRoute {
    PARAMETER missionSettings, orbitSettings, availableDeltaV, baseRequiredDeltaV, candidateHeading, candidatePitchoverStart, candidatePitchoverEnd, candidateFinalPitch, candidateGravityTurnEnd, baseHeading, desiredMixFactor.

    LOCAL headingPenalty TO ABS(candidateHeading - baseHeading) * 3.5.
    LOCAL pitchoverPenalty TO ABS(candidatePitchoverStart - 250) / 2.
    SET pitchoverPenalty TO pitchoverPenalty + (ABS(candidatePitchoverEnd - 6000) / 1.5).
    LOCAL gravityPenalty TO ABS(candidateFinalPitch - 20) * 6.
    SET gravityPenalty TO gravityPenalty + (ABS(candidateGravityTurnEnd - 60000) / 10).
    LOCAL mixFactor TO ClampValue((90 - candidateFinalPitch) / 90, 0, 1).
    LOCAL mixPenalty TO ABS(mixFactor - desiredMixFactor) * 90.
    LOCAL estimatedDeltaV TO baseRequiredDeltaV + headingPenalty + pitchoverPenalty + gravityPenalty + mixPenalty.
    LOCAL predictedApoapsis TO orbitSettings["target_apoapsis"] + ((20 - candidateFinalPitch) * 250) - (ABS(candidateHeading - baseHeading) * 180).
    LOCAL predictedPeriapsis TO orbitSettings["target_periapsis"] + ((candidatePitchoverEnd - 6000) * 1.5) - (ABS(candidateHeading - baseHeading) * 120).
    LOCAL meetsBand TO ABS(predictedApoapsis - orbitSettings["target_apoapsis"]) <= orbitSettings["apoapsis_tolerance"] AND ABS(predictedPeriapsis - orbitSettings["target_periapsis"]) <= orbitSettings["periapsis_tolerance"] AND estimatedDeltaV <= availableDeltaV.
    LOCAL score TO estimatedDeltaV.

    IF NOT meetsBand {
        SET score TO score + 5000.
    }.

    RETURN LEXICON(
        "route_status", "CANDIDATE",
        "route_name", "",
        "launch_heading_deg", candidateHeading,
        "pitchover_start_altitude_m", candidatePitchoverStart,
        "pitchover_end_altitude_m", candidatePitchoverEnd,
        "gravity_turn_final_pitch_deg", candidateFinalPitch,
        "gravity_turn_end_altitude_m", candidateGravityTurnEnd,
        "estimated_delta_v_mps", estimatedDeltaV,
        "predicted_downrange_m", EstimateForecastHandoffDownrange(candidateFinalPitch, candidateHeading, orbitSettings),
        "predicted_altitude_m", orbitSettings["stage_one_handoff_apoapsis"],
        "predicted_apoapsis_m", predictedApoapsis,
        "predicted_periapsis_m", predictedPeriapsis,
        "score_mps", score,
        "meets_band", meetsBand
    ).
}.

GLOBAL FUNCTION EstimateForecastHandoffDownrange {
    PARAMETER candidateFinalPitch, candidateHeading, orbitSettings.

    LOCAL pitchRadiansScale TO MAX(0.15, SIN(candidateFinalPitch)).
    LOCAL horizontalFraction TO COS(candidateFinalPitch).
    LOCAL baseDownrange TO orbitSettings["stage_one_handoff_apoapsis"] * (horizontalFraction / pitchRadiansScale) * 0.12.
    LOCAL headingPenalty TO ABS(candidateHeading - 90) * 750.

    RETURN MAX(0, baseDownrange + headingPenalty).
}.

GLOBAL FUNCTION BuildLaunchForecastTrajectorySamples {
    PARAMETER routeAssessment, orbitSettings, sampleIndex.

    LOCAL sampleCount TO 16.
    LOCAL routePoints TO "".
    LOCAL launchAltitude TO SHIP:ALTITUDE.
    LOCAL targetAltitude TO orbitSettings["stage_one_handoff_apoapsis"].
    LOCAL targetDownrange TO routeAssessment["predicted_downrange_m"].
    LOCAL altitudeExponent TO LerpValue(1.65, 1.05, ClampValue((90 - routeAssessment["gravity_turn_final_pitch_deg"]) / 90, 0, 1)).
    LOCAL downrangeExponent TO LerpValue(1.55, 0.95, ClampValue((90 - routeAssessment["gravity_turn_final_pitch_deg"]) / 90, 0, 1)).
    LOCAL i TO 0.

    UNTIL i >= sampleCount {
        LOCAL progress TO i / MAX(1, sampleCount - 1).
        LOCAL altitudeValue TO launchAltitude + ((targetAltitude - launchAltitude) * (progress ^ altitudeExponent)).
        LOCAL downrangeValue TO targetDownrange * (progress ^ downrangeExponent).

        IF i > 0 {
            SET routePoints TO routePoints + ";".
        }.

        SET routePoints TO routePoints + ROUND(downrangeValue, 0) + "|" + ROUND(altitudeValue, 0).
        SET i TO i + 1.
    }.

    RETURN routePoints.
}.

GLOBAL FUNCTION BuildForecastRouteName {
    PARAMETER launchHeading, pitchoverStart, pitchoverEnd, finalPitch, gravityTurnEnd.

    RETURN "HDG " + ROUND(launchHeading, 1) +
        " PIT " + ROUND(pitchoverStart, 0) + "-" + ROUND(pitchoverEnd, 0) +
        " GT " + ROUND(finalPitch, 1) + "@" + ROUND(gravityTurnEnd, 0).
}.

GLOBAL FUNCTION BuildLaunchStageDeltaVBreakdown {
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

GLOBAL FUNCTION BuildStageReadinessReport {
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

GLOBAL FUNCTION GetStageMassSummary {
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

GLOBAL FUNCTION GetStageEffectiveIsp {
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

GLOBAL FUNCTION GetStageBurnTimeEstimate {
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

GLOBAL FUNCTION GetPropellantNamesFromParts {
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

GLOBAL FUNCTION AppendPartList {
    PARAMETER destinationParts, sourceParts.

    FOR sourcePart IN sourceParts {
        destinationParts:ADD(sourcePart).
    }.
}.

GLOBAL FUNCTION EstimateOrbitInsertionDeltaV {
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

GLOBAL FUNCTION EstimateLaunchLosses {
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

GLOBAL FUNCTION LerpValue {
    PARAMETER startValue, endValue, blendFraction.

    RETURN startValue + ((endValue - startValue) * ClampValue(blendFraction, 0, 1)).
}.

GLOBAL FUNCTION ClampValue {
    PARAMETER value, minimumValue, maximumValue.

    IF value < minimumValue {
        RETURN minimumValue.
    }.

    IF value > maximumValue {
        RETURN maximumValue.
    }.

    RETURN value.
}.

GLOBAL FUNCTION FormatTwoDigits {
    PARAMETER value.

    LOCAL roundedValue TO ROUND(MAX(0, value), 0).

    IF roundedValue < 10 {
        RETURN "0" + roundedValue.
    }.

    RETURN "" + roundedValue.
}.
