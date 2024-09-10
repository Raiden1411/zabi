const env_parser = @import("src/utils/env_load.zig");
const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.14.0-dev.1349+6a21875dd";

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

    const mod = b.addModule("zabi", .{ .root_source_file = b.path("src/root.zig") });

    addDependencies(b, mod, target, optimize);

    const load_variables = b.option(bool, "load_variables", "Load enviroment variables from a \"env\" file.") orelse false;
    const env_file_path = b.option([]const u8, "env_file_path", "Specify the location of a env variables file") orelse ".env";

    const lib_unit_tests = b.addTest(.{
        .name = "zabi-tests",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = b.path("test_runner.zig"),
    });

    addDependencies(b, &lib_unit_tests.root_module, target, optimize);
    var run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    if (load_variables) {
        loadVariables(b, env_file_path, run_lib_unit_tests);
    }

    // Build and run coverage test runner if `zig build coverage` was ran
    buildAndRunConverage(b, target, optimize);

    // Build and generate docs for zabi. Uses the `doc_comments` spread across the codebase.
    // Always build in `ReleaseFast`.
    buildDocs(b, target);

    // Build the wasm file. Always build in `ReleaseSmall` on `wasm32-freestanding.
    buildWasm(b);
}
/// Adds zabi project dependencies.
fn addDependencies(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const c_kzg_4844_dep = b.dependency("c-kzg-4844", .{
        .target = target,
        .optimize = optimize,
    });
    const blst_dep = b.dependency("blst", .{
        .target = target,
        .optimize = optimize,
    });
    const ws = b.dependency("ws", .{ .target = target, .optimize = optimize });

    mod.addImport("c-kzg-4844", c_kzg_4844_dep.module("c-kzg-4844"));
    mod.addImport("ws", ws.module("websocket"));
    mod.linkLibrary(c_kzg_4844_dep.artifact("c-kzg-4844"));
    mod.linkLibrary(blst_dep.artifact("blst"));
}
/// Build the coverage test executable and run it
fn buildAndRunConverage(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib_unit_tests = b.addTest(.{
        .name = "zabi-tests-coverage",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = b.path("test_runner.zig"),
    });

    addDependencies(b, &lib_unit_tests.root_module, target, optimize);
    var run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("coverage", "Run unit tests with kcov coverage");
    test_step.dependOn(&run_lib_unit_tests.step);

    const coverage_output = b.makeTempPath();
    const include = b.fmt("--include-pattern=/src", .{});
    const args = &[_]std.Build.Step.Run.Arg{
        .{ .bytes = b.dupe("kcov") },
        .{ .bytes = b.dupe(include) },
        .{ .bytes = b.pathJoin(&.{ coverage_output, "output" }) },
    };

    var tests_run = b.addRunArtifact(lib_unit_tests);
    run_lib_unit_tests.has_side_effects = true;
    run_lib_unit_tests.argv.insertSlice(b.allocator, 0, args) catch @panic("OutOfMemory");

    const install_coverage = b.addInstallDirectory(.{
        .source_dir = .{ .cwd_relative = b.pathJoin(&.{ coverage_output, "output" }) },
        .install_dir = .{ .custom = "coverage" },
        .install_subdir = "",
    });

    test_step.dependOn(&tests_run.step);

    install_coverage.step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&install_coverage.step);
}
/// Builds and runs a runner to generate documentation based on the `doc_comments` tokens in the codebase.
fn buildDocs(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const docs = b.addExecutable(.{
        .name = "docs",
        .root_source_file = b.path("build/docs_generate.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });

    var docs_run = b.addRunArtifact(docs);
    docs_run.has_side_effects = true;

    const docs_step = b.step("docs", "Generate documentation based on the source code.");
    docs_step.dependOn(&docs_run.step);
}
/// Builds for wasm32-freestanding target.
fn buildWasm(b: *std.Build) void {
    const wasm_crosstarget: std.Target.Query = .{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            // We use this to explicitly request shared memory.
            .atomics,

            // Not explicitly used but compiler could use them if they want.
            .bulk_memory,
            .reference_types,
            .sign_ext,
        }),
    };

    const wasm = b.addExecutable(.{
        .name = "zabi_wasm",
        .root_source_file = b.path("src/root_wasm.zig"),
        .target = b.resolveTargetQuery(wasm_crosstarget),
        .optimize = .ReleaseSmall,
        .link_libc = true,
    });

    // Browser target
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    // Memory defaults.
    wasm.initial_memory = 65536 * 32;
    wasm.max_memory = 65536 * 65336;

    wasm.root_module.stack_protector = true;

    addDependencies(b, &wasm.root_module, b.resolveTargetQuery(wasm_crosstarget), .ReleaseSmall);

    const wasm_install = b.addInstallArtifact(wasm, .{});
    const wasm_step = b.step("wasm", "Build wasm library");

    wasm_step.dependOn(&wasm_install.step);
}
/// Loads enviroment variables from a `.env` file in case they aren't already present.
fn loadVariables(b: *std.Build, env_path: []const u8, exe: *std.Build.Step.Run) void {
    var file = std.fs.cwd().openFile(env_path, .{}) catch |err|
        std.debug.panic("Failed to read from {s} file! Error: {s}", .{ env_path, @errorName(err) });
    defer file.close();

    const source = file.readToEndAllocOptions(b.allocator, std.math.maxInt(u32), null, @alignOf(u8), 0) catch |err|
        std.debug.panic("Failed to read from {s} file! Error: {s}", .{ env_path, @errorName(err) });
    defer b.allocator.free(source);

    const env = exe.getEnvMap();

    env_parser.parseToEnviromentVariables(b.allocator, source, env) catch |err|
        std.debug.panic("Failed to load from {s} file! Error: {s}", .{ env_path, @errorName(err) });
}
