# Launch Rule Sheet

## 1.0 CONTROLLED DOCUMENT

- Prepared by: Flight Operations
- Applies to: NASA Launch Stack, SLS Block 1 mission set
- Authority: Flight Operations Director, Chief Engineer, Mission Manager
- Control source: tower CPU, vehicle CPU, mission configuration, parts manifest

This document defines the launch conditions for the software-controlled stack. If this sheet and the flight software disagree, the software gate is binding.

## 2.0 PURPOSE

This sheet states what may be launched and what shall not be launched.

It covers:

- weather limits
- software readiness
- countdown discipline
- liftoff commit criteria
- scrub and abort conditions
- ascent software limits that affect launch acceptance

Relevant software files:

- `Space_Launch_System_B1/mission_configuration.ks`
- `SLS_Launch_Tower/tower_main.ks`
- `Space_Launch_System_B1/SLS_Main.ks`
- `Space_Launch_System_B1/sls_core_stage_guidance.ks`
- `Space_Launch_System_B1/sls_upper_stage_guidance.ks`
- `Space_Launch_System_B1/sls_parts_manifest.ks`

## 3.0 MISSION STRUCTURE

The stack is treated as three control layers:

1. tower countdown and launch window control
2. vehicle terminal countdown and liftoff control
3. ascent and upper-stage guidance

Launch is not approved unless all three layers are nominal.

## 4.0 LAUNCH COMMIT CRITERIA

### 4.1 GO / NO-GO POLL

Launch is GO only when all of the following are true:

- the parts manifest resolves correctly
- the tower and vehicle are using the same mission settings
- the tower handoff is valid when `use_mcc_app = TRUE`
- the countdown mode is valid for the mission
- weather is acceptable
- the readiness report is GO, or WATCH with explicit management acceptance
- core ignition health is nominal
- pad release is nominal
- liftoff thrust is nominal
- delta-v margin is positive
- time warp is not active

If any hard gate fails, the launch is NO-GO.

### 4.2 LAUNCH COMMIT STANDARD

The stack does not launch into uncertainty.

If the status is unclear, the correct action is HOLD.

## 5.0 WEATHER AND ENVIRONMENT

The current software does not read live weather sensors. Weather is therefore an operator gate.

### 5.1 GO WEATHER

Launch may proceed when:

- there is no lightning in the launch or ascent corridor
- there is no thunderstorm activity over the pad or downrange
- surface wind is within pad limits
- gust spread is stable and acceptable
- visibility is sufficient for pad and liftoff monitoring
- cloud ceiling is high enough for safe operations
- there is no heavy precipitation, icing, hail, or dense fog

### 5.2 NO-GO WEATHER

Launch shall not proceed when:

- lightning is present
- a thunderstorm cell is active nearby
- crosswind or gusting exceeds the accepted handling limit
- rain, hail, icing, or freezing precipitation is present
- visibility is too poor for pad or ascent tracking
- the cloud ceiling is too low for safe launch operations

### 5.3 WEATHER DEFAULT

If weather is marginal, the default is HOLD.

## 6.0 SOFTWARE GATES

### 6.1 MANIFEST VALIDATION

The vehicle shall not launch unless the manifest resolves cleanly.

NO-GO conditions:

- missing engine groups
- missing booster, core, upper-stage, abort, or release hardware
- part names or module actions do not match the vessel

If validation fails, the vehicle stays in hold.

### 6.2 TOWER HANDOFF

When `use_mcc_app = TRUE`, the tower is the source of truth for launch timing.

Rules:

- the tower must publish a handoff message
- the vehicle must accept a non-stale handoff
- the handoff must match the intended launch epoch

NO-GO conditions:

- handoff not received
- handoff stale
- tower CPU tag mismatch
- vessel mismatch

When `use_mcc_app = FALSE`, the system may run locally, but the same launch timing logic still applies.

### 6.3 COUNTDOWN MODE

Supported modes:

- `MANUAL_COUNTDOWN`
- `RELATIVE_INCLINATION`

Rules:

- manual countdown must be `HH:MM:SS`
- manual countdown must be at least `00:00:30`
- if the target body matches the launch body, the software resolves to manual countdown
- if the mission is windowed, the tower only goes live inside the relative inclination window

NO-GO conditions:

- invalid time format
- countdown shorter than the minimum
- invalid target body selection

### 6.4 TIME WARP

Countdown operations shall not be performed under active time warp.

NO-GO conditions:

- time warp active during window calculation
- time warp active during countdown

### 6.5 READINESS REPORT

The readiness report is built from thrust, mass, and delta-v estimates.

Fixed thresholds:

- minimum liftoff TWR: `1.15`
- watch delta-v margin: `500 m/s`

Interpretation:

- GO means the stack clears thrust and delta-v gates
- WATCH means the stack clears thrust but the delta-v margin is low
- NO-GO means the stack is short on thrust or delta-v

Default posture:

- GO launches normally
- WATCH requires management sign-off
- NO-GO does not launch

### 6.6 CORE IGNITION HEALTH

At terminal count, the vehicle checks core engine health before release.

Software gate:

- all configured core engines must be active
- thrust ratio must be at least `0.90`

NO-GO conditions:

- any core engine fails to light
- thrust ratio falls below the ignition threshold

### 6.7 PAD RELEASE

Pad release is retried briefly by the launch system.

NO-GO conditions:

- pad release does not confirm
- pad release timeout expires

If pad release fails, scrub the launch.

### 6.8 LIFTOFF HEALTH

After booster ignition and pad release, the vehicle validates liftoff performance.

Software gate:

- thrust ratio must be at least `0.88` during the validation window

NO-GO conditions:

- thrust loss after liftoff
- liftoff thrust below the minimum threshold

## 7.0 COUNTDOWN PROCEDURES

### 7.1 HOLD AUTHORITY

The tower may place the count in hold before launch.

The vehicle accepts hold and resume commands only while the countdown state is still valid.

### 7.2 CHANGE CONTROL

Countdown changes are allowed only before engine start or release.

Rules:

- before engine start, the operator may set or adjust the count
- after engine start, countdown changes are rejected
- after release trigger, countdown changes are rejected
- abort remains available at all times

### 7.3 TERMINAL COUNT

The terminal sequence is fixed by software.

Nominal events:

- engine start at `T-00:00:06`
- vehicle release at `T-00:00:00`
- liftoff commit at `T-00:00:00`
- tower clear altitude: `250 m`

## 8.0 ABORT AND SCRUB CONDITIONS

### 8.1 PRE-LAUNCH SCRUB

Scrub the launch if any of the following occur:

- manifest validation fails
- weather goes NO-GO
- tower handoff is missing or invalid
- countdown cannot be armed correctly
- core ignition health is below threshold
- pad release fails
- readiness report is NO-GO

### 8.2 IN-COUNTDOWN ABORT

Abort the count if any of the following occur:

- operator issues abort
- core ignition thrust is low
- liftoff thrust is low
- the launch system reports a release failure
- tower and vehicle state are no longer synchronized

### 8.3 ABORT AUTHORITY

Abort overrides hold, resume, and launch continuation.

### 8.4 STALE STATE

If the tower or vehicle receives stale control data, the correct response is HOLD and revalidate.

## 9.0 ASCENT SOFTWARE LIMITS

These are not separate launch approvals. They are launch-relevant software limits that must remain consistent with the vehicle state.

### 9.1 BOOSTER SEPARATION

Booster separation occurs only when:

- vertical speed is at least `50 m/s`
- booster thrust has tailed down to `0.15` of peak thrust or below

### 9.2 MAX-Q PROTECTION

The ascent controller limits throttle during max-q.

Configured values:

- max-q start altitude: `9000 m`
- max-q end altitude: `17000 m`
- max-q throttle cap: `0.72`

### 9.3 CORE-STAGE SHUTDOWN

Core-stage cutoff is managed by apoapsis, ETA, and fuel state.

Important floor:

- core-stage minimum fuel fraction: `0.15`

### 9.4 ABORT COVER JETTISON

Abort cover jettison is not a pre-launch approval item.

Software rule:

- do not jettison the abort cover until altitude is at least `140000 m`
- do not jettison it before `T+198 s`

## 10.0 UPPER-STAGE RULES

### 10.1 UPPER-STAGE IGNITION

The upper stage ignites only when the burn directive says to burn.

Ignition sequencing:

- ignition delay: `2 s`
- settle time: `5 s`
- ignition grace time: `6 s`

### 10.2 ORBIT COMPLETION

The upper stage is complete when the vehicle is within orbit tolerance.

Orbit tolerances:

- apoapsis tolerance: `2500 m`
- periapsis tolerance: `5000 m`

## 11.0 DECISION MATRIX

| Gate | GO | WATCH | NO-GO |
| --- | --- | --- | --- |
| Weather | All limits satisfied | Marginal but acceptable with manual acceptance | Lightning, storms, severe wind, low visibility, icing |
| Manifest | All parts resolve | N/A | Any required part missing |
| Tower handoff | Valid and current | N/A | Missing, stale, or mismatched |
| Countdown mode | Valid mode selected | N/A | Invalid mode or bad manual count |
| Readiness report | GO | WATCH with sign-off | NO-GO |
| Core ignition | Thrust ratio >= 0.90 | N/A | Below threshold |
| Pad release | Confirmed | N/A | Timeout or failure |
| Liftoff thrust | Thrust ratio >= 0.88 | N/A | Below threshold |
| Time warp | Off | N/A | On |

## 12.0 REFERENCE SOFTWARE CONSTANTS

The current stack uses these values:

- manual countdown minimum: `00:00:30`
- relative inclination tolerance: `0.25 deg`
- tower handoff lead time: `120 s`
- core ignition readiness check: `0.5 s` before launch
- core ignition minimum thrust ratio: `0.90`
- liftoff validation window: `3 s`
- liftoff minimum thrust ratio: `0.88`
- minimum liftoff TWR: `1.15`
- delta-v watch margin: `500 m/s`
- core-stage fuel floor: `0.15`
- booster separation vertical speed floor: `50 m/s`
- booster separation thrust ratio: `0.15`
- max-q throttle cap: `0.72`
- tower clear altitude: `250 m`

## 13.0 FINAL RULE

If a launch condition is not explicitly permitted here or in the software, it is not approved.
