// SLS mission configuration.
// Consumer pattern:
//   RUNPATH("0:/NASA/Space_Launch_System_B1/mission_configuration.ks").
//   LOCAL missionConfig TO GetMissionConfiguration().

// The navigation helper depends on the shared maths library, so load maths
// first to make sure limitarg()/clamp() and related helpers are available.
RUNPATH("0:/Libraries/maths_library").
RUNPATH("0:/Libraries/navigation_library").

GLOBAL FUNCTION ComputeSlsLaunchHeading {
    PARAMETER targetInclination, targetApoapsisMeters, targetPeriapsisMeters.

    LOCAL launchBody TO SHIP:BODY.
    LOCAL targetApoapsisRadius TO launchBody:RADIUS + targetApoapsisMeters.
    LOCAL targetPeriapsisRadius TO launchBody:RADIUS + targetPeriapsisMeters.
    LOCAL targetSemiMajorAxis TO (targetPeriapsisRadius + targetApoapsisRadius) / 2.
    LOCAL targetOrbitSpeed TO SQRT(launchBody:MU * (2 / targetPeriapsisRadius - 1 / targetSemiMajorAxis)).

    // Reuse the standard launch-azimuth geometry helper so the selected
    // inclination directly determines the heading used at liftoff.
    RETURN launchAzimuth(targetInclination, targetOrbitSpeed, targetInclination < 0).
}.

GLOBAL FUNCTION GetMissionConfiguration {
    // User-editable mission inputs. Keep this block small.
    LOCAL userSettings TO LEXICON(
        "mission_name", "SLS_ORION_ARTEMIS",
        "use_mcc_app", FALSE,
        "target_body", "Earth",
        "target_body_apoapsis", 800000,
        "target_body_periapsis", 456000,
        "target_inclination", -28.62,
        "manual_countdown_time", "00:00:30",
        "launch_roll_degrees", 90
    ).

    // Internal mission defaults. These remain in the runtime config, but they are not meant to be edited often.
    LOCAL feetToMeters TO 0.3048.
    LOCAL nasaCoreStageSeparationAltitude TO 547560 * feetToMeters.
    LOCAL stageOneHandoffApoapsis TO nasaCoreStageSeparationAltitude.
    LOCAL missionTargetApoapsis TO userSettings["target_body_apoapsis"].
    LOCAL missionTargetPeriapsis TO userSettings["target_body_periapsis"].
    LOCAL computedLaunchHeading TO ComputeSlsLaunchHeading(
        userSettings["target_inclination"],
        missionTargetApoapsis,
        missionTargetPeriapsis
    ).
    LOCAL stableMissionOrbitPeriapsis TO missionTargetPeriapsis - 25000.
    LOCAL parkingOrbitTolerance TO 2500.
    LOCAL maxQThrottleLimit TO 0.72.
    LOCAL launchWindowMode TO "AUTO".
    LOCAL countdownRefreshRate TO 1.
    LOCAL windowAlignmentTolerance TO 0.25.
    LOCAL windowSolutionRefreshSeconds TO 1800.
    LOCAL relativeInclinationSearchStepSeconds TO 300.
    LOCAL relativeInclinationRefineStepSeconds TO 5.

    LOCAL handoffTimeSeconds TO 120.
    LOCAL vehicleId TO "sls_block_1".
    LOCAL vehicleCpuTag TO "SLS_MAIN_CPU".
    LOCAL vehicleVesselName TO "SLS Crew".
    LOCAL engineStartTimeSeconds TO 6.
    LOCAL coreEngineReadyCheckTimeSeconds TO 0.5.
    LOCAL coreEngineStartMinThrustRatio TO 0.9.
    LOCAL vehicleReleaseTimeSeconds TO 0.
    LOCAL releaseAbortTimeoutSeconds TO 2.
    LOCAL releaseConfirmVerticalSpeed TO 0.5.
    LOCAL liftoffCommitTimeSeconds TO 0.
    LOCAL liftoffValidationSeconds TO 3.
    LOCAL liftoffMinThrustRatio TO 0.88.
    LOCAL postLiftoffPitchHold TO 90.
    LOCAL postLiftoffHeading TO computedLaunchHeading.
    LOCAL postLiftoffRoll TO userSettings["launch_roll_degrees"].
    LOCAL postLiftoffThrottle TO 1.0.
    LOCAL towerClearAltitude TO 250.

    LOCAL launchConfig TO LEXICON(
        "handoff_time_seconds", handoffTimeSeconds,
        "vehicle_id", vehicleId,
        "vehicle_cpu_tag", vehicleCpuTag,
        "vehicle_vessel_name", vehicleVesselName,
        "engine_start_time_seconds", engineStartTimeSeconds,
        "core_engine_ready_check_time_seconds", coreEngineReadyCheckTimeSeconds,
        "core_engine_start_min_thrust_ratio", coreEngineStartMinThrustRatio,
        "vehicle_release_time_seconds", vehicleReleaseTimeSeconds,
        "release_abort_timeout_seconds", releaseAbortTimeoutSeconds,
        "release_confirm_vertical_speed", releaseConfirmVerticalSpeed,
        "liftoff_commit_time_seconds", liftoffCommitTimeSeconds,
        "liftoff_validation_seconds", liftoffValidationSeconds,
        "liftoff_min_thrust_ratio", liftoffMinThrustRatio,
        "post_liftoff_pitch_hold", postLiftoffPitchHold,
        "post_liftoff_heading", postLiftoffHeading,
        "post_liftoff_roll", postLiftoffRoll,
        "post_liftoff_throttle", postLiftoffThrottle,
        "tower_clear_altitude", towerClearAltitude
    ).

    LOCAL ascentConfig TO LEXICON(
        "launch_heading", computedLaunchHeading,
        "roll_program_start_vertical_speed", 50,
        "steering_roll_ts", 20,
        "pitchover_start_altitude", 250,
        "pitchover_end_altitude", 6000,
        "pitchover_start_pitch", 90,
        "pitchover_end_pitch", 60,
        "boost_guidance_end_altitude", 50000,
        "boost_guidance_end_pitch", 20,
        "boost_guidance_curve_exponent", 0.6,
        "core_guidance_start_altitude", 50000,
        "core_guidance_end_altitude", nasaCoreStageSeparationAltitude,
        "core_stage_terminal_pitch", 12,
        "core_guidance_curve_exponent", 0.7,
        "gravity_turn_start_altitude", 6000,
        "gravity_turn_end_altitude", 60000,
        "gravity_turn_final_pitch", 15,
        "gravity_turn_curve_exponent", 0.65,
        "gravity_turn_min_pitch", 20,
        "pitch_up_rate_limit", 0.5,
        "pitch_down_rate_limit", 1.0,
        "max_q_start_altitude", 9000,
        "max_q_end_altitude", 17000,
        "max_q_throttle_limit", maxQThrottleLimit,
        "solid_booster_min_throttle", 1.0,
        "core_stage_min_throttle", 0.65,
        "core_stage_max_throttle", 1.0,
        "core_stage_apoapsis_hold_throttle", 0.95,
        "core_stage_apoapsis_overshoot_throttle", 0.75,
        "apoapsis_pitch_up_shortfall", 12000,
        "apoapsis_pitch_up_bias_max", 0.75,
        "stage_one_handoff_apoapsis_buffer", 30000,
        "stage_one_handoff_apoapsis_control_band", 60000,
        "stage_one_handoff_pitch_up_gain", 2.0,
        "stage_one_handoff_pitch_down_gain", 9.0,
        "stage_one_handoff_eta_margin", 20,
        "stage_one_handoff_eta_control_band", 60,
        "stage_one_handoff_eta_pitch_up_gain", 1.0,
        "stage_one_handoff_eta_pitch_down_gain", 5.0,
        "stage_one_apoapsis_safety_fraction", 0.75,
        "stage_one_apoapsis_safety_pitch_down_gain", 10.0,
        "stage_one_apoapsis_safety_throttle_down_gain", 0.7,
        "stage_one_vertical_speed_floor", 90,
        "stage_one_vertical_speed_control_band", 120,
        "stage_one_vertical_speed_pitch_gain", 0.5,
        "stage_one_booster_sep_recovery_pitch_bias", 0.0,
        "stage_one_booster_sep_recovery_end_altitude", 80000,
        "engine_cutoff_target_apoapsis", stageOneHandoffApoapsis,
        "apoapsis_throttle_down_margin", 15000,
        "apoapsis_fine_tune_margin", 5000,
        "apoapsis_cutoff_margin", 250,
        "stage_one_meco_eta_threshold", 20,
        "stage_one_meco_vertical_speed_threshold", 120,
        "guidance_update_interval", 0.1
    ).

    LOCAL orbitConfig TO LEXICON(
        "target_apoapsis", missionTargetApoapsis,
        "target_periapsis", missionTargetPeriapsis,
        "stage_one_handoff_apoapsis", stageOneHandoffApoapsis,
        "apoapsis_tolerance", parkingOrbitTolerance,
        "periapsis_tolerance", 5000,
        "stable_orbit_min_periapsis", stableMissionOrbitPeriapsis
    ).

    LOCAL stagingConfig TO LEXICON(
        "booster_separation_thrust_ratio", 0.15,
        "booster_separation_vertical_speed_min", 50,
        "core_engine_min_operating_thrust", 50,
        "core_stage_min_fuel_fraction", 0.15,
        "upper_stage_ignition_delay", 2,
        "upper_stage_settle_time", 5,
        "upper_stage_ignition_grace_time", 6,
        "upper_stage_ullage_prep_lead_time", 20,
        "upper_stage_perigee_raise_start_eta", 45,
        "upper_stage_perigee_raise_throttle_down_band", 40000,
        "upper_stage_perigee_raise_apoapsis_guard_band", 25000,
        "upper_stage_min_fuel_fraction", 0.15,
        "upper_stage_vertical_speed_deadband", 2.0,
        "upper_stage_vertical_speed_pitch_gain", 0.12,
        "upper_stage_vertical_speed_pitch_bias", 2.0,
        "upper_stage_vertical_speed_filter_alpha", 0.15,
        "upper_stage_pitch_up_rate_limit", 0.45,
        "upper_stage_pitch_down_rate_limit", 0.65,
        "upper_stage_min_throttle", 0.2,
        "upper_stage_max_throttle", 1.0,
        "upper_stage_throttle_down_band", 30000,
        "upper_stage_guidance_interval", 0.1
    ).

    LOCAL readinessConfig TO LEXICON(
        "minimum_liftoff_twr", 1.15,
        "watch_delta_v_margin_mps", 500,
        "launch_loss_floor_mps", 600,
        "launch_loss_ceiling_mps", 1700,
        "launch_loss_atmosphere_reference_height_m", 100000
    ).

    RETURN LEXICON(
        "mission", LEXICON(
            "mission_name", userSettings["mission_name"],
            "use_mcc_app", userSettings["use_mcc_app"],
            "target_body", userSettings["target_body"],
            "target_body_apoapsis", userSettings["target_body_apoapsis"],
            "target_body_periapsis", userSettings["target_body_periapsis"],
            "target_inclination", userSettings["target_inclination"],
            "launch_window_mode", launchWindowMode,
            "manual_countdown_time", userSettings["manual_countdown_time"],
            "manual_countdown_min_seconds", 30,
            "manual_countdown_reject_seconds", 10,
            "countdown_refresh_rate", countdownRefreshRate,
            "window_alignment_tolerance", windowAlignmentTolerance,
            "window_solution_refresh_seconds", windowSolutionRefreshSeconds,
            "relative_inclination_search_step_seconds", relativeInclinationSearchStepSeconds,
            "relative_inclination_refine_step_seconds", relativeInclinationRefineStepSeconds
        ),
        "launch", launchConfig,
        "ascent", ascentConfig,
        "orbit", orbitConfig,
        "staging", stagingConfig,
        "readiness", readinessConfig
    ).
}
