const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;
const session_mod = @import("session.zig");

const TmateEnvNode = struct {
    name: [*:0]u8,
    value: [*:0]u8,
    next: ?*TmateEnvNode = null,
};

var env_head: ?*TmateEnvNode = null;

pub export fn tmate_set_env(name_ptr: ?[*:0]const u8, value_ptr: ?[*:0]const u8) callconv(.c) void {
    const name = name_ptr orelse return;
    const value = value_ptr orelse return;

    var cur = env_head;
    while (cur) |node| : (cur = node.next) {
        if (c.strcmp(node.name, name) == 0) {
            c.free(node.value);
            node.value = c.xstrdup(value);
            return;
        }
    }

    const raw = c.xmalloc(@sizeOf(TmateEnvNode)) orelse c_mod.fatal("out of memory", .{});
    const new_node: *TmateEnvNode = @ptrCast(@alignCast(raw));
    new_node.* = .{
        .name = c.xstrdup(name),
        .value = c.xstrdup(value),
        .next = env_head,
    };
    env_head = new_node;
}

pub export fn tmate_format(ft: ?*anyopaque) callconv(.c) void {
    const tree = ft orelse return;
    var cur = env_head;
    while (cur) |node| : (cur = node.next) {
        c.format_add(@ptrCast(tree), node.name, "%s", node.value);
    }
}

pub export fn tmate_has_received_env() callconv(.c) c_int {
    return session_mod.tmate_session.tmate_env_ready;
}

pub fn getEnvValue(name: []const u8) ?[]const u8 {
    var cur = env_head;
    while (cur) |node| : (cur = node.next) {
        const node_name = std.mem.span(node.name);
        if (std.mem.eql(u8, node_name, name)) {
            return std.mem.span(node.value);
        }
    }
    return null;
}
