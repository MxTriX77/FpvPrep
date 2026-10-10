# Offline test of fpv.ps1 against a simulated flight controller.
#   powershell -ExecutionPolicy Bypass -File tests\sim.ps1 [-Lang en] [-Show]
# No USB and no real data: bf.ps1 is replaced by the pretend flight controller in simfc.ps1,
# and presets\ and quads\ live in a temporary folder.
param([string]$Lang = 'en', [switch]$Show)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$data = Join-Path $env:TEMP "fpvprep_sim_$PID"
New-Item -ItemType Directory -Force (Join-Path $data 'presets') | Out-Null
Set-Content (Join-Path $data 'presets\SIM.txt') -Encoding utf8 -Value @(
    "# Saved settings for 'SIM'.",
    'set roll_rc_rate = 5', 'set roll_srate = 25', 'set roll_expo = 45',
    'set pitch_rc_rate = 5', 'set pitch_srate = 25', 'set pitch_expo = 45',
    'set yaw_rc_rate = 9', 'set yaw_srate = 30', 'set yaw_expo = 20',
    'set thr_expo = 25', 'set deadband = 3', 'set yaw_deadband = 3',
    'set rc_smoothing_auto_factor = 60', 'set f_roll = 40', 'set f_pitch = 40')

. (Join-Path $repo 'fpv.ps1') -Lang $Lang -DataRoot $data -NoMain
. (Join-Path $PSScriptRoot 'simfc.ps1')

# ---------------------------------------------------------------- stand-ins for the USB side
$script:sent = @(); $script:saves = 0; $script:answers = @()
function Wait-Port([int]$seconds = 15) { return $true }
function Busy([int]$ms) { }
function Run-BF([string[]]$commands, [bool]$save) { $script:sent += $commands; if ($save) { $script:saves++ }; return (Sim-FC $commands $save) }
function Read-Answer { $a = 'n'; if ($script:answers.Count) { $a = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1) }; Write-Host $a; return $a }

# Runs one console line and returns everything it printed as text
function Line([string]$text, [string[]]$answers = @()) {
    $script:answers = @($answers)
    $recs = & { Dispatch $text } 6>&1
    $sb = New-Object Text.StringBuilder
    foreach ($r in $recs) {
        if ($r -isnot [System.Management.Automation.InformationRecord]) { continue }
        [void]$sb.Append($r.MessageData.Message); if (-not $r.MessageData.NoNewLine) { [void]$sb.Append("`n") }
    }
    $t = $sb.ToString()
    if ($Show) { Write-Host $t }
    return $t
}
$script:pass = 0; $script:fail = 0
function Check([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; if ($Show) { Write-Host "  pass  $what" -ForegroundColor Green } }
    else { $script:fail++; Write-Host "  FAIL  $what" -ForegroundColor Red }
}
function Val([string]$k) { foreach ($sec in 'master', 'profile', 'rates') { if ($script:fc[$sec].Contains($k)) { return $script:fc[$sec][$k] } }; return $null }
function Has([string]$text, [string]$key) { return $text.Contains((T $key)) }
function Preset([string]$name) { return (Get-Content (Join-Path $data "presets\$name.txt") -Raw) }
# A command with its direction word said $n times: "yaw more" -> "yaw more more"
function Again([string]$cmd, [int]$n) { return $cmd + ((' ' + ($cmd -split ' ')[-1]) * ($n - 1)) }
$C = $script:STR['test_words']   # the command words of the language under test
$green = "$(T 'r_motors')  //  $(T 'good_motors')"

# ---------------------------------------------------------------- bind and status
$script:fc = New-FC

$o = Line $C.bind_none
Check 'bind with no name and no history asks which quad' (Has $o 'f_which')
$o = Line $C.unknown
Check 'an unknown line is reported, nothing is sent' ((Has $o 'f_unknowncmd') -and $script:sent.Count -eq 0)
$o = Line $C.status
Check 'status works before any bind' ($o.Contains('5150aaaa') -and $o.Contains((T 'chip_sensors')) -and $o.Contains("8S 4.23 $(T 'unit_v')") -and $o.Contains('4/4') -and $o.Contains((T 'good_status')))

$before = $script:saves
$o = Line "$($C.bind) SIM"
Check 'bind shows the drone and says bound' ($o.Contains('5150aaaa') -and $o.Contains('SIM20') -and $o.Contains('4.5.0') -and $o.Contains((T 'seen_no')) -and $o.Contains(((T 'b_bound') -f 'SIM 5150aaaa', '').Substring(0, 20)))
Check 'bind says nothing about saved settings' (-not $o.Contains((T 'preset_std')) -and -not ($o -match '\b15\b'))
Check 'bind does not run the health check' (-not (Has $o 'h_step'))
Check 'bind writes nothing to the drone' ($script:saves -eq $before -and (Val 'roll_srate') -eq '15')
$copy = Get-ChildItem (Join-Path $data 'quads') -Filter '*_SIM_5150aaaa_before.txt'
Check 'bind saves a config copy without the dump' ($copy.Count -eq 1 -and -not ((Get-Content $copy.FullName -Raw) -match 'thr_mid'))
Check 'bind remembers the quad name' ((Last-Name) -eq 'SIM')

$o = Line $C.status
Check 'status shows rates, the health check and a green verdict' ($o.Contains('70 / 150') -and (Has $o 'h_step') -and $o.Contains((T 'good_status')))
Check 'status shows nothing about throttle' (-not ($o -match '(?i)\bthr|throttle') -and -not $o.ToLower().Contains($C.thr_more.Split(' ')[0]))
Check 'status says nothing about saved settings' (-not $o.Contains((T 'preset_std')) -and -not ($o -match '\b15\b'))
Check 'no line carries a clock time' (-not ($o -match '\d\d:\d\d:\d\d'))

# ---------------------------------------------------------------- fix
$o = Line $C.fix_ctl
Check 'fix controls writes all 15 values' ((Val 'roll_srate') -eq '25' -and (Val 'yaw_srate') -eq '30' -and (Val 'thr_expo') -eq '25' -and (Val 'deadband') -eq '3' -and (Val 'f_pitch') -eq '40' -and (Val 'rc_smoothing_auto_factor') -eq '60')
Check 'fix controls confirms by reading back' ($o.Contains((T 'ok_confirmed' 15)) -and $o.Contains((T 'done_ctl')))
Check 'fix controls saves an after copy' (@(Get-ChildItem (Join-Path $data 'quads') -Filter '*_SIM_5150aaaa_after.txt').Count -eq 1)
$before = $script:saves
$o = Line $C.fix_ctl
Check 'fix controls always writes in full, even when the drone already has the values' ($script:saves -eq $before + 1 -and $o.Contains((T 'ok_confirmed' 15)))
$o = Line "$($C.bind) SIM"
Check 'a second bind does not overwrite the first copy of the drone' (@(Get-ChildItem (Join-Path $data 'quads') -Filter '*_5150aaaa_before.txt').Count -eq 1 -and (Get-Content $copy.FullName -Raw) -match 'set roll_srate = 15')
$o = Line $C.fix_short
Check 'the bare word works as fix controls' ($o.Contains((T 'r_fix' (T 'w_ctl'))) -and $o.Contains((T 'ok_confirmed' 15)))
$o = Line $C.fix_snd
Check 'fix sound switches the beeps off and confirms' (-not $script:fc.beeps -and (Has $o 'ok_snd'))
Check 'the sound choice is kept with the type' ((Preset 'SIM') -match '# sound: off')
$o = Line $C.snd_on
Check 'set sound on brings the buzzer back and confirms' ($script:fc.beeps -and (Has $o 'ok_snd_on') -and (Preset 'SIM') -match '# sound: on' -and $script:sent -contains 'beeper ALL')
$o = Line $C.fix_snd; $script:fc.beeps = $true; $o = Line $C.fix_ctl
Check 'set controls applies the saved sound choice' (-not $script:fc.beeps -and (Has $o 'ok_snd'))
# a file of one drone's own values (made by hand, by its id) is written on top of the type's
New-Item -ItemType Directory -Force (Join-Path $data 'presets\drones') | Out-Null
Set-Content (Join-Path $data 'presets\drones\5150aaaa.txt') -Encoding utf8 -Value @('# this drone only', 'set thr_mid = 100', 'set thr_expo = 100')
$o = Line $C.fix_ctl
Check 'one drone''s own values are written on top of the type''s' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '100' -and (Val 'roll_srate') -eq '25')
[IO.File]::Delete((Join-Path $data 'presets\drones\5150aaaa.txt'))
$script:fc.rates.thr_mid = '50'; $script:fc.rates.thr_expo = '25'
Check 'the standard set shipped with the tool leaves the throttle curve alone' (-not ((Get-Content (Join-Path $repo 'presets\_default.txt') -Raw) -match '(?m)^set (thr_|throttle)'))

# ---------------------------------------------------------------- axis tuning
$o = Line $C.yaw_more @('y')
Check 'yaw more steps centre by 10 and full stick by 40' ((Val 'yaw_rc_rate') -eq '10' -and (Val 'yaw_srate') -eq '34' -and $o.Contains('90 -> 100') -and $o.Contains('300 -> 340'))
Check 'an axis change is applied and remembered without any question' ((Preset 'SIM') -match 'set yaw_srate = 34' -and -not ((Preset 'SIM') -match 'set yaw_srate = 30') -and -not $o.Contains((T 'yn')))
$o = Line $C.pr_less @('y')
Check 'pitch roll less: one step on both axes' ((Val 'roll_rc_rate') -eq '4' -and (Val 'pitch_rc_rate') -eq '4' -and (Val 'roll_srate') -eq '22' -and (Val 'pitch_srate') -eq '22')
$before = $script:saves
$o = Line $C.thr_more
Check 'throttle with no direction lists the two choices and writes nothing' ((Has $o 'n_thrwhat') -and $script:saves -eq $before -and (Val 'thr_expo') -eq '25')
$script:fc.rates.rates_type = 'BETAFLIGHT'
$before = $script:saves
$o = Line $C.yaw_more @('y')
Check 'axis tuning refuses rates that are not ACTUAL' ($script:saves -eq $before -and $o.Contains('BETAFLIGHT'))
$script:fc.rates.rates_type = 'ACTUAL'

# ---------------------------------------------------------------- pid stiffer / softer
$o = Line $C.bare_stiffer
Check 'the bare word is not a command' (Has $o 'f_unknowncmd')
$o = Line $C.pid
Check 'pid alone lists the two choices' (Has $o 'n_pidwhat')
$o = Line $C.pid_stiffer @('n')
Check 'pid stiffer shows old and new, the risk line, and asks' ($o.Contains('65 / 20 / 70 -> 72 / 22 / 77') -and $o.Contains('60 / 20 / 65 -> 66 / 22 / 72') -and (Has $o 'w_risky') -and (Val 'p_roll') -eq '65')
$o = Line $C.pid_stiffer @('y')
Check 'pid stiffer raises roll and pitch P, I, D by 10 %' ((Val 'p_roll') -eq '72' -and (Val 'i_roll') -eq '22' -and (Val 'd_roll') -eq '77' -and (Val 'd_min_roll') -eq '66' -and (Val 'p_pitch') -eq '66' -and (Val 'd_pitch') -eq '72')
Check 'the level is stored with the type' ((Preset 'SIM') -match '# stiffness: 1')
$o = Line $C.pid_stiffer @('y'); $o = Line $C.pid_stiffer @('y')
Check 'three steps are 30 % of the original, not compounded' ((Val 'p_roll') -eq '85' -and (Val 'd_roll') -eq '91' -and (Val 'p_pitch') -eq '78')
$before = $script:saves
$o = Line $C.pid_stiffer @('y')
Check 'a fourth step is refused at the limit' ($script:saves -eq $before -and (Val 'p_roll') -eq '85')
$o = Line $C.pid_softer @('y')
Check 'pid softer steps back down' ((Val 'p_roll') -eq '78' -and (Preset 'SIM') -match '# stiffness: 2')
Check 'yaw PID and feedforward are never touched' ((Val 'f_roll') -eq '40' -and -not ($script:sent -match '^set (p|i|d)_yaw'))

# ---------------------------------------------------------------- motors
$o = Line $C.motors
Check 'motors: four rows, healthy, green' ($o.Contains('1200') -and $o.Contains('1210') -and $o.Contains($green) -and -not $script:fc.running)
Check 'motors always sends the stop command' ($script:sent -contains 'motor 255 1000')
$script:fc.rpm = @(1200, 1195, 0, 1210)
$n0 = $script:sent.Count; $o = Line $C.motors_full
Check 'motors -3 runs for about three seconds: four speed readings, and says 3 s' (@($script:sent | Select-Object -Skip $n0 | Where-Object { $_ -eq 'dshot_telemetry_info' }).Count -eq 4 -and $o.Contains((T 'm_step' 3)))
Check 'a motor that does not turn is red: do not fly' ($o.Contains((T 'm_dead' 3)) -and $o.Contains(((T 'v_fail') -f (T 'r_motors'), '').Substring(0, 16)))
$script:fc.rpm = @(1200, 1195, 900, 1210)
$o = Line $C.motors
Check 'uneven motors are a remark' ($o.Contains(((T 'm_spread') -f 28).Substring(0, 12)) -and -not $o.Contains($green))
$script:fc.rpm = @(1200, 1195, 1188, 1210)

# ---------------------------------------------------------------- health check
$script:fc.volts = 2960; $script:fc.flags = 'RXLOSS CLI THROTTLE'; $script:fc.master.acc_calibration = '0,0,0,0'
$o = Line $C.status
Check 'status lists battery, radio, accelerometer and arming remarks' ($o.Contains((T 'h_batt_low' 8 '3.70')) -and (Has $o 'h_radio_off') -and (Has $o 'h_acc_uncal') -and $o.Contains((T 'arm_THROTTLE')))
Check 'remarks make the verdict yellow, not red' ($o.Contains(((T 'v_warn') -f 'SIM 5150aaaa', '').Substring(0, 24)))
$script:fc.volts = 3381; $script:fc.flags = 'ARMSWITCH CLI'; $script:fc.master.acc_calibration = '58,7,-6,1'
$o = Line $C.status
Check 'an arm switch left on is red' ((Has $o 'arm_ARMSWITCH') -and $o.Contains(((T 'v_fail') -f 'SIM 5150aaaa', '').Substring(0, 24)))
$script:fc.volts = 0; $script:fc.cells = 0; $script:fc.flags = 'RPMFILTER DSHOT_TELEM CLI'
$o = Line $C.status
Check 'no battery: said once, ESC flags not reported as faults' ((Has $o 'h_nobatt') -and -not $o.Contains((T 'arm_RPMFILTER')) -and -not $o.Contains('4/4'))
$script:fc.volts = 3381; $script:fc.cells = 8; $script:fc.flags = 'CLI'
$script:fc.escErr = @(0, 100, 0, 0)
$o = Line $C.status
Check 'a silent ESC at rest is a remark' ($o.Contains((T 'h_esc' 2)) -and $o.Contains(((T 'v_warn') -f 'SIM 5150aaaa', '').Substring(0, 24)))
$script:fc.escErr = @(0, 0, 0, 0)
$script:fc.gyro = 'NONE'
$o = Line $C.status
Check 'no gyro is red' ((Has $o 'h_nogyro') -and $o.Contains(((T 'v_fail') -f 'SIM 5150aaaa', '').Substring(0, 24)))
$script:fc.gyro = 'ICM42688P'

# ---------------------------------------------------------------- other drones and types
$script:fc = New-FC '77bb00112233445566778899'
$o = Line $C.bind_none
Check 'bind with no name uses the last quad type' ($o.Contains('77bb0011') -and $o.Contains('SIM'))
$o = Line $C.fix_ctl
Check 'the next drone gets the type''s rates and its stiffness level' ((Val 'roll_srate') -eq '22' -and (Val 'yaw_srate') -eq '34' -and (Val 'thr_expo') -eq '25' -and (Val 'p_roll') -eq '78' -and (Val 'd_pitch') -eq '78')

$script:fc = New-FC 'c0ffee001122334455667788' 'OTHER'
$o = Line "$($C.bind) SIM"
$o = Line $C.fix_ctl
Check 'a drone whose own name differs from its type is set without any question' ((Val 'roll_srate') -eq '22' -and -not $o.Contains((T 'yn')))

# set name: the name the drone shows on its OSD
$before = $script:saves
$o = Line "$($C.set_name) Bird_7"
Check 'set name writes the OSD name and confirms it' ((Val 'craft_name') -eq 'Bird_7' -and $o.Contains('OTHER -> Bird_7') -and $o.Contains((T 'ok_confirmed' 1)) -and $script:saves -eq $before + 1)
$o = Line "$($C.bind) SIM"
Check 'bind then shows the new name' ($o.Contains('Bird_7'))
$before = $script:saves
$o = Line "$($C.set_name) a_name_that_is_far_too_long"
Check 'a name over 16 characters is refused and nothing is written' ((Has $o 'f_badname') -and $script:saves -eq $before -and (Val 'craft_name') -eq 'Bird_7')
$o = Line "$($C.set_name) bad;name"
Check 'a name with other characters is refused' ((Has $o 'f_badname') -and $script:saves -eq $before)
$o = Line $C.set_name
Check 'set name with no name says how to use it' ((Has $o 'n_namewhat') -and $script:saves -eq $before)
$o = Line $C.old_fix
Check 'the old word for set still works' ($o.Contains((T 'r_fix' (T 'w_ctl'))) -and $o.Contains((T 'done_ctl')))
$script:fc = New-FC 'abcdef001122334455667788' 'NEWQ1'
$o = Line "$($C.bind) NEWQ"
$o = Line $C.fix_ctl
Check 'a new type: fix controls says so and writes nothing' ($o.Contains((T 'f_nopreset' 'NEWQ')) -and (Val 'roll_srate') -eq '15')
$o = Line $C.yaw_more @('y')
Check 'a new type: a confirmed change creates its saved settings' ((Test-Path (Join-Path $data 'presets\NEWQ.txt')) -and (Preset 'NEWQ') -match 'set yaw_srate = 19')
Add-Content (Join-Path $data 'presets\NEWQ.txt') 'set no_such_setting = 1'
$o = Line $C.fix_ctl
Check 'a line the drone rejects is reported, not hidden' ((Has $o 'f_rejected') -and (Has $o 'b_problems'))

# a type with no file of its own, once the standard set exists
Set-Content (Join-Path $data 'presets\_default.txt') -Encoding utf8 -Value @(
    '# standard set', 'set rates_type = ACTUAL', 'set roll_rc_rate = 5', 'set roll_srate = 25', 'set yaw_srate = 27',
    'set thr_mid = 43', 'set thr_expo = 40', 'set deadband = 4')
$script:fc = New-FC 'dddd00001111222233334444' 'ZED7'
$o = Line "$($C.bind) ZED"
$o = Line $C.fix_ctl
Check 'fix controls writes the standard set to it' ((Val 'roll_srate') -eq '25' -and (Val 'thr_mid') -eq '43' -and (Val 'thr_expo') -eq '40' -and (Val 'deadband') -eq '4')
$o = Line $C.yaw_more @('y')
Check 'a change for a new type starts its file from the standard set' ((Preset 'ZED') -match 'set thr_mid = 43' -and (Preset 'ZED') -match 'set yaw_srate = 31')
$script:fc = New-FC 'eeee00001111222233334444' 'ZED7'
$o = Line "$($C.bind) ZED"; $o = Line $C.fix_ctl
Check 'the next drone of that type gets the standard set plus the change' ((Val 'thr_mid') -eq '43' -and (Val 'yaw_srate') -eq '31' -and (Val 'roll_srate') -eq '25')

# a name may be typed in any case and any letters, without quotes
$script:fc = New-FC 'f00d00001111222233334444' 'ZED7'
$o = Line "$($C.bind) zed"
Check 'a lower-case name is accepted and finds the same type' ($o.Contains('f00d0000') -and $o.Contains('ZED') -and (Last-Name) -eq 'zed')
$o = Line "$($C.bind) $($C.odd_name)"
Check 'a lower-case name in the console language is accepted' ($o.Contains($C.odd_name.ToUpper()) -and (Last-Name) -eq $C.odd_name)
# a drone that an older version left with its own throttle curve (45 / 40) gets the builder's back
Set-Content (Join-Path $data 'presets\THR.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc = New-FC 'aaaa11110000222233334444' 'THR20'
$script:fc.rates.thr_mid = '45'; $script:fc.rates.thr_expo = '40'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) THR"; $o = Line $C.fix_ctl
Check 'the old tool''s throttle curve is replaced by what the other rate profiles hold' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '100' -and $o.Contains('45 / 40 -> 100 / 100') -and (Val 'roll_srate') -eq '25')
$script:fc = New-FC 'bbbb11110000222233334444' 'THR20'
$script:fc.rates.thr_mid = '45'; $script:fc.rates.thr_expo = '40'
$o = Line "$($C.bind) THR"; $o = Line $C.fix_ctl
Check 'with the other profiles at firmware default it goes back to the default curve' ((Val 'thr_mid') -eq '50' -and (Val 'thr_expo') -eq '0')
$script:fc = New-FC 'cccc11110000222233334444' 'THR20'
$script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '100'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) THR"; $n0 = $script:sent.Count; $o = Line $C.fix_ctl
Check 'a throttle curve the tool did not write is never touched' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '100' -and -not $o.Contains((T 'kv_thr_back')) -and -not (@($script:sent | Select-Object -Skip $n0) -match '^set thr_'))
# a type whose saved settings name a throttle curve: every drone of the type gets that curve
Set-Content (Join-Path $data 'presets\CRV.txt') -Encoding utf8 -Value @('# with its own throttle curve', 'set roll_srate = 25', 'set thr_mid = 100', 'set thr_expo = 78')
$script:fc = New-FC 'dddd11110000222233334444' 'CRV20'
$script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '100'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) CRV"; $o = Line $C.fix_ctl
Check 'a throttle curve named in a type''s settings is written' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '78' -and (Val 'roll_srate') -eq '25')
$script:fc = New-FC 'eeee11110000222233334444' 'CRV20'
$script:fc.rates.thr_mid = '45'; $script:fc.rates.thr_expo = '40'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) CRV"; $o = Line $C.fix_ctl
Check 'and it is what a drone with the old tool''s curve gets, not the builder''s' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '78' -and -not $o.Contains((T 'kv_thr_back')))

# ---------------------------------------------------------------- throttle softer / sharper
# the curve in the type's profile moves, by thr_expo only. One hung from the top (thr_mid 100)
# gets softer with less expo
$o = Line $C.thr_softer
Check 'throttle softer on a top-hung curve takes 10 off the expo and keeps thr_mid' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '68' -and $o.Contains('100 / 78 -> 100 / 68') -and -not $o.Contains((T 'yn')))
Check 'the new curve is in the type''s profile, both values' ((Preset 'CRV') -match 'set thr_expo = 68' -and (Preset 'CRV') -match 'set thr_mid = 100' -and -not ((Preset 'CRV') -match 'set thr_expo = 78'))
$o = Line $C.thr_sharper
Check 'throttle sharper undoes it' ((Val 'thr_expo') -eq '78' -and (Preset 'CRV') -match 'set thr_expo = 78')
$o = Line (Again $C.thr_softer 2)
Check 'the word said twice is two steps at once' ((Val 'thr_expo') -eq '58' -and $o.Contains('100 / 78 -> 100 / 58'))
$o = Line (Again $C.thr_sharper 3)
Check 'and three times is three' ((Val 'thr_expo') -eq '88')
$o = Line (Again $C.thr_sharper 2); $before = $script:saves; $o = Line $C.thr_sharper
Check 'the curve stops at the limit and nothing more is written' ((Val 'thr_expo') -eq '100' -and $script:saves -eq $before -and $o.Contains((T 'n_limit' (T 'kv_thr'))))
$script:fc = New-FC 'ffff11110000222233334444' 'CRV20'
$script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '60'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) CRV"; $o = Line $C.thr_softer
Check 'the profile''s curve is the starting point, not what this drone happens to hold' ((Val 'thr_expo') -eq '90' -and $o.Contains('100 / 60 -> 100 / 90'))
# softer means softer at lift-off AND in flight: it stops where the stick travel between the two
# is widest. The firmware's own table is the yardstick, so that is checked first.
Check 'the throttle table is the firmware''s' (((Thr-Table 100 100) -join ' ') -eq '0 271 488 657 784 875 936 973 992 999 1000' -and ((Thr-Table 45 40) -join ' ') -eq '0 156 270 354 420 480 543 620 716 837 1000' -and ((Thr-Table 50 0) -join ' ') -eq '0 100 200 300 400 500 600 700 800 900 1000')
$widest = Thr-Softest 100
$o = Line (Again $C.thr_softer 10)
Check 'softer stops where lift-off to cruise has the most stick travel' ((Val 'thr_expo') -eq "$widest" -and $widest -gt 20 -and $widest -lt 60 -and (Thr-Travel 100 $widest) -gt (Thr-Travel 100 100) + 10 -and (Thr-Travel 100 $widest) -ge (Thr-Travel 100 0))
$before = $script:saves; $o = Line $C.thr_softer
Check 'and then says so and writes nothing' ($script:saves -eq $before -and $o.Contains((T 'n_limit' (T 'kv_thr'))))
$o = Line $C.thr_sharper
Check 'from the softest point sharper goes back the way it came' ((Val 'thr_expo') -eq "$($widest + 10)")
# a type with no curve in its profile starts from the drone's own; a curve bent around the
# middle gets softer with MORE expo
$script:fc = New-FC 'aaaa22220000222233334444' 'MID20'
Set-Content (Join-Path $data 'presets\MID.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc.rates.thr_mid = '50'; $script:fc.rates.thr_expo = '20'
$o = Line "$($C.bind) MID"; $o = Line $C.thr_softer
Check 'a curve bent around the middle gets softer with more expo' ((Val 'thr_mid') -eq '50' -and (Val 'thr_expo') -eq '30' -and (Val 'roll_srate') -eq '15')
Check 'a profile that had no curve now names both values' ((Preset 'MID') -match 'set thr_mid = 50' -and (Preset 'MID') -match 'set thr_expo = 30')
$o = Line (Again $C.thr_softer 10)
$e = [int](Val 'thr_expo')
Check 'and softer never leaves a dead part between lift-off and cruise' ($e -gt 40 -and -not (Thr-Dead 50 $e) -and (Thr-Dead 50 ($e + 1)))
$script:fc = New-FC 'bbbb22220000222233334444' 'OLD20'
Set-Content (Join-Path $data 'presets\OLD.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc.rates.thr_mid = '45'; $script:fc.rates.thr_expo = '40'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) OLD"; $o = Line $C.thr_softer
Check 'a drone with the old tool''s curve starts from what its other rate profiles hold' ((Val 'thr_mid') -eq '100' -and (Val 'thr_expo') -eq '90' -and $o.Contains('45 / 40 -> 100 / 90'))

# ---------------------------------------------------------------- set sticks on / off
$script:fc = New-FC 'dddd22220000222233334444' 'STK20'
$o = Line "$($C.bind) STK"; $o = Line $C.sticks_on
Check 'set sticks on puts both pictures at the bottom centre, visible, Mode 2' ((Val 'osd_stick_overlay_left_pos') -eq '14567' -and (Val 'osd_stick_overlay_right_pos') -eq '14576' -and (Val 'osd_stick_overlay_radio_mode') -eq '2' -and (Val 'roll_srate') -eq '15')
$o = Line $C.sticks_off
Check 'set sticks off hides them and keeps their place' ((Val 'osd_stick_overlay_left_pos') -eq '231' -and (Val 'osd_stick_overlay_right_pos') -eq '240')
$script:fc = New-FC 'eeee22220000222233334444' 'STK21'
$o = Line "$($C.bind) STK"; $o = Line $C.sticks_on; $o = Line $C.sticks_off; $o = Line $C.sticks_on
$script:fc = New-FC 'ffff22220000222233334444' 'STK22'
$o = Line "$($C.bind) STK"; $o = Line $C.fix_ctl
Check 'the choice is kept with the type: set controls gives the next drone its sticks' ((Preset 'STK') -match '# sticks: on' -and -not ((Preset 'STK') -match '# sticks: off') -and (Val 'osd_stick_overlay_left_pos') -eq '14567' -and (Val 'osd_stick_overlay_radio_mode') -eq '2')
$before = $script:saves; $o = Line $C.sticks
Check 'set sticks alone lists the two choices' ((Has $o 'n_stickswhat') -and $script:saves -eq $before)
$script:fc.master.Remove('osd_stick_overlay_left_pos'); $o = Line $C.sticks_on
Check 'a firmware without the stick picture is said so, nothing written' ((Has $o 'f_nosticks') -and $script:saves -eq $before)

# ---------------------------------------------------------------- set horizon on / off
$script:fc = New-FC 'aaaa33330000222233334444' 'HOR20'
$o = Line "$($C.bind) HOR"; $o = Line $C.hor_on
Check 'set horizon on shows the horizon line where it is and keeps the choice with the type' ((Val 'osd_ah_pos') -eq '14542' -and (Preset 'HOR') -match '# horizon: on')
$script:fc = New-FC 'bbbb33330000222233334444' 'HOR21'
$o = Line "$($C.bind) HOR"; $o = Line $C.fix_ctl
Check 'set controls gives the next drone of the type its horizon' ((Val 'osd_ah_pos') -eq '14542')
$o = Line $C.hor_off
Check 'set horizon off hides it' ((Val 'osd_ah_pos') -eq '206' -and (Preset 'HOR') -match '# horizon: off')

# ---------------------------------------------------------------- set controls -m: rates by hand
# the keyboard part is stood in for: it types new values into the fields and says where to write
$script:typed = @{}; $script:toProfile = $true; $script:opened = $null
function Edit-Screen($fields, [string]$who, [string]$NAME, [string]$title) {
    $script:opened = @($fields | ForEach-Object { "$($_.key)=$($_.text)" })
    if ($script:typed.Contains('cancel')) { return $null }
    foreach ($f in $fields) { if ($script:typed.Contains($f.key)) { $f.text = $script:typed[$f.key] } }
    return @{ toProfile = $script:toProfile }
}
Set-Content (Join-Path $data 'presets\EDT.txt') -Encoding utf8 -Value @('# rates only', 'set yaw_srate = 24')
$script:fc = New-FC 'cccc33330000222233334444' 'EDT20'
$o = Line "$($C.bind) EDT"
$script:typed = @{ roll_rc_rate = '60'; roll_srate = '300'; roll_expo = '35' }; $script:toProfile = $false
$o = Line $C.edit
Check 'the editor opens on what the drone holds now' ($script:opened -contains 'roll_rc_rate=70' -and $script:opened -contains 'yaw_srate=150' -and $script:opened -contains 'pitch_expo=0' -and $script:opened.Count -eq 9)
Check 'typed values are written and read back' ((Val 'roll_rc_rate') -eq '6' -and (Val 'roll_srate') -eq '30' -and (Val 'roll_expo') -eq '35' -and (Val 'yaw_srate') -eq '15' -and $o.Contains('70 -> 60') -and $o.Contains((T 'ok_confirmed' 9)))
Check 'drone only: the profile is left as it was' ((Has $o 'ok_drone_only') -and -not ((Preset 'EDT') -match 'roll_srate'))
$script:typed = @{ yaw_srate = '260' }; $script:toProfile = $true
$o = Line $C.edit
Check 'drone and profile: the values go into the type''s file too' ((Val 'yaw_srate') -eq '26' -and (Preset 'EDT') -match 'set yaw_srate = 26' -and (Preset 'EDT') -match 'set roll_srate = 30')
$script:typed = @{ cancel = 1 }; $before = $script:saves
$o = Line $C.edit
Check 'leaving the editor without saving writes nothing' ($script:saves -eq $before -and (Has $o 'n_nothing'))
$chk = @(@{ key = 'roll_rc_rate'; label = 'a'; min = 10; max = 500; text = '300' }, @{ key = 'roll_srate'; label = 'b'; min = 20; max = 1000; text = '200' }, @{ key = 'pitch_rc_rate'; label = 'c'; min = 10; max = 500; text = '50' }, @{ key = 'pitch_srate'; label = 'd'; min = 20; max = 1000; text = '220' }, @{ key = 'yaw_rc_rate'; label = 'e'; min = 10; max = 500; text = '80' }, @{ key = 'yaw_srate'; label = 'f'; min = 20; max = 1000; text = '240' })
Check 'full stick below near centre is refused, and so is a value out of range' ((Edit-Check $chk) -eq (T 'ed_bad_full' 'b') -and (& { $chk[0].text = '5'; Edit-Check $chk }) -eq (T 'ed_bad' 'a' 10 500))

# ---------------------------------------------------------------- pid -m: PID by hand
Set-Content (Join-Path $data 'presets\PDM.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc = New-FC 'dddd33330000222233334444' 'PDM20'
$o = Line "$($C.bind) PDM"
$script:typed = @{ p_roll = '50'; d_pitch = '40' }; $script:toProfile = $false
$o = Line $C.pid_edit
Check 'pid -m opens on the drone''s PID and writes what is typed' ($script:opened -contains 'p_roll=65' -and $script:opened -contains 'd_min_pitch=60' -and (Val 'p_roll') -eq '50' -and (Val 'd_pitch') -eq '40' -and (Val 'i_roll') -eq '20' -and $o.Contains('65 -> 50') -and (Has $o 'w_risky') -and -not ((Preset 'PDM') -match 'p_roll'))
$script:typed = @{ p_roll = '60' }; $script:toProfile = $true
$o = Line $C.pid_edit
Check 'saved to the profile the typed PID stays there, level 0' ((Val 'p_roll') -eq '60' -and (Preset 'PDM') -match 'set p_roll = 60' -and (Preset 'PDM') -match '# stiffness: 0')
$script:fc = New-FC 'eeee33330000222233334444' 'PDM21'
$o = Line "$($C.bind) PDM"; $o = Line $C.fix_ctl
Check 'set controls gives the next drone of the type the typed PID' ((Val 'p_roll') -eq '60' -and (Val 'd_pitch') -eq '40')
$o = Line $C.pid_stiffer @('y')
Check 'pid stiffer then scales from the typed values' ((Val 'p_roll') -eq '66' -and (Preset 'PDM') -match '# stiffness: 1' -and (Preset 'PDM') -match 'set p_roll = 60')

# ---------------------------------------------------------------- the direction word more than once
Set-Content (Join-Path $data 'presets\TWO.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc = New-FC 'cccc22220000222233334444' 'TWO20'
$o = Line "$($C.bind) TWO"; $o = Line (Again $C.yaw_more 2)
Check 'yaw more more is two steps at once' ((Val 'yaw_rc_rate') -eq '9' -and (Val 'yaw_srate') -eq '23' -and $o.Contains('70 -> 90') -and $o.Contains('150 -> 230'))
$o = Line (Again $C.pid_stiffer 2) @('y')
Check 'pid stiffer stiffer is two levels at once' ((Val 'p_roll') -eq '78' -and (Preset 'TWO') -match '# stiffness: 2')
$o = Line (Again $C.pid_stiffer 4) @('y')
Check 'more words than there are levels left stops at the last level' ((Val 'p_roll') -eq '85' -and (Preset 'TWO') -match '# stiffness: 3')
# ---------------------------------------------------------------- throttle -m: the curve by hand
Set-Content (Join-Path $data 'presets\THM.txt') -Encoding utf8 -Value @('# rates only', 'set roll_srate = 25')
$script:fc = New-FC 'bbbb44440000222233334444' 'THM20'
$script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '100'
$o = Line "$($C.bind) THM"
$script:typed = @{ thr_expo = '65' }; $script:toProfile = $true
$o = Line $C.thr_edit
Check 'throttle -m opens on the drone''s curve, writes what is typed and saves both values' ($script:opened -contains 'thr_mid=100' -and $script:opened -contains 'thr_expo=100' -and $script:opened.Count -eq 2 -and (Val 'thr_expo') -eq '65' -and (Val 'thr_mid') -eq '100' -and $o.Contains('100 / 100 -> 100 / 65') -and (Preset 'THM') -match 'set thr_mid = 100' -and (Preset 'THM') -match 'set thr_expo = 65')
$script:typed = @{ thr_expo = '101' }
Check 'a value outside 0 to 100 is refused by the editor' ((Edit-Check @(@{ key = 'thr_mid'; label = 'm'; min = 0; max = 100; text = '100' }, @{ key = 'thr_expo'; label = 'e'; min = 0; max = 100; text = '101' })) -eq (T 'ed_bad' 'e' 0 100))
$script:typed = @{}

# ---------------------------------------------------------------- yaw -m, pitch roll -m: one axis by hand
$script:fc = New-FC 'cccc44440000222233334444' 'THM21'
$o = Line "$($C.bind) THM"
$script:typed = @{ yaw_srate = '300' }; $script:toProfile = $false
$o = Line $C.yaw_edit
Check 'yaw -m shows only yaw and writes what is typed' (($script:opened -join ' ') -eq 'yaw_rc_rate=70 yaw_srate=150 yaw_expo=0' -and (Val 'yaw_srate') -eq '30' -and (Val 'roll_srate') -eq '15' -and $o.Contains((T 'ok_confirmed' 3)))
$script:typed = @{ cancel = 1 }
$o = Line $C.pr_edit
Check 'pitch roll -m shows those two axes' ($script:opened.Count -eq 6 -and -not (($script:opened -join ' ') -match 'yaw'))
$script:typed = @{}

# ---------------------------------------------------------------- status -diff and restore
Set-Content (Join-Path $data 'presets\DIF.txt') -Encoding utf8 -Value @('# rates and a curve', 'set roll_rc_rate = 5', 'set roll_srate = 22', 'set thr_mid = 100', 'set thr_expo = 100')
$script:fc = New-FC 'aaaa44440000222233334444' 'DIF20'
$script:fc.rates.thr_mid = '100'; $script:fc.rates.thr_expo = '100'; $script:fc.otherThr = @('100', '100')
$o = Line "$($C.bind) DIF"; $before = $script:saves; $o = Line $C.diff
Check 'status -diff on an untouched drone: every value, nothing marked, nothing written' ((Has $o 'r_diff') -and $o.Contains('70 / 150') -and $o.Contains(((T 'df_same_bar') -f 'DIF aaaa4444', '').Substring(0, 24)) -and -not $o.Contains('=> ') -and $script:saves -eq $before)
$o = Line $C.fix_ctl; $o = Line (Again $C.thr_softer 2); $o = Line $C.pid_stiffer @('y'); $o = Line $C.diff
Check 'a changed value is marked and shown old -> new' ($o.Contains('=> ') -and ($o -match '70 / 150 \S+\s+->\s+50 / 220') -and $o.Contains(((T 'df_bar') -f 'DIF aaaa4444', 4, 0, '').Substring(0, 30)))
Check 'steps are said in words: 2 x softer, 1 x stiffer' ($o.Contains((T 'df_times' 2 (T 'w_softer').ToLower())) -and $o.Contains((T 'df_times' 1 (T 'w_stiffer').ToLower())) -and ($o -match '100 / 100\s+->\s+100 / 80'))
$before = $script:saves; $o = Line $C.restore @('n')
Check 'restore lists what it will put back and asks first' ($o.Contains('50 / 220') -and (Has $o 'q_apply') -and $script:saves -eq $before -and (Val 'roll_srate') -eq '22')
$o = Line $C.restore @('y')
Check 'restore puts the drone back as it arrived' ((Val 'roll_rc_rate') -eq '7' -and (Val 'roll_srate') -eq '15' -and (Val 'thr_expo') -eq '100' -and (Val 'p_roll') -eq '65' -and (Val 'd_pitch') -eq '65' -and $o.Contains(((T 'b_restored') -f 'DIF aaaa4444', '').Substring(0, 24)))
Check 'and leaves the profile alone' ((Preset 'DIF') -match 'set thr_expo = 80' -and (Preset 'DIF') -match '# stiffness: 1')
$before = $script:saves; $o = Line $C.restore @('y')
Check 'a second restore has nothing to do' ((Has $o 'n_restore_same') -and $script:saves -eq $before)
[IO.File]::Delete((Join-Path $data 'quads\orig_aaaa4444.txt'))
$o = Line $C.fix_ctl; $o = Line $C.diff
Check 'a drone bound by an older version is compared with its saved before listing' ($o.Contains('=> ') -and ($o -match '100 / 100\s+->\s+100 / 80') -and -not $o.Contains('50 / 220'))

# ---------------------------------------------------------------- status -p NAME: a saved profile, no drone
$n0 = $script:sent.Count; $o = Line "$($C.prof) dif"
Check 'status -p NAME shows what the profile holds without touching USB' ($script:sent.Count -eq $n0 -and $o.Contains((T 'r_profile' 'DIF')) -and $o.Contains('50 / 220') -and $o.Contains('100 / 80') -and $o.Contains('+1') -and -not $o.Contains('=> '))
$o = Line "$($C.prof) DIF -diff"
Check 'with -diff it is set against the standard and what differs is marked' ($script:sent.Count -eq $n0 -and $o.Contains('=> ') -and ($o -match '->\s+100 / 80') -and $o.Contains(((T 'pf_diff_bar') -f 'DIF', 0, 0).Substring(0, 12)))
$o = Line "$($C.prof) NOSUCH"
Check 'a name with no profile is said so' ($o.Contains((T 'f_nopreset' 'NOSUCH')) -and $script:sent.Count -eq $n0)

# ---------------------------------------------------------------- the safety limit
# everything the console ever sent must pass bf.ps1's own guard
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'bf.ps1'), [ref]$null, [ref]$null)
$assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$forbidden' }, $true)
$forbidden = Invoke-Expression $assign.Right.Extent.Text
$blocked = @($script:sent | Sort-Object -Unique | Where-Object { $_.Trim() -match $forbidden })
Check "none of the $(@($script:sent | Sort-Object -Unique).Count) distinct commands sent is refused by bf.ps1" ($blocked.Count -eq 0)
Check 'bf.ps1 still refuses switch, channel and failsafe commands' (('aux 0 0 0 900 2100 0 0' -match $forbidden) -and ('set failsafe_delay = 5' -match $forbidden) -and ('rxfail 3 h' -match $forbidden) -and ('beacon RX_LOST' -match $forbidden) -and ('beeper RX_LOST' -match $forbidden) -and -not ('beeper ALL' -match $forbidden) -and ('defaults' -match $forbidden))
$shipped = @(Get-ChildItem (Join-Path $repo 'presets') -Filter '*.txt' | ForEach-Object { Get-Content $_.FullName } | Where-Object { $_ -and $_ -notmatch '^\s*#' })
Check "all $($shipped.Count) lines of the shipped settings files are plain 'set' lines the guard allows" (@($shipped | Where-Object { $_ -notmatch '^set \w+ = \S+$' -or $_ -match $forbidden }).Count -eq 0)

[IO.Directory]::Delete($data, $true)
Write-Host ''
Write-Host ("  {0}: {1} passed, {2} failed" -f $Lang, $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail
