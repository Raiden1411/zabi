const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zig-abi", .{ .source_file = .{ .path = "src/main.zig" } });

    const lib = b.addStaticLibrary(.{
        .name = "zig-abi",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // addDeps(b, lib);
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

// pub fn addDeps(b: *std.Build, step: *std.Build.CompileStep) void {
//     const ziglyph_dep = b.dependency("ziglyph", .{
//         .target = step.target,
//         .optimize = step.optimize,
//     });
//     step.addModule("ziglyph", ziglyph_dep.module("ziglyph"));
// }
