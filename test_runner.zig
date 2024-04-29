const builtin = @import("builtin");
const std = @import("std");
const ws = @import("src/tests/clients/ws_server.zig");

const HttpClient = @import("src/tests/clients/server.zig");
const IpcServer = @import("src/tests/clients/ipc_server.zig");
const WsContext = @import("src/tests/clients/ws_server.zig").WsContext;
const WsHandler = @import("src/tests/clients/ws_server.zig").WsHandler;

const TestResults = struct {
    passed: u16 = 0,
    failed: u16 = 0,
    skipped: u16 = 0,
    leaked: u16 = 0,
};

pub const std_options: std.Options = .{
    .log_level = .warn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Starts the HTTP server
    var http_server: HttpClient = undefined;
    defer http_server.deinit();

    try http_server.init(.{
        .allocator = gpa.allocator(),
    });
    try http_server.listenLoopInSeperateThread(false);

    // Starts the WS server
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    try ws.listenLoopInSeperateThread(arena.allocator(), 69);

    // Starts the IPC server
    var ipc_server: IpcServer = undefined;
    defer ipc_server.deinit();

    try ipc_server.init(gpa.allocator(), .{});
    try ipc_server.listenLoopInSeperateThread();

    var results: TestResults = .{};
    const printer = TestsPrinter.init(std.io.getStdErr().writer());
    const test_funcs: []const std.builtin.TestFn = builtin.test_functions;

    printer.fmt("\r\x1b[0K", .{});
    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};
        const test_result = test_runner.func();

        printer.status("Running {s}...", .{test_runner.name});

        if (std.testing.allocator_instance.deinit() == .leak) {
            printer.status("leaked!\n", .{});
        }

        if (test_result) |_| {
            results.passed += 1;
            printer.status("passed!\n", .{});
        } else |err| switch (err) {
            error.SkipZigTest => {
                results.skipped += 1;
                printer.status("skipped!\n", .{});
            },
            else => {
                results.failed += 1;
                printer.status("failed!\n", .{});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                break;
            },
        }
    }

    const total_tests = results.passed + results.failed;

    printer.status("\nZABI Tests: {d} of {d} tests passed\n", .{ results.passed, total_tests });

    if (results.skipped > 0) {
        printer.status("\n{d} skipped tests\n", .{results.skipped});
    }

    if (results.leaked > 0) {
        printer.status("\n{d} leaked tests\n", .{results.leaked});
    }
}

const TestsPrinter = struct {
    writer: std.fs.File.Writer,

    fn init(writer: std.fs.File.Writer) TestsPrinter {
        return .{ .writer = writer };
    }

    fn fmt(self: TestsPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch unreachable;
    }

    fn status(self: TestsPrinter, comptime format: []const u8, args: anytype) void {
        // const color = switch (s) {
        // 	.pass => "\x1b[32m",
        // 	.fail => "\x1b[31m",
        // 	.skip => "\x1b[33m",
        // 	else => "",
        // };
        // const out = self.out;
        // out.writeAll(color) catch @panic("writeAll failed?!");
        std.fmt.format(self.writer, format, args) catch @panic("std.fmt.format failed?!");
        self.fmt("\x1b[0m", .{});
    }
};
