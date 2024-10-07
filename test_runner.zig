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

/// Wraps the stderr with our color stream.
const ColorWriterStream = ColorWriter(@TypeOf(std.io.getStdErr().writer()));

pub fn main() !void {
    var results: TestResults = .{};

    var printer: ColorWriterStream = .{
        .color = .auto,
        .underlaying_writer = std.io.getStdErr().writer(),
        .next_color = .reset,
    };

    startAnvilInstances(std.heap.page_allocator) catch {
        printer.setNextColor(.red);
        try printer.writer().writeAll("error: ");

        printer.setNextColor(.bold);
        try printer.writer().writeAll("Failed to connect to anvil! Please ensure that it is running on port 6969\n");

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

        printer.setNextColor(.yellow);
        try printer.writer().print(" |{s}|", .{submodule});

        const name = name_blk: {
            while (iter.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    _ = iter.next();
                    const rest = iter.rest();
                    break :name_blk if (rest.len > 0) rest else test_runner.name;
                }
            } else break :name_blk test_runner.name;
        };

        printer.setNextColor(.dim);
        try printer.writer().print("{s}Running {s}...", .{ " " ** 2, name });

        if (test_result) |_| {
            results.passed += 1;

            printer.setNextColor(.green);
            try printer.writer().writeAll("✓\n");
        } else |err| switch (err) {
            error.SkipZigTest => {
                results.skipped += 1;

                printer.setNextColor(.white);
                try printer.writer().writeAll("skipped!\n");
            },
            else => {
                results.failed += 1;

                printer.setNextColor(.red);
                try printer.writer().writeAll("✘\n");
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                break;
            },
        }

        if (std.testing.allocator_instance.deinit() == .leak) {
            results.leaked += 1;

            printer.setNextColor(.blue);
            try printer.writer().writeAll("leaked!\n");
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

/// Custom writer that we use to write tests result and with specific tty colors.
fn ColorWriter(comptime UnderlayingWriter: type) type {
    return struct {
        /// Set of possible errors from this writer.
        const Error = UnderlayingWriter.Error || std.os.windows.SetConsoleTextAttributeError;

        const Writer = std.io.Writer(*Self, Error, write);
        const Self = @This();

        pub const BORDER = "=" ** 80;
        pub const PADDING = " " ** 35;

        /// The writer that we will use to write to.
        underlaying_writer: UnderlayingWriter,
        /// Zig color tty config.
        color: ZigColor,
        /// Next tty color to apply in the stream.
        next_color: TerminalColors,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
        /// Write function that will write to the stream with the `next_color`.
        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyColor(self.next_color);
            try self.writeNoColor(bytes);
            try self.applyColor(.reset);

            return bytes.len;
        }
        /// Writes the test boarder with the specified module.
        pub fn writeBoarder(self: *Self, module: Modules) Error!void {
            try self.applyColor(.green);
            try self.underlaying_writer.print("\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, @tagName(module), BORDER });
            try self.applyColor(.reset);
        }
        /// Sets the next color in the stream
        pub fn setNextColor(self: *Self, next: TerminalColors) void {
            self.next_color = next;
        }
        /// Writes the next color to the stream.
        pub fn applyColor(self: *Self, color: TerminalColors) Error!void {
            try self.color.renderOptions().ttyconf.setColor(self.underlaying_writer, color);
        }
        /// Writes to the stream without colors.
        pub fn writeNoColor(self: *Self, bytes: []const u8) UnderlayingWriter.Error!void {
            if (bytes.len == 0)
                return;

            try self.underlaying_writer.writeAll(bytes);
        }
        /// Prints all of the test results.
        pub fn printResult(self: *Self, results: TestResults) Error!void {
            try self.underlaying_writer.writeAll("\n    ZABI Tests: ");
            try self.applyColor(.green);
            try self.underlaying_writer.print("{d} passed\n", .{results.passed});
            try self.applyColor(.reset);

            try self.underlaying_writer.writeAll("    ZABI Tests: ");
            try self.applyColor(.red);
            try self.underlaying_writer.print("{d} failed\n", .{results.failed});
            try self.applyColor(.reset);

            try self.underlaying_writer.writeAll("    ZABI Tests: ");
            try self.applyColor(.yellow);
            try self.underlaying_writer.print("{d} skipped\n", .{results.skipped});
            try self.applyColor(.reset);

            try self.underlaying_writer.writeAll("    ZABI Tests: ");
            try self.applyColor(.blue);
            try self.underlaying_writer.print("{d} leaked\n", .{results.leaked});
            try self.applyColor(.reset);
        }
    };
}

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
