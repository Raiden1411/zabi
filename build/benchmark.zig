const builtin = @import("builtin");
const color = @import("color.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const ColorWriterStream = color.ColorWriter;
const LockedStderr = std.Io.LockedStderr;
const PriorityDequeue = std.PriorityDequeue;
const TestFn = std.builtin.TestFn;

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
        /// Array containing the time per run.
        samples: [max_samples]u64 = undefined,
        /// PriorityDequeue used to keep track of the slowest tests.
        dequeue: Queue,
        /// Keeps std_err so that it can be used to get the terminal windows size
        std_err: LockedStderr,

        /// Sets the inital state of the stream and queue.
        pub fn init(allocator: Allocator) Allocator.Error!Self {
            var queue = Queue.init(allocator, {});
            errdefer queue.deinit();

            try queue.ensureTotalCapacity(max_slowest_tracker);
            var std_err = std.debug.lockStderr(&.{});

            return .{
                .color_stream = .init(std_err.terminal().writer, &.{}),
                .dequeue = queue,
                .std_err = std_err,
            };
        }
        /// Clears any allocated memory for the queue.
        pub fn deinit(self: Self) void {
            self.dequeue.deinit();
            std.debug.unlockStderr();
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
            while (count < max_warmup) : (count += 1)
                try runner.func();

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
        pub fn getColTerminalSize(self: Self) usize {
            var winsize: Winsize = undefined;
            _ = std.os.linux.ioctl(self.std_err.file_writer.file.handle, TIOCGWINSZ, @intFromPtr(&winsize));

            return @intCast(winsize.ws_col);
        }
        /// Prints the slowest tests that ran.
        ///
        /// `Slowest tests:` <- red
        /// xxxx with an average of x
        pub fn printSlowestQueue(self: *Self) ColorWriterStream.Error!void {
            if (self.dequeue.count() == 0)
                return;

            var writer = &self.color_stream.writer;

            self.color_stream.setNextColor(.red);
            try writer.writeAll("  Slowest Tests:\n");

            while (self.dequeue.removeMaxOrNull()) |slowest|
                try self.printSlowest(slowest);
        }
        /// Prints the current module as a header.
        ///
        /// ==== module name ====
        pub fn printHeader(self: *Self, module: []const u8) ColorWriterStream.Error!void {
            var writer = &self.color_stream.writer;

            const col = self.getColTerminalSize();
            var buffer: [100]u8 = undefined;

            var discarding = std.Io.Writer.Discarding.init(&buffer);
            var void_writter = &discarding.writer;

            try void_writter.print(" Running {s} module ", .{module});
            try void_writter.flush();

            try writer.splatByteAll('\n', 2);

            self.color_stream.setNextColor(.bright_green);
            const padding = col -| discarding.count;

            const left_pad = @divFloor(padding, 2);
            const right_pad = padding - left_pad;

            try writer.splatByteAll('=', left_pad);

            try writer.writeAll(buffer[0..discarding.count]);

            try writer.splatByteAll('=', right_pad);
            try writer.splatByteAll('\n', 2);
        }
        /// Prints the a element of the slowest queue.
        /// xxxx with an average of x
        pub fn printSlowest(self: *Self, slowest: SlowestTests) !void {
            var writer = &self.color_stream.writer;

            try writer.splatByteAll(' ', 4);

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
            var writer = &self.color_stream.writer;
            const index = std.mem.lastIndexOf(u8, name, "test.").?;

            try writer.splatByteAll(' ', 2);
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
            var writer = &self.color_stream.writer;

            // Prints the headers.
            try writer.splatByteAll(' ', 4);
            try writer.writeAll("measurements");
            self.color_stream.setNextColor(.green);
            try writer.splatByteAll(' ', 6);
            try writer.writeAll("mean");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" ± ");
            self.color_stream.setNextColor(.green);
            try writer.writeAll("σ");

            try writer.splatByteAll(' ', 12);
            self.color_stream.setNextColor(.bright_cyan);
            try writer.writeAll("min");
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" … ");
            self.color_stream.setNextColor(.bright_red);
            try writer.writeAll("max");
            try writer.writeByte('\n');

            // Prints the results
            self.color_stream.setNextColor(.reset);
            try writer.splatByteAll(' ', 4);
            try writer.writeAll("wall_time:");
            try writer.splatByteAll(' ', 6);
            self.color_stream.setNextColor(.green);
            try self.printUnit(result.mean);
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" ± ");
            self.color_stream.setNextColor(.green);
            try self.printUnit(result.stdiv);

            try writer.splatByteAll(' ', 4);
            self.color_stream.setNextColor(.bright_cyan);
            try self.printUnit(@floatFromInt(result.min));
            self.color_stream.setNextColor(.bold);
            try writer.writeAll(" … ");
            self.color_stream.setNextColor(.bright_red);
            try self.printUnit(@floatFromInt(result.max));
            try writer.splatByteAll('\n', 2);
        }
        /// Converts the result into a human readable unit of measurement and prints it.
        pub fn printUnit(self: *Self, number: f64) ColorWriterStream.Error!void {
            var writer = &self.color_stream.writer;
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
                try writer.print("{d: >4.0}", .{num});
            } else if (num >= 100) {
                try writer.print("{d: >4.0}", .{num});
            } else if (num >= 10) {
                try writer.print("{d: >3.1}", .{num});
            } else {
                try writer.print("{d: >3.2}", .{num});
            }

            self.color_stream.setNextColor(.dim);
            try writer.writeAll(unit);
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

            if (self.samples[0..sample_index].len > 1) {
                @branchHint(.likely);
                std_div /= @floatFromInt(self.samples[0..sample_index].len - 1);
            }

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

    var runner: BenchmarkRunner(1000, 10, 5) = try .init(std.heap.smp_allocator);
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
