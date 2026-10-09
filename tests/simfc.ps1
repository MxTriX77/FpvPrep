# A pretend Betaflight 4.5 flight controller held in memory. Used by tests\sim.ps1 and by the
# UI mocks. It answers the same text commands in the same layout as a real board, and like a
# real one it only keeps "set" changes when the session ends with save.
# The board in use is $script:fc; make one with New-FC.

# ---------------------------------------------------------------- the pretend flight controller
function New-FC([string]$id = '5150aaaa1111222233334444', [string]$craft = 'SIM20') {
    return @{
        id = $id; volts = 3381; cells = 8; flags = 'CLI'; cpu = 51; gyro = 'ICM42688P'; acc = 'ICM42688P'
        rpm = @(1200, 1195, 1188, 1210); escErr = @(0, 0, 0, 0); running = $false; beeps = $true
        otherThr = $null   # thr_mid, thr_expo of rate profiles 1-3 when they are not at the default
        master = [ordered]@{ acc_calibration = '58,7,-6,1'; small_angle = '100'; dyn_idle_min_rpm = '0'; deadband = '0'; yaw_deadband = '0'
                             rc_smoothing_auto_factor = '30'; craft_name = $craft }
        profile = [ordered]@{ p_roll = '65'; i_roll = '20'; d_roll = '70'; d_min_roll = '60'; p_pitch = '60'; i_pitch = '20'; d_pitch = '65'; d_min_pitch = '60'
                              f_roll = '80'; f_pitch = '80'; feedforward_transition = '0'; feedforward_jitter_factor = '7'; feedforward_boost = '15' }
        rates = [ordered]@{ thr_mid = '50'; thr_expo = '0'; rates_type = 'ACTUAL'; roll_rc_rate = '7'; pitch_rc_rate = '7'; yaw_rc_rate = '7'
                            roll_expo = '0'; pitch_expo = '0'; yaw_expo = '0'; roll_srate = '15'; pitch_srate = '15'; yaw_srate = '15'
                            throttle_limit_type = 'OFF'; throttle_limit_percent = '100' }
    }
}
function Sim-FC([string[]]$commands, [bool]$save) {
    $fc = $script:fc; $o = @(); $staged = @(); $rejected = @(); $first = $true; $beepOff = $false
    foreach ($c in $commands) {
        if ($first) { $o += $c; $first = $false } else { $o += "# $c" }   # the real echo: first line bare, the rest after the prompt
        switch -Regex ($c) {
            '^status$' {
                $state = 'OK'; if ($fc.cells -eq 0) { $state = 'NOT PRESENT' }
                $o += "MCU F40X Clock=168MHz (PLLP-HSE), Vref=3.30V, Core temp=44degC"
                $o += "Gyros detected: gyro 1 locked"
                $o += "GYRO=$($fc.gyro), ACC=$($fc.acc), BARO=DPS310"
                $o += "CPU:$($fc.cpu)%, cycle time: 125, GYRO rate: 8000, RX rate: 250, System rate: 9"
                $o += "Voltage: $($fc.volts) * 0.01V ($($fc.cells)S battery - $state)"
                $o += "I2C Errors: 0"
                $o += "Arming disable flags: $($fc.flags)"; $o += ''
            }
            '^dshot_telemetry_info$' {
                $o += 'Dshot reads: 91453'; $o += 'Dshot invalid pkts: 0'; $o += ''
                $o += 'Motor    Type   eRPM    RPM     Hz Invalid   TEMP    VCC   CURR  ST/EV   DBG1   DBG2   DBG3'
                $o += '=====  ====== ====== ====== ====== ======= ====== ====== ====== ====== ====== ====== ======'
                for ($m = 0; $m -lt 4; $m++) {
                    $v = 0; if ($fc.running) { $v = $fc.rpm[$m] }
                    $o += ("    {0}   R----   {1,5}  {2,5}     {3,2}  {4,5:0.00}%      0   0.00      0      0" -f ($m + 1), ($v * 7), $v, [int]($v / 60), $fc.escErr[$m])
                }
                $o += ''
            }
            '^diff all$' {
                $o += '# version'; $o += '# Betaflight / STM32F405 (S405) 4.5.0 Apr 28 2024 / 01:55:44 (c155f58) MSP API: 1.46'; $o += ''
                $o += 'board_name STM32F405'; $o += "mcu_id $($fc.id)"; $o += ''
                if (-not $fc.beeps) { $o += 'beeper -GYRO_CALIBRATED'; $o += 'beeper -RX_LOST' }
                $o += '# master'; $o += "set craft_name = $($fc.master.craft_name)"; $o += ''
                # four rate profiles as a real board lists them: the active one (0), then three the
                # console never writes to; a value equal to the firmware default is not listed
                for ($n = 0; $n -lt 4; $n++) {
                    $o += "rateprofile $n"; $o += ''; $o += "# rateprofile $n"
                    if ($n -eq 0) {
                        if ($fc.rates.thr_mid -ne '50') { $o += "set thr_mid = $($fc.rates.thr_mid)" }
                        if ($fc.rates.thr_expo -ne '0') { $o += "set thr_expo = $($fc.rates.thr_expo)" }
                        $o += "set roll_srate = $($fc.rates.roll_srate)"
                    } elseif ($fc.otherThr) { $o += "set thr_mid = $($fc.otherThr[0])"; $o += "set thr_expo = $($fc.otherThr[1])" }
                    $o += ''
                }
                $o += '# restore original rateprofile selection'; $o += 'rateprofile 0'; $o += ''
            }
            '^dump$' {
                $o += '# master'; foreach ($k in $fc.master.Keys) { $o += "set $k = $($fc.master[$k])" }; $o += ''
                $o += 'profile 0'; $o += ''; $o += '# profile 0'; foreach ($k in $fc.profile.Keys) { $o += "set $k = $($fc.profile[$k])" }; $o += ''
                $o += 'rateprofile 0'; $o += ''; $o += '# rateprofile 0'; foreach ($k in $fc.rates.Keys) { $o += "set $k = $($fc.rates[$k])" }; $o += ''
            }
            '^set (\w+) = (.+)$' {
                $k = $Matches[1]; $v = $Matches[2].Trim()
                if ($fc.master.Contains($k) -or $fc.profile.Contains($k) -or $fc.rates.Contains($k)) { $staged += , @($k, $v); $o += "$k set to $v" }
                else { $o += '###ERROR: INVALID NAME###'; $rejected += $c }
            }
            '^beeper -' { $beepOff = $true }
            '^beacon -' { }
            '^motor 255 1050$' { $fc.running = $true; $o += 'Using all outputs.'; $o += 'all motors: 146' }
            '^motor 255 1000$' { $fc.running = $false; $o += 'Using all outputs.'; $o += 'all motors: 0' }
            default { $o += '###ERROR: UNKNOWN COMMAND###'; $rejected += $c }
        }
    }
    if ($save) {   # only a saved session keeps its changes, as on the real board
        foreach ($s in $staged) { foreach ($sec in 'master', 'profile', 'rates') { if ($fc[$sec].Contains($s[0])) { $fc[$sec][$s[0]] = $s[1] } } }
        if ($beepOff) { $fc.beeps = $false }
    }
    $fc.running = $false   # the board restarts at the end of every session
    if ($rejected.Count) { $o += ''; $o += "### REJECTED BY THE FC ($($rejected.Count)):"; $o += ($rejected | ForEach-Object { "   $_" }) }
    return ($o -join "`n")
}
