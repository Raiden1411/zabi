const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Anvil = @import("zabi-clients").Anvil;
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

/// Struct that will contain the test results.
const TestResults = struct {
    passed: u16 = 0,
    failed: u16 = 0,
    skipped: u16 = 0,
    leaked: u16 = 0,
};

/// ZABI's custom test runner with pretty printing.
const Runner = struct {
    const Self = @This();

    pub const empty: Self = .{
        .color_stream = .empty,
        .result = .{},
    };

    /// Color stream to write outputs
    color_stream: ColorWriterStream,
    /// Test results.
    result: TestResults,

    /// Connect to the anvil instance an reset it.
    pub fn resetAnvilInstance(self: *Self, allocator: Allocator) !void {
        startAnvilInstances(allocator) catch {
            self.color_stream.setNextColor(.red);
            try self.color_stream.writer().writeAll("error: ");

            self.color_stream.setNextColor(.bold);
            try self.color_stream.writer().writeAll("Failed to connect to anvil! Please ensure that it is running on port 6969\n");

            std.process.exit(1);
        };
    }
    /// Writes the test module name.
    pub fn writeModule(self: *Self, module: []const u8) ColorWriterStream.Error!void {
        try self.color_stream.writeModule(module);
    }
    /// Writes the test name.
    pub fn writeTestName(self: *Self, name: []const u8) ColorWriterStream.Error!void {
        try self.color_stream.writeTestName(name);
    }
    /// Write a success result to the stream
    pub fn writeSuccess(self: *Self) ColorWriterStream.Error!void {
        self.result.passed += 1;

        self.color_stream.setNextColor(.green);
        try self.color_stream.writer().writeAll("✓\n");
    }
    /// Write a skipped result to the stream
    pub fn writeSkipped(self: *Self) ColorWriterStream.Error!void {
        self.result.skipped += 1;

        self.color_stream.setNextColor(.yellow);
        try self.color_stream.writer().writeAll("skipped!\n");
    }
    /// Write a fail result to the stream
    pub fn writeFail(self: *Self) ColorWriterStream.Error!void {
        self.result.failed += 1;

        self.color_stream.setNextColor(.red);
        try self.color_stream.writer().writeAll("✘\n");
    }
    /// Write a skipped result to the stream
    pub fn writeLeaked(self: *Self) ColorWriterStream.Error!void {
        self.result.leaked += 1;

        self.color_stream.setNextColor(.blue);
        try self.color_stream.writer().writeAll("leaked!\n");
    }
    /// Pretty print the test results.
    pub fn writeResult(self: *Self) ColorWriterStream.Error!void {
        try self.color_stream.printResult(self.result);
    }
};

/// Custom writer that we use to write tests result and with specific tty colors.
fn ColorWriter(comptime UnderlayingWriter: type) type {
    return struct {
        /// Set of possible errors from this writer.
        const Error = UnderlayingWriter.Error || std.os.windows.SetConsoleTextAttributeError;

        const Writer = std.io.Writer(*Self, Error, write);
        const Self = @This();

        /// Initial empty state.
        pub const empty: Self = .{
            .color = .auto,
            .underlaying_writer = std.io.getStdErr().writer(),
            .next_color = .reset,
        };

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
        /// Writes the test module to the stream.
        pub fn writeModule(self: *Self, module: []const u8) !void {
            self.setNextColor(.yellow);
            try self.applyColor(self.next_color);
            try self.underlaying_writer.print(" |{s}|", .{module});
            try self.applyColor(.reset);
        }
        /// Writes the test name with ansi `dim`.
        pub fn writeTestName(self: *Self, test_name: []const u8) !void {
            self.setNextColor(.dim);
            try self.applyColor(self.next_color);
            try self.underlaying_writer.print(" Running {s}...", .{test_name});
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

/// Main test runner.
pub fn main() !void {
    const test_funcs: []const TestFn = builtin.test_functions;

    // Return if we don't have any tests.
    if (test_funcs.len <= 1)
        return;

    var runner: Runner = .empty;
    try runner.resetAnvilInstance(std.heap.page_allocator);

    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};

        if (std.mem.endsWith(u8, test_runner.name, ".test_0") or
            std.ascii.endsWithIgnoreCase(test_runner.name, "Root"))
            continue;

        var iter = std.mem.splitScalar(u8, test_runner.name, '.');

        try runner.writeModule(iter.first());
        try runner.writeTestName(iter.rest());

        if (test_runner.func()) |_| try runner.writeSuccess() else |err| switch (err) {
            error.SkipZigTest => try runner.writeSkipped(),
            else => {
                try runner.writeFail();
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpStackTrace(trace.*);

                break;
            },
        }

        if (std.testing.allocator_instance.deinit() == .leak)
            try runner.writeLeaked();
    }

    try runner.writeResult();
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
