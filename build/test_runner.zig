const builtin = @import("builtin");
const color = @import("color.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Anvil = @import("zabi").clients.Anvil;
const ColorWriterStream = color.ColorWriter;
const FileWriter = std.fs.File.Writer;
const Options = std.Options;
const TestFn = std.builtin.TestFn;

pub const std_options: Options = .{
    .log_level = .info,
};

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

    /// Color stream to write outputs
    color_stream: ColorWriterStream,
    /// Test results.
    result: TestResults,

    /// Connect to the anvil instance an reset it.
    pub fn resetAnvilInstance(self: *Self, allocator: Allocator, env: *std.process.Environ.Map) !void {
        startAnvilInstances(allocator, env) catch {
            var writer = &self.color_stream.writer;

            self.color_stream.setNextColor(.yellow);
            try writer.writeAll("warning: ");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll("Failed to connect to anvil! Please ensure that it is running on port 6969\n");

            self.color_stream.setNextColor(.yellow);
            try writer.writeAll("warning: ");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll("Test will run but client tests might fail\n\n");
        };
    }
    /// Writes the test module name.
    pub fn writeModuleName(self: *Self, module: []const u8) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.color_stream.setNextColor(.yellow);

        try writer.print(" |{s}|", .{module});
    }
    /// Writes the test object name.
    pub fn writeFileName(self: *Self, object: []const u8) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.color_stream.setNextColor(.blue);

        try writer.print("|{s}|", .{object});
    }
    /// Writes the test name.
    pub fn writeTestName(self: *Self, name: []const u8) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.color_stream.setNextColor(.dim);

        const index = std.mem.lastIndexOf(u8, name, "test.") orelse unreachable;

        try writer.print(" Running {s}...", .{name[index + 5 ..]});
    }
    /// Write a success result to the stream
    pub fn writeSuccess(self: *Self, elapsed_ns: u64) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.result.passed += 1;

        self.color_stream.setNextColor(.green);
        try writer.writeAll("✓ ");
        try self.writeElapsed(elapsed_ns);
        try writer.writeByte('\n');
    }
    /// Write a skipped result to the stream
    pub fn writeSkipped(self: *Self, elapsed_ns: u64) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.result.skipped += 1;

        self.color_stream.setNextColor(.yellow);
        try writer.writeAll("skipped ");
        try self.writeElapsed(elapsed_ns);
        try writer.writeByte('\n');
    }
    /// Write a fail result to the stream
    pub fn writeFail(self: *Self, elapsed_ns: u64) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.result.failed += 1;

        self.color_stream.setNextColor(.red);
        try writer.writeAll("✘ ");
        try self.writeElapsed(elapsed_ns);
        try writer.writeByte('\n');
    }
    /// Write a skipped result to the stream
    pub fn writeLeaked(self: *Self, elapsed_ns: u64) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        self.result.leaked += 1;

        self.color_stream.setNextColor(.blue);
        try writer.writeAll("leaked ");
        try self.writeElapsed(elapsed_ns);
        try writer.writeByte('\n');
    }
    /// Writes elapsed time in human-readable format (ns, us, ms, s)
    fn writeElapsed(self: *Self, elapsed_ns: u64) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;
        const elapsed: f64 = @floatFromInt(elapsed_ns);
        var num: f64 = undefined;
        var unit: []const u8 = undefined;

        if (elapsed >= 1_000_000_000) {
            num = elapsed / 1_000_000_000;
            unit = "s";
        } else if (elapsed >= 1_000_000) {
            num = elapsed / 1_000_000;
            unit = "ms";
        } else if (elapsed >= 1_000) {
            num = elapsed / 1_000;
            unit = "us";
        } else {
            num = elapsed;
            unit = "ns";
        }

        self.color_stream.setNextColor(.dim);
        if (num >= 100 or @round(num) == num) {
            try writer.print("({d:.0}{s})", .{ num, unit });
        } else if (num >= 10) {
            try writer.print("({d:.1}{s})", .{ num, unit });
        } else {
            try writer.print("({d:.2}{s})", .{ num, unit });
        }
    }
    /// Pretty print the test results.
    pub fn writeResult(self: *Self) ColorWriterStream.Error!void {
        var writer = &self.color_stream.writer;

        self.color_stream.setNextColor(.reset);
        try writer.writeAll("\n    ZABI Tests: ");

        self.color_stream.setNextColor(.green);
        try writer.print("{d} passed\n", .{self.result.passed});

        self.color_stream.setNextColor(.reset);
        try writer.writeAll("    ZABI Tests: ");

        self.color_stream.setNextColor(.red);
        try writer.print("{d} failed\n", .{self.result.failed});

        self.color_stream.setNextColor(.reset);
        try writer.writeAll("    ZABI Tests: ");

        self.color_stream.setNextColor(.yellow);
        try writer.print("{d} skipped\n", .{self.result.skipped});

        self.color_stream.setNextColor(.reset);
        try writer.writeAll("    ZABI Tests: ");

        self.color_stream.setNextColor(.blue);
        try writer.print("{d} leaked\n", .{self.result.leaked});

        self.color_stream.setNextColor(.reset);
    }
};

/// Main test runner.
pub fn main(init: std.process.Init.Minimal) !void {
    @disableInstrumentation();
    const test_funcs: []const TestFn = builtin.test_functions;

    // Return if we don't have any tests (filters may reduce to 0).
    if (test_funcs.len == 1)
        return;

    var writer_buffer: [1024]u8 = undefined;

    const writer = std.debug.lockStderr(&writer_buffer).terminal().writer;
    defer std.debug.unlockStderr();

    std.testing.io_instance = .init(std.heap.page_allocator, .{ .environ = init.environ });
    defer std.testing.io_instance.deinit();

    var environ_map = try std.testing.io_instance.environ.process_environ.createMap(std.heap.page_allocator);
    defer environ_map.deinit();

    var runner: Runner = .{
        .color_stream = .init(writer, &.{}),
        .result = .{},
    };
    try runner.resetAnvilInstance(std.heap.page_allocator, &environ_map);

    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};

        if (std.mem.endsWith(u8, test_runner.name, ".test_0") or
            std.ascii.endsWithIgnoreCase(test_runner.name, "Root"))
            continue;

        var iter = std.mem.splitScalar(u8, test_runner.name, '.');

        try runner.writeModuleName(iter.first());
        if (iter.next()) |file_name|
            try runner.writeFileName(file_name);

        try runner.writeTestName(iter.rest());

        var timer = try std.time.Timer.start();
        const result = test_runner.func();
        const elapsed = timer.read();

        if (result) |_| try runner.writeSuccess(elapsed) else |err| switch (err) {
            error.SkipZigTest => try runner.writeSkipped(elapsed),
            else => {
                try runner.writeFail(elapsed);
                if (@errorReturnTrace()) |trace|
                    std.debug.dumpStackTrace(trace);
            },
        }

        if (std.testing.allocator_instance.deinit() == .leak)
            try runner.writeLeaked(elapsed);
    }

    try runner.writeResult();
}

/// Connects to the anvil instance. Fails if it cant.
fn startAnvilInstances(allocator: std.mem.Allocator, env: *std.process.Environ.Map) !void {
    var threaded_io: std.Io.Threaded = .init(allocator, .{ .environ = .empty });
    defer threaded_io.deinit();

    const mainnet = env.get("ANVIL_FORK_URL") orelse return error.MissingEnviromentVariable;

    var anvil: Anvil = undefined;
    defer anvil.deinit();

    anvil.initClient(.{ .allocator = allocator, .io = threaded_io.io() });

    try anvil.reset(.{
        .forking = .{ .jsonRpcUrl = mainnet },
    });
}
