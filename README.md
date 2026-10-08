# FPV PREP

A small Windows console for preparing Betaflight quads over USB before a flight: find the drone, check its health, write a quad type's saved stick settings into it, and adjust them in plain steps.

It talks to the flight controller through Betaflight's own text command line (the same one as the CLI tab in Betaflight Configurator). Nothing is installed on the quad, and it works offline.

## Run

Double-click `FPV.cmd`. Keep Betaflight Configurator closed or disconnected: only one program can hold the USB port.

| Command | What it does |
|---|---|
| `bind "NAME"` | Finds the drone on USB and shows what it is: id, name, firmware, whether it was bound before, how many stick settings match its type's. Writes nothing. NAME is whatever you call that kind of quad; no name = same as last time. |
| `status` | The drone's current rates, a health check, and a green / yellow / red verdict. Writes nothing. |
| `motors [full]` | All four motors together, about 1 second at idle or 3 seconds. **Props off.** |
| `fix controls` (or `controls`) | Writes the type's saved stick settings (`presets\NAME.txt`) and its stiffness level into the drone, then reads back to confirm. A type with no file of its own gets the standard set for heavy quads (`presets\_default.txt`). |
| `fix sound` (or `sound`) | Switches the buzzer and motor beacon off. |
| `yaw more`, `pitch roll less`, `throttle slightly more` | Adjusts rates in fixed steps. Shows old and new values and asks before applying. A confirmed change is remembered for the quad type. |
| `pid stiffer`, `pid softer` | Scales roll and pitch P, I and D together, 10 % of the drone's original values per step, from -2 to +3. Shows old and new values and a risk warning, and asks before applying. The level is remembered for the quad type. |
| `radio` | Reads an EdgeTX radio's stick calibration in USB storage mode. Read only. |
| `help`, `exit` | |

## What the health check reads

Sensors present, accelerometer calibrated, processor load, sensor bus errors, battery cells and volts per cell, radio link, each ESC answering (motors at rest), and the reasons Betaflight would refuse to arm. Everything healthy is packed into two lines; each problem gets one line.

## Why PID is only scaled

A PID worked out from assumed inertia and thrust lands a factor of 2-3 away from a real tune, so the builder's values are never replaced. What a payload changes is bounded: 40-100 % more roll and pitch inertia against about 35 % more motor gain at the higher hover throttle leaves the loop 4-32 % weaker than when the drone was tuned empty. `pid stiffer` covers that range in 10 % steps. Each drone's original values are recorded the first time it is touched, so steps never compound. It can still make a drone that was tuned loaded slightly worse, which is what the warning says.

## Safety limit

`bf.ps1` refuses, before the port is opened, any command that could change switches, aux channels, adjustments, the channel map, receiver or failsafe settings, pin or resource mapping, servos, serial ports or features. It changes flight feel only: rates, PID, feedforward, throttle curve, stick smoothing and deadband, and beeps off.

Every session ends with the flight controller restarting. That is how Betaflight leaves command-line mode.

Axis tuning works only on drones whose rates are in the ACTUAL format; on any other format it refuses instead of guessing.

## Files

| File | Purpose |
|---|---|
| `FPV.cmd` | Launcher. |
| `fpv.ps1` | The console: commands, checks, screens. No text of its own. |
| `lang\en.ps1` | All text and command words. Add a language by copying it; start with `fpv.ps1 -Lang xx`. |
| `bf.ps1` | One serial session with the flight controller, with the safety limit. |
| `presets\NAME.txt` | Created by the console the first time you adjust a quad type: its stick settings and stiffness level. None are shipped. |
| `presets\_default.txt` | The standard set for heavy 10-13 inch quads (2.5-3.7 kg). Its header explains how each number was calculated. |
| `tests\sim.ps1`, `tests\simfc.ps1` | Offline test and the pretend flight controller it runs against. |

A release is `FPV.cmd`, `fpv.ps1`, `bf.ps1`, one file from `lang\` and the `presets\` folder. Config copies, hardware ids and the log are written to `quads\`, which is not part of this repository.

## Test

```
powershell -ExecutionPolicy Bypass -File tests\sim.ps1
```

No USB and no drone needed. It replaces the serial side with a simulated Betaflight 4.5 board and checks every command, including that nothing the console sends is on `bf.ps1`'s refusal list.

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 (built in). Tested against Betaflight 4.5.0. The drone must be the only serial port on the PC.
