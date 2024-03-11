const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.12.0-dev.3182+f3227598e";

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zabi", .{ .root_source_file = .{ .path = "src/root.zig" }, .link_libc = true });

    const coverage = b.option(bool, "generate_coverage", "Generate coverage data with kcov") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage_output_dir", "Output directory for coverage data") orelse b.pathJoin(&.{ b.install_prefix, "kcov" });

    addDependencies(b, mod, target, optimize);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .name = "zabi-tests",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    addDependencies(b, &lib_unit_tests.root_module, target, optimize);
    var run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    if (coverage) {
        const include = b.fmt("--include-pattern=/src", .{});
        const args = &[_]std.Build.Step.Run.Arg{ .{ .bytes = b.dupe("kcov") }, .{ .bytes = b.dupe("--collect-only") }, .{ .bytes = b.dupe(include) }, .{ .bytes = b.dupe(coverage_output_dir) } };

        // var tests_run = b.addRunArtifact(lib_unit_tests);
        run_lib_unit_tests.has_side_effects = true;
        run_lib_unit_tests.argv.insertSlice(0, args) catch @panic("OutOfMemory");
        // test_step.dependOn(&tests_run.step);
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Coverage build option with kcov
}

fn addDependencies(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const secp256k1_dep = b.dependency("secp256k1", .{
        .target = target,
        .optimize = optimize,
    });
    const c_kzg_4844_dep = b.dependency("c-kzg-4844", .{
        .target = target,
        .optimize = optimize,
    });
    const blst_dep = b.dependency("blst", .{
        .target = target,
        .optimize = optimize,
    });
    const ws = b.dependency("ws", .{ .target = target, .optimize = optimize });

    mod.addImport("secp256k1", secp256k1_dep.module("secp256k1"));
    mod.addImport("c-kzg-4844", c_kzg_4844_dep.module("c-kzg-4844"));
    mod.addImport("ws", ws.module("websocket"));
    mod.linkLibrary(secp256k1_dep.artifact("secp256k1"));
    mod.linkLibrary(c_kzg_4844_dep.artifact("c-kzg-4844"));
    mod.linkLibrary(blst_dep.artifact("blst"));
}
