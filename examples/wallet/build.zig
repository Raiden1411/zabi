const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("wallet_example", .{ .root_source_file = b.path("wallet.zig") });

    const exe = b.addExecutable(.{
        .name = "wallet_example",
        .root_source_file = b.path("wallet.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe);
    b.installArtifact(exe);
}

fn addDependencies(b: *std.Build, step: *std.Build.Step.Compile) void {
    const target = step.root_module.resolved_target.?;
    const optimize = step.root_module.optimize.?;

    const zabi = b.dependency("zabi", .{
        .target = target,
        .optimize = optimize,
    });

    step.root_module.addImport("zabi-clients", zabi.module("zabi-clients"));
    step.root_module.addImport("zabi-utils", zabi.module("zabi-utils"));
}
