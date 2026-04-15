# NASA Launch Stack

This folder contains the kOS scripts and MCC tooling for the SLS Block 1 launch stack. The code is split into three main parts:

- the launch tower CPU
- the vehicle CPU
- the optional MCC application and file bridge

The scripts are written so the same stack can run in two modes:

- `use_mcc_app = TRUE` for remote operator control through the MCC app
- `use_mcc_app = FALSE` for standalone launches without the app

## Folder Layout

- `SLS_Launch_Tower/`
  - tower countdown logic and pad handoff
- `Space_Launch_System_B1/`
  - vehicle entry point, mission configuration, ascent guidance, staging logic, and part manifest
- `MCC_Interface/`
  - shared text files used by the tower, vehicle, and MCC app
- `NASA_MCC_APP/`
  - the Python mission-control frontend

## High-Level Flow

1. `SLS_Launch_Tower/tower_main.ks` runs on the pad tower CPU.
2. `Space_Launch_System_B1/SLS_Main.ks` runs on the vehicle CPU.
3. `Space_Launch_System_B1/mission_configuration.ks` defines the mission and guidance settings.
4. `Space_Launch_System_B1/sls_parts_manifest.ks` maps script actions to real vessel parts.
5. `Space_Launch_System_B1/sls_core_stage_guidance.ks` handles launch, booster separation, core-stage ascent, and abort hardware.
6. `Space_Launch_System_B1/sls_upper_stage_guidance.ks` handles upper-stage coast and burn logic.
7. `NASA_MCC_APP/` optionally provides a GUI for countdown control and telemetry.

The tower publishes countdown state, the vehicle reads that state, and both sides exchange status through text files in `MCC_Interface/` when the MCC app is enabled.

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

The tower and data CPUs should auto-start from a local `boot.ks` if you want fully hands-off launches.

Tower boot helper:

```kerboscript
RUNPATH("0:/NASA/SLS_Launch_Tower/tower_main.ks").
```

Vehicle boot helper:

```kerboscript
RUNPATH("0:/NASA/Space_Launch_System_B1/SLS_Main.ks").
```

If you are using the separate flight-data CPU, copy the contents of `Space_Launch_System_B1/SLS_Data_CPU_boot.ks` into that CPU’s local `boot.ks`.

### 3. Install the MCC app if you want remote control

If you want tower and vehicle commands routed through the GUI, run the Python app in:

- `NASA_MCC_APP/app.py`

The app reads and writes the bridge files in `MCC_Interface/`.

If you do not want to use the app, set `use_mcc_app` to `FALSE` in `mission_configuration.ks`. The scripts are wired to run in standalone mode without tower handoff dependency.

## What Each File Does

### `Space_Launch_System_B1/SLS_Main.ks`

This is the vehicle entry point.

It:

- loads the mission config
- loads the part manifest
- validates that the vessel has the hardware the scripts expect
- waits for the launch time
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

This file also computes the launch heading from the selected inclination, so the vehicle does not default to a fixed eastward launch.

### `Space_Launch_System_B1/sls_parts_manifest.ks`

This file maps script actions to actual parts on the vessel.

If a part name or title changes in the craft file, update this manifest.

This is the file to edit when you need to:

- rename engine targets
- change decoupler names
- change launch clamp or tower hardware
- add or remove abort hardware

The manifest must match the craft exactly enough for the resolver to find the parts.

### `Space_Launch_System_B1/sls_core_stage_guidance.ks`

This file controls:

- booster separation
- core-stage pitch and throttle shaping
- apoapsis recovery behavior
- core-stage cutoff logic
- abort-cover jettison sequencing

Stage 1 is intentionally not a simple fixed pitch program. It uses launch configuration, current altitude, vertical speed, apoapsis error, and fuel state to decide whether to keep burning or cut off.

Key behaviors:

- If apoapsis is slightly high and the stage still has fuel, it reduces pitch and throttle to recover the profile.
- If fuel is low, it will shut down cleanly instead of wasting the stage.
- The abort hardware is only jettisoned after boosters separate, altitude is high enough, and the flight has passed the configured time gate.
- The abort motor is activated before the cover decouples so the engine is live while it is still on the vessel.

### `Space_Launch_System_B1/sls_upper_stage_guidance.ks`

This file controls the second stage burn and coast logic.

It decides when to:

- ignite for the initial insertion burn
- coast to the next burn window
- burn again to raise periapsis
- hold if the target orbit is already achieved

If you want to change the upper-stage burn window or throttle behavior, this is the file to edit.

### `SLS_Launch_Tower/tower_main.ks`

This file runs the launch tower countdown.

It:

- computes or accepts the launch window
- handles countdown state
- sends the vehicle handoff when MCC mode is enabled
- displays tower status

In standalone mode, the tower does not try to contact the vehicle vessel through the MCC bridge.

### `NASA_MCC_APP/`

This is the optional operator app.

It:

- displays mission status
- reads tower and vehicle status
- writes operator commands to the bridge
- can hold, resume, and re-arm the count

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
   - change part names/titles if the craft uses different hardware
3. `Space_Launch_System_B1/sls_core_stage_guidance.ks`
   - change ascent profile, stage 1 cutoff thresholds, or abort timing
4. `Space_Launch_System_B1/sls_upper_stage_guidance.ks`
   - change stage 2 ignition, coast, and burn window logic
5. `SLS_Launch_Tower/tower_main.ks`
   - change tower countdown and handoff behavior

## Common Tuning Points

- `target_inclination`
  - drives the computed launch heading
- `post_liftoff_roll`
  - sets the initial roll program
- `core_stage_min_fuel_fraction`
  - controls when stage 1 is allowed to shut down
- `apoapsis_cutoff_margin`
  - controls how much overshoot is tolerated before the guidance starts to recover instead of cutting
- `upper_stage_perigee_raise_start_eta`
  - controls when stage 2 begins looking for the perigee-raise burn
- `upper_stage_perigee_raise_throttle_down_band`
  - changes how aggressively upper-stage throttle backs off near target orbit
- `use_mcc_app`
  - toggles between remote operator mode and standalone mode

## Troubleshooting

- If launch validation fails, check `sls_parts_manifest.ks` first.
- If the launch heading looks wrong, check `target_inclination` in `mission_configuration.ks`.
- If the tower is waiting forever in standalone mode, confirm `use_mcc_app` is `FALSE`.
- If a stage command fails on a missing part, the part title or part name in the manifest does not match the vessel.
- If the MCC app is enabled, make sure the files in `MCC_Interface/` are writable.

## Notes

- The launch guidance is written for the SLS Block 1 stack in this folder.
- The code uses a mix of open-loop shaping and state-based heuristics because that is more stable than a single fixed pitch table for this vehicle.
- The comments in the guidance files are intentionally detailed so the flight logic is easier to audit when you revisit it later.
