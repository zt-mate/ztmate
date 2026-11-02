const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;

fn statusMessageClient(client: *c.struct_client, message: [*:0]const u8) void {
    const limit: c.u_int = @intCast(c.options_get_number(c.global_options, "message-limit"));
    const opts = if (client.session != null) client.session.*.options else c.global_s_options;
    const delay: c_longlong = c.options_get_number(opts, "ztmate-display-time");

    c.status_prompt_clear(client);
    c.status_message_clear(client);

    _ = c.xasprintf(&client.message_string, "[ztmate] %s", message);

    const raw_msg = c.xcalloc(1, @sizeOf(c.struct_message_entry)) orelse c_mod.fatal("out of memory", .{});
    const msg: *c.struct_message_entry = @ptrCast(@alignCast(raw_msg));
    msg.msg_time = c.time(null);
    msg.msg_num = client.message_next;
    client.message_next += 1;
    msg.msg = c.xstrdup(client.message_string);

    // TAILQ_INSERT_TAIL(&client.message_log, msg, entry)
    msg.entry.tqe_next = null;
    msg.entry.tqe_prev = client.message_log.tqh_last;
    client.message_log.tqh_last.* = msg;
    client.message_log.tqh_last = &msg.entry.tqe_next;

    // Prune messages exceeding limit
    var cur = client.message_log.tqh_first;
    while (cur != null) {
        const item: *c.struct_message_entry = cur;
        const next = item.entry.tqe_next;
        if (item.msg_num + limit >= client.message_next) {
            break;
        }
        c.free(item.msg);
        if (item.entry.tqe_next != null) {
            item.entry.tqe_next.*.entry.tqe_prev = item.entry.tqe_prev;
        } else {
            client.message_log.tqh_last = item.entry.tqe_prev;
        }
        item.entry.tqe_prev.* = item.entry.tqe_next;
        c.free(item);
        cur = next;
    }

    if (delay > 0) {
        var tv: c.struct_timeval = .{
            .tv_sec = @intCast(@divTrunc(delay, 1000)),
            .tv_usec = @intCast(@mod(delay, 1000) * 1000),
        };

        if (c.event_initialized(&client.message_timer) != 0) {
            _ = c.event_del(&client.message_timer);
        }
        c.event_set(&client.message_timer, -1, 0, c_mod.status_message_callback, client);
        _ = c.event_add(&client.message_timer, &tv);
    }

    client.flags |= c.CLIENT_STATUS | c.CLIENT_FORCE_STATUS;
    c.recalculate_sizes();
}

fn statusMessageSession(message: [*:0]const u8) void {
    if (c.tmate_foreground != 0) return;

    const s = c.sessions_RB_MINMAX(&c.sessions, c_mod.RB_NEGINF);
    if (s == null) {
        c.cfg_add_cause("%s", message);
        return;
    }

    if (s.*.curw == null or s.*.curw.*.window == null) return;
    const wp = s.*.curw.*.window.*.active;
    if (wp == null) return;

    if (wp.*.mode == &c.window_copy_mode) {
        c.window_copy_add(wp, "%s", message);
    }
}

pub fn statusMessageZ(message: [*:0]const u8) void {
    c.log_emit(c.LOG_INFO, "%s", message);

    var cur = c.clients.tqh_first;
    while (cur != null) {
        const client_ptr: *c.struct_client = cur;
        if ((client_ptr.flags & c.CLIENT_READONLY) == 0) {
            statusMessageClient(client_ptr, message);
        }
        cur = client_ptr.entry.tqe_next;
    }

    statusMessageSession(message);
}

pub fn statusMessage(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    statusMessageZ(slice.ptr);
}

pub export fn __tmate_status_message(fmt: ?[*:0]const u8, ap: [*c]std.meta.Child(c.va_list)) callconv(.c) void {
    const f = fmt orelse return;
    var message: [*c]u8 = null;
    _ = c.xvasprintf(&message, f, ap);
    if (message != null) {
        statusMessageZ(@ptrCast(message));
        c.free(message);
    }
}

pub export fn tmate_status_message(fmt: ?[*:0]const u8, ...) callconv(.c) void {
    const f = fmt orelse return;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    __tmate_status_message(f, @ptrCast(&ap));
}
