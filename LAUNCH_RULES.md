# Launch Rule Sheet (LRS)

## 1.0 Controlled Document

- Prepared by: Flight Operations
- Applies to: NASA Launch Stack, SLS Block 1 mission set
- Authority: Flight Operations Director, Chief Engineer, Mission Manager
- Control source: tower CPU, vehicle CPU, mission configuration, parts manifest

This document defines the launch conditions for the software-controlled stack. If this sheet and the flight software disagree, the software gate is binding.

## 2.0 Purpose and Scope

This sheet states what may be launched and what shall not be launched.

It covers:

- weather limits
- tower and vehicle software gates
- countdown discipline
- liftoff commit criteria
- scrub and abort conditions
- ascent limits enforced by the flight software

Relevant software files:

- `Space_Launch_System_B1/mission_configuration.ks`
- `SLS_Launch_Tower/tower_main.ks`
- `Space_Launch_System_B1/SLS_Main.ks`
- `Space_Launch_System_B1/sls_core_stage_guidance.ks`
- `Space_Launch_System_B1/sls_upper_stage_guidance.ks`
- `Space_Launch_System_B1/sls_parts_manifest.ks`

## 3.0 Launch Control Model

The stack is treated as three control layers:

1. tower countdown and launch-window control
2. vehicle terminal countdown and liftoff control
3. ascent and upper-stage guidance

AG6 arms the tower only. The vehicle does not self-arm. The tower is the source of truth for launch timing and sends the handoff command that the vehicle waits for.

When `use_mcc_app = TRUE`, tower and vehicle commands may pass through the MCC bridge. When `use_mcc_app = FALSE`, the same tower-to-vehicle timing logic still applies locally, but the app is not required.

## 4.0 Launch Commit Policy

Launch is GO only when all of the following are true:

- the parts manifest resolves correctly
- the tower and vehicle are using the same mission settings
- the tower handoff is valid
- the countdown mode is valid for the mission
- weather is acceptable
- the readiness report is GO, or WATCH with explicit management acceptance
- core ignition health is nominal
- pad release is nominal
- liftoff thrust is nominal
- delta-v margin is positive
- time warp is not active

If any hard gate fails, the launch is NO-GO.

The correct response to unclear state is HOLD.

## 5.0 Weather And Environment

The software stack does not read live weather sensors. Weather is therefore an operator gate.

### 5.1 GO Weather

Launch may proceed when:

- there is no lightning in the launch or ascent corridor
- there is no thunderstorm activity over the pad or downrange
- surface wind is within pad limits
- gust spread is stable and acceptable
- visibility is sufficient for pad and liftoff monitoring
- cloud ceiling is high enough for safe operations
- there is no heavy precipitation, icing, hail, or dense fog

### 5.2 NO-GO Weather

Launch shall not proceed when:

- lightning is present
- a thunderstorm cell is active nearby
- crosswind or gusting exceeds the accepted handling limit
- rain, hail, icing, or freezing precipitation is present
- visibility is too poor for pad or ascent tracking
- the cloud ceiling is too low for safe launch operations

If weather is marginal, the default is HOLD.

## 6.0 Software Gates

### 6.1 Manifest Validation

The vehicle shall not launch unless the manifest resolves cleanly.

NO-GO conditions:

- missing engine groups
- missing booster, core, upper-stage, abort, release, or fairing hardware
- part names or module actions do not match the vessel

### 6.2 Tower Handoff

The tower is the source of truth for launch timing.

Rules:

- the tower must publish a handoff message
- the vehicle must accept a non-stale handoff
- the handoff must match the intended launch epoch

NO-GO conditions:

- handoff not received
- handoff stale
- tower CPU tag mismatch
- vehicle vessel mismatch

### 6.3 Countdown Modes

Supported modes:

- `MANUAL_COUNTDOWN`
- `RELATIVE_INCLINATION`

Rules:

- manual countdown must be formatted as `HH:MM:SS`
- manual countdown must be at least `00:00:30`
- if the target body matches the launch body, the software resolves to manual countdown
- if the mission is windowed, the tower only goes live inside the relative inclination window

### 6.4 Readiness Gates

The readiness report must be nominal before terminal count can proceed.

Watch conditions are allowed only with explicit acceptance.

### 6.5 Core Ignition Health

At terminal count, the vehicle checks core engine health before release.

Gate values:

- minimum liftoff TWR: `1.15`
- core ignition minimum thrust ratio: `0.90`

### 6.6 Liftoff Health

After booster ignition and pad release, the vehicle validates liftoff performance.

Gate values:

- liftoff thrust ratio must be at least `0.88` during the validation window

### 6.7 Hold, Abort, And Stale State

The tower may place the count in hold before launch.

The vehicle accepts hold and resume commands only while the countdown state is still valid.

Abort remains available at all times.

If the tower or vehicle receives stale control data, the correct response is HOLD and revalidate.

## 7.0 Stage 1 Ascent Rules

Stage 1 is controlled by launch configuration, altitude, vertical speed, apoapsis error, and fuel state.

Current rules:

- roll is suppressed until liftoff vertical speed is established
- the ascent profile is intentionally flatter than a simple gravity-turn table
- the vehicle should not exceed the target apoapsis on stage 1
- if the target apoapsis is reached, stage 1 shuts down
- if the target apoapsis is not reached, stage 1 keeps burning even if fuel is low
- if fuel is exhausted before the target is reached, the stage must stop
- the abort cover is not jettisoned until the time and altitude gates are satisfied
- the abort motor is activated before the cover decouples
- the Orion fairing panels deploy after the abort sequence is complete and the vehicle is above the configured altitude gate

## 8.0 Upper-Stage Rules

The upper stage follows a burn-and-coast sequence.

Rules:

- the engine is activated once per burn window
- throttle is latched for the burn and is not spammed frame by frame
- ullage is prepped before the next burn window
- the engine does not repeatedly activate and shut down during spool-up
- the initial insertion burn is conservative and should not overdrive apoapsis
- the later perigee-raise burn may use vertical-speed recovery to help shape the orbit
- if the target orbit is achieved, the upper stage shuts down cleanly

## 9.0 Decision Matrix

| Item | GO | WATCH | NO-GO |
| --- | --- | --- | --- |
| Weather | All limits satisfied | Marginal but acceptable with manual acceptance | Lightning, storms, severe wind, low visibility, icing |
| Manifest | All parts resolve | N/A | Any required part missing |
| Tower handoff | Valid and current | N/A | Missing, stale, or mismatched |
| Countdown mode | Valid mode selected | N/A | Invalid mode or bad manual count |
| Readiness report | GO | WATCH with sign-off | NO-GO |
| Core ignition | Thrust ratio >= `0.90` | N/A | Below threshold |
| Pad release | Confirmed | N/A | Timeout or failure |
| Liftoff thrust | Thrust ratio >= `0.88` | N/A | Below threshold |

## 10.0 Current Fixed Values

These values are hard-coded or defaulted in the current launch stack:

- manual countdown minimum: `00:00:30`
- relative inclination tolerance: `0.25 deg`
- tower handoff lead time: `120 s`
- core ignition readiness check: `0.5 s` before launch
- tower clear altitude: `250 m`
- max-q start altitude: `9000 m`
- max-q end altitude: `17000 m`
- max-q throttle cap: `0.72`
- stage 1 target apoapsis is the cutoff point
- abort cover release gate: `T+198 s` and `140 km`
- fairing panel deploy gate: `150 km`
- upper-stage ullage lead time: `20 s`
- upper-stage ignition grace time: `6 s`

## 11.0 Final Rule

If a status is unclear, the system holds. If the software says hold, the vehicle holds.
