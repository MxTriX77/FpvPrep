# FPV PREP

A small Windows console for preparing Betaflight quads over USB before a flight: find the drone, check its health, write a quad type's saved stick settings into it, and adjust them in plain steps.

It talks to the flight controller through Betaflight's own text command line (the same one as the CLI tab in Betaflight Configurator). Nothing is installed on the quad, and it works offline.

## Run

Double-click `FPV.cmd`. Keep Betaflight Configurator closed or disconnected: only one program can hold the USB port.

| Command | What it does |
|---|---|
| `bind "NAME"` | Finds the drone on USB and shows what it is: id, name, firmware, whether it was bound before. Writes nothing. NAME is whatever you call that kind of quad; no name = same as last time. |
| `status` | The drone's current rates, a health check, and a green / yellow / red verdict. Writes nothing. |
| `motors`, `motors -N` | All four motors together at idle speed, for about 1 second or N seconds (up to 10). It runs the same with props on or off. With props on, keep hands and the USB cable clear: if the cable comes out mid-run the stop command cannot reach the drone, and only the battery plug stops the motors. |
| `set controls` (or `controls`) | Writes the type's saved stick settings (`presets\NAME.txt`) and its stiffness level into the drone, always in full, then reads back to confirm. A type with no file of its own gets the standard set for heavy quads (`presets\_default.txt`). |
| `set controls -m` | Opens a full-screen editor on the rates the drone holds now (roll, pitch, yaw: near centre, full stick, expo). Up/down move, digits type, left/right step a value or choose where to write: this drone only, or this drone and the type's profile. Enter writes and closes, Esc cancels. |
| `set sound off`, `set sound on` | Off switches the buzzer and the motor beacon off; on brings the buzzer back (the beacon stays off). Remembered for the quad type, so `set controls` applies it to every drone of that type. |
| `set horizon on`, `set horizon off` | Shows or hides the horizon line on the OSD, where the drone already has it. Remembered for the quad type. |
| `set name NAME` | Changes the name the drone shows on its OSD. Latin letters, digits, space and `_ . -`, up to 16 characters. |
| `set sticks on`, `set sticks off` | Shows or hides the two stick pictures on the OSD, side by side at the bottom centre (Mode 2). Their size is fixed by the firmware. Written to the connected drone and remembered for the quad type, so `set controls` gives it to every drone of that type. |
| `yaw more`, `pitch roll less`, `yaw more more` | Adjusts rates in fixed steps. Shows old and new values and writes them. The change is remembered for the quad type; the opposite word undoes it. Say the word again for that many steps at once. |
| `throttle softer`, `throttle stiffer` | Makes the type's throttle gentler or sharper where it is worked: at lift-off and in flight. Shows old and new curve and writes it. Remembered for the quad type; the opposite word undoes it, and saying it again takes more steps at once. |
| `pid stiffer`, `pid softer` | Scales roll and pitch P, I and D together, 10 % of the drone's original values per step, from -2 to +3. Shows old and new values and a risk warning, and asks before applying. The level is remembered for the quad type. |
| `pid -m` | The same editor on the PID values the drone holds now (roll and pitch P, I, D, D min; yaw P and I), written as typed. Saved to the profile they become what every drone of the type gets, and what `pid stiffer` and `pid softer` scale from. |
| `radio` | Reads an EdgeTX radio's stick calibration in USB storage mode. Read only. |
| `help`, `exit` | |

## What the health check reads

Sensors present, accelerometer calibrated, processor load, sensor bus errors, battery cells and volts per cell, radio link, each ESC answering (motors at rest), and the reasons Betaflight would refuse to arm. Everything healthy is packed into two lines; each problem gets one line.

## Why PID is only scaled

A PID worked out from assumed inertia and thrust lands a factor of 2-3 away from a real tune, so the builder's values are never replaced. What a payload changes is bounded: 40-100 % more roll and pitch inertia against about 35 % more motor gain at the higher hover throttle leaves the loop 4-32 % weaker than when the drone was tuned empty. `pid stiffer` covers that range in 10 % steps. Each drone's original values are recorded the first time it is touched, so steps never compound. It can still make a drone that was tuned loaded slightly worse, which is what the warning says.

## Safety limit

`bf.ps1` refuses, before the port is opened, any command that could change switches, aux channels, adjustments, the channel map, receiver or failsafe settings, pin or resource mapping, servos, serial ports or features. It changes flight feel only: rates, PID, feedforward, the throttle curve, stick smoothing and deadband, the OSD name, and beeps.

## Throttle

The standard set holds no throttle curve. How much power a quad has in hand cannot be worked out from the bench, and its builder has usually shaped the throttle for it, so a new quad keeps the curve it came with.

`throttle softer` and `throttle stiffer` are for a type whose throttle is too jumpy, or too dull. Betaflight has no throttle sensitivity setting of its own: how much power a small stick movement adds is the steepness of the curve at that point. So the command works on the same 11-point table the firmware builds. It measures how much stick travel lies between lift-off power and cruise power of a loaded quad (50 % and 85 %), and moves `thr_expo`, 10 a step, the way that widens it: down for a curve hung from the top (steepest at the bottom of the stick), up for one bent around the middle. It stops where that stretch is widest, because past that point lift-off would get softer only at the price of flight, and it never leaves a nearly dead part inside the stretch. `thr_mid` is not moved, so the top of the stick keeps its meaning and full stick is always full power. The starting point is the curve already saved for the type, or the drone's own if none is saved. The result is saved for the type (`set thr_mid`, `set thr_expo`), and `set controls` then gives it to every drone of that type. A softer curve puts lift-off a little higher on the stick.

An early version wrote its own curve (`thr_mid 45`, `thr_expo 40`) into the active rate profile. Where `set controls` still finds exactly that pair and the type has no curve saved, it puts back what the drone's other rate profiles hold.

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
| `tests\mock.ps1` | The console against the pretend flight controller, to try it with nothing plugged in. |
| `tests\console.ps1` | Opens a launcher in a real console window, types into it and reads its screen back. Catches what the simulator test cannot: the `.cmd` itself, typed input, cursor animation. |
| `build.ps1` | Runs the simulator test, then makes one release folder per language (named by the `release` entry of its language file) and one mock folder (`MOCK\MOCK.cmd`), and checks each launcher in a real window. |

Run `.\build.ps1` to make the releases and the mock, on the Desktop unless `-OutRoot` says otherwise. For English that is `CONFIGURATOR\CONFIG.cmd`. Config copies, hardware ids and the log are written to `quads\`, which is not part of this repository.

## Test

```
powershell -ExecutionPolicy Bypass -File tests\sim.ps1
```

No USB and no drone needed. It replaces the serial side with a simulated Betaflight 4.5 board and checks every command, including that nothing the console sends is on `bf.ps1`'s refusal list.

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 (built in). Tested against Betaflight 4.5.0. The drone must be the only serial port on the PC.
