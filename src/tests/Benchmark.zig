const std = @import("std");

const Allocator = std.mem.Allocator;
const ArgsTuple = std.meta.ArgsTuple;

pub const BenchmarkOptions = struct {
    runs: u32 = 10_000,
    warmup_runs: u32 = 100,
};

pub const BenchmarkResult = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    opts: BenchmarkOptions,
    mean: u64,

    pub fn printSummary(self: *const Self) void {
        std.debug.print("Benchmark summary for {d} trials:\n", .{self.opts.runs});
        std.debug.print("Mean: \x1b[32m{s}\n", .{std.fmt.fmtDuration(self.mean)});
    }
};

fn invoke(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) void {
    const ReturnType = @typeInfo(@TypeOf(func)).Fn.return_type.?;
    switch (@typeInfo(ReturnType)) {
        .ErrorUnion => {
            const item = @call(.never_inline, func, args) catch {
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                return;
            };

            if (@hasDecl(@TypeOf(item), "deinit")) item.deinit();
        },
        else => {
            const item = @call(.never_inline, func, args);
            if (@hasDecl(@TypeOf(item), "deinit")) item.deinit();
            return;
        },
    }
}

pub fn benchmark(
    allocator: Allocator,
    comptime func: anytype,
    args: ArgsTuple(@TypeOf(func)),
    opts: BenchmarkOptions,
) !BenchmarkResult {
    var count: usize = 0;
    while (count < opts.warmup_runs) : (count += 1) {
        invoke(func, args);
    }
    var timer = try std.time.Timer.start();
    while (count < opts.runs) : (count += 1) {
        invoke(func, args);
    }
    const mean = @divFloor(timer.lap(), opts.runs);
    return .{ .allocator = allocator, .opts = opts, .mean = mean };
}
