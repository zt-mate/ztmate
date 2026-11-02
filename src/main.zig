const root = @import("root.zig");

extern fn tmux_main(argc: c_int, argv: [*c][*c]u8) c_int;

pub export fn main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    return tmux_main(argc, argv);
}

comptime {
    _ = root;
}
