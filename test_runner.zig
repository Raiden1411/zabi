const builtin = @import("builtin");
const std = @import("std");
const ws = @import("src/tests/clients/ws_server.zig");

const Anvil = @import("src/tests/Anvil.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const HttpClient = @import("src/tests/clients/server.zig");
const IpcServer = @import("src/tests/clients/ipc_server.zig");
const TestFn = std.builtin.TestFn;
const WsContext = @import("src/tests/clients/ws_server.zig").WsContext;
const WsHandler = @import("src/tests/clients/ws_server.zig").WsHandler;

const TestResults = struct {
    passed: u16 = 0,
    failed: u16 = 0,
    skipped: u16 = 0,
    leaked: u16 = 0,
};

pub const std_options: std.Options = .{
    .log_level = .info,
};

const BORDER = "=" ** 80;
const PADDING = " " ** 35;

const Modules = enum {
    abi,
    clients,
    crypto,
    encoding,
    evm,
    decoding,
    @"human-readable",
    meta,
    utils,
};

pub fn main() !void {
    const test_funcs: []const TestFn = builtin.test_functions;

    // Return if we don't have any tests.
    if (test_funcs.len <= 1)
        return;

    const allocator = std.heap.page_allocator;

    var anvil: Anvil = undefined;
    defer anvil.killProcessAndDeinit();

    try anvil.initProcess(.{
        .alloc = allocator,
        .fork_url = "https://eth-mainnet.g.alchemy.com/v2/EYebpRd8FEJ0WYXQ3Afl6O85T8vo6XvO",
        .localhost = "http://localhost:6969/",
    });

    // // Starts the HTTP server
    // var http_server: HttpClient = undefined;
    // defer http_server.deinit();
    //
    // try http_server.init(.{
    //     .allocator = allocator,
    // });
    // try http_server.listenLoopInSeperateThread(false);

    // Starts the IPC server
    var ipc_server: IpcServer = undefined;
    defer ipc_server.deinit();

    try ipc_server.init(allocator, .{});
    try ipc_server.listenLoopInSeperateThread();

    // // Starts the WS server
    // var arena = ArenaAllocator.init(allocator);
    // defer arena.deinit();
    //
    // try ws.listenLoopInSeperateThread(arena.allocator(), 69);

    var results: TestResults = .{};
    const printer = TestsPrinter.init(std.io.getStdErr().writer());

    var module: Modules = .abi;

    printer.fmt("\r\x1b[0K", .{});
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, @tagName(module), BORDER });
    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};
        const test_result = test_runner.func();

        if (std.mem.endsWith(u8, test_runner.name, ".test_0")) {
            continue;
        }

        var iter = std.mem.splitScalar(u8, test_runner.name, '.');
        const module_name = iter.next().?;

        const current_module = std.meta.stringToEnum(Modules, module_name);

        if (current_module) |c_module| {
            if (c_module != module) {
                module = c_module;
                printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, @tagName(module), BORDER });
            }
        }

        const submodule = iter.next().?;
        printer.print("\x1b[1;33m |{s}|", .{submodule});

        const name = name_blk: {
            while (iter.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    const rest = iter.rest();
                    break :name_blk if (rest.len > 0) rest else test_runner.name;
                }
            } else break :name_blk test_runner.name;
        };

        printer.print("\x1b[2m{s}Running {s}...", .{ " " ** 2, name });

        if (test_result) |_| {
            results.passed += 1;
            printer.print("\x1b[1;32m✓\n", .{});
        } else |err| switch (err) {
            error.SkipZigTest => {
                results.skipped += 1;
                printer.print("skipped!\n", .{});
            },
            else => {
                results.failed += 1;
                printer.print("\x1b[1;31m✘\n", .{});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            },
        }

        if (std.testing.allocator_instance.deinit() == .leak) {
            printer.print("leaked!\n", .{});
        }
    }

    printer.print("\n{s}ZABI Tests: \x1b[1;32m{d} passed\n", .{ " " ** 4, results.passed });
    printer.print("{s}ZABI Tests: \x1b[1;31m{d} failed\n", .{ " " ** 4, results.failed });
    printer.print("{s}ZABI Tests: \x1b[1;33m{d} skipped\n", .{ " " ** 4, results.skipped });
    printer.print("{s}ZABI Tests: \x1b[1;34m{d} leaked\n", .{ " " ** 4, results.leaked });
}

const TestsPrinter = struct {
    writer: std.fs.File.Writer,

    fn init(writer: std.fs.File.Writer) TestsPrinter {
        return .{ .writer = writer };
    }

    fn fmt(self: TestsPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch unreachable;
    }

    fn print(self: TestsPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch @panic("Format failed!");
        self.fmt("\x1b[0m", .{});
    }
};
