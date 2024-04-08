const builtin = @import("builtin");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("blst", .{});

    const upstream = b.dependency("blst", .{});
    const lib = try buildBlst(b, upstream, target, optimize);
    module.addIncludePath(upstream.path("src"));

    b.installArtifact(lib);
}

fn buildBlst(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{ .name = "blst", .target = target, .optimize = optimize });

    lib.addIncludePath(upstream.path("src"));
    lib.addIncludePath(upstream.path("build"));

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    if (!target.result.isDarwin()) {
        try flags.appendSlice(&.{"-D__BLST_PORTABLE__"});
    }

    lib.addCSourceFiles(.{ .root = upstream.path(""), .flags = flags.items, .files = &.{ "src/server.c", "build/assembly.S" } });
    lib.installHeadersDirectory(upstream.path("src"), "", .{});
    lib.linkLibC();

    return lib;
}
