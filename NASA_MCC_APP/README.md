# NASA MCC APP

Python mission-control frontend for the kOS SLS countdown flow.

## What it does

- Shows a NASA-branded landing screen with vehicle selection.
- Opens a resizable mission-control hub for `SLS Block 1`.
- Publishes operator commands to `../MCC_Interface/command.txt`.
- Reads live tower and vehicle status from `../MCC_Interface/tower_status.txt` and `../MCC_Interface/vehicle_status.txt`.
- Surfaces launch-readiness telemetry from the vehicle, including estimated delta-v, liftoff TWR, and a short ascent profile summary.
- Switches between a telemetry window page and a visual flight-data page.
- Reads the flight-data snapshot and log from `../MCC_Interface/vehicle_flight.txt` and `../MCC_Interface/vehicle_flight_log.csv` when the data CPU is running.
- Lets the operator:
  - hold the tower countdown
  - resume the tower countdown
  - arm or re-arm the tower countdown
- Supports addable telemetry cards and detachable data windows.

## Launch Model

- The tower is the source of truth for launch timing.
- AG6 arms the tower, not the vehicle.
- The vehicle waits for the tower handoff before terminal count begins.
- The app can queue tower commands, but it does not start the vehicle directly.

## Build to EXE

From this folder:

```powershell
.\build_exe.ps1
```

Output:

- `dist/NASA_MCC_APP.exe`

## Run from source

```powershell
python .\app.py
```

## Integration notes

- `SLS_Launch_Tower/tower_main.ks` reads operator commands and writes tower status.
- `Space_Launch_System_B1/SLS_Main.ks` waits for the tower handoff, then reads operator commands during standby and terminal count, and writes vehicle status.
- `Space_Launch_System_B1/SLS_Data_CPU.ks` runs on the separate flight-data core and writes `vehicle_flight.txt` plus `vehicle_flight_log.csv`.
- `Space_Launch_System_B1/SLS_Data_CPU_boot.ks` is a boot helper for that core. It waits for ship unpack before starting the logger. Copy its contents into the data CPU's local `boot.ks` if you want it to auto-start with the vessel.
- `MCC_Interface/mcc_bridge.ks` is the shared kOS bridge helper.
- The app cannot start an idle kOS CPU by itself. For the tower CPU, use a local processor boot file that runs:

```kerboscript
RUNPATH("0:/NASA/SLS_Launch_Tower/tower_main.ks").
```

- A ready-made archive version is included at `SLS_Launch_Tower/tower_boot.ks`. Copy its contents into the tower processor's local `boot.ks` if you want the tower to auto-start whenever that CPU boots.
