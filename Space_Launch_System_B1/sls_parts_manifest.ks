GLOBAL FUNCTION GetSlsPartsManifest {
    RETURN LEXICON(
        "core_engines", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("SSME"),
            "required_count", 4,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "core_stage_propellant_tanks", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("SLS Core Stage Propellant Tank"),
            "required_count", 1,
            "trigger_type", "module_action",
            "trigger_name", "ToggleAction",
            "trigger_value", TRUE
        ),
        "upper_stage_engines", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("RL-10C-3"),
            "required_count", 1,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "booster_engines", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("PC.5Seg.RSRM", "benjee10.SLS.BOLE.booster"),
            "required_count", 2,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "abort_protective_cover", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Orion Abort Protective Cover"),
            "required_count", 1,
            "trigger_type", "module_event",
            "module_name", "ModuleDecouple",
            "trigger_name", "Decouple"
        ),
        "abort_jettison_motor", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Orion Abort Jettison Motor"),
            "required_count", 1,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "orion_fairing_panels", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("benjee10.orion.fairingPanel"),
            "required_count", 3,
            "trigger_type", "module_event",
            "module_name", "ModuleDecouple",
            "trigger_name", "Decouple"
        ),
        "abort_launch_motor", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Orion Launch Abort Motor"),
            "required_count", 1,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "booster_separation_motors", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("benjee10.SLS.BOLE.sepMotor", "benjee10.SLS.boosterSepMotor"),
            "required_count", 0,
            "trigger_type", "module_action",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "hold_down_release", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("AM.MLP.SaturnMobileLauncherBaseFree"),
            "required_count", 1,
            "trigger_type", "module_event",
            "module_name", "ModuleDecouple",
            "trigger_name", "Decouple"
        ),
        "launch_clamps", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("AM.MLP.HoldArmSaturnV"),
            "required_count", 2,
            "trigger_type", "module_action",
            "module_name", "ModuleAnimateGenericExtra",
            "trigger_value", TRUE,
            "trigger_name", "ToggleAction"
        ),
        "crew_access_arm", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Saturn Tower Crew Access Arm"),
            "required_count", 1,
            "trigger_type", "module_action",
            "trigger_value", TRUE,
            "trigger_name", "Retract Arm"
        ),
        "booster_separation", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("BOLE SRM Radial Decoupler"),
            "required_count", 2,
            "trigger_type", "module_event",
            "trigger_name", "Decouple"
        ),
        "core_stage_separation", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Launch Vehicle Stage Adapter"),
            "required_count", 1,
            "trigger_type", "module_event",
            "trigger_name", "Decouple"
        ),
        "core_stage_separation_motors", LEXICON(
            "lookup_type", "part_name",
            "identifiers", LIST("bluedog.Lateraltron"),
            "required_count", 2,
            "trigger_type", "module_action",
            "module_name", "ModuleEnginesRF",
            "trigger_value", TRUE,
            "trigger_name", "Activate Engine"
        ),
        "upper_stage_rcs_hardware", LEXICON(
            "lookup_type", "part_title",
            "identifiers", LIST("Exploration Upper Stage"),
            "required_count", 1,
            "trigger_type", "module_action",
            "trigger_name", "ToggleAction",
            "trigger_value", TRUE
        )
    ).
}
