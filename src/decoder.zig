const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const proto = @import("protocol.zig");
const msgpack = @import("msgpack.zig");
const msg_mod = @import("msg.zig");
const env_mod = @import("env.zig");
const encoder_mod = @import("encoder.zig");

fn handleNotify(_: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const msg = msgpack.unpack_string(uk);
    defer c.free(msg);
    if (msg != null) {
        msg_mod.statusMessageZ(@ptrCast(msg));
    }
}

fn handleLegacyPaneKey(_: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const key: c.key_code = @bitCast(msgpack.unpack_int(uk));

    const s = c.sessions_RB_MINMAX(&c.sessions, c_mod.RB_NEGINF) orelse return;
    if (s.*.curw == null) return;
    const w = s.*.curw.*.window orelse return;
    const wp = w.*.active orelse return;

    c.window_pane_key(wp, null, s, key, null);
}

fn findWindowPane(s: *c.struct_session, pane_id: c_int) ?*c.struct_window_pane {
    if (pane_id != -1) {
        return c.window_pane_find_by_id(@intCast(pane_id));
    }
    if (s.curw == null) return null;
    const w = s.curw.*.window orelse return null;
    return w.*.active;
}

fn handlePaneKey(_: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const pane_id: c_int = @truncate(msgpack.unpack_int(uk));
    const key: c.key_code = @bitCast(msgpack.unpack_int(uk));

    const s = c.sessions_RB_MINMAX(&c.sessions, c_mod.RB_NEGINF) orelse return;
    const wp = findWindowPane(s, pane_id) orelse return;

    c.window_pane_key(wp, null, s, key, null);
}

fn handleResize(session: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    session.min_sx = @truncate(msgpack.unpack_int(uk));
    session.min_sy = @truncate(msgpack.unpack_int(uk));
    c.recalculate_sizes();
}

fn flushCfgCauses(client_id: c_int) void {
    var i: c.u_int = 0;
    while (i < c_mod.cfg_ncauses) : (i += 1) {
        encoder_mod.tmate_failed_cmd(client_id, c_mod.cfg_causes[i]);
        c.free(c_mod.cfg_causes[i]);
    }
    c.free(@ptrCast(c_mod.cfg_causes));
    c_mod.cfg_causes = null;
    c_mod.cfg_ncauses = 0;
}

fn handleExecCmdStr(_: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const client_id: c_int = @truncate(msgpack.unpack_int(uk));
    const cmd_str = msgpack.unpack_string(uk);
    defer c.free(cmd_str);

    var cmdlist: ?*c.struct_cmd_list = null;
    var cause: [*c]u8 = null;

    if (c.cmd_string_parse(cmd_str, &cmdlist, null, 0, &cause) != 0) {
        encoder_mod.tmate_failed_cmd(client_id, cause);
        c.free(cause);
        return;
    }

    const cmd_q = c.cmdq_new(null);
    _ = c.cmdq_run(cmd_q, cmdlist, null);
    c.cmd_list_free(cmdlist);
    _ = c.cmdq_free(cmd_q);

    flushCfgCauses(client_id);
}

fn handleExecCmd(_: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const client_id: c_int = @truncate(msgpack.unpack_int(uk));
    const argc: c_int = uk.argc;
    const u_argc: usize = @intCast(@max(argc, 0));

    const raw_argv = c.xmalloc(@sizeOf([*c]u8) * u_argc) orelse c_mod.fatal("out of memory", .{});
    const argv: [*c][*c]u8 = @ptrCast(@alignCast(raw_argv));
    defer c.cmd_free_argv(argc, argv);

    var i: usize = 0;
    while (i < u_argc) : (i += 1) {
        argv[i] = msgpack.unpack_string(uk);
    }

    var cause: [*c]u8 = null;
    const cmd = c.cmd_parse(argc, argv, null, 0, &cause);
    if (cmd == null) {
        encoder_mod.tmate_failed_cmd(client_id, cause);
        c.free(cause);
        return;
    }

    const raw_list = c.xcalloc(1, @sizeOf(c.struct_cmd_list)) orelse c_mod.fatal("out of memory", .{});
    const cmdlist: *c.struct_cmd_list = @ptrCast(@alignCast(raw_list));
    cmdlist.references = 1;
    cmdlist.list.tqh_first = null;
    cmdlist.list.tqh_last = &cmdlist.list.tqh_first;

    // TAILQ_INSERT_TAIL(&cmdlist.list, cmd, qentry)
    cmd.*.qentry.tqe_next = null;
    cmd.*.qentry.tqe_prev = cmdlist.list.tqh_last;
    cmdlist.list.tqh_last.* = cmd;
    cmdlist.list.tqh_last = &cmd.*.qentry.tqe_next;

    const cmd_q = c.cmdq_new(null);
    _ = c.cmdq_run(cmd_q, cmdlist, null);
    c.cmd_list_free(cmdlist);
    _ = c.cmdq_free(cmd_q);

    flushCfgCauses(client_id);
}

fn maybeSaveReconnectionData(session: *c.struct_tmate_session, name: [*:0]const u8, value: [*:0]const u8) void {
    if (c.strcmp(name, "ztmate_reconnection_data") == 0) {
        c.free(session.reconnection_data);
        session.reconnection_data = c.xstrdup(value);
    }
}

fn handleSetEnv(session: *c.struct_tmate_session, uk: *c.struct_tmate_unpacker) void {
    const name = msgpack.unpack_string(uk);
    const value = msgpack.unpack_string(uk);
    defer {
        c.free(name);
        c.free(value);
    }

    if (name != null and value != null) {
        env_mod.tmate_set_env(@ptrCast(name), @ptrCast(value));
        maybeSaveReconnectionData(session, @ptrCast(name), @ptrCast(value));
    }
}

fn handleReady(session: *c.struct_tmate_session, _: *c.struct_tmate_unpacker) void {
    session.tmate_env_ready = 1;
    c.signal_waiting_clients("ztmate-ready");
}

pub export fn tmate_dispatch_slave_message(
    session_ptr: ?*c.struct_tmate_session,
    uk_ptr: ?*c.struct_tmate_unpacker,
) callconv(.c) void {
    const session = session_ptr orelse return;
    const uk = uk_ptr orelse return;

    const cmd_raw = msgpack.unpack_int(uk);
    const msg_type = std.enums.fromInt(proto.DaemonInMsgType, cmd_raw) orelse {
        c_mod.logInfo("Bad message type: {d}", .{cmd_raw});
        return;
    };

    switch (msg_type) {
        .notify => handleNotify(session, uk),
        .legacy_pane_key => handleLegacyPaneKey(session, uk),
        .resize => handleResize(session, uk),
        .exec_cmd_str => handleExecCmdStr(session, uk),
        .set_env => handleSetEnv(session, uk),
        .ready => handleReady(session, uk),
        .pane_key => handlePaneKey(session, uk),
        .exec_cmd => handleExecCmd(session, uk),
    }
}
