const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.12.0-dev.1767+1e42a3de89";

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

    _ = b.addModule("zabi", .{ .source_file = .{ .path = "src/root.zig" } });

    const coverage = b.option(bool, "generate_coverage", "Generate coverage data with kcov") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage_output_dir", "Output directory for coverage data") orelse b.pathJoin(&.{ b.install_prefix, "kcov" });

    const lib = b.addStaticLibrary(.{
        .name = "zabi",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    // addDeps(b, lib);
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .name = "zabi-tests",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Coverage build option with kcov
    if (coverage) {
        const include = b.fmt("--include-pattern=/src", .{});
        const args = &[_]std.build.RunStep.Arg{ .{ .bytes = b.dupe("kcov") }, .{ .bytes = b.dupe("--collect-only") }, .{ .bytes = b.dupe(include) }, .{ .bytes = b.dupe(coverage_output_dir) } };

        var tests_run = b.addRunArtifact(lib_unit_tests);
        tests_run.has_side_effects = true;
        tests_run.argv.insertSlice(0, args) catch @panic("OutOfMemory");

        var merge = std.build.RunStep.create(b, "merge kcov");
        merge.has_side_effects = true;
        merge.addArgs(&.{
            "kcov",
            "--merge",
            coverage_output_dir,
            b.pathJoin(&.{ coverage_output_dir, "test" }),
        });
        merge.step.dependOn(&b.addRemoveDirTree(coverage_output_dir).step);
        merge.step.dependOn(&tests_run.step);
        test_step.dependOn(&merge.step);
    }
}
