const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("benchmark", .{ .root_source_file = .{ .path = "benchmark.zig" } });

    const exe = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = .{ .path = "benchmark.zig" },
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe);
    b.installArtifact(exe);

    const runner = b.addRunArtifact(exe);
    const step = b.step("bench", "Benchmark zabi");
    step.dependOn(&runner.step);
}

fn addDependencies(b: *std.Build, step: *std.Build.Step.Compile) void {
    const target = step.root_module.resolved_target.?;
    const optimize = step.root_module.optimize.?;

    const zabi = b.dependency("zabi", .{
        .target = target,
        .optimize = optimize,
    });

    step.root_module.addImport("zabi", zabi.module("zabi"));
}
