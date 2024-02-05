const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = target;
    _ = optimize;
}

/// Add the SDK framework, include, and library paths to the given module.
/// The module target is used to determine the SDK to use so it must have
/// a resolved target.
pub fn addPaths(b: *std.Build, m: *std.Build.Module) !void {
    // The cache. This always uses b.allocator and never frees memory
    // (which is idiomatic for a Zig build exe).
    const Cache = struct {
        const Key = struct {
            arch: std.Target.Cpu.Arch,
            os: std.Target.Os.Tag,
            abi: std.Target.Abi,
        };

        var map: std.AutoHashMapUnmanaged(Key, ?[]const u8) = .{};
    };

    const target = m.resolved_target.?.result;
    const gop = try Cache.map.getOrPut(b.allocator, .{
        .arch = target.cpu.arch,
        .os = target.os.tag,
        .abi = target.abi,
    });

    // This executes `xcrun` to get the SDK path. We don't want to execute
    // this multiple times so we cache the value.
    if (!gop.found_existing) {
        gop.value_ptr.* = std.zig.system.darwin.getSdk(
            b.allocator,
            m.resolved_target.?.result,
        );
    }

    // The active SDK we want to use
    const path = gop.value_ptr.* orelse return error.AppleSDKNotFound;
    m.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ path, "/System/Library/Frameworks" }) });
    m.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ path, "/usr/include" }) });
    m.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ path, "/usr/lib" }) });
}
