const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("secp256k1", .{ .root_source_file = .{ .path = "root.zig" } });

    const upstream = b.dependency("secp256k1", .{});
    const lib = try buildSecp256k1(b, upstream, target, optimize);
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

fn buildSecp256k1(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{ .name = "secp256k1", .target = target, .optimize = optimize });

    lib.addIncludePath(upstream.path("."));
    lib.addIncludePath(upstream.path("src"));

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{"-DENABLE_MODULE_RECOVERY=1"});
    lib.addCSourceFiles(.{ .dependency = upstream, .flags = flags.items, .files = &.{ "src/secp256k1.c", "src/precomputed_ecmult.c", "src/precomputed_ecmult_gen.c" } });
    lib.defineCMacro("USE_FIELD_10X26", "1");
    lib.defineCMacro("USE_SCALAR_8X32", "1");
    lib.defineCMacro("USE_ENDOMORPHISM", "1");
    lib.defineCMacro("USE_NUM_NONE", "1");
    lib.defineCMacro("USE_FIELD_INV_BUILTIN", "1");
    lib.defineCMacro("USE_SCALAR_INV_BUILTIN", "1");
    lib.installHeadersDirectoryOptions(.{ .source_dir = upstream.path("src"), .install_dir = .header, .install_subdir = "", .include_extensions = &.{".h"} });
    lib.installHeadersDirectoryOptions(.{ .source_dir = upstream.path("include"), .install_dir = .header, .install_subdir = "", .include_extensions = &.{".h"} });
    lib.linkLibC();

    return lib;
}
