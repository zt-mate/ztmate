pub const TMATE_PROTOCOL_VERSION: i64 = 6;
pub const VERSION: [:0]const u8 = "2.4.0";

pub const ControlOutMsgType = enum(i64) {
    header = 0,
    daemon_out_msg = 1,
    snapshot = 2,
    client_join = 3,
    client_left = 4,
    exec = 5,
    latency = 6,
};

pub const ControlInMsgType = enum(i64) {
    daemon_fwd_msg = 0,
    request_snapshot = 1,
    pane_keys = 2,
    resize = 3,
    exec_response = 4,
    rename_session = 5,
};

pub const DaemonOutMsgType = enum(i64) {
    header = 0,
    sync_layout = 1,
    pty_data = 2,
    exec_cmd_str = 3,
    failed_cmd = 4,
    status = 5,
    sync_copy_mode = 6,
    write_copy_mode = 7,
    fin = 8,
    ready = 9,
    reconnect = 10,
    snapshot = 11,
    exec_cmd = 12,
    uname = 13,
};

pub const DaemonInMsgType = enum(i64) {
    notify = 0,
    legacy_pane_key = 1,
    resize = 2,
    exec_cmd_str = 3,
    set_env = 4,
    ready = 5,
    pane_key = 6,
    exec_cmd = 7,
};
