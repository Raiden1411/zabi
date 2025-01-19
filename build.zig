const env_parser = @import("src/utils/env_load.zig");
const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.14.0-dev.2547+77c63ac36";

/// Build zabi modules and test runners.
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

    // Build the library with all modules.
    const zabi = b.addModule("zabi", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDependencies(b, zabi, target, optimize);

    // Build the library with the abi module.
    const zabi_abi = b.addModule("zabi-abi", .{
        .root_source_file = b.path("src/abi/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the sol-ast module.
    const zabi_ast = b.addModule("zabi-ast", .{
        .root_source_file = b.path("src/ast/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the rpc-clients module.
    const zabi_clients = b.addModule("zabi-clients", .{
        .root_source_file = b.path("src/clients/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDependencies(b, zabi_clients, target, optimize);

    // Build the library with the crypto module.
    const zabi_crypto = b.addModule("zabi-crypto", .{
        .root_source_file = b.path("src/crypto/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDependencies(b, zabi_crypto, target, optimize);

    // Build the library with the decoding module.
    const zabi_decoding = b.addModule("zabi-decoding", .{
        .root_source_file = b.path("src/decoding/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the ens-client module.
    const zabi_ens = b.addModule("zabi-ens", .{
        .root_source_file = b.path("src/clients/ens/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the encoding module.
    const zabi_encoding = b.addModule("zabi-encoding", .{
        .root_source_file = b.path("src/encoding/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the evm module.
    const zabi_evm = b.addModule("zabi-evm", .{
        .root_source_file = b.path("src/evm/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the human-readable abi parsing module.
    const zabi_human = b.addModule("zabi-human", .{
        .root_source_file = b.path("src/human-readable/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the meta-programming module.
    const zabi_meta = b.addModule("zabi-meta", .{
        .root_source_file = b.path("src/meta/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the op-stack module.
    const zabi_op_stack = b.addModule("zabi-op-stack", .{
        .root_source_file = b.path("src/clients/optimism/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the library with the types module.
    const zabi_types = b.addModule("zabi-types", .{
        .root_source_file = b.path("src/types/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDependencies(b, zabi_types, target, optimize);

    // Build the library with the utils module.
    const zabi_utils = b.addModule("zabi-utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Adds the dependencies for `zabi` module.
    {
        zabi.addImport("zabi-abi", zabi_abi);
        zabi.addImport("zabi-ast", zabi_ast);
        zabi.addImport("zabi-clients", zabi_clients);
        zabi.addImport("zabi-crypto", zabi_crypto);
        zabi.addImport("zabi-decoding", zabi_decoding);
        zabi.addImport("zabi-encoding", zabi_encoding);
        zabi.addImport("zabi-ens", zabi_ens);
        zabi.addImport("zabi-evm", zabi_evm);
        zabi.addImport("zabi-human", zabi_human);
        zabi.addImport("zabi-meta", zabi_meta);
        zabi.addImport("zabi-op-stack", zabi_op_stack);
        zabi.addImport("zabi-types", zabi_types);
        zabi.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-abi` module.
    {
        zabi_abi.addImport("zabi-decoding", zabi_decoding);
        zabi_abi.addImport("zabi-encoding", zabi_encoding);
        zabi_abi.addImport("zabi-human", zabi_human);
        zabi_abi.addImport("zabi-meta", zabi_meta);
        zabi_abi.addImport("zabi-types", zabi_types);
    }

    // Adds the dependencies for `zabi-client` module.
    {
        zabi_clients.addImport("zabi-abi", zabi_abi);
        zabi_clients.addImport("zabi-crypto", zabi_crypto);
        zabi_clients.addImport("zabi-decoding", zabi_decoding);
        zabi_clients.addImport("zabi-encoding", zabi_encoding);
        zabi_clients.addImport("zabi-evm", zabi_evm);
        zabi_clients.addImport("zabi-meta", zabi_meta);
        zabi_clients.addImport("zabi-types", zabi_types);
        zabi_clients.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-crypto` module.
    {
        zabi_crypto.addImport("zabi-utils", zabi_utils);
        zabi_crypto.addImport("zabi-types", zabi_types);
    }

    // Adds the dependencies for `zabi-decoding` module.
    {
        zabi_decoding.addImport("zabi-meta", zabi_meta);
        zabi_decoding.addImport("zabi-types", zabi_types);
        zabi_decoding.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-encoding` module.
    {
        zabi_encoding.addImport("zabi-abi", zabi_abi);
        zabi_encoding.addImport("zabi-crypto", zabi_crypto);
        zabi_encoding.addImport("zabi-meta", zabi_meta);
        zabi_encoding.addImport("zabi-types", zabi_types);
        zabi_encoding.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-ens` module.
    {
        zabi_ens.addImport("zabi-abi", zabi_abi);
        zabi_ens.addImport("zabi-clients", zabi_clients);
        zabi_ens.addImport("zabi-decoding", zabi_decoding);
        zabi_ens.addImport("zabi-encoding", zabi_encoding);
        zabi_ens.addImport("zabi-types", zabi_types);
        zabi_ens.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-evm` module.
    {
        zabi_evm.addImport("zabi-utils", zabi_utils);
        zabi_evm.addImport("zabi-meta", zabi_meta);
        zabi_evm.addImport("zabi-types", zabi_types);
    }

    // Adds the dependencies for `zabi-human` module.
    {
        zabi_human.addImport("zabi-abi", zabi_abi);
        zabi_human.addImport("zabi-meta", zabi_meta);
    }

    // Adds the dependencies for `zabi-meta` module.
    {
        zabi_meta.addImport("zabi-abi", zabi_abi);
        zabi_meta.addImport("zabi-types", zabi_types);
    }

    // Adds the dependencies for `zabi-op-stack` module.
    {
        zabi_op_stack.addImport("zabi-abi", zabi_abi);
        zabi_op_stack.addImport("zabi-clients", zabi_clients);
        zabi_op_stack.addImport("zabi-crypto", zabi_crypto);
        zabi_op_stack.addImport("zabi-decoding", zabi_decoding);
        zabi_op_stack.addImport("zabi-encoding", zabi_encoding);
        zabi_op_stack.addImport("zabi-meta", zabi_meta);
        zabi_op_stack.addImport("zabi-types", zabi_types);
        zabi_op_stack.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-types` module.
    {
        zabi_types.addImport("zabi-abi", zabi_abi);
        zabi_types.addImport("zabi-meta", zabi_meta);
        zabi_types.addImport("zabi-utils", zabi_utils);
    }

    // Adds the dependencies for `zabi-utils` module.
    {
        zabi_utils.addImport("zabi-meta", zabi_meta);
        zabi_utils.addImport("zabi-types", zabi_types);
    }

    // Runs the tests or coverage steps.
    buildTestOrCoverage(b, target, optimize, zabi);

    // Runs the benchmark
    buildBenchmark(b, target, optimize, zabi);

    // Builds the examples.
    buildExamples(b, target, optimize, zabi);

    // Build and generate docs for zabi. Uses the `doc_comments` spread across the codebase.
    // Always build in `ReleaseFast`.
    buildDocs(b, target);

    // Build the wasm file. Always build in `ReleaseSmall` on `wasm32-freestanding`.
    buildWasm(b, zabi);
}

// Builds and runs the main tests of zabi or the coverage from kcov.
fn buildTestOrCoverage(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
) void {
    const load_variables = b.option(bool, "load_variables", "Load enviroment variables from a \"env\" file.") orelse false;
    const env_file_path = b.option([]const u8, "env_file_path", "Specify the location of a env variables file") orelse ".env";

    // Builds and runs the main tests of zabi.
    {
        const lib_unit_tests = b.addTest(.{
            .name = "zabi-tests",
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .test_runner = b.path("build/test_runner.zig"),
        });
        lib_unit_tests.root_module.addImport("zabi", module);
        addDependencies(b, lib_unit_tests.root_module, target, optimize);

        var run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);

        if (load_variables)
            loadVariables(b, env_file_path, run_lib_unit_tests);
    }

    // Build and run coverage test runner if `zig build coverage` was ran
    {
        const coverage_lib_unit_tests = b.addTest(.{
            .name = "zabi-tests-coverage",
            .root_source_file = b.path("tests/root_benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .test_runner = b.path("build/test_runner.zig"),
        });
        coverage_lib_unit_tests.root_module.addImport("zabi", module);
        const test_step_coverage = b.step("coverage", "Run unit tests with kcov coverage");

        const kcov_collect = std.Build.Step.Run.create(b, "collect coverage");
        kcov_collect.rename_step_with_output_arg = false;

        if (load_variables)
            loadVariables(b, env_file_path, kcov_collect);

        kcov_collect.addArgs(&.{
            "kcov",
            "--clean",
        });
        kcov_collect.addPrefixedDirectoryArg("--include-pattern=", b.path("src"));
        _ = kcov_collect.addOutputFileArg(coverage_lib_unit_tests.name);
        kcov_collect.addArtifactArg(coverage_lib_unit_tests);
        kcov_collect.enableTestRunnerMode();

        const install_coverage = b.addInstallDirectory(.{
            .source_dir = kcov_collect.addOutputFileArg("."),
            .install_dir = .{ .custom = "coverage" },
            .install_subdir = "",
        });
        test_step_coverage.dependOn(&install_coverage.step);
    }
}

/// Build the wasm binary.
fn buildWasm(b: *std.Build, module: *std.Build.Module) void {
    const wasm_crosstarget: std.Target.Query = .{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
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
    });
    wasm.root_module.addImport("zabi", module);

    // Browser target
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    // Memory defaults.
    wasm.initial_memory = 65536 * 32;
    wasm.max_memory = 65536 * 65336;

    wasm.root_module.stack_protector = true;

    const wasm_install = b.addInstallArtifact(wasm, .{});
    const wasm_step = b.step("wasm", "Build wasm library");

    wasm_step.dependOn(&wasm_install.step);
}

/// Adds zabi project dependencies.
fn addDependencies(
    b: *std.Build,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const c_kzg_4844_dep = b.dependency("c-kzg-4844", .{
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("c-kzg-4844", c_kzg_4844_dep.module("c-kzg-4844"));
    mod.linkLibrary(c_kzg_4844_dep.artifact("c-kzg-4844"));
}
/// Builds and runs the benchmarks
fn buildBenchmark(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dependency: *std.Build.Module,
) void {
    const bench = b.addTest(.{
        .name = "benchmark",
        .root_source_file = b.path("tests/root_benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = b.path("build/benchmark.zig"),
    });
    bench.root_module.addImport("zabi", dependency);
    addDependencies(b, bench.root_module, target, optimize);

    var bench_run = b.addRunArtifact(bench);

    const bench_step = b.step("bench", "Benchmark zabi");
    bench_step.dependOn(&bench_run.step);
}
/// Builds all of zabi examples so that we can leverage this also for CI
fn buildExamples(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dependency: *std.Build.Module,
) void {
    const examples_step = b.step("examples", "Build all of zabi's examples");

    const examples: []const []const u8 = &.{
        "examples/watch/watch.zig",
        "examples/watch/logs.zig",
        "examples/transfer/transfer.zig",
        "examples/interpreter/interpreter.zig",
        "examples/block_explorer/explorer.zig",
        "examples/wallet/wallet.zig",
        "examples/contract/contract.zig",
        "examples/autobahn/autobahn.zig",
    };

    inline for (examples) |example| {
        const index = std.mem.lastIndexOfScalar(u8, example, '/').?;
        const example_exe = b.addExecutable(.{
            // example name -> filename - .zig extension
            .name = example[index + 1 .. example.len - 4],
            .root_source_file = b.path(example),
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("zabi", dependency);
        addDependencies(b, example_exe.root_module, target, optimize);

        var install_artifact = b.addInstallArtifact(example_exe, .{});
        examples_step.dependOn(&install_artifact.step);
    }
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
