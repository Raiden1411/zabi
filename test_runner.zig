const builtin = @import("builtin");
const std = @import("std");

const Anvil = @import("src/tests/Anvil.zig");
const TestFn = std.builtin.TestFn;

/// Struct that will contain the test results.
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

/// Enum of the possible test modules.
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
    checkCommand(std.heap.page_allocator, "anvil");
    const test_funcs: []const TestFn = builtin.test_functions;

    // Return if we don't have any tests.
    if (test_funcs.len <= 1)
        return;

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

        var iter = std.mem.splitAny(u8, test_runner.name, ".");
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

/// Checks if a command is installed on the system.
fn checkCommand(allocator: std.mem.Allocator, comptime command: []const u8) void {
    const env = std.process.getEnvVarOwned(allocator, "PATH") catch unreachable;
    defer allocator.free(env);

    var iter = std.mem.tokenizeAny(u8, env, ":");

    while (iter.next()) |path| {
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch continue;

        var walker = dir.walk(allocator) catch continue;
        defer walker.deinit();

        while (walker.next() catch continue) |sub_path| {
            if (std.mem.eql(u8, sub_path.basename, command))
                return;
        }
    }

    @panic("Failed to find " ++ command ++ " executable");
}
