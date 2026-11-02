const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const proto = @import("protocol.zig");
const msgpack = @import("msgpack.zig");
const session_mod = @import("session.zig");

const TMATE_MAX_PTY_SIZE: usize = 16 * 1024;
const SAVED_TMUX_CMD_INITIAL_SIZE: c_uint = 256;
const RECONNECTION_MAX_HISTORY_LINE: c_uint = 300;

extern const cmd_bind_key_entry: c.struct_cmd_entry;
extern const cmd_unbind_key_entry: c.struct_cmd_entry;
extern const cmd_set_option_entry: c.struct_cmd_entry;
extern const cmd_set_window_option_entry: c.struct_cmd_entry;

inline fn pk() *c.msgpack_packer {
    return &session_mod.tmate_session.encoder.pk;
}

inline fn packArray(n: usize) void {
    _ = msgpack.msgpack_pack_array(pk(), n);
}

inline fn packInt(v: anytype) void {
    _ = msgpack.msgpack_pack_int64(pk(), @intCast(v));
}

inline fn packUint(v: anytype) void {
    _ = msgpack.msgpack_pack_uint64(pk(), @intCast(v));
}

inline fn packString(s: ?[*:0]const u8) void {
    msgpack.msgpack_pack_string(pk(), s);
}

inline fn packStrHeader(len: usize) void {
    _ = msgpack.msgpack_pack_str(pk(), len);
}

inline fn packStrBody(ptr: ?*const anyopaque, len: usize) void {
    _ = msgpack.msgpack_pack_str_body(pk(), ptr, len);
}

inline fn packNil() void {
    _ = msgpack.msgpack_pack_nil(pk());
}

pub export fn tmate_write_header() callconv(.c) void {
    packArray(3);
    packInt(@intFromEnum(proto.DaemonOutMsgType.header));
    packInt(proto.TMATE_PROTOCOL_VERSION);
    packString(proto.VERSION.ptr);
}

pub export fn tmate_write_uname() callconv(.c) void {
    var name: c.struct_utsname = undefined;
    if (c.uname(&name) < 0) {
        c_mod.logDebug("uname() failed", .{});
        return;
    }

    packArray(6);
    packInt(@intFromEnum(proto.DaemonOutMsgType.uname));
    packString(@ptrCast(&name.sysname[0]));
    packString(@ptrCast(&name.nodename[0]));
    packString(@ptrCast(&name.release[0]));
    packString(@ptrCast(&name.version[0]));
    packString(@ptrCast(&name.machine[0]));
}

pub export fn tmate_write_ready() callconv(.c) void {
    packArray(1);
    packInt(@intFromEnum(proto.DaemonOutMsgType.ready));
}

pub export fn tmate_sync_layout() callconv(.c) void {
    const s = c.sessions_RB_MINMAX(&c.sessions, c_mod.RB_NEGINF) orelse return;

    var num_windows: usize = 0;
    var wl_it = c.winlinks_RB_MINMAX(&s.*.windows, c_mod.RB_NEGINF);
    while (wl_it != null) : (wl_it = c.winlinks_RB_NEXT(wl_it)) {
        if (wl_it.*.window != null) {
            num_windows += 1;
        }
    }

    if (num_windows == 0) return;

    var active_window_idx: c_int = -1;

    packArray(5);
    packInt(@intFromEnum(proto.DaemonOutMsgType.sync_layout));
    packInt(s.*.sx);
    packInt(s.*.sy);

    packArray(num_windows);
    wl_it = c.winlinks_RB_MINMAX(&s.*.windows, c_mod.RB_NEGINF);
    while (wl_it != null) : (wl_it = c.winlinks_RB_NEXT(wl_it)) {
        const wl: *c.struct_winlink = wl_it;
        const w: *c.struct_window = wl.window orelse continue;

        w.tmate_last_sync_active_pane = null;
        var active_pane_id: c_int = -1;

        if (active_window_idx == -1) {
            active_window_idx = wl.idx;
        }

        packArray(4);
        packInt(wl.idx);
        packString(w.name);

        var num_panes: usize = 0;
        var wp_it = w.panes.tqh_first;
        while (wp_it != null) : (wp_it = wp_it.*.entry.tqe_next) {
            num_panes += 1;
        }

        packArray(num_panes);
        wp_it = w.panes.tqh_first;
        while (wp_it != null) : (wp_it = wp_it.*.entry.tqe_next) {
            const wp: *c.struct_window_pane = wp_it;
            packArray(5);
            packInt(wp.id);
            packInt(wp.sx);
            packInt(wp.sy);
            packInt(wp.xoff);
            packInt(wp.yoff);

            if (wp == w.active) {
                w.tmate_last_sync_active_pane = wp;
                active_pane_id = @intCast(wp.id);
            }
        }
        packInt(active_pane_id);
    }

    if (s.*.curw != null) {
        active_window_idx = s.*.curw.*.idx;
    }

    packInt(active_window_idx);
}

pub export fn tmate_pty_data(wp_ptr: ?*c.struct_window_pane, buf_ptr: ?[*]const u8, len_in: usize) callconv(.c) void {
    const wp = wp_ptr orelse return;
    var buf = buf_ptr orelse return;
    var len = len_in;

    while (len > 0) {
        const to_write = @min(len, TMATE_MAX_PTY_SIZE);

        packArray(3);
        packInt(@intFromEnum(proto.DaemonOutMsgType.pty_data));
        packInt(wp.id);
        packStrHeader(to_write);
        packStrBody(buf, to_write);

        buf += to_write;
        len -= to_write;
    }
}

pub export fn tmate_should_replicate_cmd(cmd: ?*const c.struct_cmd_entry) callconv(.c) c_int {
    const entry = cmd orelse return 0;
    if (entry == &cmd_bind_key_entry or
        entry == &cmd_unbind_key_entry or
        entry == &cmd_set_option_entry or
        entry == &cmd_set_window_option_entry)
    {
        return 1;
    }
    return 0;
}

fn rawExecCmdArgs(argc: c_int, argv: [*c][*c]const u8) void {
    const count: usize = @intCast(argc);
    packArray(count + 1);
    packInt(@intFromEnum(proto.DaemonOutMsgType.exec_cmd));

    var i: usize = 0;
    while (i < count) : (i += 1) {
        packString(argv[i]);
    }
}

fn appendSavedCmd(session: *c.struct_tmate_session, argc: c_int, argv: [*c][*c]const u8) void {
    const sc = &session.saved_tmux_cmds;
    const elem_size = @sizeOf(@TypeOf(sc.cmds[0]));

    if (sc.cmds == null) {
        sc.capacity = SAVED_TMUX_CMD_INITIAL_SIZE;
        const raw = c.xmalloc(elem_size * sc.capacity) orelse c_mod.fatal("out of memory", .{});
        sc.cmds = @ptrCast(@alignCast(raw));
        sc.tail = 0;
    }

    if (sc.tail == sc.capacity) {
        sc.capacity *= 2;
        const raw = c.xrealloc(sc.cmds, elem_size * sc.capacity) orelse c_mod.fatal("out of memory", .{});
        sc.cmds = @ptrCast(@alignCast(raw));
    }

    sc.cmds[sc.tail].argc = argc;
    sc.cmds[sc.tail].argv = c.cmd_copy_argv(argc, @ptrCast(@constCast(argv)));
    sc.tail += 1;
}

fn replaySavedCmd(session: *c.struct_tmate_session) void {
    const sc = &session.saved_tmux_cmds;
    var i: c_uint = 0;
    while (i < sc.tail) : (i += 1) {
        rawExecCmdArgs(sc.cmds[i].argc, @ptrCast(sc.cmds[i].argv));
    }
}

fn extractCmd(cmd: *c.struct_cmd, out_argc: *c_int, out_argv: *[*c][*c]u8) void {
    const args: *c.struct_args = cmd.args;
    var argc: c_int = 1; // cmd name

    var entry_it = c_mod.args_tree_RB_MINMAX(&args.tree, c_mod.RB_NEGINF);
    while (entry_it) |entry| : (entry_it = c_mod.args_tree_RB_NEXT(entry)) {
        argc += 1;
        if (entry.value != null) {
            argc += 1;
        }
    }
    argc += args.argc;

    const raw_argv = c.xmalloc(@sizeOf([*c]u8) * @as(usize, @intCast(argc))) orelse c_mod.fatal("out of memory", .{});
    const argv: [*c][*c]u8 = @ptrCast(@alignCast(raw_argv));

    var next: usize = 0;
    argv[next] = c.xstrdup(cmd.entry.*.name);
    next += 1;

    entry_it = c_mod.args_tree_RB_MINMAX(&args.tree, c_mod.RB_NEGINF);
    while (entry_it) |entry| : (entry_it = c_mod.args_tree_RB_NEXT(entry)) {
        _ = c.xasprintf(&argv[next], "-%c", @as(c_int, entry.flag));
        next += 1;
        if (entry.value != null) {
            argv[next] = c.xstrdup(entry.value);
            next += 1;
        }
    }

    var i: c_int = 0;
    while (i < args.argc) : (i += 1) {
        argv[next] = c.xstrdup(args.argv[@intCast(i)]);
        next += 1;
    }

    out_argc.* = argc;
    out_argv.* = argv;
}

pub export fn tmate_exec_cmd_args(argc: c_int, argv: [*c][*c]const u8) callconv(.c) void {
    rawExecCmdArgs(argc, argv);
    appendSavedCmd(&session_mod.tmate_session, argc, argv);
}

pub export fn tmate_set_val(name: ?[*:0]const u8, value: ?[*:0]const u8) callconv(.c) void {
    const n = name orelse return;
    const v = value orelse return;
    var buf: [*c]u8 = null;
    _ = c.xasprintf(&buf, "%s=%s", n, v);
    defer c.free(buf);

    var args = [_][*c]const u8{
        "set-option",
        "ztmate-set",
        buf,
    };
    tmate_exec_cmd_args(3, &args[0]);
}

pub export fn tmate_exec_cmd(cmd_ptr: ?*c.struct_cmd) callconv(.c) void {
    const cmd = cmd_ptr orelse return;
    var argc: c_int = 0;
    var argv: [*c][*c]u8 = null;

    extractCmd(cmd, &argc, &argv);
    tmate_exec_cmd_args(argc, @ptrCast(argv));
    c.cmd_free_argv(argc, argv);
}

pub export fn tmate_failed_cmd(client_id: c_int, cause: ?[*:0]const u8) callconv(.c) void {
    packArray(3);
    packInt(@intFromEnum(proto.DaemonOutMsgType.failed_cmd));
    packInt(client_id);
    packString(cause);
}

var old_left: [*c]u8 = null;
var old_right: [*c]u8 = null;

pub export fn tmate_status(left_ptr: ?[*:0]const u8, right_ptr: ?[*:0]const u8) callconv(.c) void {
    const left = left_ptr orelse return;
    const right = right_ptr orelse return;

    if (old_left != null and c.strcmp(old_left, left) == 0 and
        old_right != null and c.strcmp(old_right, right) == 0)
    {
        return;
    }

    packArray(3);
    packInt(@intFromEnum(proto.DaemonOutMsgType.status));
    packString(left);
    packString(right);

    c.free(old_left);
    c.free(old_right);
    old_left = c.xstrdup(left);
    old_right = c.xstrdup(right);
}

pub export fn tmate_sync_copy_mode(wp_ptr: ?*c.struct_window_pane) callconv(.c) void {
    const wp = wp_ptr orelse return;
    const data_opt: ?*c.struct_window_copy_mode_data = @ptrCast(@alignCast(wp.modedata));

    packArray(3);
    packInt(@intFromEnum(proto.DaemonOutMsgType.sync_copy_mode));
    packInt(wp.id);

    if (wp.mode != &c.window_copy_mode or data_opt == null or data_opt.?.inputtype == c.WINDOW_COPY_PASSWORD) {
        packArray(0);
        return;
    }

    const data = data_opt.?;
    packArray(6);
    packInt(@intFromBool(data.backing == &wp.base));
    packInt(data.oy);
    packInt(data.cx);
    packInt(data.cy);

    if (data.screen.sel.flag != 0 and data.backing != null and data.backing.*.grid != null) {
        const grid = data.backing.*.grid;
        const sel_y: i64 = -@as(i64, @intCast(data.sely)) +
            @as(i64, @intCast(grid.*.hsize)) +
            @as(i64, @intCast(grid.*.sy)) - 1;
        packArray(3);
        packInt(data.selx);
        packInt(@as(c_int, @truncate(sel_y)));
        packInt(data.rectflag);
    } else {
        packArray(0);
    }

    if (data.inputprompt != null) {
        packArray(3);
        packInt(data.inputtype);
        packString(data.inputprompt);
        packString(data.inputstr);
    } else {
        packArray(0);
    }
}

pub export fn tmate_write_copy_mode(wp_ptr: ?*c.struct_window_pane, str: ?[*:0]const u8) callconv(.c) void {
    const wp = wp_ptr orelse return;
    packArray(3);
    packInt(@intFromEnum(proto.DaemonOutMsgType.write_copy_mode));
    packInt(wp.id);
    packString(str);
}

pub export fn tmate_write_fin() callconv(.c) void {
    packArray(1);
    packInt(@intFromEnum(proto.DaemonOutMsgType.fin));
}

fn doSnapshotGrid(grid: *c.struct_grid, max_history_lines: c_uint) void {
    const max_lines: c_uint = max_history_lines + grid.sy;
    const total_lines: c_uint = grid.hsize + grid.sy;

    var line_i: c_uint = if (total_lines > max_lines) total_lines - max_lines else 0;

    packArray(total_lines - line_i);
    while (line_i < total_lines) : (line_i += 1) {
        const line = &grid.linedata[line_i];
        var gc: c.struct_grid_cell = undefined;

        packArray(2);
        var str_len: usize = 0;
        var i: c_uint = 0;
        while (i < line.cellsize) : (i += 1) {
            c.grid_get_cell(grid, i, line_i, &gc);
            str_len += gc.data.size;
        }

        packStrHeader(str_len);
        i = 0;
        while (i < line.cellsize) : (i += 1) {
            c.grid_get_cell(grid, i, line_i, &gc);
            packStrBody(&gc.data.data[0], gc.data.size);
        }

        packArray(line.cellsize);
        i = 0;
        while (i < line.cellsize) : (i += 1) {
            c.grid_get_cell(grid, i, line_i, &gc);
            const packed_attr: u32 = (@as(u32, gc.flags) << 24) |
                (@as(u32, gc.attr) << 16) |
                (@as(u32, gc.unnamed_1.bg) << 8) |
                @as(u32, gc.unnamed_0.fg);
            packUint(packed_attr);
        }
    }
}

fn doSnapshotPane(wp: *c.struct_window_pane, max_history_lines: c_uint) void {
    const screen = &wp.base;

    packArray(4);
    packInt(wp.id);
    packUint(@as(c_uint, @bitCast(screen.mode)));

    packArray(3);
    packInt(screen.cx);
    packInt(screen.cy);
    doSnapshotGrid(screen.grid, max_history_lines);

    if (wp.saved_grid != null) {
        packArray(3);
        packInt(wp.saved_cx);
        packInt(wp.saved_cy);
        doSnapshotGrid(wp.saved_grid, max_history_lines);
    } else {
        packNil();
    }
}

fn sendSessionSnapshot(max_history_lines: c_uint) void {
    packArray(2);
    packInt(@intFromEnum(proto.DaemonOutMsgType.snapshot));

    const s = c.sessions_RB_MINMAX(&c.sessions, c_mod.RB_NEGINF) orelse {
        c_mod.fatal("no session?", .{});
    };

    var num_panes: usize = 0;
    var wl_it = c.winlinks_RB_MINMAX(&s.*.windows, c_mod.RB_NEGINF);
    while (wl_it != null) : (wl_it = c.winlinks_RB_NEXT(wl_it)) {
        const w = wl_it.*.window orelse continue;
        var pane_it = w.*.panes.tqh_first;
        while (pane_it != null) : (pane_it = pane_it.*.entry.tqe_next) {
            num_panes += 1;
        }
    }

    packArray(num_panes);
    wl_it = c.winlinks_RB_MINMAX(&s.*.windows, c_mod.RB_NEGINF);
    while (wl_it != null) : (wl_it = c.winlinks_RB_NEXT(wl_it)) {
        const w = wl_it.*.window orelse continue;
        var pane_it = w.*.panes.tqh_first;
        while (pane_it != null) : (pane_it = pane_it.*.entry.tqe_next) {
            doSnapshotPane(pane_it, max_history_lines);
        }
    }
}

fn sendReconnectionData(session: *c.struct_tmate_session) void {
    if (session.reconnection_data == null) return;

    packArray(2);
    packInt(@intFromEnum(proto.DaemonOutMsgType.reconnect));
    packString(session.reconnection_data);
}

pub export fn tmate_send_reconnection_state(session_ptr: ?*c.struct_tmate_session) callconv(.c) void {
    const session = session_ptr orelse return;

    msgpack.tmate_encoder_destroy(&session.encoder);
    msgpack.tmate_encoder_init(&session.encoder, null, session);

    tmate_write_header();
    sendReconnectionData(session);
    replaySavedCmd(session);
    tmate_write_uname();
    tmate_write_ready();

    tmate_sync_layout();
    sendSessionSnapshot(RECONNECTION_MAX_HISTORY_LINE);
}
