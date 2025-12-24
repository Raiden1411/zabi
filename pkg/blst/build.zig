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
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "blst",
        .root_module = mod,
    });

    lib.root_module.addIncludePath(upstream.path("src"));
    lib.root_module.addIncludePath(upstream.path("build"));

    var flags = std.array_list.Managed([]const u8).init(b.allocator);
    defer flags.deinit();

    if (!target.result.isDarwinLibC()) {
        try flags.appendSlice(&.{"-D__BLST_PORTABLE__"});
    }

    lib.root_module.addCSourceFiles(.{ .root = upstream.path(""), .flags = flags.items, .files = &.{ "src/server.c", "build/assembly.S" } });
    lib.installHeadersDirectory(upstream.path("src"), "", .{});
    lib.root_module.link_libc = true;

    return lib;
}
