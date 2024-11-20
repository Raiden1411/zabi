const builtin = @import("builtin");
const color = @import("color.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Anvil = @import("zabi").clients.Anvil;
const ColorWriter = color.ColorWriter;
const FileWriter = std.fs.File.Writer;
const Options = std.Options;
const TestFn = std.builtin.TestFn;

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
            self.color_stream.setNextColor(.yellow);
            try self.color_stream.writer().writeAll("warning: ");
            self.color_stream.setNextColor(.bold);
            try self.color_stream.writer().writeAll("Failed to connect to anvil! Please ensure that it is running on port 6969\n");

            self.color_stream.setNextColor(.yellow);
            try self.color_stream.writer().writeAll("warning: ");
            self.color_stream.setNextColor(.bold);
            try self.color_stream.writer().writeAll("Test will run but client tests might fail\n\n");
        };
    }
    /// Writes the test module name.
    pub fn writeModule(self: *Self, module: []const u8) ColorWriterStream.Error!void {
        self.color_stream.setNextColor(.yellow);
        try self.color_stream.writer().print(" |{s}|", .{module});
        try self.color_stream.applyReset();
    }
    /// Writes the test name.
    pub fn writeTestName(self: *Self, name: []const u8) ColorWriterStream.Error!void {
        self.color_stream.setNextColor(.dim);

        const index = std.mem.lastIndexOf(u8, name, "test.") orelse unreachable;

        try self.color_stream.writer().print(" Running {s}...", .{name[index + 5 ..]});
        try self.color_stream.applyReset();
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
        self.color_stream.setNextColor(.reset);
        try self.color_stream.writer().writeAll("\n    ZABI Tests: ");
        self.color_stream.setNextColor(.green);
        try self.color_stream.writer().print("{d} passed\n", .{self.result.passed});
        self.color_stream.setNextColor(.reset);

        try self.color_stream.writer().writeAll("    ZABI Tests: ");
        self.color_stream.setNextColor(.red);
        try self.color_stream.writer().print("{d} failed\n", .{self.result.failed});
        self.color_stream.setNextColor(.reset);

        try self.color_stream.writer().writeAll("    ZABI Tests: ");
        self.color_stream.setNextColor(.yellow);
        try self.color_stream.writer().print("{d} skipped\n", .{self.result.skipped});
        self.color_stream.setNextColor(.reset);

        try self.color_stream.writer().writeAll("    ZABI Tests: ");
        self.color_stream.setNextColor(.blue);
        try self.color_stream.writer().print("{d} leaked\n", .{self.result.leaked});
        self.color_stream.setNextColor(.reset);
    }
};

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
