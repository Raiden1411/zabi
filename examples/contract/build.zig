const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("contract_example", .{ .root_source_file = b.path("contract.zig") });

    const module = b.createModule(.{
        .root_source_file = b.path("contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "contract_example",
        .root_module = module,
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

    step.root_module.addImport("zabi", zabi.module("zabi"));

    // You can also use this
    // step.root_module.addImport("zabi-abi", zabi.module("zabi-abi"));
    // step.root_module.addImport("zabi-clients", zabi.module("zabi-clients"));
    // step.root_module.addImport("zabi-human", zabi.module("zabi-human"));
    // step.root_module.addImport("zabi-utils", zabi.module("zabi-utils"));
}
