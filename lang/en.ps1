# English text and command words for fpv.ps1. Returns one table.
# Keys starting with rx_ are regular expressions matched against the lower-cased input line.
@{
    # ---- marks, prompts, units
    st_ok = ' OK '; st_warn = 'WARN'; st_fail = 'FAIL'
    yn = '[Y/N]'; yes_rx = '^\s*[Yy]'
    sec = '{0:0.0} s'; unit_rpm = 'rpm'; unit_dps = 'deg/s'; unit_v = 'V'

    # ---- command words
    rx_bind   = '^(bind|connect|connected)(\s+|$)'
    rx_fix    = '^(set|fix)(\s+|$)'
    rx_fix_short = '^(controls|sound)(\s+|$)'
    rx_name = '^(name)(\s+|$)'
    rx_sticks = '^(sticks?)(\s+|$)'; rx_on = '\b(on|show)\b'; rx_off = '\b(off|hide)\b'
    rx_horizon = '^(horizon([\s_]*bar)?)(\s+|$)'
    rx_help   = '^(help|\?)$'
    rx_status = '^(status)\b'
    rx_diff = '(^|\s)-?-?(diff|d)(\s|$)'
    rx_restore = '^(restore)$'
    rx_radio  = '^(radio|tx12)\b'
    rx_exit   = '^(exit|quit|q)$'
    rx_radio_name = '^(TX12|radio)$'
    rx_motor  = 'motor'
    rx_full   = 'full|long'
    rx_quiet_flag = '(--)?(quiet|silent)[\s_-]*(motors?|check)'
    rx_full_flag  = '(--)?full[\s_-]*(motors?|check)'
    rx_flag_strip = '(--)?(quiet|silent|full|no)[\s_-]*(motors?|check)|--bf'
    rx_ctl = 'control|rates?|sticks?'
    rx_snd = 'sound|beep|buzzer'
    rx_yaw = '\b(yaw)\b'; rx_pitch = '\b(pitch)\b'; rx_roll = '\b(roll)\b'
    rx_more = '\b(more|faster|sharper|higher|up)\b'
    rx_less = '\b(less|slower|softer|lower|down)\b'

    # ---- build: the folder and launcher of this language's release
    release = @{ folder = 'CONFIGURATOR'; launcher = 'CONFIG.cmd' }

    # ---- start screen
    banner = @(
        @('  FPVPREP 1.0', 'White', '  --  Betaflight pre-flight utility', 'Gray'),
        @('  build {0}  win32  serial cli 115200 8N1', 'DarkGray'),
        @('', 'DarkGray'),
        @('  writes flight feel only. switches, channels, failsafe: never written.', 'DarkYellow')
    )
    kv_saved = 'saved settings'; kv_last = 'last quad'
    warn_bf = '[!!] keep the Betaflight program closed'
    note_help = 'help - commands'
    mock_bar = 'MOCK  //  pretend drone  //  nothing is read from or written to USB'
    mock_note = 'each  status  goes round: healthy, with remarks, faulty'

    # ---- shared steps and failures
    s_find = 'acquiring drone on USB'
    f_nousb = 'no drone on USB. Re-seat the cable and try again.'
    f_noread = 'could not read the drone. Is the Betaflight program open? Close it.'
    f_unknowncmd = 'unknown command. type  help'
    kv_id = 'drone id'; kv_craft = 'calls itself'; kv_fw = 'firmware'; kv_seen = 'bound before'
    seen_yes = 'YES'; seen_no = 'no - new drone'
    kv_drone = 'drone'
    errors = @(
        @('No serial port|No drone on USB', 'no drone on USB. Re-seat the cable.'),
        @('is busy', 'the port is busy. Close the Betaflight program or press Disconnect in it.'),
        @('Several ports', 'this PC has several serial ports and I cannot pick one: {0}'),
        @('Refused', 'refused: that is not a flight-feel setting. {0}'),
        @('No CLI answer', 'the drone does not answer. Close the Betaflight program and retry.')
    )

    # ---- bind
    r_bind = 'BIND {0}'
    s_read = 'reading config'
    f_which = 'which quad? type:  bind "NAME"'
    preset_std = 'standard for heavy 10/13 inch quads'
    n_skipped = "did not understand: '{0}'"
    n_bindmotor = 'for the motors:  motors'
    b_bound = '{0}  //  BOUND  //  {1}'
    good_status = 'READY'

    # ---- health check
    h_step = 'checking the drone'
    chip_sensors = 'sensors'; chip_ok = 'ok'; chip_cpu = 'cpu'; chip_batt = 'battery'
    chip_radio = 'radio'; chip_linked = 'linked'; chip_escs = 'ESCs'
    h_nogyro = 'no gyro detected'
    h_noacc = 'no accelerometer'
    h_acc_uncal = 'accelerometer not calibrated'
    h_cpu = 'processor load {0}%'
    h_i2c = 'sensor bus errors: {0}'
    h_temp = 'processor {0} C'
    h_nobatt = 'battery not connected'
    h_batt_low = 'battery {0}S {1} V - not full'
    h_batt_crit = 'battery {0}S {1} V - flat'
    h_radio_off = 'radio not linked'
    h_esc = 'ESC {0} is not answering'
    h_arm = 'will not arm: {0}'
    arm_ARMSWITCH = 'THE ARM SWITCH IS ON'
    arm_THROTTLE = 'throttle stick is not at the bottom'
    arm_ANGLE = 'the drone is tilted too far'
    arm_LOAD = 'processor overloaded'
    arm_ACC_CALIB = 'accelerometer calibration needed'
    arm_MOTOR_PROTO = 'motor protocol not configured'
    arm_RPMFILTER = 'RPM filter has no motor data'
    arm_DSHOT_TELEM = 'no telemetry from the ESCs'
    arm_DSHOT_BBANG = 'motor signal output not working'
    arm_REBOOT_REQD = 'a reboot is required'
    arm_FAILSAFE = 'failsafe is active'
    arm_BADRX = 'radio signal just came back'
    arm_BOXFAILSAFE = 'failsafe switch is on'
    arm_RUNAWAY = 'runaway takeoff protection tripped'
    arm_CRASH = 'crash detection tripped'
    arm_PARALYZE = 'paralyze mode is on'
    arm_GPS = 'waiting for GPS'
    arm_RESCUE_SW = 'rescue switch is on'

    # ---- verdict
    v_fail = '{0}  //  DO NOT FLY  //  {1}'
    v_warn = '{0}  //  REMARKS  //  {1}'
    v_good = '{0}  //  {1}  //  {2}'

    # ---- motor check
    r_motors = 'MOTORS'; good_motors = 'OK'
    m_step = 'spinning motors: all four, {0} s, idle'
    m_noread = 'no speed readout from the motors. Is the battery plugged in?'
    m_row = 'motor {0}'; m_err = 'err {0}%'
    m_dead = 'motor {0} did not turn'
    m_noisy = 'motor {0}: noisy signal'
    m_spread = 'motors differ by {0}%'
    m_nostop = 'motor stop not confirmed'
    chip_motors = 'motors'; chip_even = 'even'; chip_after = 'after run'; chip_stopped = 'stopped'

    # ---- fix
    n_fixwhat = 'set what?   set controls   /   set sound   /   set name NAME   /   set sticks on'
    f_bindfirst = 'bind to a drone first:  bind "NAME"'
    r_fix = 'SET  //  {0}'; w_ctl = 'CONTROLS'; w_snd = 'SOUND'
    s_readdrone = 'reading the drone'
    f_nopreset = 'no saved settings for {0}'
    r_sticks = 'SET  //  STICKS {0}'; w_on = 'ON'; w_off = 'OFF'
    n_stickswhat = 'set sticks on   /   set sticks off'
    f_nosticks = 'this firmware has no stick picture for the OSD'
    kv_sticks = 'sticks on the OSD'
    b_sticks = '{0}  //  STICKS {1}  //  {2}'
    r_horizon = 'SET  //  HORIZON {0}'
    n_horizonwhat = 'set horizon on   /   set horizon off'
    f_nohorizon = 'this firmware has no horizon line for the OSD'
    kv_horizon = 'horizon on the OSD'
    b_horizon = '{0}  //  HORIZON {1}  //  {2}'
    r_name = 'SET  //  NAME'
    n_namewhat = 'which name?   set name NAME   /   set sticks on'
    f_badname = 'name: Latin letters, digits, space and _ . - only, up to 16 characters'
    kv_osdname = 'name on the OSD'
    w_name_hidden = 'the name is not shown on this drone''s OSD'
    b_named = '{0}  //  NAME SET  //  {1}'
    n_nothing = 'nothing changed.'
    s_ctl = 'controls: {0} values'
    kv_thr_back = 'throttle, builder''s curve back'
    w_thr_unknown = 'throttle curve 45 / 40 came from an older version; the original is not known'
    s_snd = 'sound: {0}'
    s_write = 'writing to drone and saving'
    s_verify = 'drone restarting, reading back'
    f_rejected = 'the drone rejected a line:'
    f_missing = 'values that did not stick: {0}'
    i_missing = '{0} : wanted {1}, the drone has {2}'
    ok_confirmed = 'confirmed: {0} of {0} values are in the drone'
    ok_snd = 'beeps are off'; ok_snd_on = 'beeps are on'
    w_snd_unconf = 'could not confirm the sound setting'
    done_ctl = 'controls'; done_snd = 'sound'
    b_fixed = '{0}  //  SET: {1}  //  {2}'
    b_problems = 'PROBLEMS  //  see above'

    # ---- yaw / pitch / roll  more / less
    r_tune = 'TUNE  //  {0} {1}'
    ax_yaw = 'YAW'; ax_pitch = 'PITCH'; ax_roll = 'ROLL'
    w_more = 'MORE'; w_less = 'LESS'
    s_readrates = 'reading current rates'
    f_unknown = 'do not know what quad this is. first:  bind "NAME"'
    f_notactual = "this drone's rates are in '{0}' format, not ACTUAL. Axis tuning does not work on it."
    f_noaxis = 'rates for {0} not found in the config.'
    n_limit = '{0}: already at the limit'
    kv_centre = '{0}, near centre'; kv_full = '{0}, full stick'
    n_nochange = 'nothing to change.'
    q_apply = 'apply?'
    ok_remembered = 'remembered for every {0}.'
    b_done = '{0}  //  DONE  //  {1}'

    # ---- set controls -m: the editor
    r_edit = 'SET  //  CONTROLS BY HAND'
    ed_title = 'CONTROLS BY HAND'; ed_pidtitle = 'PID BY HAND'; r_pidedit = 'PID  //  BY HAND'
    ed_thrtitle = 'THROTTLE CURVE BY HAND'; r_thredit = 'THROTTLE  //  BY HAND'; ed_thrmid = 'throttle mid'; ed_threxpo = 'throttle expo'
    ed_expo = '{0}, expo'
    ed_target = 'write to'
    ed_drone = 'this drone only'
    ed_profile = 'this drone + profile {0}'
    ed_keys = 'up/down move   digits type   left/right change   Enter save   Esc cancel'
    ed_range = '{0} to {1}'
    ed_bad = '{0}: must be {1} to {2}'
    ed_bad_full = '{0}: must be above near centre'
    ok_drone_only = 'written to this drone only.'

    # ---- throttle softer / throttle sharper
    rx_thr = '^(throttle|thr)(\s+|$)'
    rx_thr_softer = '\b(softer|soften)\b'
    rx_thr_sharper = '\b(stiffer|sharper|sharpen)\b'
    n_thrwhat = 'throttle softer   /   throttle stiffer'
    r_thr = 'THROTTLE  //  {0}'
    s_readthr = 'reading the throttle curve'
    f_nothr = 'throttle curve not found in the config'
    kv_thr = 'throttle curve'

    # ---- pid stiffer / pid softer
    rx_pid = '^(pid)(\s+|$)'
    rx_stiffer = '\b(stiffer)\b'
    rx_softer = '\b(softer)\b'
    n_pidwhat = 'pid stiffer   /   pid softer'
    r_stiff = 'PID  //  {0}'; w_stiffer = 'STIFFER'; w_softer = 'SOFTER'
    s_readpid = 'reading PID'
    f_nopid = 'PID not found in the config'
    kv_pid = '{0} P / I / D'; kv_level = 'stiffness'
    n_stifflimit = 'stiffness {0}: at the limit'
    w_risky = 'a little risky: it may help, or it may make things slightly worse'

    # ---- status, radio
    r_status = 'STATUS'
    r_diff = 'STATUS  //  DIFF'
    df_none = 'no saved copy of how this drone arrived'
    df_bar = '{0}  //  CHANGED: {1} of {2}  //  {3}'
    df_same_bar = '{0}  //  AS IT ARRIVED  //  {1}'
    df_pid4 = '{0} P / I / D / Dmin'; df_pid2 = '{0} P / I'
    df_deadband = 'deadband, sticks / yaw'
    df_smooth = 'stick smoothing'
    df_ff = 'feedforward, fade / jitter / boost'
    df_times = '{0} x {1}'
    r_restore = 'RESTORE'
    n_restore_same = 'nothing to restore: the drone is as it arrived.'
    b_restored = '{0}  //  RESTORED  //  {1}'
    s_readonly = 'reading config (nothing is changed)'
    kv_rates = '{0}, centre / full stick'; kv_ratefmt = 'rates format'
    r_radio = 'RADIO'
    s_calib = 'reading stick calibration (read only)'
    f_noradio = 'radio not found. On the radio choose "USB Storage (SD)".'
    kv_axis = 'stick axis {0}'
    f_calib = 'a stick axis is badly calibrated. On the radio: SYS, HARDWARE, Calibration.'
    ok_calib = 'all four stick axes healthy'

    # ---- help: two items = command and what it does, one item = a note, none = blank line
    r_help = 'COMMANDS'
    help = @(
        @('bind "NAME"', 'find the drone on USB'),
        @('status [ -diff ]', 'check the drone; -diff: what changed since it arrived'),
        @('motors [ -N ]', 'motor run for N seconds, 1 if not given'),
        @(),
        @('set controls [ -m ]', 'write the stick settings; -m: type the rates by hand'),
        @('set sound [ on | off ]', 'the beeper'),
        @('set sticks [ on | off ]', 'stick pictures on the OSD'),
        @('set horizon [ on | off ]', 'horizon line on the OSD'),
        @('set name NAME', 'change the name shown on the OSD'),
        @(),
        @('yaw | pitch | roll  [ more | less ]', 'rates'),
        @('throttle [ softer | stiffer | -m ]', 'throttle curve; -m: type it by hand'),
        @('pid [ stiffer | softer | -m ]', 'roll and pitch PID, 10% a step; -m: type them by hand. risky'),
        @('say the word again for a bigger step:  yaw more more'),
        @(),
        @('restore', 'put the drone back as it arrived'),
        @('radio', 'radio stick calibration'),
        @('help / exit', '')
    )
    # ---- the lines tests\sim.ps1 types, so the same test runs in every language
    test_words = @{
        bind = 'bind'; bind_none = 'bind'; unknown = 'make it pretty'; status = 'status'
        fix_ctl = 'set controls'; fix_snd = 'set sound off'; snd_on = 'set sound on'; old_fix = 'fix controls'; set_name = 'set name'; sticks_on = 'set sticks on'; sticks_off = 'set sticks off'; sticks = 'set sticks'
        yaw_more = 'yaw more'; pr_less = 'pitch roll less'
        motors = 'motors'; motors_full = 'motors -3'
        fix_short = 'controls'; pid = 'pid'; pid_stiffer = 'pid stiffer'; pid_softer = 'pid softer'; bare_stiffer = 'stiffer'; thr_more = 'throttle more'; thr_softer = 'throttle softer'; thr_sharper = 'throttle stiffer'; edit = 'set controls -m'; pid_edit = 'pid -m'; thr_edit = 'throttle -m'; diff = 'status -diff'; restore = 'restore'; hor_on = 'set horizon on'; hor_off = 'set horizon off'; odd_name = 'heavy'; help = 'help'; exit = 'exit'
    }
}
