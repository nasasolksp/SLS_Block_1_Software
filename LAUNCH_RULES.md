# Launch Rules Sheet (LRS)

## 1.0 CONTROLLED DOCUMENT

- Prepared by: Flight Operations
- Applies to: NASA Launch Stack, SLS Block 1 mission set
- Authority: Flight Operations Director, Chief Engineer, Mission Manager, tower CPU, vehicle CPU
- Purpose: define what may and may not be launched under software-controlled operations

This sheet is intended to be read with the flight software, not instead of it. If this document and the software disagree, the software gate remains mandatory for launch.

## 2.0 SCOPE

This launch rule sheet covers:

- pre-launch readiness
- weather and environment limits
- tower and vehicle software gates
- countdown discipline
- liftoff commit criteria
- scrub and abort conditions
- early ascent constraints that the flight software enforces automatically

The relevant software files are:

- `Space_Launch_System_B1/mission_configuration.ks`
- `SLS_Launch_Tower/tower_main.ks`
- `Space_Launch_System_B1/SLS_Main.ks`
- `Space_Launch_System_B1/sls_core_stage_guidance.ks`
- `Space_Launch_System_B1/sls_upper_stage_guidance.ks`
- `Space_Launch_System_B1/sls_parts_manifest.ks`

## 3.0 LAUNCH COMMIT POLICY

Launch is GO only when all of the following are true:

- the parts manifest validates cleanly
- the tower and vehicle are using the same mission configuration
- the tower handoff is valid when `use_mcc_app = TRUE`
- the countdown mode is valid for the selected mission
- the weather is within limits
- the launch readiness report is GO or WATCH with explicit management acceptance
- the core ignition and liftoff thrust checks are nominal
- the vehicle has positive delta-v margin
- the launch window is open, or the countdown is manually controlled by the operator

Launch is NO-GO if any hard gate fails.

## 4.0 WEATHER AND ENVIRONMENT RULES

The current software stack does not ingest live weather sensors, so weather is an operator-held launch gate. If weather is not acceptable, the tower stays in hold even if the code is otherwise ready.

### 4.1 GO WEATHER

Launch may proceed when all of the following are true:

- no lightning in or near the ascent corridor
- no active thunderstorm cell over the pad or downrange corridor
- sustained surface winds are within pad limits
- gust spread is stable and below the vehicle handling limit
- visibility is sufficient for tower and pad operations
- ceiling is high enough for safe visual liftoff tracking
- no heavy precipitation, icing, or dense fog

### 4.2 NO-GO WEATHER

Launch shall not proceed when any of the following are present:

- lightning or thunderstorm activity
- severe gusting or crosswind conditions
- rain, hail, freezing rain, or icing that can affect pad hardware or engines
- visibility that prevents reliable pad and liftoff monitoring
- cloud ceiling too low for safe launch ops
- any weather condition that makes the tower or vehicle recovery path unsafe

### 4.3 WEATHER POLICY NOTE

If weather is marginal but not clearly unsafe, the default action is HOLD, not ACCEPT.

## 5.0 SOFTWARE GATES

The flight software defines the actual launch sequence. The following gates are mandatory.

### 5.1 MANIFEST VALIDATION

The vehicle may not launch unless the parts manifest resolves correctly.

NO-GO conditions include:

- missing required engine groups
- missing booster, core, upper-stage, abort, or release hardware
- part names or module actions that do not match the vessel

If manifest validation fails, the vehicle remains in hold.

### 5.2 TOWER HANDOFF

When `use_mcc_app = TRUE`, the tower is the source of truth for launch timing.

Rules:

- the tower must publish a valid handoff message
- the vehicle must accept a non-stale handoff
- the handoff must be valid at or near the planned launch epoch

NO-GO conditions include:

- handoff not received
- handoff stale
- tower CPU tag mismatch
- vehicle vessel mismatch

When `use_mcc_app = FALSE`, the stack may operate locally, but the vehicle still follows the same launch timing logic.

### 5.3 COUNTDOWN MODE

Two countdown modes are supported:

- `MANUAL_COUNTDOWN`
- `RELATIVE_INCLINATION`

Rules:

- manual countdown must be formatted as `HH:MM:SS`
- manual countdown must be at least `00:00:30`
- if the target body is the same as the launch body, the software resolves to manual countdown
- if the mission is windowed, the tower will only go live inside the relative inclination window

NO-GO conditions include:

- invalid countdown format
- countdown shorter than the minimum allowed value
- invalid target body selection

### 5.4 TIME WARP

Launch countdown operations shall not be conducted under active time warp.

NO-GO conditions include:

- active time warp during tower window calculation
- active time warp during launch countdown

### 5.5 READINESS REPORT

The readiness report is built from vehicle mass, thrust, and delta-v estimates.

Gate values:

- minimum liftoff TWR: `1.15`
- watch delta-v margin: `500 m/s`

Rules:

- `GO` means the stack is above the liftoff TWR floor and has positive delta-v margin
- `WATCH` means the stack is above the TWR floor but the delta-v margin is below `500 m/s`
- `NO-GO` means the stack is short on thrust or delta-v

The default launch posture is:

- GO without waiver
- WATCH only with management sign-off
- NO-GO never launches

### 5.6 CORE IGNITION HEALTH

At terminal count, the vehicle checks core engine health before release.

Software gate:

- all configured core engines must be active
- thrust ratio must be at least `0.90`

NO-GO conditions include:

- any core engine fails to light
- thrust ratio falls below the minimum ignition threshold

### 5.7 LIFTOFF HEALTH

After booster ignition and pad release, the vehicle validates liftoff performance.

Software gate:

- thrust ratio must be at least `0.88` during the validation window

NO-GO conditions include:

- thrust loss after liftoff
- liftoff thrust below the minimum threshold

### 5.8 PAD RELEASE

The launch system retries pad release for a short window.

NO-GO conditions include:

- pad release does not confirm
- pad release timeout expires

If pad release fails, the launch is scrubbed immediately.

## 6.0 COUNTDOWN RULES

### 6.1 HOLD AUTHORITY

The tower may place the count in hold before launch.

The vehicle will accept hold and resume commands only while they are still relevant to the countdown state.

### 6.2 COUNTDOWN CHANGE RULES

Countdown changes are allowed only before the vehicle is locked out by engine start or release.

Rules:

- before engine start, the operator may set or adjust the count
- after engine start, countdown changes are rejected
- after release trigger, countdown changes are rejected
- abort remains available at all times

### 6.3 TERMINAL COUNT

The terminal sequence is fixed by software.

Nominal terminal events:

- engine start at `T-00:00:06`
- vehicle release at `T-00:00:00`
- liftoff commit at `T-00:00:00`
- tower clear altitude: `250 m`

## 7.0 ABORT AND SCRUB CONDITIONS

### 7.1 PRE-LAUNCH SCRUB

Scrub the launch if any of the following occur:

- manifest validation fails
- weather goes NO-GO
- tower handoff is invalid or missing
- countdown cannot be armed correctly
- core ignition health is below threshold
- pad release fails
- readiness report is NO-GO

### 7.2 IN-COUNTDOWN ABORT

Abort the count if any of the following occur:

- operator issues abort
- core ignition thrust is low
- liftoff thrust is low
- the launch system reports a release failure
- the tower or vehicle loses the required state sync

### 7.3 ABORT AUTHORITY

Abort always overrides hold, resume, and launch continuation.

### 7.4 STALE STATE HANDLING

If the tower or vehicle receives stale control data, the correct response is hold and revalidate.

## 8.0 ASCENT SOFTWARE LIMITS

These are not pre-launch commit gates, but they are part of the launch rule set because the flight software enforces them automatically.

### 8.1 BOOSTER SEPARATION

Booster separation occurs only when:

- vertical speed is at least `50 m/s`
- booster thrust has tailed down to `0.15` of peak thrust or below

### 8.2 MAX-Q PROTECTION

The ascent controller limits throttle during max-q.

Configured limits:

- max-q start altitude: `9000 m`
- max-q end altitude: `17000 m`
- max-q throttle cap: `0.72`

### 8.3 CORE-STAGE SHUTDOWN

Core-stage cutoff is managed by apoapsis, ETA, and fuel state.

Important floor:

- core-stage minimum fuel fraction: `0.15`

### 8.4 ABORT COVER AND JETTISON

The abort cover jettison is not a pre-launch decision.

Software rule:

- do not jettison the abort cover until altitude is at least `140000 m`
- do not jettison it before `T+198 s`

## 9.0 UPPER-STAGE RULES

### 9.1 UPPER-STAGE IGNITION

The upper stage only ignites when the burn directive says to burn.

Ignition sequencing rules:

- ignition delay: `2 s`
- settle time: `5 s`
- ignition grace time: `6 s`

### 9.2 ORBIT COMPLETION

The upper stage is complete when the vehicle is within orbit tolerance.

Orbit tolerances:

- apoapsis tolerance: `2500 m`
- periapsis tolerance: `5000 m`

## 10.0 LAUNCH DECISION MATRIX

| Gate | GO | WATCH | NO-GO |
| --- | --- | --- | --- |
| Weather | All weather limits satisfied | Marginal but acceptable with manual acceptance | Lightning, storms, severe wind, low visibility, icing |
| Manifest | All parts resolve | None | Any required part missing |
| Tower handoff | Valid and current | N/A | Missing, stale, or mismatched |
| Countdown mode | Valid mode selected | N/A | Invalid mode or bad manual count |
| Readiness report | GO | WATCH with sign-off | NO-GO |
| Core ignition | Thrust ratio >= 0.90 | N/A | Below threshold |
| Liftoff thrust | Thrust ratio >= 0.88 | N/A | Below threshold |
| Pad release | Confirmed | N/A | Timeout or failure |
| Time warp | Off | N/A | On |

## 11.0 DEFAULT LAUNCH STANDARD

If there is any uncertainty, the standard is:

1. hold
2. revalidate software state
3. recheck weather
4. reissue the count only after the gate is clean

Do not launch to clear ambiguity. Launch only when the stack, the software, and the weather all agree.

## 12.0 REFERENCE SOFTWARE CONSTANTS

These values are hard-coded or defaulted in the current launch stack:

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
