const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const msgpack = @import("msgpack.zig");
const decoder_mod = @import("decoder.zig");
const encoder_mod = @import("encoder.zig");
const session_mod = @import("session.zig");
const msg_mod = @import("msg.zig");

const KEEPALIVE_IDLE: c_int = 30;
const KEEPALIVE_CNT: c_int = 4;
const KEEPALIVE_INTVL: c_int = 11;
const WRITE_TIMEOUT: c_int = 80;

fn readChannel(client: *c.struct_tmate_ssh_client) void {
    const decoder = &client.tmate_session.*.decoder;
    var buf: [*c]u8 = null;
    var len: usize = 0;

    while (true) {
        msgpack.tmate_decoder_get_buffer(decoder, &buf, &len);
        const n = c.ssh_channel_read_nonblocking(client.channel, buf, @intCast(len), 0);
        if (n < 0) {
            const err_ptr = c.ssh_get_error(client.session);
            killSshClientFmt(client, "Error reading from channel: {s}", .{
                if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
            });
            break;
        }
        if (n == 0) break;

        msgpack.tmate_decoder_commit(decoder, @intCast(n));
    }
}

fn onDecoderRead(userdata: ?*anyopaque, uk: ?*c.struct_tmate_unpacker) callconv(.c) void {
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(userdata orelse return));
    decoder_mod.tmate_dispatch_slave_message(client.tmate_session, uk);
}

fn onEncoderWrite(userdata: ?*anyopaque, buffer: ?*c.struct_evbuffer) callconv(.c) void {
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(userdata orelse return));
    const evb = buffer orelse return;
    if (client.channel == null) return;

    while (true) {
        const len = c.evbuffer_get_length(evb);
        if (len == 0) break;

        const buf = c.evbuffer_pullup(evb, -1);
        const written = c.ssh_channel_write(client.channel, buf, @intCast(len));
        if (written < 0) {
            const err_ptr = c.ssh_get_error(client.session);
            killSshClientFmt(client, "Error writing to channel: {s}", .{
                if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
            });
            break;
        }

        _ = c.evbuffer_drain(evb, @intCast(written));
    }
}

fn onSshAuthServerComplete(connected_client: *c.struct_tmate_ssh_client) void {
    const session = connected_client.tmate_session;
    var cur = session.*.clients.tqh_first;
    while (cur != null) {
        const client: *c.struct_tmate_ssh_client = cur;
        const next = client.node.tqe_next;
        if (client != connected_client) {
            killSshClient(client, null);
        }
        cur = next;
    }
}

fn getIdentity() [*c]u8 {
    const identity = c.options_get_string(c.global_options, "ztmate-identity");
    if (identity == null or c.strlen(identity) == 0) {
        return null;
    }

    if (c.strchr(identity, '/') != null) {
        return c.xstrdup(identity);
    }

    var out: [*c]u8 = null;
    _ = c.xasprintf(&out, "%%d/%s", identity);
    return out;
}

fn passphraseCallback(
    _: [*c]const u8,
    buf: [*c]u8,
    len: usize,
    _: c_int,
    _: c_int,
    userdata: ?*anyopaque,
) callconv(.c) c_int {
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(userdata orelse return -1));
    client.tmate_session.*.need_passphrase = 1;

    if (client.tmate_session.*.passphrase != null) {
        _ = c.strlcpy(buf, client.tmate_session.*.passphrase, len);
    } else if (len > 0) {
        buf[0] = 0;
    }
    return 0;
}

fn onPassphraseRead(passphrase: [*c]const u8, priv: ?*anyopaque) callconv(.c) void {
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(priv orelse return));
    client.tmate_session.*.passphrase = c.xstrdup(passphrase);
    onSshClientEvent(client);
}

fn requestPassphrase(client: *c.struct_tmate_ssh_client) void {
    const wp = c.window_pane_tree_RB_MINMAX(&c.all_window_panes, c_mod.RB_NEGINF) orelse return;

    if (wp.*.mode != null) {
        const existing_data: *c.struct_window_copy_mode_data = @ptrCast(@alignCast(wp.*.modedata));
        if (existing_data.inputtype == c.WINDOW_COPY_PASSWORD) {
            return;
        }
        c.window_pane_reset_mode(wp);
    }

    _ = c.window_pane_set_mode(wp, &c.window_copy_mode);
    c.window_copy_init_from_pane(wp, 0);
    const data: *c.struct_window_copy_mode_data = @ptrCast(@alignCast(wp.*.modedata));

    data.inputtype = c.WINDOW_COPY_PASSWORD;
    data.inputprompt = "SSH key passphrase";

    c.mode_key_init(&data.mdata, &c.mode_key_tree_vi_edit);

    _ = c.window_copy_update_selection(wp, 1);
    c.window_copy_redraw_screen(wp);

    data.password_cb = onPassphraseRead;
    data.password_cb_private = client;
}

fn setSockOptInt(fd: c_int, level: c_int, optname: c_int, val: c_int, comptime label: []const u8) void {
    var flag: c_int = val;
    if (c.setsockopt(fd, level, optname, &flag, @sizeOf(c_int)) < 0) {
        const err = std.c._errno().*;
        if (err != c.EINVAL) {
            const err_str = c.strerror(err);
            c_mod.logInfo("setsockopt({s}, {d}) failed {s}", .{
                label,
                val,
                if (err_str != null) std.mem.span(err_str) else "error",
            });
        }
    }
}

fn tuneSocketOpts(fd: c_int) void {
    setSockOptInt(fd, c.IPPROTO_IP, c.IP_TOS, 0x10, "IPPROTO_IP, IP_TOS");
    setSockOptInt(fd, c.IPPROTO_TCP, c.TCP_NODELAY, 1, "IPPROTO_TCP, TCP_NODELAY");
    setSockOptInt(fd, c.SOL_SOCKET, c.SO_KEEPALIVE, 1, "SOL_SOCKET, SO_KEEPALIVE");
    if (@hasDecl(c, "TCP_KEEPIDLE")) {
        setSockOptInt(fd, c.IPPROTO_TCP, c.TCP_KEEPIDLE, KEEPALIVE_IDLE, "IPPROTO_TCP, TCP_KEEPIDLE");
    }
    if (@hasDecl(c, "TCP_KEEPCNT")) {
        setSockOptInt(fd, c.IPPROTO_TCP, c.TCP_KEEPCNT, KEEPALIVE_CNT, "IPPROTO_TCP, TCP_KEEPCNT");
    }
    if (@hasDecl(c, "TCP_KEEPINTVL")) {
        setSockOptInt(fd, c.IPPROTO_TCP, c.TCP_KEEPINTVL, KEEPALIVE_INTVL, "IPPROTO_TCP, TCP_KEEPINTVL");
    }
    if (@hasDecl(c, "TCP_USER_TIMEOUT")) {
        setSockOptInt(fd, c.IPPROTO_TCP, c.TCP_USER_TIMEOUT, 1000 * WRITE_TIMEOUT, "IPPROTO_TCP, TCP_USER_TIMEOUT");
    }
}

fn initConnFd(client: *c.struct_tmate_ssh_client) void {
    if (client.ev_ssh != null) return;

    const fd = c.ssh_get_fd(client.session);
    if (fd < 0) return;

    tuneSocketOpts(fd);

    client.ev_ssh = c.event_new(
        client.tmate_session.*.ev_base,
        fd,
        c.EV_READ | c.EV_PERSIST,
        onSshClientEventCb,
        client,
    );
    if (client.ev_ssh == null) {
        c_mod.fatal("out of memory", .{});
    }
    _ = c.event_add(client.ev_ssh, null);
}

fn onSshClientEvent(client: *c.struct_tmate_ssh_client) void {
    while (true) {
        switch (client.state) {
            c.SSH_INIT => {
                const session = c.ssh_new();
                client.session = session;
                if (session == null) {
                    c_mod.fatal("cannot ssh_new()", .{});
                }

                _ = c.ssh_set_callbacks(session, &client.ssh_callbacks);

                var verbosity: c_int = c.SSH_LOG_NOLOG + c.log_get_level();
                var port: c_int = @intCast(c.options_get_number(c.global_options, "ztmate-server-port"));

                c.ssh_set_blocking(session, 0);
                _ = c.ssh_options_set(session, c.SSH_OPTIONS_HOST, client.server_ip);
                _ = c.ssh_options_set(session, c.SSH_OPTIONS_LOG_VERBOSITY, &verbosity);
                _ = c.ssh_options_set(session, c.SSH_OPTIONS_PORT, &port);
                _ = c.ssh_options_set(session, c.SSH_OPTIONS_USER, "ztmate");
                _ = c.ssh_options_set(session, c.SSH_OPTIONS_COMPRESSION, "yes");

                const identity = getIdentity();
                if (identity != null) {
                    _ = c.ssh_options_set(session, c.SSH_OPTIONS_IDENTITY, identity);
                    _ = c.unsetenv("SSH_AUTH_SOCK");
                    c.free(identity);
                }

                client.state = c.SSH_CONNECT;
            },
            c.SSH_CONNECT => {
                switch (c.ssh_connect(client.session)) {
                    c.SSH_AGAIN => {
                        initConnFd(client);
                        return;
                    },
                    c.SSH_ERROR => {
                        const err_ptr = c.ssh_get_error(client.session);
                        killSshClientFmt(client, "Error connecting: {s}", .{
                            if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
                        });
                        return;
                    },
                    c.SSH_OK => {
                        initConnFd(client);
                        if (client.server_ip != null) {
                            c_mod.logDebug("Establishing connection to {s}", .{
                                std.mem.span(@as([*:0]const u8, @ptrCast(client.server_ip))),
                            });
                        }
                        client.state = c.SSH_AUTH_SERVER;
                    },
                    else => return,
                }
            },
            c.SSH_AUTH_SERVER => {
                var pubkey: c.ssh_key = null;
                if (c.ssh_get_server_publickey(client.session, &pubkey) < 0) {
                    c_mod.fatal("ssh_get_server_publickey", .{});
                }

                var hash: [*c]u8 = null;
                var hash_len: usize = 0;
                if (c.ssh_get_publickey_hash(pubkey, c.SSH_PUBLICKEY_HASH_SHA256, &hash, &hash_len) < 0) {
                    c.ssh_key_free(pubkey);
                    killSshClientFmt(client, "Failed to get server fingerprint", .{});
                    return;
                }

                const hash_str = c.ssh_get_fingerprint_hash(c.SSH_PUBLICKEY_HASH_SHA256, hash, hash_len);
                if (hash_str == null) {
                    c_mod.fatal("malloc failed", .{});
                }

                const key_type = c.ssh_key_type(pubkey);
                const server_hash_str: [*:0]const u8 = switch (key_type) {
                    c.SSH_KEYTYPE_RSA => c.options_get_string(c.global_options, "ztmate-server-rsa-fingerprint") orelse "",
                    c.SSH_KEYTYPE_ECDSA,
                    c.SSH_KEYTYPE_ECDSA_P256,
                    c.SSH_KEYTYPE_ECDSA_P384,
                    c.SSH_KEYTYPE_ECDSA_P521,
                    => c.options_get_string(c.global_options, "ztmate-server-ecdsa-fingerprint") orelse "",
                    c.SSH_KEYTYPE_ED25519 => c.options_get_string(c.global_options, "ztmate-server-ed25519-fingerprint") orelse "",
                    else => "",
                };

                const match = (c.strcmp(hash_str, server_hash_str) == 0);
                if (!match) {
                    killSshClientFmt(
                        client,
                        "Server fingerprint not recognized: `{s}', expected `{s}'",
                        .{
                            std.mem.span(server_hash_str),
                            std.mem.span(@as([*:0]const u8, @ptrCast(hash_str))),
                        },
                    );
                }

                c.ssh_key_free(pubkey);
                c.ssh_clean_pubkey_hash(&hash);
                c.free(hash_str);

                if (!match) return;

                if (client.server_ip != null) {
                    c_mod.logDebug("Connected to {s}", .{
                        std.mem.span(@as([*:0]const u8, @ptrCast(client.server_ip))),
                    });
                }
                onSshAuthServerComplete(client);
                client.state = c.SSH_AUTH_CLIENT_NONE;
            },
            c.SSH_AUTH_CLIENT_NONE => {
                switch (c.ssh_userauth_none(client.session, null)) {
                    c.SSH_AUTH_AGAIN => return,
                    c.SSH_AUTH_ERROR => {
                        const err_ptr = c.ssh_get_error(client.session);
                        killSshClientFmt(client, "Auth error: {s}", .{
                            if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
                        });
                        return;
                    },
                    c.SSH_AUTH_SUCCESS => {
                        c_mod.logDebug("Auth successful via none method", .{});
                        client.state = c.SSH_NEW_CHANNEL;
                    },
                    c.SSH_AUTH_PARTIAL, c.SSH_AUTH_DENIED => {
                        client.state = c.SSH_AUTH_CLIENT_PUBKEY;
                    },
                    else => return,
                }
            },
            c.SSH_AUTH_CLIENT_PUBKEY => {
                client.tried_passphrase = client.tmate_session.*.passphrase;
                switch (c.ssh_userauth_publickey_auto(client.session, null, client.tried_passphrase)) {
                    c.SSH_AUTH_AGAIN => return,
                    c.SSH_AUTH_PARTIAL, c.SSH_AUTH_INFO, c.SSH_AUTH_DENIED => {
                        if (client.tmate_session.*.need_passphrase != 0) {
                            requestPassphrase(client);
                        } else {
                            killSshClientFmt(client, "SSH keys not found. Run 'ssh-keygen' to create keys.", .{});
                            return;
                        }

                        if (client.tried_passphrase != null) {
                            msg_mod.statusMessage(
                                "Can't load SSH key. Try typing passphrase again in case of typo. ctrl-c to abort.",
                                .{},
                            );
                        }
                        return;
                    },
                    c.SSH_AUTH_ERROR => {
                        const err_ptr = c.ssh_get_error(client.session);
                        killSshClientFmt(client, "Auth error: {s}", .{
                            if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
                        });
                        return;
                    },
                    c.SSH_AUTH_SUCCESS => {
                        c_mod.logDebug("Auth successful with pubkey", .{});
                        client.state = c.SSH_NEW_CHANNEL;
                    },
                    else => return,
                }
            },
            c.SSH_NEW_CHANNEL => {
                const channel = c.ssh_channel_new(client.session);
                client.channel = channel;
                if (channel == null) {
                    c_mod.fatal("cannot ssh_channel_new()", .{});
                }
                client.state = c.SSH_OPEN_CHANNEL;
            },
            c.SSH_OPEN_CHANNEL => {
                switch (c.ssh_channel_open_session(client.channel)) {
                    c.SSH_AGAIN => return,
                    c.SSH_ERROR => {
                        const err_ptr = c.ssh_get_error(client.session);
                        killSshClientFmt(client, "Error opening channel: {s}", .{
                            if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
                        });
                        return;
                    },
                    c.SSH_OK => {
                        c_mod.logDebug("Session opened, initializing ztmate", .{});
                        client.state = c.SSH_BOOTSTRAP;
                    },
                    else => return,
                }
            },
            c.SSH_BOOTSTRAP => {
                switch (c.ssh_channel_request_subsystem(client.channel, "ztmate")) {
                    c.SSH_AGAIN => return,
                    c.SSH_ERROR => {
                        const err_ptr = c.ssh_get_error(client.session);
                        killSshClientFmt(client, "Error initializing ztmate: {s}", .{
                            if (err_ptr != null) std.mem.span(err_ptr) else "unknown",
                        });
                        return;
                    },
                    c.SSH_OK => {
                        c_mod.logDebug("Ready", .{});
                        c.ssh_set_blocking(client.session, 1);
                        client.state = c.SSH_READY;

                        if (client.tmate_session.*.reconnected) {
                            encoder_mod.tmate_send_reconnection_state(client.tmate_session);
                        }

                        msgpack.tmate_encoder_set_ready_callback(
                            &client.tmate_session.*.encoder,
                            onEncoderWrite,
                            client,
                        );
                        msgpack.tmate_decoder_init(
                            &client.tmate_session.*.decoder,
                            onDecoderRead,
                            client,
                        );

                        c.free(client.tmate_session.*.last_server_ip);
                        client.tmate_session.*.last_server_ip = c.xstrdup(client.server_ip);
                    },
                    else => return,
                }
            },
            c.SSH_READY => {
                readChannel(client);
                return;
            },
            else => return,
        }
    }
}

fn onSshClientEventCb(_: c.evutil_socket_t, _: c_short, arg: ?*anyopaque) callconv(.c) void {
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(arg orelse return));
    onSshClientEvent(client);
}

fn killSshClientFmt(client: *c.struct_tmate_ssh_client, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, fmt, args) catch "SSH error";
    killSshClient(client, slice.ptr);
}

fn killSshClient(client: *c.struct_tmate_ssh_client, message_opt: ?[*:0]const u8) void {
    const session = client.tmate_session;

    // TAILQ_REMOVE(&session.clients, client, node)
    if (client.node.tqe_next != null) {
        client.node.tqe_next.*.node.tqe_prev = client.node.tqe_prev;
    } else {
        session.*.clients.tqh_last = client.node.tqe_prev;
    }
    client.node.tqe_prev.* = client.node.tqe_next;

    const last_client = (session.*.clients.tqh_first == null);

    if (message_opt != null and last_client) {
        msg_mod.statusMessageZ(message_opt.?);
    }

    if (client.server_ip != null) {
        c_mod.logDebug("SSH client killed ({s})", .{
            std.mem.span(@as([*:0]const u8, @ptrCast(client.server_ip))),
        });
    }

    if (client.ev_ssh != null) {
        _ = c.event_del(client.ev_ssh);
        c.event_free(client.ev_ssh);
        client.ev_ssh = null;
    }

    if (client.state == c.SSH_READY) {
        msgpack.tmate_encoder_set_ready_callback(&session.*.encoder, null, null);
        msgpack.tmate_decoder_destroy(&session.*.decoder);

        session.*.min_sx = -1;
        session.*.min_sy = -1;
        c.recalculate_sizes();
    }

    if (client.session != null) {
        c.ssh_free(client.session);
        client.session = null;
        client.channel = null;
    }

    if (last_client) {
        session_mod.tmate_reconnect_session(session, message_opt);
    }

    c.free(client.server_ip);
    c.free(client);
}

pub export fn connect_ssh_client(client_ptr: ?*c.struct_tmate_ssh_client) callconv(.c) void {
    const client = client_ptr orelse return;
    std.debug.assert(client.session == null);
    client.state = c.SSH_INIT;
    onSshClientEvent(client);
}

fn sshLogFunction(priority: c_int, function: [*c]const u8, buffer: [*c]const u8, _: ?*anyopaque) callconv(.c) void {
    c_mod.logDebug("[{d}] [{s}] {s}", .{
        priority,
        if (function != null) std.mem.span(function) else "",
        if (buffer != null) std.mem.span(buffer) else "",
    });
}

pub export fn tmate_ssh_client_alloc(
    session_ptr: ?*c.struct_tmate_session,
    server_ip: ?[*:0]const u8,
) callconv(.c) ?*c.struct_tmate_ssh_client {
    const session = session_ptr orelse return null;
    const raw = c.xmalloc(@sizeOf(c.struct_tmate_ssh_client)) orelse c_mod.fatal("out of memory", .{});
    const client: *c.struct_tmate_ssh_client = @ptrCast(@alignCast(raw));
    client.* = std.mem.zeroes(c.struct_tmate_ssh_client);

    _ = c.ssh_set_log_callback(sshLogFunction);

    client.ssh_callbacks = std.mem.zeroes(c.struct_ssh_callbacks_struct);
    client.ssh_callbacks.size = @sizeOf(c.struct_ssh_callbacks_struct);
    client.ssh_callbacks.userdata = client;
    client.ssh_callbacks.auth_function = passphraseCallback;

    client.tmate_session = session;

    // TAILQ_INSERT_TAIL(&session.clients, client, node)
    client.node.tqe_next = null;
    client.node.tqe_prev = session.clients.tqh_last;
    session.clients.tqh_last.* = client;
    session.clients.tqh_last = &client.node.tqe_next;

    client.server_ip = if (server_ip != null) c.xstrdup(server_ip.?) else c.xstrdup("");
    client.state = c.SSH_NONE;
    client.session = null;
    client.channel = null;

    return client;
}
