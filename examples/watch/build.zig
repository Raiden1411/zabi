const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("watch_example", .{ .root_source_file = b.path("watch.zig") });
    _ = b.addModule("logs_example", .{ .root_source_file = b.path("logs.zig") });

    const exe = b.addExecutable(.{
        .name = "watch_example",
        .root_source_file = b.path("watch.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe);
    b.installArtifact(exe);

    const exe_logs = b.addExecutable(.{
        .name = "logs_example",
        .root_source_file = b.path("logs.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe_logs);
    b.installArtifact(exe_logs);
}

fn addDependencies(b: *std.Build, step: *std.Build.Step.Compile) void {
    const target = step.root_module.resolved_target.?;
    const optimize = step.root_module.optimize.?;

    const zabi = b.dependency("zabi", .{
        .target = target,
        .optimize = optimize,
    });

    step.root_module.addImport("zabi-decoding", zabi.module("zabi-decoding"));
    step.root_module.addImport("zabi-clients", zabi.module("zabi-clients"));
    step.root_module.addImport("zabi-utils", zabi.module("zabi-utils"));
}
