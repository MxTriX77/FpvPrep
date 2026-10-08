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
    "# Saved settings for 'SIM'.", '# craft: SIM20',
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
Check 'bind reports 0 of 15 controls' ($o.Contains((T 'ctl_count' 0 15 'SIM')))
Check 'bind does not run the health check' (-not (Has $o 'h_step'))
Check 'bind writes nothing to the drone' ($script:saves -eq $before -and (Val 'roll_srate') -eq '15')
$copy = Get-ChildItem (Join-Path $data 'quads') -Filter '*_SIM_5150aaaa_before.txt'
Check 'bind saves a config copy without the dump' ($copy.Count -eq 1 -and -not ((Get-Content $copy.FullName -Raw) -match 'thr_mid'))
Check 'bind remembers the quad name' ((Last-Name) -eq 'SIM')

$o = Line $C.status
Check 'status shows rates, the health check and a green verdict' ($o.Contains('70 / 150') -and (Has $o 'h_step') -and $o.Contains((T 'good_status')))
Check 'status says nothing about saved settings' (-not $o.Contains((T 'kv_ctl')) -and -not $o.Contains((T 'preset_std')))
Check 'no line carries a clock time' (-not ($o -match '\d\d:\d\d:\d\d'))

# ---------------------------------------------------------------- fix
$o = Line $C.fix_ctl
Check 'fix controls writes all 15 values' ((Val 'roll_srate') -eq '25' -and (Val 'yaw_srate') -eq '30' -and (Val 'thr_expo') -eq '25' -and (Val 'deadband') -eq '3' -and (Val 'f_pitch') -eq '40' -and (Val 'rc_smoothing_auto_factor') -eq '60')
Check 'fix controls confirms by reading back' ($o.Contains((T 'ok_confirmed' 15)) -and $o.Contains((T 'done_ctl')))
Check 'fix controls saves an after copy' (@(Get-ChildItem (Join-Path $data 'quads') -Filter '*_SIM_5150aaaa_after.txt').Count -eq 1)
$before = $script:saves
$o = Line $C.fix_ctl
Check 'fix controls a second time changes nothing' ($script:saves -eq $before -and $o.Contains((T 'b_nofix' 'SIM 5150aaaa')))
$o = Line $C.fix_short
Check 'the bare word works as fix controls' ($o.Contains((T 'r_fix' (T 'w_ctl'))) -and $o.Contains((T 'b_nofix' 'SIM 5150aaaa')))
$o = Line $C.fix_snd
Check 'fix sound switches the beeps off and confirms' (-not $script:fc.beeps -and (Has $o 'ok_snd'))

# ---------------------------------------------------------------- axis tuning
$o = Line $C.yaw_more @('y')
Check 'yaw more steps centre by 10 and full stick by 40' ((Val 'yaw_rc_rate') -eq '10' -and (Val 'yaw_srate') -eq '34' -and $o.Contains('90 -> 100') -and $o.Contains('300 -> 340'))
Check 'an axis change is applied and remembered without any question' ((Preset 'SIM') -match 'set yaw_srate = 34' -and -not ((Preset 'SIM') -match 'set yaw_srate = 30') -and -not $o.Contains((T 'yn')))
$o = Line $C.pr_slightly_less @('y')
Check 'pitch roll slightly less: half steps on both axes' ((Val 'roll_rc_rate') -eq '4' -and (Val 'pitch_rc_rate') -eq '4' -and (Val 'roll_srate') -eq '23' -and (Val 'pitch_srate') -eq '23')
$o = Line $C.thr_much_more @('y')
Check 'throttle much more: expo down by 20' ((Val 'thr_expo') -eq '5')
$o = Line $C.thr_more
Check 'throttle more again: expo down to 0' ((Val 'thr_expo') -eq '0')
$before = $script:saves
$o = Line $C.thr_more
Check 'throttle stops at the limit and writes nothing' ((Val 'thr_expo') -eq '0' -and (Has $o 'n_nochange') -and $script:saves -eq $before)
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
$o = Line $C.motors_full
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
Check 'the next drone gets the type''s rates and its stiffness level' ((Val 'roll_srate') -eq '23' -and (Val 'yaw_srate') -eq '34' -and (Val 'thr_expo') -eq '0' -and (Val 'p_roll') -eq '78' -and (Val 'd_pitch') -eq '78')

$script:fc = New-FC 'c0ffee001122334455667788' 'OTHER'
$o = Line "$($C.bind) SIM"
Check 'bind warns when the drone does not look like the type' ($o.Contains('OTHER'))
$before = $script:saves
$o = Line $C.fix_ctl @('n')
Check 'fix controls asks first and changes nothing on no' ($script:saves -eq $before -and (Val 'roll_srate') -eq '15')
$o = Line $C.fix_ctl @('y')
Check 'and applies on yes' ((Val 'roll_srate') -eq '23')

$script:fc = New-FC 'abcdef001122334455667788' 'NEWQ1'
$o = Line "$($C.bind) NEWQ"
Check 'a new type: bind says there are no saved settings' ($o.Contains((T 'ctl_none' 'NEWQ')))
$o = Line $C.fix_ctl
Check 'a new type: fix controls says so and writes nothing' ($o.Contains((T 'f_nopreset' 'NEWQ')) -and (Val 'roll_srate') -eq '15')
$o = Line $C.yaw_more @('y')
Check 'a new type: a confirmed change creates its saved settings' ((Test-Path (Join-Path $data 'presets\NEWQ.txt')) -and (Preset 'NEWQ') -match '# craft: NEWQ1')
Add-Content (Join-Path $data 'presets\NEWQ.txt') 'set no_such_setting = 1'
$o = Line $C.fix_ctl
Check 'a line the drone rejects is reported, not hidden' ((Has $o 'f_rejected') -and (Has $o 'b_problems'))

# a type with no file of its own, once the standard set exists
Set-Content (Join-Path $data 'presets\_default.txt') -Encoding utf8 -Value @(
    '# standard set', 'set rates_type = ACTUAL', 'set roll_rc_rate = 5', 'set roll_srate = 25', 'set yaw_srate = 27',
    'set thr_mid = 43', 'set thr_expo = 40', 'set deadband = 4')
$script:fc = New-FC 'dddd00001111222233334444' 'ZED7'
$o = Line "$($C.bind) ZED"
Check 'a type with no file is measured against the standard set' ($o.Contains((T 'ctl_count_std' 1 7)))
$o = Line $C.fix_ctl
Check 'fix controls writes the standard set to it' ((Val 'roll_srate') -eq '25' -and (Val 'thr_mid') -eq '43' -and (Val 'thr_expo') -eq '40' -and (Val 'deadband') -eq '4')
$o = Line $C.yaw_more @('y')
Check 'a change for a new type starts its file from the standard set' ((Preset 'ZED') -match 'set thr_mid = 43' -and (Preset 'ZED') -match 'set yaw_srate = 31' -and (Preset 'ZED') -match '# craft: ZED7')
$script:fc = New-FC 'eeee00001111222233334444' 'ZED7'
$o = Line "$($C.bind) ZED"; $o = Line $C.fix_ctl
Check 'the next drone of that type gets the standard set plus the change' ((Val 'thr_mid') -eq '43' -and (Val 'yaw_srate') -eq '31' -and (Val 'roll_srate') -eq '25')

# ---------------------------------------------------------------- the safety limit
# everything the console ever sent must pass bf.ps1's own guard
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'bf.ps1'), [ref]$null, [ref]$null)
$assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$forbidden' }, $true)
$forbidden = Invoke-Expression $assign.Right.Extent.Text
$blocked = @($script:sent | Sort-Object -Unique | Where-Object { $_.Trim() -match $forbidden })
Check "none of the $(@($script:sent | Sort-Object -Unique).Count) distinct commands sent is refused by bf.ps1" ($blocked.Count -eq 0)
Check 'bf.ps1 still refuses switch, channel and failsafe commands' (('aux 0 0 0 900 2100 0 0' -match $forbidden) -and ('set failsafe_delay = 5' -match $forbidden) -and ('rxfail 3 h' -match $forbidden) -and ('beeper ALL' -match $forbidden) -and ('defaults' -match $forbidden))
$shipped = @(Get-ChildItem (Join-Path $repo 'presets') -Filter '*.txt' | ForEach-Object { Get-Content $_.FullName } | Where-Object { $_ -and $_ -notmatch '^\s*#' })
Check "all $($shipped.Count) lines of the shipped settings files are plain 'set' lines the guard allows" (@($shipped | Where-Object { $_ -notmatch '^set \w+ = \S+$' -or $_ -match $forbidden }).Count -eq 0)

[IO.Directory]::Delete($data, $true)
Write-Host ''
Write-Host ("  {0}: {1} passed, {2} failed" -f $Lang, $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $script:fail
