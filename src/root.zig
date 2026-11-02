pub const c_mod = @import("c.zig");
pub const protocol = @import("protocol.zig");
pub const debug = @import("debug.zig");
pub const env = @import("env.zig");
pub const msg = @import("msg.zig");
pub const msgpack = @import("msgpack.zig");
pub const encoder = @import("encoder.zig");
pub const decoder = @import("decoder.zig");
pub const session = @import("session.zig");
pub const ssh_client = @import("ssh_client.zig");

comptime {
    _ = debug;
    _ = env;
    _ = msg;
    _ = msgpack;
    _ = encoder;
    _ = decoder;
    _ = session;
    _ = ssh_client;
}

test "ztmate Zig modules unit tests" {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    // Test env module
    env.tmate_set_env("ztmate_ssh", "ssh test@localhost");
    try std.testing.expectEqualStrings("ssh test@localhost", env.getEnvValue("ztmate_ssh").?);
    env.tmate_set_env("ztmate_ssh", "ssh updated@localhost");
    try std.testing.expectEqualStrings("ssh updated@localhost", env.getEnvValue("ztmate_ssh").?);
}

test "ztmate encoder and decoder protocol integration" {
    const std = @import("std");
    const c = c_mod.c;

    const base = c.event_init();
    try std.testing.expect(base != null);
    session.tmate_session_init(base);

    // Verify tmate_session_init wrote TMATE_OUT_HEADER [0, 6, "2.4.0"] into encoder.buffer
    const evb = session.tmate_session.encoder.buffer;
    const len = c.evbuffer_get_length(evb);
    try std.testing.expect(len > 0);
    const encoded_ptr = c.evbuffer_pullup(evb, -1);

    const ReaderState = struct {
        msg_type: i64 = -1,
        proto_ver: i64 = -1,
        version: [32]u8 = undefined,
        version_len: usize = 0,

        fn onMsg(userdata: ?*anyopaque, uk: ?*c.struct_tmate_unpacker) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(userdata.?));
            self.msg_type = msgpack.unpack_int(uk);
            self.proto_ver = msgpack.unpack_int(uk);
            var buf: [*c]const u8 = null;
            var slen: usize = 0;
            msgpack.unpack_buffer(uk, &buf, &slen);
            @memcpy(self.version[0..slen], buf[0..slen]);
            self.version_len = slen;
        }
    };

    var state = ReaderState{};
    var dec: c.struct_tmate_decoder = undefined;
    msgpack.tmate_decoder_init(&dec, ReaderState.onMsg, &state);
    defer msgpack.tmate_decoder_destroy(&dec);

    var dec_buf: [*c]u8 = null;
    var dec_cap: usize = 0;
    msgpack.tmate_decoder_get_buffer(&dec, &dec_buf, &dec_cap);
    try std.testing.expect(dec_cap >= len);
    @memcpy(dec_buf[0..len], encoded_ptr[0..len]);
    msgpack.tmate_decoder_commit(&dec, len);

    try std.testing.expectEqual(@as(i64, @intFromEnum(protocol.DaemonOutMsgType.header)), state.msg_type);
    try std.testing.expectEqual(@as(i64, protocol.TMATE_PROTOCOL_VERSION), state.proto_ver);
    try std.testing.expectEqualStrings("2.4.0", state.version[0..state.version_len]);

    msgpack.tmate_encoder_destroy(&session.tmate_session.encoder);
}
