const std = @import("std");

pub const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cDefine("IS_LINUX", "1");
    @cDefine("HAVE_CURSES_H", "1");
    @cInclude("sys/types.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/utsname.h");
    @cInclude("netinet/in.h");
    @cInclude("netinet/tcp.h");
    @cInclude("errno.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
    @cInclude("execinfo.h");
    @cInclude("event2/dns.h");
    @cInclude("event2/util.h");
    @cInclude("event2/event.h");
    @cInclude("tmate.h");
    @cInclude("tmate-protocol.h");
    @cInclude("window-copy.h");
});

/// Internal args_entry structure from arguments.c
pub const ArgsEntry = extern struct {
    flag: u8,
    value: [*c]u8,
    entry: extern struct {
        rbe_left: ?*ArgsEntry,
        rbe_right: ?*ArgsEntry,
        rbe_parent: ?*ArgsEntry,
        rbe_color: c_int,
    },
};

pub extern fn args_tree_RB_MINMAX(head: *c.struct_args_tree, val: c_int) ?*ArgsEntry;
pub extern fn args_tree_RB_NEXT(elm: *ArgsEntry) ?*ArgsEntry;
pub extern fn status_message_callback(fd: c_int, event: c_short, arg: ?*anyopaque) void;

pub extern var cfg_causes: [*c][*c]u8;
pub extern var cfg_ncauses: c.u_int;

pub const RB_NEGINF: c_int = -1;

pub fn logDebug(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    c.log_emit(c.LOG_DEBUG, "%s", slice.ptr);
}

pub fn logInfo(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    c.log_emit(c.LOG_INFO, "%s", slice.ptr);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrintZ(&buf, fmt, args) catch "fatal error";
    c.fatalx("%s", slice.ptr);
}
