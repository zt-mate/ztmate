const std = @import("std");
const c_mod = @import("c.zig");
const c = c_mod.c;

pub export fn tmate_print_stack_trace() callconv(.c) void {
    var array: [20]?*anyopaque = undefined;
    const size_i = c.backtrace(&array[0], 20);
    if (size_i <= 0) return;

    const size: usize = @intCast(size_i);
    const strings = c.backtrace_symbols(&array[0], size_i);
    if (strings == null) return;
    defer c.free(@ptrCast(strings));

    c_mod.logInfo("============ {d} stack frames ============", .{size});

    var i: usize = 1;
    while (i < size) : (i += 1) {
        if (strings[i]) |sym| {
            c.log_emit(c.LOG_INFO, "%s", sym);
        }
    }
}

fn handleCrash(sig: c_int) callconv(.c) void {
    const what: [*:0]const u8 = if (sig == c.SIGSEGV) "SIGSEGV" else "SIGABRT";
    c.log_emit(c.LOG_INFO, "%s printing stack trace", what);
    tmate_print_stack_trace();

    _ = c.signal(sig, c.SIG_DFL);
    _ = c.kill(c.getpid(), sig);
}

pub export fn tmate_catch_sigsegv() callconv(.c) void {
    _ = c.signal(c.SIGSEGV, handleCrash);
    _ = c.signal(c.SIGABRT, handleCrash);
}

pub export fn tmate_preload_trace_lib() callconv(.c) void {
    var array: [1]?*anyopaque = undefined;
    _ = c.backtrace(&array[0], 1);
}
