# NASA Launch Stack

This folder contains the kOS scripts and MCC tooling for the SLS Block 1 launch stack.

The stack is split into three cooperating pieces:

- the launch tower CPU
- the vehicle CPU
- the optional MCC application and file bridge

The scripts support two operating styles:

- `use_mcc_app = TRUE` for remote operator control through the MCC app
- `use_mcc_app = FALSE` for local operation without the app

In both cases the tower remains the source of truth for launch timing. The vehicle does not self-arm. It waits for the tower handoff command before terminal count begins.

## Folder Layout

- `SLS_Launch_Tower/`
  - tower countdown logic and handoff publication
- `Space_Launch_System_B1/`
  - vehicle entry point, mission configuration, ascent guidance, staging logic, and parts manifest
- `MCC_Interface/`
  - shared text files used by the tower, vehicle, and MCC app
- `NASA_MCC_APP/`
  - the Python mission-control frontend

## High-Level Flow

1. `SLS_Launch_Tower/tower_main.ks` runs on the pad tower CPU.
2. `Space_Launch_System_B1/SLS_Main.ks` runs on the vehicle CPU.
3. `Space_Launch_System_B1/mission_configuration.ks` defines the mission and guidance settings.
4. `Space_Launch_System_B1/sls_parts_manifest.ks` maps script actions to real vessel parts.
5. `Space_Launch_System_B1/sls_core_stage_guidance.ks` handles launch, booster separation, core-stage ascent, fairing deployment, and abort hardware.
6. `Space_Launch_System_B1/sls_upper_stage_guidance.ks` handles upper-stage coast and burn logic.
7. `NASA_MCC_APP/` optionally provides a GUI for tower commands and telemetry.

The tower publishes countdown state, the vehicle reads that state, and both sides exchange status through text files in `MCC_Interface/`.

## Setup

### 1. Put the scripts in the correct kOS paths

The kOS scripts expect to be reachable under the `0:/NASA/...` path inside the game.

The important files are:

- `0:/NASA/SLS_Launch_Tower/tower_main.ks`
- `0:/NASA/Space_Launch_System_B1/SLS_Main.ks`
- `0:/NASA/Space_Launch_System_B1/mission_configuration.ks`
- `0:/NASA/Space_Launch_System_B1/sls_parts_manifest.ks`
- `0:/NASA/Space_Launch_System_B1/sls_core_stage_guidance.ks`
- `0:/NASA/Space_Launch_System_B1/sls_upper_stage_guidance.ks`
- `0:/NASA/MCC_Interface/mcc_bridge.ks`

### 2. Boot the CPUs

The tower and data CPUs should auto-start from a local `boot.ks` if you want hands-off launches.

Tower boot helper:

```kerboscript
RUNPATH("0:/NASA/SLS_Launch_Tower/tower_main.ks").
```

Vehicle boot helper:

```kerboscript
RUNPATH("0:/NASA/Space_Launch_System_B1/SLS_Main.ks").
```

If you are using the separate flight-data CPU, copy the contents of `Space_Launch_System_B1/SLS_Data_CPU_boot.ks` into that CPU's local `boot.ks`.

The data CPU also writes a prelaunch forecast CSV:

- `MCC_Interface/vehicle_launch_forecast.csv`

During countdown that file is refreshed with the current best launch profile and a sampled route preview. It is a deterministic forecast, not live flight telemetry. The MCC app uses it before liftoff and then switches to `vehicle_flight_log.csv` after launch.

### 3. Install the MCC app if you want remote control

If you want tower commands and telemetry routed through the GUI, run the Python app in:

- `NASA_MCC_APP/app.py`

The app reads and writes the bridge files in `MCC_Interface/`.

If you do not want to use the app, set `use_mcc_app` to `FALSE` in `mission_configuration.ks`. The tower still arms the launch and sends the vehicle handoff locally.

### 4. Launch discipline

- AG6 arms the tower only.
- The vehicle waits for the tower handoff before terminal count.
- Do not start the vehicle CPU expecting it to self-arm the countdown.

## What Each File Does

### `Space_Launch_System_B1/SLS_Main.ks`

This is the vehicle entry point.

It:

- loads the mission config
- loads the parts manifest
- validates that the vessel has the hardware the scripts expect
- waits for the tower handoff
- starts engines, releases the pad, and hands off to ascent guidance
- switches to upper-stage guidance after core-stage separation

### `Space_Launch_System_B1/mission_configuration.ks`

This is the main place to tune mission behavior.

Important settings live in the `userSettings` block:

- `mission_name`
- `use_mcc_app`
- `target_body`
- `target_body_apoapsis`
- `target_body_periapsis`
- `target_inclination`
- `manual_countdown_time`
- `launch_roll_degrees`

This file computes the launch heading from the selected inclination, so the vehicle does not default to a fixed eastward launch.

### `Space_Launch_System_B1/sls_parts_manifest.ks`

This file maps script actions to actual parts on the vessel.

If a part name or title changes in the craft file, update this manifest.

This is the file to edit when you need to:

- rename engine targets
- change decoupler names
- change launch clamp or tower hardware
- add or remove abort hardware
- update fairing panel triggers

The manifest must match the craft closely enough for the resolver to find the parts and the correct module actions.

### `Space_Launch_System_B1/sls_core_stage_guidance.ks`

This file controls:

- booster separation
- core-stage pitch and throttle shaping
- apoapsis recovery behavior
- core-stage cutoff logic
- abort-cover jettison sequencing
- Orion abort motor and fairing deployment sequencing

Stage 1 is intentionally not a fixed pitch table.
It uses launch configuration, current altitude, vertical speed, apoapsis error, and fuel state to decide whether to keep burning or cut off.

Current stage-1 behavior:

- roll is held off until the vehicle is actually moving
- the ascent profile is deliberately flatter than a tall gravity turn
- the target apoapsis is the hard cutoff point for stage 1
- if stage 1 reaches the target apoapsis, the core stage shuts down
- if stage 1 is still below target, it keeps burning until the target is reached or the tank is empty
- the abort motor is activated before the cover decouples
- the abort cover is only jettisoned after the altitude and time gates are satisfied
- the Orion fairing panels deploy after the configured altitude gate is met

### `Space_Launch_System_B1/sls_upper_stage_guidance.ks`

This file controls the second-stage burn and coast logic.

It decides when to:

- ignite for the initial insertion burn
- coast to the next burn window
- burn again to raise periapsis
- hold if the target orbit is already achieved

Current upper-stage behavior:

- the burn throttle is latched instead of being reissued every frame
- the engine is activated once per burn window
- ullage is prepped before the next burn window
- the engine is not repeatedly activated and shut down during spool-up
- the later perigee-raise burn may use vertical-speed recovery to help shape the orbit
- if the target orbit is achieved, the upper stage shuts down cleanly

### `SLS_Launch_Tower/tower_main.ks`

This file runs the launch tower countdown.

It:

- computes or accepts the launch window
- handles countdown state
- sends the vehicle handoff in both MCC and standalone modes
- displays tower status

The tower is the launch-time source of truth.

### `NASA_MCC_APP/`

This is the optional operator app.

It:

- displays mission status
- reads tower and vehicle status
- writes operator commands to the bridge
- can hold, resume, and arm the tower countdown

Run it from source:

```powershell
python .\app.py
```

Build it to an executable:

```powershell
.\build_exe.ps1
```

## What To Change First

If you are tuning a mission, start here:

1. `Space_Launch_System_B1/mission_configuration.ks`
   - change target body, inclination, apoapsis, periapsis, countdown, and launch roll
2. `Space_Launch_System_B1/sls_parts_manifest.ks`
   - change part names or module actions if the craft uses different hardware
3. `Space_Launch_System_B1/sls_core_stage_guidance.ks`
   - change ascent profile, stage 1 cutoff behavior, abort timing, or fairing deployment
4. `Space_Launch_System_B1/sls_upper_stage_guidance.ks`
   - change stage 2 ignition, coast, ullage, and burn-window logic
5. `SLS_Launch_Tower/tower_main.ks`
   - change tower countdown and handoff behavior

## Common Tuning Points

- `target_inclination`
  - drives the computed launch heading
- `post_liftoff_roll`
  - sets the initial roll program
- `upper_stage_ullage_prep_lead_time`
  - controls how early ullage is pulsed before the next upper-stage burn
- `upper_stage_perigee_raise_start_eta`
  - controls when stage 2 begins looking for the perigee-raise burn
- `use_mcc_app`
  - toggles between remote operator mode and standalone tower operation

## Troubleshooting

- If launch validation fails, check `sls_parts_manifest.ks` first.
- If the launch heading looks wrong, check `target_inclination` in `mission_configuration.ks`.
- If the tower looks idle, confirm `tower_main.ks` is running on the tower CPU.
- If the vehicle starts too early, confirm the tower has sent a handoff and the vehicle CPU has not been started out of sequence.
- If a stage command fails on a missing part, the part title or part name in the manifest does not match the vessel.
- If the MCC app is enabled, make sure the files in `MCC_Interface/` are writable.

## Notes

- The launch guidance is written for the SLS Block 1 stack in this folder.
- The code uses a mix of open-loop shaping and state-based heuristics because that is more stable than a single fixed pitch table for this vehicle.
- The comments in the guidance files are intentionally detailed so the flight logic is easier to audit when you revisit it later.
