# English text and command words for fpv.ps1. Returns one table.
# Keys starting with rx_ are regular expressions matched against the lower-cased input line.
@{
    # ---- marks, prompts, units
    st_ok = ' OK '; st_warn = 'WARN'; st_fail = 'FAIL'
    yn = '[Y/N]'; yes_rx = '^\s*[Yy]'
    sec = '{0:0.0} s'; unit_rpm = 'rpm'; unit_dps = 'deg/s'; unit_v = 'V'

    # ---- command words
    rx_bind   = '^(bind|connect|connected)(\s+|$)'
    rx_fix    = '^(fix)(\s+|$)'
    rx_fix_short = '^(controls|sound)(\s+|$)'
    rx_help   = '^(help|\?)$'
    rx_status = '^(status)\b'
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
    rx_yaw = '\b(yaw)\b'; rx_pitch = '\b(pitch)\b'; rx_roll = '\b(roll)\b'; rx_throttle = '\b(throttle|thr)\b'
    rx_more = '\b(more|faster|sharper|higher|up)\b'
    rx_less = '\b(less|slower|softer|lower|down)\b'
    rx_half = '\b(slightly|bit|little)\b'
    rx_double = '\b(much|lot|way)\b'

    # ---- start screen
    banner = @(
        @('  FPVPREP 1.0', 'White', '  --  Betaflight pre-flight utility', 'Gray'),
        @('  build {0}  win32  serial cli 115200 8N1', 'DarkGray'),
        @('  writes flight feel only. switches, channels, failsafe: never written.', 'DarkGray')
    )
    kv_workspace = 'workspace'; kv_saved = 'saved settings'; kv_usb = 'usb'; kv_last = 'last quad'
    usb_none = 'none'; usb_found = 'drone detected'
    warn_bf = '[!!] keep the Betaflight program closed'
    note_help = 'help - commands'

    # ---- shared steps and failures
    s_find = 'acquiring drone on USB'
    f_nousb = 'no drone on USB. Re-seat the cable and try again.'
    f_noread = 'could not read the drone. Is the Betaflight program open? Close it.'
    f_unknowncmd = 'unknown command. type  help'
    kv_id = 'drone id'; kv_craft = 'calls itself'; kv_fw = 'firmware'; kv_seen = 'seen before'
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
    kv_ctl = 'controls'; ctl_count = '{0} of {1} like every {2}'; ctl_none = 'no saved settings for {0} yet'
    kv_own = 'own tweaks'; own_count = '{0}, this drone only'
    ctl_count_std = '{0} of {1} like the standard heavy set'
    preset_std = 'standard heavy'
    w_craft = "this drone calls itself '{0}'. That does not look like a {1}."
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
    m_step_quiet = 'spinning motors: all four, 1 s, idle'
    m_step_full = 'spinning motors: all four, 3 s'
    m_noread = 'no speed readout from the motors. Is the battery plugged in?'
    m_row = 'motor {0}'; m_err = 'err {0}%'
    m_dead = 'motor {0} did not turn'
    m_noisy = 'motor {0}: noisy signal'
    m_spread = 'motors differ by {0}%'
    m_nostop = 'motor stop not confirmed'
    chip_motors = 'motors'; chip_even = 'even'; chip_after = 'after run'; chip_stopped = 'stopped'

    # ---- fix
    n_fixwhat = 'fix what?   fix controls   /   fix sound'
    f_bindfirst = 'bind to a drone first:  bind "NAME"'
    r_fix = 'FIX  //  {0}'; w_ctl = 'CONTROLS'; w_snd = 'SOUND'
    s_readdrone = 'reading the drone'
    f_nopreset = 'no saved settings for {0}'
    q_anyway = 'apply {0} settings to it anyway?'
    n_nothing = 'nothing changed.'
    ok_ctl_same = 'controls already like every {0} ({1} of {1}). not changed.'
    s_ctl = 'controls for {0} ({1} values)'
    s_snd = 'sound: off'
    s_write = 'writing to drone and saving'
    s_verify = 'drone restarting, reading back'
    f_rejected = 'the drone rejected a line:'
    f_missing = 'values that did not stick: {0}'
    i_missing = '{0} : wanted {1}, the drone has {2}'
    ok_confirmed = 'confirmed: {0} of {0} values are in the drone'
    ok_snd = 'beeps are off'
    w_snd_unconf = 'could not confirm the beeps are off'
    done_ctl = 'controls'; done_snd = 'sound'
    b_fixed = '{0}  //  FIXED: {1}  //  {2}'
    b_nofix = '{0}  //  NOTHING TO FIX'
    b_problems = 'PROBLEMS  //  see above'

    # ---- yaw / pitch / roll / throttle  more / less
    r_tune = 'TUNE  //  {0} {1}'
    ax_yaw = 'YAW'; ax_pitch = 'PITCH'; ax_roll = 'ROLL'; ax_throttle = 'THROTTLE'
    w_more = 'MORE'; w_less = 'LESS'
    s_readrates = 'reading current rates'
    f_unknown = 'do not know what quad this is. first:  bind "NAME"'
    f_notactual = "this drone's rates are in '{0}' format, not ACTUAL. Axis tuning does not work on it."
    f_nothr = 'thr_expo not found in the config.'
    f_noaxis = 'rates for {0} not found in the config.'
    n_limit = '{0}: already at the limit'
    kv_thr = 'throttle, expo'; thr_sharper = 'sharper'; thr_softer = 'softer around centre'
    kv_centre = '{0}, near centre'; kv_full = '{0}, full stick'
    n_nochange = 'nothing to change.'
    q_apply = 'apply?'
    ok_remembered = 'remembered for every {0}.'
    b_done = '{0}  //  DONE  //  {1}'

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
    s_readonly = 'reading config (nothing is changed)'
    kv_rates = '{0}, centre / full stick'; kv_ratefmt = 'rates format'
    kv_preset = 'saved settings {0}'; preset_count = '{0} of {1} in the drone'
    r_radio = 'RADIO'
    s_calib = 'reading stick calibration (read only)'
    f_noradio = 'radio not found. On the radio choose "USB Storage (SD)".'
    kv_axis = 'stick axis {0}'
    f_calib = 'a stick axis is badly calibrated. On the radio: SYS, HARDWARE, Calibration.'
    ok_calib = 'all four stick axes healthy'

    # ---- help: two items = command and what it does, one item = a note, none = blank line
    r_help = 'COMMANDS'
    help = @(
        @('bind "NAME"           ', 'find the drone on USB'),
        @('status                ', 'check the drone'),
        @('motors [full]         ', 'motor run. PROPS OFF'),
        @(),
        @('fix controls          ', 'write the stick settings'),
        @('fix sound             ', 'switch the beeper off'),
        @(),
        @('yaw | pitch | roll | throttle   more | less   [slightly | much]', ''),
        @('pid stiffer | softer  ', 'roll and pitch PID, 10% a step. risky'),
        @(),
        @('radio                 ', 'radio stick calibration'),
        @('help / exit', '')
    )
    # ---- the lines tests\sim.ps1 types, so the same test runs in every language
    test_words = @{
        bind = 'bind'; bind_none = 'bind'; unknown = 'make it pretty'; status = 'status'
        fix_ctl = 'fix controls'; fix_snd = 'fix sound'
        yaw_more = 'yaw more'; pr_slightly_less = 'pitch roll slightly less'
        thr_much_more = 'throttle much more'; thr_more = 'throttle more'
        motors = 'motors'; motors_full = 'motors full'
        fix_short = 'controls'; pid = 'pid'; pid_stiffer = 'pid stiffer'; pid_softer = 'pid softer'; bare_stiffer = 'stiffer'
    }
}
