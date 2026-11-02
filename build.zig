const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_flags = &[_][]const u8{
        "-std=gnu99",
        "-D_GNU_SOURCE=1",
        "-DIS_LINUX=1",
        "-DPACKAGE_STRING=\"ztmate 2.4.0\"",
        "-DPACKAGE_VERSION=\"2.4.0\"",
        "-DVERSION=\"2.4.0\"",
        "-DTMUX_CONF=\"/etc/tmux.conf\"",
        "-DHAVE_CURSES_H=1",
        "-DHAVE_DIRENT_H=1",
        "-DHAVE_EXECINFO_H=1",
        "-DHAVE_FCNTL_H=1",
        "-DHAVE_INTTYPES_H=1",
        "-DHAVE_NCURSES_H=1",
        "-DHAVE_PATHS_H=1",
        "-DHAVE_PTY_H=1",
        "-DHAVE_STDINT_H=1",
        "-DHAVE_SYS_DIR_H=1",
        "-DHAVE_TERM_H=1",
        "-DHAVE_BACKTRACE=1",
        "-DHAVE_DIRFD=1",
        "-DHAVE_FLOCK=1",
        "-DHAVE_SYSCONF=1",
        "-DHAVE_CFMAKERAW=1",
        "-DHAVE_FORKPTY=1",
        "-DHAVE_DAEMON=1",
        "-DHAVE_SETENV=1",
        "-DHAVE_ASPRINTF=1",
        "-DHAVE_STRCASESTR=1",
        "-DHAVE_STRSEP=1",
        "-DHAVE_OPENAT=1",
        "-DHAVE_BSD_TYPES=1",
        "-DHAVE___PROGNAME=1",
        "-DHAVE_PROC_PID=1",
        "-Dmain=tmux_main",
        "-Wno-unused-parameter",
        "-Wno-unused-variable",
        "-Wno-null-pointer-arithmetic",
        "-Wno-deprecated-declarations",
        "-Wno-format-nonliteral",
        "-Wno-sign-compare",
    };

    const tmux_c_sources = &[_][]const u8{
        "alerts.c",
        "arguments.c",
        "attributes.c",
        "cfg.c",
        "client.c",
        "cmd-attach-session.c",
        "cmd-bind-key.c",
        "cmd-break-pane.c",
        "cmd-capture-pane.c",
        "cmd-choose-buffer.c",
        "cmd-choose-client.c",
        "cmd-choose-tree.c",
        "cmd-clear-history.c",
        "cmd-command-prompt.c",
        "cmd-confirm-before.c",
        "cmd-copy-mode.c",
        "cmd-detach-client.c",
        "cmd-display-message.c",
        "cmd-display-panes.c",
        "cmd-find.c",
        "cmd-find-window.c",
        "cmd-if-shell.c",
        "cmd-join-pane.c",
        "cmd-kill-pane.c",
        "cmd-kill-server.c",
        "cmd-kill-session.c",
        "cmd-kill-window.c",
        "cmd-list-buffers.c",
        "cmd-list-clients.c",
        "cmd-list-keys.c",
        "cmd-list-panes.c",
        "cmd-list-sessions.c",
        "cmd-list-windows.c",
        "cmd-list.c",
        "cmd-load-buffer.c",
        "cmd-lock-server.c",
        "cmd-move-window.c",
        "cmd-new-session.c",
        "cmd-new-window.c",
        "cmd-paste-buffer.c",
        "cmd-pipe-pane.c",
        "cmd-queue.c",
        "cmd-refresh-client.c",
        "cmd-rename-session.c",
        "cmd-rename-window.c",
        "cmd-resize-pane.c",
        "cmd-respawn-pane.c",
        "cmd-respawn-window.c",
        "cmd-rotate-window.c",
        "cmd-run-shell.c",
        "cmd-save-buffer.c",
        "cmd-select-layout.c",
        "cmd-select-pane.c",
        "cmd-select-window.c",
        "cmd-send-keys.c",
        "cmd-set-buffer.c",
        "cmd-set-environment.c",
        "cmd-set-hook.c",
        "cmd-set-option.c",
        "cmd-show-environment.c",
        "cmd-show-messages.c",
        "cmd-show-options.c",
        "cmd-source-file.c",
        "cmd-split-window.c",
        "cmd-string.c",
        "cmd-swap-pane.c",
        "cmd-swap-window.c",
        "cmd-switch-client.c",
        "cmd-unbind-key.c",
        "cmd-wait-for.c",
        "cmd.c",
        "colour.c",
        "control.c",
        "control-notify.c",
        "environ.c",
        "format.c",
        "grid-view.c",
        "grid.c",
        "hooks.c",
        "input-keys.c",
        "input.c",
        "job.c",
        "key-bindings.c",
        "key-string.c",
        "layout-custom.c",
        "layout-set.c",
        "layout.c",
        "log.c",
        "mode-key.c",
        "names.c",
        "notify.c",
        "options-table.c",
        "options.c",
        "paste.c",
        "proc.c",
        "resize.c",
        "screen-redraw.c",
        "screen-write.c",
        "screen.c",
        "server-client.c",
        "server-fn.c",
        "server.c",
        "session.c",
        "signal.c",
        "status.c",
        "style.c",
        "tmux.c",
        "tty-acs.c",
        "tty-keys.c",
        "tty-term.c",
        "tty.c",
        "utf8.c",
        "window-choose.c",
        "window-clock.c",
        "window-copy.c",
        "window.c",
        "xmalloc.c",
        "xterm-keys.c",
        "osdep-linux.c",
        "compat/imsg.c",
        "compat/imsg-buffer.c",
        "compat/closefrom.c",
        "compat/strlcat.c",
        "compat/strlcpy.c",
        "compat/fgetln.c",
        "compat/fparseln.c",
        "compat/getopt.c",
        "compat/vis.c",
        "compat/unvis.c",
        "compat/strtonum.c",
        "compat/b64_ntop.c",
        "compat/reallocarray.c",
    };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addIncludePath(b.path("."));
    exe_mod.addIncludePath(b.path("compat"));
    exe_mod.addIncludePath(b.path("include"));
    exe_mod.addLibraryPath(b.path("lib"));

    exe_mod.addCSourceFiles(.{
        .files = tmux_c_sources,
        .flags = c_flags,
    });

    exe_mod.linkSystemLibrary("event", .{});
    exe_mod.linkSystemLibrary("ssh", .{});
    exe_mod.linkSystemLibrary("ncurses", .{});
    exe_mod.linkSystemLibrary("tinfo", .{});

    const exe = b.addExecutable(.{
        .name = "ztmate",
        .root_module = exe_mod,
    });
    exe.rdynamic = true;
    b.installArtifact(exe);

    const run_step = b.step("run", "Run ztmate");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addIncludePath(b.path("."));
    test_mod.addIncludePath(b.path("compat"));
    test_mod.addIncludePath(b.path("include"));
    test_mod.addLibraryPath(b.path("lib"));
    test_mod.addCSourceFiles(.{
        .files = tmux_c_sources,
        .flags = c_flags,
    });
    test_mod.linkSystemLibrary("event", .{});
    test_mod.linkSystemLibrary("ssh", .{});
    test_mod.linkSystemLibrary("ncurses", .{});
    test_mod.linkSystemLibrary("tinfo", .{});

    const exe_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
