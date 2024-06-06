const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.13.0-dev.211+6a65561e3";

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

    const mod = b.addModule("zabi", .{ .root_source_file = b.path("src/root.zig"), .link_libc = true });

    addDependencies(b, mod, target, optimize);

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

    // Creates and runs the wallet client test runner.
    {
        const wallet = b.addExecutable(.{
            .name = "wallet_test",
            .root_source_file = b.path("src/wallet_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        addDependencies(b, &wallet.root_module, target, optimize);

        var wallet_run = b.addRunArtifact(wallet);
        wallet_run.has_side_effects = true;

        if (b.args) |args| wallet_run.addArgs(args);

        const wallet_step = b.step("wallet_test", "Run the wallet client tests");
        wallet_step.dependOn(&wallet_run.step);
    }
    // Creates and runs the rpc client http/s test runner.
    {
        const http = b.addExecutable(.{
            .name = "rpc_test",
            .root_source_file = b.path("src/rpc_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        addDependencies(b, &http.root_module, target, optimize);

        var http_run = b.addRunArtifact(http);
        http_run.has_side_effects = true;

        if (b.args) |args| http_run.addArgs(args);

        const http_step = b.step("rpc_test", "Run the http client tests");
        http_step.dependOn(&http_run.step);
    }

    // Build and run the http server if `zig build server` was ran
    buildHttpServer(b, target, optimize);

    // Build and run the ipc server if `zig build ipcserver` was ran
    buildIpcServer(b, target, optimize);

    // Build and run the ws server if `zig build wsserver` was ran
    buildWsServer(b, target, optimize);

    // Build and run coverage test runner if `zig build coverage` was ran
    buildAndRunConverage(b, target, optimize);
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
/// Builds and runs the IPC Server
fn buildIpcServer(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const ipc = b.addExecutable(.{
        .name = "ipc_server",
        .root_source_file = b.path("src/ipc_server.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addDependencies(b, &ipc.root_module, target, optimize);

    var ipc_run = b.addRunArtifact(ipc);
    ipc_run.has_side_effects = true;

    if (b.args) |args| ipc_run.addArgs(args);

    const ipc_step = b.step("ipcserver", "Run the ipc server");
    ipc_step.dependOn(&ipc_run.step);
}
/// Builds and runs the Ws Server
fn buildWsServer(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const ws = b.addExecutable(.{
        .name = "ws_server",
        .root_source_file = b.path("src/ws_server.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addDependencies(b, &ws.root_module, target, optimize);

    var ws_run = b.addRunArtifact(ws);
    ws_run.has_side_effects = true;

    if (b.args) |args| ws_run.addArgs(args);

    const ws_step = b.step("wsserver", "Run the ws server");
    ws_step.dependOn(&ws_run.step);
}
/// Builds and runs the Http Server
fn buildHttpServer(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const http = b.addExecutable(.{
        .name = "http_server",
        .root_source_file = b.path("src/rpc_server.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addDependencies(b, &http.root_module, target, optimize);

    var http_run = b.addRunArtifact(http);
    http_run.has_side_effects = true;

    if (b.args) |args| http_run.addArgs(args);

    const http_step = b.step("server", "Run the http server");
    http_step.dependOn(&http_run.step);
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
