const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const PriorityDequeue = std.PriorityDequeue;
const TestFn = std.builtin.TestFn;
const TerminalColors = std.io.tty.Color;
const ZigColor = std.zig.Color;

/// Wraps the stderr with our color stream.
const ColorWriterStream = ColorWriter(@TypeOf(std.io.getStdErr().writer()));

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
    };
}

/// Custom benchmark runner that pretty prints all of the taken measurements.
/// Heavily inspired by [poop](https://github.com/andrewrk/poop/tree/main)
pub fn BenchmarkRunner(
    comptime max_samples: comptime_int,
    comptime max_warmup: comptime_int,
    comptime max_slowest_tracker: comptime_int,
) type {
    return struct {
        const Self = @This();

        /// PriorityDequeue used to track the slowest tests.
        const Queue = PriorityDequeue(SlowestTests, void, SlowestTests.compareResult);

        /// Result type when calling ioctl to grab the terminal size.
        const Winsize = extern struct {
            ws_row: c_ushort,
            ws_col: c_ushort,
            ws_xpixel: c_ushort,
            ws_ypixel: c_ushort,
        };

        /// Computed results from bench test run.
        const BenchmarkResult = struct {
            max: u64,
            min: u64,
            mean: f64,
            stdiv: f64,
        };

        /// Slowest test tracker.
        const SlowestTests = struct {
            mean: f64,
            name: []const u8,

            /// Compare function use to place items in the queue.
            fn compareResult(context: void, a: SlowestTests, b: SlowestTests) std.math.Order {
                _ = context;
                return std.math.order(a.mean, b.mean);
            }
        };

        /// Max amount of time tests are allowed to run if they dont complete the total runs.
        const max_timer = std.time.ns_per_s * 5;

        /// https://docs.rs/libc/latest/libc/constant.TIOCGWINSZ.html
        const TIOCGWINSZ: u32 = 0x5413;

        /// Internal color stream used to send ansi codes to the terminal.
        color_stream: ColorWriterStream,
        /// Array containing the the time per run.
        samples: [max_samples]u64 = undefined,
        /// PriorityDequeue used to keep track of the slowest tests.
        dequeue: Queue,

        /// Sets the inital state of the stream and queue.
        pub fn init(allocator: Allocator) Allocator.Error!Self {
            var queue = Queue.init(allocator, {});
            errdefer queue.deinit();

            try queue.ensureTotalCapacity(max_slowest_tracker);

            return .{
                .color_stream = .empty,
                .dequeue = queue,
            };
        }
        /// Clears any allocated memory for the queue.
        pub fn deinit(self: Self) void {
            self.dequeue.deinit();
        }
        /// Main bench runner that will run the tests and calculate their performance.
        ///
        /// Pretty prints all of the measurements like the example bellow.
        ///
        /// ```sh
        /// Benchmarking: FooBar
        ///
        /// measurements      mean ± σ            min … max
        /// wall_time:       136us ± 23.6us     129us …  761us
        /// ```
        pub fn run(self: *Self, runner: TestFn) anyerror!void {
            var count: usize = 0;
            while (count < max_warmup) : (count += 1) {
                try runner.func();
            }

            var timer = try std.time.Timer.start();
            var sample_index: usize = 0;

            const first_start = timer.read();
            while (sample_index < max_samples) : (sample_index += 1) {
                const start = timer.read();
                try runner.func();
                const end = timer.read();

                self.samples[sample_index] = end - start;

                // Caps at 5 seconds for really heavy tests.
                if ((timer.read() - first_start) > max_timer)
                    break;
            }

            const result = self.computeSamples(sample_index);
            const name = try self.printBenchmarkTestName(runner.name);

            if (self.dequeue.count() < max_slowest_tracker) {
                try self.dequeue.add(.{ .name = name, .mean = result.mean });
            } else {
                const peek = self.dequeue.peekMin().?;

                if (result.mean > peek.mean) {
                    _ = self.dequeue.removeMin();
                    try self.dequeue.add(.{ .name = name, .mean = result.mean });
                }
            }

            try self.printResult(result);
        }
        /// Gets the col size of the terminal.
        pub fn getColTerminalSize() usize {
            var winsize: Winsize = undefined;
            _ = std.os.linux.ioctl(std.io.getStdErr().handle, TIOCGWINSZ, @intFromPtr(&winsize));

            return @intCast(winsize.ws_col);
        }
        /// Prints the slowest tests that ran.
        ///
        /// `Slowest tests:` <- red
        /// xxxx with an average of x
        pub fn printSlowestQueue(self: *Self) ColorWriterStream.Error!void {
            if (self.dequeue.count() == 0)
                return;

            var writer = self.color_stream.writer();

            self.color_stream.setNextColor(.red);
            try writer.writeAll("  Slowest Tests:\n");

            while (self.dequeue.removeMaxOrNull()) |slowest| {
                try self.printSlowest(slowest);
            }
        }
        /// Prints the current module as a header.
        ///
        /// ==== module name ====
        pub fn printHeader(self: *Self, module: []const u8) ColorWriterStream.Error!void {
            var writer = self.color_stream.writer();

            const col = @divFloor(getColTerminalSize(), 2);

            try self.color_stream.writer().writeByteNTimes('\n', 2);
            self.color_stream.setNextColor(.bright_green);
            try writer.writeByteNTimes('=', col - @divFloor(module.len, 2) - 9);

            try writer.print(" Running {s} module ", .{module});

            try writer.writeByteNTimes('=', col - @divFloor(module.len, 2) - 8);
            try writer.writeByteNTimes('\n', 2);
        }
        /// Prints the a element of the slowest queue.
        /// xxxx with an average of x
        pub fn printSlowest(self: *Self, slowest: SlowestTests) !void {
            var writer = self.color_stream.writer();

            try writer.writeByteNTimes(' ', 4);

            self.color_stream.setNextColor(.dim);
            try writer.writeAll(slowest.name);
            try writer.writeByte(':');

            self.color_stream.setNextColor(.reset);
            try writer.writeAll(" with an average runtime of ");
            try self.printUnit(slowest.mean);
            try writer.writeByte('\n');
        }
        /// Prints the name of the test.
        /// Benchmark: test_name
        pub fn printBenchmarkTestName(self: *Self, name: []const u8) ColorWriterStream.Error![]const u8 {
            var writer = self.color_stream.writer();
            const index = std.mem.lastIndexOf(u8, name, "test.").?;

            try writer.writeByteNTimes(' ', 2);
            self.color_stream.setNextColor(.dim);
            try writer.writeAll("Benchmarking: ");

            self.color_stream.setNextColor(.bold);
            try writer.writeAll(name[index + 5 ..]);
            try writer.writeByte('\n');

            return name[index + 5 ..];
        }
        /// Prints the result of the benchmark with the max, min, mean and standart deviation.
        ///
        /// Example:
        ///
        /// measurements      mean ± σ            min … max
        /// wall_time:       427us ± 51.5us     403us … 1.22ms
        pub fn printResult(self: *Self, result: BenchmarkResult) ColorWriterStream.Error!void {
            var writer = self.color_stream.writer();

            // Prints the headers.
            try writer.writeByteNTimes(' ', 4);
            try writer.writeAll("measurements");
            self.color_stream.setNextColor(.green);
            try writer.writeByteNTimes(' ', 6);
            try writer.writeAll("mean");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" ± ");
            self.color_stream.setNextColor(.green);
            try writer.writeAll("σ");

            try writer.writeByteNTimes(' ', 12);
            self.color_stream.setNextColor(.bright_cyan);
            try writer.writeAll("min");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" … ");
            self.color_stream.setNextColor(.bright_red);
            try writer.writeAll("max");
            try writer.writeByte('\n');

            // Prints the results
            self.color_stream.setNextColor(.reset);
            try writer.writeByteNTimes(' ', 4);
            try writer.writeAll("wall_time:");
            try writer.writeByteNTimes(' ', 6);
            self.color_stream.setNextColor(.green);
            try self.printUnit(result.mean);
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" ± ");
            self.color_stream.setNextColor(.green);
            try self.printUnit(result.stdiv);

            try writer.writeByteNTimes(' ', 4);
            self.color_stream.setNextColor(.bright_cyan);
            try self.printUnit(@floatFromInt(result.min));
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" … ");
            self.color_stream.setNextColor(.bright_red);
            try self.printUnit(@floatFromInt(result.max));
            try writer.writeByteNTimes('\n', 2);
        }
        /// Converts the result into a human readable unit of measurement and prints it.
        pub fn printUnit(self: *Self, number: f64) ColorWriterStream.Error!void {
            var num: f64 = 0;
            var unit: []const u8 = "";

            if (number >= 1000_000_000_000) {
                num = number / 1000_000_000_000;
                unit = "ks";
            } else if (number >= 1000_000_000) {
                num = number / 1000_000_000;
                unit = "s";
            } else if (number >= 1000_000) {
                num = number / 1000_000;
                unit = "ms";
            } else if (number >= 1000) {
                num = number / 1000;
                unit = "us";
            } else {
                num = number;
                unit = "ns";
            }

            if (num >= 1000 or @round(num) == num) {
                try self.color_stream.writer().print("{d: >4.0}", .{num});
            } else if (num >= 100) {
                try self.color_stream.writer().print("{d: >4.0}", .{num});
            } else if (num >= 10) {
                try self.color_stream.writer().print("{d: >3.1}", .{num});
            } else {
                try self.color_stream.writer().print("{d: >3.2}", .{num});
            }

            self.color_stream.setNextColor(.dim);
            try self.color_stream.writer().writeAll(unit);
        }
        /// Computes all of the collected samples and returns the result.
        pub fn computeSamples(self: *Self, sample_index: usize) BenchmarkResult {
            var max: u64 = 0;
            var min: u64 = std.math.maxInt(u64);
            var total: u64 = 0;

            for (self.samples) |sample| {
                if (sample > max) max = sample;
                if (sample < min) min = sample;

                total += sample;
            }

            const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.samples[0..sample_index].len));

            var std_div: f64 = 0;

            for (self.samples[0..sample_index]) |sample| {
                const delta = @as(f64, @floatFromInt(sample)) - mean;
                std_div += delta * delta;
            }

            std_div /= @floatFromInt(self.samples[0..sample_index].len - 1);
            std_div = @sqrt(std_div);

            return .{
                .min = min,
                .max = max,
                .stdiv = std_div,
                .mean = mean,
            };
        }
    };
}

/// Main benchmark runner
pub fn main() !void {
    const test_funcs: []const TestFn = builtin.test_functions;

    var runner: BenchmarkRunner(5000, 50, 5) = try .init(std.heap.c_allocator);
    defer runner.deinit();

    var module: []const u8 = "";
    for (test_funcs) |test_runner| {
        std.testing.allocator_instance = .{};
        defer _ = std.testing.allocator_instance.deinit();

        if (std.mem.endsWith(u8, test_runner.name, ".test_0") or
            std.ascii.endsWithIgnoreCase(test_runner.name, "Root"))
            continue;

        var iter = std.mem.splitScalar(u8, test_runner.name, '.');
        const first = iter.first();

        // Print the next header of benchs to run and the slowest tests of the current module.
        if (!std.mem.eql(u8, module, first)) {
            module = first;

            try runner.printSlowestQueue();
            try runner.printHeader(module);
        }

        try runner.run(test_runner);
    }

    // This the last set of module tests.
    try runner.printSlowestQueue();
}
