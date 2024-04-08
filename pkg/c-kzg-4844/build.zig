const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("c-kzg-4844", .{ .root_source_file = .{ .path = "root.zig" } });

    const upstream = b.dependency("c-kzg-4844", .{});

    const lib = try buildKzg(b, upstream, target, optimize);
    module.addIncludePath(upstream.path("src"));

    if (target.query.isNative()) {
        const test_exe = b.addTest(.{
            .name = "test",
            .root_source_file = .{ .path = "root.zig" },
            .target = target,
            .optimize = optimize,
        });
        test_exe.linkLibrary(lib);

        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);

        b.installArtifact(test_exe);
    }
    b.installArtifact(lib);
}

fn buildKzg(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{ .name = "c-kzg-4844", .target = target, .optimize = optimize });
    const blst_dep = b.dependency("blst", .{
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibrary(blst_dep.artifact("blst"));

    lib.addIncludePath(upstream.path("src"));
    lib.addIncludePath(.{ .path = "" });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    lib.addCSourceFiles(.{ .root = upstream.path("."), .flags = flags.items, .files = &.{"src/c_kzg_4844.c"} });
    lib.installHeadersDirectory(upstream.path("src"), "", .{});
    lib.installHeadersDirectory(upstream.path(""), "", .{});
    lib.linkLibC();

    return lib;
}
