const std = @import("std");
const builtin = @import("builtin");

/// Copied from std since it's no longer exposed.
pub fn maybeIgnoreSigpipe() void {
    const have_sigpipe_support = switch (builtin.os.tag) {
        .linux,
        .plan9,
        .solaris,
        .netbsd,
        .openbsd,
        .haiku,
        .macos,
        .ios,
        .watchos,
        .tvos,
        .dragonfly,
        .freebsd,
        => true,

        else => false,
    };

    if (have_sigpipe_support and !std.options.keep_sigpipe) {
        const posix = std.posix;
        const act: posix.Sigaction = .{
            // Set handler to a noop function instead of `SIG.IGN` to prevent
            // leaking signal disposition to a child process.
            .handler = .{ .handler = noopSigHandler },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };
        posix.sigaction(posix.SIG.PIPE, &act, null);
    }
}

fn noopSigHandler(_: c_int) callconv(.c) void {}
