const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("c_kzg_4844", .{ .root_source_file = b.path("root.zig") });

    const upstream = b.dependency("c_kzg_4844", .{});

    const lib = try buildKzg(b, upstream, target, optimize);
    module.addIncludePath(upstream.path("src"));

    if (target.query.isNative()) {
        const mod = b.createModule(.{
            .root_source_file = b.path("root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const test_exe = b.addTest(.{
            .name = "test",
            .root_module = mod,
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
    const mod = b.createModule(.{ .optimize = optimize, .target = target });
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "c_kzg_4844",
        .root_module = mod,
    });
    const blst_dep = b.dependency("blst", .{
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibrary(blst_dep.artifact("blst"));

    lib.addIncludePath(upstream.path("src"));
    lib.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "" } });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    lib.addCSourceFiles(.{ .root = upstream.path("."), .flags = flags.items, .files = &.{"src/c_kzg_4844.c"} });
    lib.installHeader(b.path("blst.h"), "blst.h");
    lib.installHeader(b.path("blst_aux.h"), "blst_aux.h");
    lib.installHeadersDirectory(upstream.path("src"), "", .{});
    lib.linkLibC();

    return lib;
}
