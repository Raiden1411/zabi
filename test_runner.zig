const builtin = @import("builtin");
const std = @import("std");

const Anvil = @import("src/clients/Anvil.zig");
const FileWriter = std.fs.File.Writer;
const Options = std.Options;
const TerminalColors = std.io.tty.Color;
const TestFn = std.builtin.TestFn;
const ZigColor = std.zig.Color;

pub const std_options: Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var results: TestResults = .{};
    const printer = TestsPrinter.init(std.io.getStdErr().writer());

    startAnvilInstances(std.heap.page_allocator) catch {
        try printer.writeAll("error: ", .bright_red);
        try printer.writeAll("Failed to connect to anvil! Please ensure that it is running on port 6969\n", .bold);

        std.process.exit(1);
    };

    const test_funcs: []const TestFn = builtin.test_functions;

    // Return if we don't have any tests.
    if (test_funcs.len <= 1)
        return;

    var module: Modules = .abi;

    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};
        const test_result = test_runner.func();

        if (std.mem.endsWith(u8, test_runner.name, ".test_0"))
            continue;

        if (std.mem.endsWith(u8, test_runner.name, "Root"))
            continue;

        var iter = std.mem.splitAny(u8, test_runner.name, ".");
        _ = iter.next();
        const module_name = iter.next().?;

        const current_module = std.meta.stringToEnum(Modules, module_name) orelse module;

        if (current_module != module) {
            module = current_module;
            try printer.writeBoarder(module);
        }

        const submodule = iter.next().?;
        try printer.print(" |{s}|", .{submodule}, .yellow);

        const name = name_blk: {
            while (iter.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    _ = iter.next();
                    const rest = iter.rest();
                    break :name_blk if (rest.len > 0) rest else test_runner.name;
                }
            } else break :name_blk test_runner.name;
        };

        try printer.print("{s}Running {s}...", .{ " " ** 2, name }, .dim);

        if (test_result) |_| {
            results.passed += 1;
            try printer.writeAll("✓\n", .green);
        } else |err| switch (err) {
            error.SkipZigTest => {
                results.skipped += 1;
                try printer.writeAll("skipped!\n", .white);
            },
            else => {
                results.failed += 1;
                try printer.writeAll("✘\n", .red);
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                break;
            },
        }

        if (std.testing.allocator_instance.deinit() == .leak) {
            results.leaked += 1;
            try printer.writeAll("leaked!\n", .blue);
        }
    }

    try printer.printResult(results);
}

/// Struct that will contain the test results.
const TestResults = struct {
    passed: u16 = 0,
    failed: u16 = 0,
    skipped: u16 = 0,
    leaked: u16 = 0,
};

/// Enum of the possible test modules.
const Modules = enum {
    abi,
    ast,
    clients,
    crypto,
    encoding,
    evm,
    decoding,
    @"human-readable",
    meta,
    utils,
};

/// Custom printer that we use to write tests result and with specific tty colors.
const TestsPrinter = struct {
    /// stderr writer.
    writer: FileWriter,
    /// Colors config to use in the terminal
    color: ZigColor,

    pub const BORDER = "=" ** 80;
    pub const PADDING = " " ** 35;

    /// Sets the initial state.
    fn init(writer: FileWriter) TestsPrinter {
        return .{
            .writer = writer,
            .color = .auto,
        };
    }

    /// Sets the terminal color.
    fn setColor(self: TestsPrinter, color: TerminalColors) !void {
        try self.color.get_tty_conf().setColor(self.writer, color);
    }
    /// Writes the board in the test runner.
    fn writeBoarder(self: TestsPrinter, module: Modules) !void {
        try self.setColor(.green);
        try self.writer.print("\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, @tagName(module), BORDER });
    }
    /// Same as FileWriter `writeAll` but with color config
    fn writeAll(self: TestsPrinter, bytes: []const u8, color: TerminalColors) !void {
        try self.setColor(color);
        try self.writer.writeAll(bytes);
        try self.setColor(.reset);
    }
    /// Same as FileWriter `print` but with color config
    fn print(self: TestsPrinter, comptime format: []const u8, args: anytype, color: TerminalColors) !void {
        try self.setColor(color);
        try self.writer.print(format, args);
        try self.setColor(.reset);
    }
    /// Prints all of the test results.
    fn printResult(self: TestsPrinter, results: TestResults) !void {
        try self.writer.writeAll("\n    ZABI Tests: ");
        try self.print("{d} passed\n", .{results.passed}, .green);

        try self.writer.writeAll("    ZABI Tests: ");
        try self.print("{d} failed\n", .{results.failed}, .red);

        try self.writer.writeAll("    ZABI Tests: ");
        try self.print("{d} skipped\n", .{results.skipped}, .yellow);

        try self.writer.writeAll("    ZABI Tests: ");
        try self.print("{d} leaked\n", .{results.leaked}, .blue);
    }
};

/// Connects to the anvil instance. Fails if it cant.
fn startAnvilInstances(allocator: std.mem.Allocator) !void {
    const mainnet = try std.process.getEnvVarOwned(allocator, "ANVIL_FORK_URL");
    defer allocator.free(mainnet);

    var anvil: Anvil = undefined;
    defer anvil.deinit();

    anvil.initClient(.{ .allocator = allocator });

    try anvil.reset(.{ .forking = .{
        .jsonRpcUrl = mainnet,
        .blockNumber = 19062632,
    } });
}
