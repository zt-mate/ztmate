const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const debug_mod = @import("debug.zig");
const session_mod = @import("session.zig");

const UNPACKER_RESERVE_SIZE: usize = 1024;

const AllocNode = struct {
    next: ?*AllocNode,
    ptr: *anyopaque,
};

fn zoneAlloc(zone_head: *?*AllocNode, size: usize) ?*anyopaque {
    if (size == 0) return null;
    const raw = c.malloc(size) orelse return null;
    const node_raw = c.malloc(@sizeOf(AllocNode)) orelse {
        c.free(raw);
        return null;
    };
    const node: *AllocNode = @ptrCast(@alignCast(node_raw));
    node.* = .{
        .next = zone_head.*,
        .ptr = raw,
    };
    zone_head.* = node;
    return raw;
}

fn zoneFreeAll(zone_head: *?*AllocNode) void {
    var cur = zone_head.*;
    while (cur) |node| {
        const next = node.next;
        c.free(node.ptr);
        c.free(node);
        cur = next;
    }
    zone_head.* = null;
}

fn writeBytes(pk: *c.msgpack_packer, bytes: []const u8) c_int {
    const cb = pk.callback orelse return -1;
    if (bytes.len == 0) return 0;
    return cb(pk.data, @ptrCast(bytes.ptr), bytes.len);
}

pub export fn msgpack_packer_init(
    pk: ?*c.msgpack_packer,
    data: ?*anyopaque,
    callback: c.msgpack_packer_write,
) callconv(.c) void {
    const p = pk orelse return;
    p.data = data;
    p.callback = callback;
}

pub export fn msgpack_pack_nil(pk: ?*c.msgpack_packer) callconv(.c) c_int {
    const p = pk orelse return -1;
    const buf = [_]u8{0xc0};
    return writeBytes(p, &buf);
}

pub export fn msgpack_pack_true(pk: ?*c.msgpack_packer) callconv(.c) c_int {
    const p = pk orelse return -1;
    const buf = [_]u8{0xc3};
    return writeBytes(p, &buf);
}

pub export fn msgpack_pack_false(pk: ?*c.msgpack_packer) callconv(.c) c_int {
    const p = pk orelse return -1;
    const buf = [_]u8{0xc2};
    return writeBytes(p, &buf);
}

pub export fn msgpack_pack_boolean(pk: ?*c.msgpack_packer, value: bool) callconv(.c) void {
    if (value) {
        _ = msgpack_pack_true(pk);
    } else {
        _ = msgpack_pack_false(pk);
    }
}

pub export fn msgpack_pack_uint64(pk: ?*c.msgpack_packer, d: u64) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (d <= 0x7f) {
        const buf = [_]u8{@intCast(d)};
        return writeBytes(p, &buf);
    } else if (d <= 0xff) {
        const buf = [_]u8{ 0xcc, @intCast(d) };
        return writeBytes(p, &buf);
    } else if (d <= 0xffff) {
        var buf: [3]u8 = undefined;
        buf[0] = 0xcd;
        std.mem.writeInt(u16, buf[1..3], @intCast(d), .big);
        return writeBytes(p, &buf);
    } else if (d <= 0xffff_ffff) {
        var buf: [5]u8 = undefined;
        buf[0] = 0xce;
        std.mem.writeInt(u32, buf[1..5], @intCast(d), .big);
        return writeBytes(p, &buf);
    } else {
        var buf: [9]u8 = undefined;
        buf[0] = 0xcf;
        std.mem.writeInt(u64, buf[1..9], d, .big);
        return writeBytes(p, &buf);
    }
}

pub export fn msgpack_pack_int64(pk: ?*c.msgpack_packer, d: i64) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (d >= 0) {
        return msgpack_pack_uint64(p, @intCast(d));
    }
    if (d >= -32) {
        const byte: u8 = @bitCast(@as(i8, @intCast(d)));
        const buf = [_]u8{byte};
        return writeBytes(p, &buf);
    } else if (d >= -128) {
        const byte: u8 = @bitCast(@as(i8, @intCast(d)));
        const buf = [_]u8{ 0xd0, byte };
        return writeBytes(p, &buf);
    } else if (d >= -32768) {
        var buf: [3]u8 = undefined;
        buf[0] = 0xd1;
        std.mem.writeInt(i16, buf[1..3], @intCast(d), .big);
        return writeBytes(p, &buf);
    } else if (d >= -2147483648) {
        var buf: [5]u8 = undefined;
        buf[0] = 0xd2;
        std.mem.writeInt(i32, buf[1..5], @intCast(d), .big);
        return writeBytes(p, &buf);
    } else {
        var buf: [9]u8 = undefined;
        buf[0] = 0xd3;
        std.mem.writeInt(i64, buf[1..9], d, .big);
        return writeBytes(p, &buf);
    }
}

pub export fn msgpack_pack_int(pk: ?*c.msgpack_packer, d: c_int) callconv(.c) c_int {
    return msgpack_pack_int64(pk, d);
}

pub export fn msgpack_pack_unsigned_int(pk: ?*c.msgpack_packer, d: c_uint) callconv(.c) c_int {
    return msgpack_pack_uint64(pk, d);
}

pub export fn msgpack_pack_array(pk: ?*c.msgpack_packer, n: usize) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (n <= 15) {
        const buf = [_]u8{0x90 | @as(u8, @intCast(n))};
        return writeBytes(p, &buf);
    } else if (n <= 0xffff) {
        var buf: [3]u8 = undefined;
        buf[0] = 0xdc;
        std.mem.writeInt(u16, buf[1..3], @intCast(n), .big);
        return writeBytes(p, &buf);
    } else {
        var buf: [5]u8 = undefined;
        buf[0] = 0xdd;
        std.mem.writeInt(u32, buf[1..5], @intCast(n), .big);
        return writeBytes(p, &buf);
    }
}

pub export fn msgpack_pack_str(pk: ?*c.msgpack_packer, l: usize) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (l <= 31) {
        const buf = [_]u8{0xa0 | @as(u8, @intCast(l))};
        return writeBytes(p, &buf);
    } else if (l <= 0xff) {
        const buf = [_]u8{ 0xd9, @intCast(l) };
        return writeBytes(p, &buf);
    } else if (l <= 0xffff) {
        var buf: [3]u8 = undefined;
        buf[0] = 0xda;
        std.mem.writeInt(u16, buf[1..3], @intCast(l), .big);
        return writeBytes(p, &buf);
    } else {
        var buf: [5]u8 = undefined;
        buf[0] = 0xdb;
        std.mem.writeInt(u32, buf[1..5], @intCast(l), .big);
        return writeBytes(p, &buf);
    }
}

pub export fn msgpack_pack_str_body(pk: ?*c.msgpack_packer, b: ?*const anyopaque, l: usize) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (l == 0) return 0;
    const ptr: [*]const u8 = @ptrCast(b orelse return -1);
    return writeBytes(p, ptr[0..l]);
}

pub export fn msgpack_pack_bin(pk: ?*c.msgpack_packer, l: usize) callconv(.c) c_int {
    const p = pk orelse return -1;
    if (l <= 0xff) {
        const buf = [_]u8{ 0xc4, @intCast(l) };
        return writeBytes(p, &buf);
    } else if (l <= 0xffff) {
        var buf: [3]u8 = undefined;
        buf[0] = 0xc5;
        std.mem.writeInt(u16, buf[1..3], @intCast(l), .big);
        return writeBytes(p, &buf);
    } else {
        var buf: [5]u8 = undefined;
        buf[0] = 0xc6;
        std.mem.writeInt(u32, buf[1..5], @intCast(l), .big);
        return writeBytes(p, &buf);
    }
}

pub export fn msgpack_pack_bin_body(pk: ?*c.msgpack_packer, b: ?*const anyopaque, l: usize) callconv(.c) c_int {
    return msgpack_pack_str_body(pk, b, l);
}

pub export fn msgpack_pack_string(pk: ?*c.msgpack_packer, str_ptr: ?[*:0]const u8) callconv(.c) void {
    const str = str_ptr orelse "";
    const len = c.strlen(str);
    _ = msgpack_pack_str(pk, len);
    _ = msgpack_pack_str_body(pk, str, len);
}

// Streaming Unpacker Implementation

const ParseError = error{
    EndOfStream,
    InvalidFormat,
    OutOfMemory,
};

fn readU8(data: []const u8, pos: *usize) ParseError!u8 {
    if (pos.* >= data.len) return error.EndOfStream;
    const b = data[pos.*];
    pos.* += 1;
    return b;
}

fn readBytes(data: []const u8, pos: *usize, n: usize) ParseError![]const u8 {
    if (pos.* + n > data.len) return error.EndOfStream;
    const s = data[pos.* .. pos.* + n];
    pos.* += n;
    return s;
}

fn readBeInt(comptime T: type, data: []const u8, pos: *usize) ParseError!T {
    const n = @divExact(@typeInfo(T).int.bits, 8);
    const bytes = try readBytes(data, pos, n);
    return std.mem.readInt(T, bytes[0..n], .big);
}

fn parseObject(data: []const u8, pos: *usize, zone: *?*AllocNode) ParseError!c.msgpack_object {
    const tag = try readU8(data, pos);

    // Positive fixint: 0x00 - 0x7f
    if (tag <= 0x7f) {
        return .{
            .type = c.MSGPACK_OBJECT_POSITIVE_INTEGER,
            .via = .{ .u64 = tag },
        };
    }
    // Fixmap: 0x80 - 0x8f
    if (tag >= 0x80 and tag <= 0x8f) {
        return parseMap(data, pos, zone, tag & 0x0f);
    }
    // Fixarray: 0x90 - 0x9f
    if (tag >= 0x90 and tag <= 0x9f) {
        return parseArray(data, pos, zone, tag & 0x0f);
    }
    // Fixstr: 0xa0 - 0xbf
    if (tag >= 0xa0 and tag <= 0xbf) {
        return parseStr(data, pos, tag & 0x1f, c.MSGPACK_OBJECT_STR);
    }
    // Negative fixint: 0xe0 - 0xff
    if (tag >= 0xe0) {
        const signed: i8 = @bitCast(tag);
        return .{
            .type = c.MSGPACK_OBJECT_NEGATIVE_INTEGER,
            .via = .{ .i64 = signed },
        };
    }

    switch (tag) {
        0xc0 => return .{
            .type = c.MSGPACK_OBJECT_NIL,
            .via = .{ .u64 = 0 },
        },
        0xc2 => return .{
            .type = c.MSGPACK_OBJECT_BOOLEAN,
            .via = .{ .boolean = false },
        },
        0xc3 => return .{
            .type = c.MSGPACK_OBJECT_BOOLEAN,
            .via = .{ .boolean = true },
        },
        0xc4 => {
            const len = try readU8(data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_BIN);
        },
        0xc5 => {
            const len = try readBeInt(u16, data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_BIN);
        },
        0xc6 => {
            const len = try readBeInt(u32, data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_BIN);
        },
        0xca => {
            const bits = try readBeInt(u32, data, pos);
            const f: f32 = @bitCast(bits);
            return .{
                .type = c.MSGPACK_OBJECT_FLOAT32,
                .via = .{ .f64 = f },
            };
        },
        0xcb => {
            const bits = try readBeInt(u64, data, pos);
            const f: f64 = @bitCast(bits);
            return .{
                .type = c.MSGPACK_OBJECT_FLOAT64,
                .via = .{ .f64 = f },
            };
        },
        0xcc => {
            const v = try readU8(data, pos);
            return .{
                .type = c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .u64 = v },
            };
        },
        0xcd => {
            const v = try readBeInt(u16, data, pos);
            return .{
                .type = c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .u64 = v },
            };
        },
        0xce => {
            const v = try readBeInt(u32, data, pos);
            return .{
                .type = c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .u64 = v },
            };
        },
        0xcf => {
            const v = try readBeInt(u64, data, pos);
            return .{
                .type = c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .u64 = v },
            };
        },
        0xd0 => {
            const v = try readBeInt(i8, data, pos);
            return .{
                .type = if (v < 0) c.MSGPACK_OBJECT_NEGATIVE_INTEGER else c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .i64 = v },
            };
        },
        0xd1 => {
            const v = try readBeInt(i16, data, pos);
            return .{
                .type = if (v < 0) c.MSGPACK_OBJECT_NEGATIVE_INTEGER else c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .i64 = v },
            };
        },
        0xd2 => {
            const v = try readBeInt(i32, data, pos);
            return .{
                .type = if (v < 0) c.MSGPACK_OBJECT_NEGATIVE_INTEGER else c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .i64 = v },
            };
        },
        0xd3 => {
            const v = try readBeInt(i64, data, pos);
            return .{
                .type = if (v < 0) c.MSGPACK_OBJECT_NEGATIVE_INTEGER else c.MSGPACK_OBJECT_POSITIVE_INTEGER,
                .via = .{ .i64 = v },
            };
        },
        0xd9 => {
            const len = try readU8(data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_STR);
        },
        0xda => {
            const len = try readBeInt(u16, data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_STR);
        },
        0xdb => {
            const len = try readBeInt(u32, data, pos);
            return parseStr(data, pos, len, c.MSGPACK_OBJECT_STR);
        },
        0xdc => {
            const len = try readBeInt(u16, data, pos);
            return parseArray(data, pos, zone, len);
        },
        0xdd => {
            const len = try readBeInt(u32, data, pos);
            return parseArray(data, pos, zone, len);
        },
        0xde => {
            const len = try readBeInt(u16, data, pos);
            return parseMap(data, pos, zone, len);
        },
        0xdf => {
            const len = try readBeInt(u32, data, pos);
            return parseMap(data, pos, zone, len);
        },
        else => return error.InvalidFormat,
    }
}

fn parseStr(data: []const u8, pos: *usize, len: usize, obj_type: c.msgpack_object_type) ParseError!c.msgpack_object {
    const bytes = try readBytes(data, pos, len);
    return .{
        .type = obj_type,
        .via = .{
            .str = .{
                .size = @intCast(len),
                .ptr = @ptrCast(bytes.ptr),
            },
        },
    };
}

fn parseArray(data: []const u8, pos: *usize, zone: *?*AllocNode, count: usize) ParseError!c.msgpack_object {
    if (count == 0) {
        return .{
            .type = c.MSGPACK_OBJECT_ARRAY,
            .via = .{
                .array = .{
                    .size = 0,
                    .ptr = null,
                },
            },
        };
    }

    const raw = zoneAlloc(zone, count * @sizeOf(c.msgpack_object)) orelse return error.OutOfMemory;
    const items: [*]c.msgpack_object = @ptrCast(@alignCast(raw));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        items[i] = try parseObject(data, pos, zone);
    }

    return .{
        .type = c.MSGPACK_OBJECT_ARRAY,
        .via = .{
            .array = .{
                .size = @intCast(count),
                .ptr = items,
            },
        },
    };
}

fn parseMap(data: []const u8, pos: *usize, zone: *?*AllocNode, count: usize) ParseError!c.msgpack_object {
    if (count == 0) {
        return .{
            .type = c.MSGPACK_OBJECT_MAP,
            .via = .{
                .map = .{
                    .size = 0,
                    .ptr = null,
                },
            },
        };
    }

    const raw = zoneAlloc(zone, count * @sizeOf(c.msgpack_object_kv)) orelse return error.OutOfMemory;
    const kvs: [*]c.msgpack_object_kv = @ptrCast(@alignCast(raw));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const k = try parseObject(data, pos, zone);
        const v = try parseObject(data, pos, zone);
        kvs[i] = .{ .key = k, .val = v };
    }

    return .{
        .type = c.MSGPACK_OBJECT_MAP,
        .via = .{
            .map = .{
                .size = @intCast(count),
                .ptr = kvs,
            },
        },
    };
}

pub export fn msgpack_unpacker_init(mpac: ?*c.msgpack_unpacker, initial_buffer_size: usize) callconv(.c) bool {
    const u = mpac orelse return false;
    const cap = if (initial_buffer_size > 0) initial_buffer_size else UNPACKER_RESERVE_SIZE;
    const buf = c.malloc(cap) orelse return false;
    u.* = .{
        .buffer = @ptrCast(buf),
        .used = 0,
        .free = cap,
        .off = 0,
        .parsed = 0,
        .z = null,
        .initial_buffer_size = cap,
        .ctx = 0,
    };
    return true;
}

pub export fn msgpack_unpacker_destroy(mpac: ?*c.msgpack_unpacker) callconv(.c) void {
    const u = mpac orelse return;
    if (u.buffer != null) {
        c.free(u.buffer);
    }
    u.* = std.mem.zeroes(c.msgpack_unpacker);
}

pub export fn msgpack_unpacker_reserve_buffer(mpac: ?*c.msgpack_unpacker, size: usize) callconv(.c) bool {
    const u = mpac orelse return false;
    if (u.off > 0) {
        const remaining = u.used - u.off;
        if (remaining > 0) {
            const buf_slice: [*]u8 = @ptrCast(u.buffer);
            std.mem.copyForwards(u8, buf_slice[0..remaining], buf_slice[u.off..u.used]);
        }
        u.used = remaining;
        u.free += u.off;
        u.off = 0;
    }

    if (u.free >= size) return true;

    const current_cap = u.used + u.free;
    const needed_cap = u.used + size;
    const new_cap = @max(current_cap * 2, needed_cap);
    const new_buf = c.realloc(u.buffer, new_cap) orelse return false;
    u.buffer = @ptrCast(new_buf);
    u.free = new_cap - u.used;
    return true;
}

pub export fn msgpack_unpacker_buffer(mpac: ?*c.msgpack_unpacker) callconv(.c) [*c]u8 {
    const u = mpac orelse return null;
    if (u.buffer == null) return null;
    return u.buffer + u.used;
}

pub export fn msgpack_unpacker_buffer_capacity(mpac: ?*const c.msgpack_unpacker) callconv(.c) usize {
    const u = mpac orelse return 0;
    return u.free;
}

pub export fn msgpack_unpacker_buffer_consumed(mpac: ?*c.msgpack_unpacker, size: usize) callconv(.c) void {
    const u = mpac orelse return;
    const actual = @min(size, u.free);
    u.used += actual;
    u.free -= actual;
}

pub export fn msgpack_unpacked_init(result: ?*c.msgpack_unpacked) callconv(.c) void {
    const r = result orelse return;
    r.* = .{
        .zone = null,
        .data = .{
            .type = c.MSGPACK_OBJECT_NIL,
            .via = .{ .u64 = 0 },
        },
    };
}

pub export fn msgpack_unpacked_destroy(result: ?*c.msgpack_unpacked) callconv(.c) void {
    const r = result orelse return;
    var zone_head: ?*AllocNode = @ptrCast(@alignCast(r.zone));
    zoneFreeAll(&zone_head);
    r.zone = null;
}

pub export fn msgpack_unpacker_next(mpac: ?*c.msgpack_unpacker, pac: ?*c.msgpack_unpacked) callconv(.c) bool {
    const u = mpac orelse return false;
    const p = pac orelse return false;

    msgpack_unpacked_destroy(p);

    if (u.off >= u.used or u.buffer == null) {
        return false;
    }

    const raw_ptr: [*]const u8 = @ptrCast(u.buffer);
    const slice = raw_ptr[0..u.used];
    var pos: usize = u.off;
    var zone_head: ?*AllocNode = null;

    const obj = parseObject(slice, &pos, &zone_head) catch |err| {
        zoneFreeAll(&zone_head);
        switch (err) {
            error.EndOfStream => return false,
            error.InvalidFormat, error.OutOfMemory => tmate_decoder_error(),
        }
    };

    u.off = pos;
    p.zone = zone_head;
    p.data = obj;
    return true;
}

// tmate_encoder & tmate_decoder functions (replaces tmate-msgpack.c)

fn onEncoderBufferReady(_: c.evutil_socket_t, _: c_short, arg: ?*anyopaque) callconv(.c) void {
    const encoder: *c.struct_tmate_encoder = @ptrCast(@alignCast(arg orelse return));
    encoder.ev_active = false;
    if (encoder.ready_callback) |cb| {
        cb(encoder.userdata, encoder.buffer);
    }
}

fn onEncoderWrite(userdata: ?*anyopaque, buf: [*c]const u8, len: usize) callconv(.c) c_int {
    const encoder: *c.struct_tmate_encoder = @ptrCast(@alignCast(userdata orelse return -1));

    if (c.evbuffer_add(encoder.buffer, buf, len) < 0) {
        c_mod.fatal("Cannot buffer encoded data", .{});
    }

    if (!encoder.ev_active) {
        c.event_active(encoder.ev_buffer, c.EV_READ, 0);
        encoder.ev_active = true;
    }

    return 0;
}

pub export fn tmate_encoder_init(
    encoder_ptr: ?*c.struct_tmate_encoder,
    callback: ?*const c.tmate_encoder_write_cb,
    userdata: ?*anyopaque,
) callconv(.c) void {
    const encoder = encoder_ptr orelse return;
    msgpack_packer_init(&encoder.pk, encoder, onEncoderWrite);
    encoder.buffer = c.evbuffer_new();
    encoder.ready_callback = callback;
    encoder.userdata = userdata;

    if (encoder.buffer == null) {
        c_mod.fatal("Can't allocate buffer", .{});
    }

    encoder.ev_buffer = c.event_new(
        session_mod.tmate_session.ev_base,
        -1,
        c.EV_READ | c.EV_PERSIST,
        onEncoderBufferReady,
        encoder,
    );
    if (encoder.ev_buffer == null) {
        c_mod.fatal("Can't allocate event", .{});
    }

    _ = c.event_add(encoder.ev_buffer, null);
    encoder.ev_active = false;
}

pub export fn tmate_encoder_destroy(encoder_ptr: ?*c.struct_tmate_encoder) callconv(.c) void {
    const encoder = encoder_ptr orelse return;
    if (encoder.buffer != null) {
        c.evbuffer_free(encoder.buffer);
    }
    if (encoder.ev_buffer != null) {
        _ = c.event_del(encoder.ev_buffer);
        c.event_free(encoder.ev_buffer);
    }
    encoder.* = std.mem.zeroes(c.struct_tmate_encoder);
}

pub export fn tmate_encoder_set_ready_callback(
    encoder_ptr: ?*c.struct_tmate_encoder,
    callback: ?*const c.tmate_encoder_write_cb,
    userdata: ?*anyopaque,
) callconv(.c) void {
    const encoder = encoder_ptr orelse return;
    encoder.ready_callback = callback;
    encoder.userdata = userdata;
    if (encoder.ready_callback) |cb| {
        cb(encoder.userdata, encoder.buffer);
    }
}

pub export fn tmate_decoder_error() callconv(.c) noreturn {
    debug_mod.tmate_print_stack_trace();
    c_mod.fatal("Received a bad message", .{});
}

pub export fn init_unpacker(uk_ptr: ?*c.struct_tmate_unpacker, obj: c.msgpack_object) callconv(.c) void {
    const uk = uk_ptr orelse return;
    if (obj.type != c.MSGPACK_OBJECT_ARRAY) {
        tmate_decoder_error();
    }
    uk.argv = obj.via.array.ptr;
    uk.argc = @intCast(obj.via.array.size);
}

pub export fn unpack_int(uk_ptr: ?*c.struct_tmate_unpacker) callconv(.c) i64 {
    const uk = uk_ptr orelse tmate_decoder_error();
    if (uk.argc == 0) {
        tmate_decoder_error();
    }

    const arg = uk.argv[0];
    if (arg.type != c.MSGPACK_OBJECT_POSITIVE_INTEGER and
        arg.type != c.MSGPACK_OBJECT_NEGATIVE_INTEGER)
    {
        tmate_decoder_error();
    }

    const val = arg.via.i64;
    uk.argv += 1;
    uk.argc -= 1;
    return val;
}

pub export fn unpack_bool(uk_ptr: ?*c.struct_tmate_unpacker) callconv(.c) bool {
    const uk = uk_ptr orelse tmate_decoder_error();
    if (uk.argc == 0) {
        tmate_decoder_error();
    }

    const arg = uk.argv[0];
    if (arg.type != c.MSGPACK_OBJECT_BOOLEAN) {
        tmate_decoder_error();
    }

    const val = arg.via.boolean;
    uk.argv += 1;
    uk.argc -= 1;
    return val;
}

pub export fn unpack_buffer(
    uk_ptr: ?*c.struct_tmate_unpacker,
    buf_out: *[*c]const u8,
    len_out: *usize,
) callconv(.c) void {
    const uk = uk_ptr orelse tmate_decoder_error();
    if (uk.argc == 0) {
        tmate_decoder_error();
    }

    const arg = uk.argv[0];
    if (arg.type != c.MSGPACK_OBJECT_STR and arg.type != c.MSGPACK_OBJECT_BIN) {
        tmate_decoder_error();
    }

    len_out.* = arg.via.str.size;
    buf_out.* = arg.via.str.ptr;

    uk.argv += 1;
    uk.argc -= 1;
}

pub export fn unpack_string(uk_ptr: ?*c.struct_tmate_unpacker) callconv(.c) [*c]u8 {
    var buf: [*c]const u8 = null;
    var len: usize = 0;
    unpack_buffer(uk_ptr, &buf, &len);

    const alloc_raw = c.xmalloc(len + 1) orelse c_mod.fatal("out of memory", .{});
    const alloc_buf: [*c]u8 = @ptrCast(alloc_raw);
    if (len > 0 and buf != null) {
        _ = c.memcpy(alloc_buf, buf, len);
    }
    alloc_buf[len] = 0;
    return alloc_buf;
}

pub export fn unpack_array(
    uk_ptr: ?*c.struct_tmate_unpacker,
    nested_ptr: ?*c.struct_tmate_unpacker,
) callconv(.c) void {
    const uk = uk_ptr orelse tmate_decoder_error();
    if (uk.argc == 0) {
        tmate_decoder_error();
    }

    init_unpacker(nested_ptr, uk.argv[0]);
    uk.argv += 1;
    uk.argc -= 1;
}

pub export fn tmate_decoder_init(
    decoder_ptr: ?*c.struct_tmate_decoder,
    reader: ?*const c.tmate_decoder_reader,
    userdata: ?*anyopaque,
) callconv(.c) void {
    const decoder = decoder_ptr orelse return;
    if (!msgpack_unpacker_init(&decoder.unpacker, UNPACKER_RESERVE_SIZE)) {
        c_mod.fatal("Cannot initialize the unpacker", .{});
    }
    decoder.reader = reader;
    decoder.userdata = userdata;
}

pub export fn tmate_decoder_destroy(decoder_ptr: ?*c.struct_tmate_decoder) callconv(.c) void {
    const decoder = decoder_ptr orelse return;
    msgpack_unpacker_destroy(&decoder.unpacker);
    decoder.* = std.mem.zeroes(c.struct_tmate_decoder);
}

pub export fn tmate_decoder_get_buffer(
    decoder_ptr: ?*c.struct_tmate_decoder,
    buf_out: *[*c]u8,
    len_out: *usize,
) callconv(.c) void {
    const decoder = decoder_ptr orelse return;
    if (!msgpack_unpacker_reserve_buffer(&decoder.unpacker, UNPACKER_RESERVE_SIZE)) {
        c_mod.fatal("cannot expand decoder buffer", .{});
    }

    buf_out.* = msgpack_unpacker_buffer(&decoder.unpacker);
    len_out.* = msgpack_unpacker_buffer_capacity(&decoder.unpacker);
}

pub export fn tmate_decoder_commit(decoder_ptr: ?*c.struct_tmate_decoder, len: usize) callconv(.c) void {
    const decoder = decoder_ptr orelse return;
    var uk: c.struct_tmate_unpacker = undefined;
    var result: c.msgpack_unpacked = undefined;

    msgpack_unpacker_buffer_consumed(&decoder.unpacker, len);

    msgpack_unpacked_init(&result);
    defer msgpack_unpacked_destroy(&result);

    while (msgpack_unpacker_next(&decoder.unpacker, &result)) {
        init_unpacker(&uk, result.data);
        if (decoder.reader) |reader| {
            reader(decoder.userdata, &uk);
        }
    }
}

test "msgpack pack and streaming unpack roundtrip" {
    const BufferCtx = struct {
        data: [512]u8 = undefined,
        len: usize = 0,

        fn writeCallback(userdata: ?*anyopaque, buf: [*c]const u8, len: usize) callconv(.c) c_int {
            const self: *@This() = @ptrCast(@alignCast(userdata.?));
            const src = buf[0..len];
            @memcpy(self.data[self.len .. self.len + len], src);
            self.len += len;
            return 0;
        }
    };

    var ctx = BufferCtx{};
    var pk: c.msgpack_packer = undefined;
    msgpack_packer_init(&pk, &ctx, BufferCtx.writeCallback);

    // Pack [6, "ztmate-2.4.0", -42, true, [100, 200]]
    _ = msgpack_pack_array(&pk, 5);
    _ = msgpack_pack_int(&pk, 6);
    msgpack_pack_string(&pk, "ztmate-2.4.0");
    _ = msgpack_pack_int(&pk, -42);
    msgpack_pack_boolean(&pk, true);
    _ = msgpack_pack_array(&pk, 2);
    _ = msgpack_pack_unsigned_int(&pk, 100);
    _ = msgpack_pack_unsigned_int(&pk, 200);

    var unpacker: c.msgpack_unpacker = undefined;
    try std.testing.expect(msgpack_unpacker_init(&unpacker, 64));
    defer msgpack_unpacker_destroy(&unpacker);

    var result: c.msgpack_unpacked = undefined;
    msgpack_unpacked_init(&result);
    defer msgpack_unpacked_destroy(&result);

    // Feed only half of the bytes first to verify streaming partial-frame handling
    const half = ctx.len / 2;
    try std.testing.expect(msgpack_unpacker_reserve_buffer(&unpacker, half));
    @memcpy(msgpack_unpacker_buffer(&unpacker)[0..half], ctx.data[0..half]);
    msgpack_unpacker_buffer_consumed(&unpacker, half);
    try std.testing.expect(!msgpack_unpacker_next(&unpacker, &result));

    // Feed the second half
    const rest = ctx.len - half;
    try std.testing.expect(msgpack_unpacker_reserve_buffer(&unpacker, rest));
    @memcpy(msgpack_unpacker_buffer(&unpacker)[0..rest], ctx.data[half..ctx.len]);
    msgpack_unpacker_buffer_consumed(&unpacker, rest);
    try std.testing.expect(msgpack_unpacker_next(&unpacker, &result));

    var uk: c.struct_tmate_unpacker = undefined;
    init_unpacker(&uk, result.data);
    try std.testing.expectEqual(@as(i64, 6), unpack_int(&uk));

    var str_ptr: [*c]const u8 = null;
    var str_len: usize = 0;
    unpack_buffer(&uk, &str_ptr, &str_len);
    try std.testing.expectEqualStrings("ztmate-2.4.0", str_ptr[0..str_len]);

    try std.testing.expectEqual(@as(i64, -42), unpack_int(&uk));
    try std.testing.expectEqual(true, unpack_bool(&uk));

    var nested: c.struct_tmate_unpacker = undefined;
    unpack_array(&uk, &nested);
    try std.testing.expectEqual(@as(i64, 100), unpack_int(&nested));
    try std.testing.expectEqual(@as(i64, 200), unpack_int(&nested));
}
