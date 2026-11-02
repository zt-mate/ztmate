const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const msgpack = @import("msgpack.zig");
const encoder_mod = @import("encoder.zig");
const msg_mod = @import("msg.zig");
const ssh_client_mod = @import("ssh_client.zig");

const TMATE_DNS_RETRY_TIMEOUT: c_long = 2;
const TMATE_RECONNECT_RETRY_TIMEOUT: c_long = 2;

pub export var tmate_session: c.struct_tmate_session = std.mem.zeroes(c.struct_tmate_session);

fn onDnsRetry(_: c.evutil_socket_t, _: c_short, arg: ?*anyopaque) callconv(.c) void {
    const session: *c.struct_tmate_session = @ptrCast(@alignCast(arg orelse return));
    if (session.ev_dns_retry != null) {
        c.event_free(session.ev_dns_retry);
        session.ev_dns_retry = null;
    }
    lookupAndConnect();
}

fn dnsCb(errcode: c_int, addr: [*c]c.struct_addrinfo, ptr: ?*anyopaque) callconv(.c) void {
    const host: [*:0]const u8 = if (ptr) |p| @ptrCast(p) else "unknown";

    if (tmate_session.ev_dnsbase != null) {
        c.evdns_base_free(tmate_session.ev_dnsbase, 0);
        tmate_session.ev_dnsbase = null;
    }

    if (errcode != 0) {
        const session = &tmate_session;
        if (session.ev_dns_retry != null) return;

        var tv: c.struct_timeval = .{
            .tv_sec = TMATE_DNS_RETRY_TIMEOUT,
            .tv_usec = 0,
        };

        session.ev_dns_retry = c.event_new(session.ev_base, -1, 0, onDnsRetry, session);
        if (session.ev_dns_retry == null) {
            c_mod.fatal("out of memory", .{});
        }
        _ = c.event_add(session.ev_dns_retry, &tv);

        const err_str = c.evutil_gai_strerror(errcode);
        msg_mod.statusMessage(
            "{s} lookup failure. Retrying in {d} seconds ({s})",
            .{
                std.mem.span(host),
                TMATE_DNS_RETRY_TIMEOUT,
                if (err_str != null) std.mem.span(err_str) else "DNS error",
            },
        );
        return;
    }

    msg_mod.statusMessage("Connecting to {s}...", .{std.mem.span(host)});

    var num_clients: usize = 0;
    var ai_it = addr;
    while (ai_it != null) : (ai_it = ai_it.*.ai_next) {
        num_clients += 1;
    }

    if (num_clients > 0) {
        const raw_list = c.xmalloc(@sizeOf(*c.struct_tmate_ssh_client) * num_clients) orelse c_mod.fatal("out of memory", .{});
        const ssh_clients: [*]?*c.struct_tmate_ssh_client = @ptrCast(@alignCast(raw_list));
        defer c.free(raw_list);

        ai_it = addr;
        var idx: usize = 0;
        while (ai_it != null) : ({
            ai_it = ai_it.*.ai_next;
            idx += 1;
        }) {
            const ai: *c.struct_addrinfo = ai_it;
            var buf: [128]u8 = undefined;
            var ip: ?[*:0]const u8 = null;

            if (ai.ai_family == c.AF_INET and ai.ai_addr != null) {
                const sin: *const c.struct_sockaddr_in = @ptrCast(@alignCast(ai.ai_addr));
                ip = c.evutil_inet_ntop(c.AF_INET, &sin.sin_addr, &buf[0], buf.len);
            } else if (ai.ai_family == c.AF_INET6 and ai.ai_addr != null) {
                const sin6: *const c.struct_sockaddr_in6 = @ptrCast(@alignCast(ai.ai_addr));
                ip = c.evutil_inet_ntop(c.AF_INET6, &sin6.sin6_addr, &buf[0], buf.len);
            }

            ssh_clients[idx] = ssh_client_mod.tmate_ssh_client_alloc(&tmate_session, ip);
        }

        idx = 0;
        while (idx < num_clients) : (idx += 1) {
            if (ssh_clients[idx]) |client| {
                ssh_client_mod.connect_ssh_client(client);
            }
        }
    }

    if (addr != null) {
        c.evutil_freeaddrinfo(addr);
    }
}

pub fn lookupAndConnect() void {
    var hints: c.struct_addrinfo = std.mem.zeroes(c.struct_addrinfo);
    hints.ai_family = c.AF_UNSPEC;
    hints.ai_flags = c.EVUTIL_AI_ADDRCONFIG;
    hints.ai_socktype = c.SOCK_STREAM;
    hints.ai_protocol = c.IPPROTO_TCP;

    std.debug.assert(tmate_session.ev_dnsbase == null);
    tmate_session.ev_dnsbase = c.evdns_base_new(tmate_session.ev_base, 1);
    if (tmate_session.ev_dnsbase == null) {
        c_mod.fatal("Cannot initialize the DNS lookup service", .{});
    }

    const tmate_server_host = c.options_get_string(c.global_options, "ztmate-server-host");
    if (tmate_server_host != null) {
        c_mod.logDebug("Looking up {s}...", .{std.mem.span(tmate_server_host)});
    }
    _ = c.evdns_getaddrinfo(
        tmate_session.ev_dnsbase,
        tmate_server_host,
        null,
        &hints,
        dnsCb,
        @constCast(tmate_server_host),
    );
}

fn initSessionInternal(session: *c.struct_tmate_session, base: ?*c.struct_event_base) void {
    session.* = std.mem.zeroes(c.struct_tmate_session);
    session.ev_base = base;

    msgpack.tmate_encoder_init(&session.encoder, null, &tmate_session);

    session.min_sx = -1;
    session.min_sy = -1;

    session.clients.tqh_first = null;
    session.clients.tqh_last = &session.clients.tqh_first;
}

pub export fn tmate_session_init(base: ?*c.struct_event_base) callconv(.c) void {
    initSessionInternal(&tmate_session, base);
    encoder_mod.tmate_write_header();
}

fn sendAuthorizedKeys() void {
    const raw_path = c.options_get_string(c.global_options, "ztmate-authorized-keys");
    if (raw_path == null or c.strlen(raw_path) == 0) return;

    var path: [*c]u8 = c.xstrdup(raw_path);
    defer c.free(path);

    c_mod.logInfo("Using {s} for access control", .{std.mem.span(@as([*:0]const u8, @ptrCast(path)))});

    if (path[0] == '~' and path[1] == '/') {
        const home = c.find_home();
        if (home != null) {
            var new_path: [*c]u8 = null;
            _ = c.xasprintf(&new_path, "%s%s", home, &path[1]);
            c.free(path);
            path = new_path;
        }
    }

    const f = c.fopen(path, "r");
    if (f == null) {
        c.cfg_add_cause("%s: %s", path, c.strerror(std.c._errno().*));
        return;
    }
    defer _ = c.fclose(f);

    var len: usize = 0;
    while (true) {
        const line = c.fparseln(f, &len, null, null, 0);
        if (line == null) break;
        if (len == 0) {
            c.free(line);
            continue;
        }
        encoder_mod.tmate_set_val("authorized_keys", line);
        c.free(line);
    }

    if (c.ferror(f) != 0) {
        c.cfg_add_cause("%s: %s", path, c.strerror(std.c._errno().*));
    }
}

pub export fn tmate_session_start() callconv(.c) void {
    if (c.tmate_foreground != 0) {
        encoder_mod.tmate_set_val("foreground", "true");
        if (c.socket_path != null) {
            c_mod.logInfo("To connect to the session locally, run: ztmate -S {s} attach", .{
                std.mem.span(@as([*:0]const u8, @ptrCast(c.socket_path))),
            });
        }
    } else {
        c.cfg_add_cause("%s", "Tip: if you wish to use ztmate only for remote access, run: ztmate -F");
        c.cfg_add_cause("%s", "To see the following messages again, run in a ztmate session: ztmate show-messages");
        c.cfg_add_cause("%s", "Press <q> or <ctrl-c> to continue");
        c.cfg_add_cause("%s", "---------------------------------------------------------------------");
    }

    sendAuthorizedKeys();
    encoder_mod.tmate_write_uname();
    encoder_mod.tmate_write_ready();
    lookupAndConnect();
}

fn onReconnectRetry(_: c.evutil_socket_t, _: c_short, arg: ?*anyopaque) callconv(.c) void {
    const session: *c.struct_tmate_session = @ptrCast(@alignCast(arg orelse return));
    if (session.ev_connection_retry != null) {
        c.event_free(session.ev_connection_retry);
        session.ev_connection_retry = null;
    }

    if (session.last_server_ip != null) {
        const client = ssh_client_mod.tmate_ssh_client_alloc(session, session.last_server_ip);
        ssh_client_mod.connect_ssh_client(client);
        c.free(session.last_server_ip);
        session.last_server_ip = null;
    } else {
        lookupAndConnect();
    }
}

pub export fn tmate_reconnect_session(session_ptr: ?*c.struct_tmate_session, message: ?[*:0]const u8) callconv(.c) void {
    const session = session_ptr orelse return;
    if (session.ev_connection_retry != null) return;

    var tv: c.struct_timeval = .{
        .tv_sec = TMATE_RECONNECT_RETRY_TIMEOUT,
        .tv_usec = 0,
    };

    session.ev_connection_retry = c.event_new(session.ev_base, -1, 0, onReconnectRetry, session);
    if (session.ev_connection_retry == null) {
        c_mod.fatal("out of memory", .{});
    }
    _ = c.event_add(session.ev_connection_retry, &tv);

    if (message != null and c.tmate_foreground == 0) {
        msg_mod.statusMessage("Reconnecting... ({s})", .{std.mem.span(message.?)});
    } else {
        msg_mod.statusMessage("Reconnecting...", .{});
    }

    session.reconnected = true;
}
