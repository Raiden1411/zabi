const abitypes = zabi.abi.abitypes;
const abi_param = zabi.abi.abi_parameter;
const std = @import("std");
const utils = zabi.utils;
const zabi = @import("zabi");

const Abi = abitypes.Abi;
const AbiParameter = abi_param.AbiParameter;
const Allocator = std.mem.Allocator;

const CliOptions = struct {
    json_abi: []const u8,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator, const is_debug = alloc: {
        break :alloc switch (@import("builtin").mode) {
            .Debug,
            .ReleaseSafe,
            => .{ debug_allocator, true },
            .ReleaseSmall,
            .ReleaseFast,
            => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();

    const parsed = utils.args.parseArgs(CliOptions, allocator, &iter);

    const file = file: {
        if (std.fs.path.isAbsolute(parsed.json_abi))
            break :file try std.fs.openFileAbsolute(parsed.json_abi);

        break :file try std.fs.cwd().openFile(parsed.json_abi, .{});
    };
    defer file.close();

    const reader = std.json.reader(allocator, file.reader());

    const abi_parsed = try std.json.parseFromTokenSource(Abi, allocator, reader, .{});
    defer abi_parsed.deinit();

    return generateSourceFromAbi(allocator, abi_parsed.value);
}

fn generateSourceFromAbi(
    allocator: Allocator,
    abi: Abi,
) Allocator.Error![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, std.atomic.cache_line);
    errdefer list.deinit();

    var writer = list.writer();

    for (abi) |element| switch (element) {
        .abiFunction => |function| {
            try writer.print("pub fn {s}(", .{function.name});
            try writeFunctionParameters(&writer, function.inputs);
            try writer.writeAll(")");
            try writeFunctionReturns(&writer, function.inputs);
        },
        inline else => continue,
    };
}

fn writeFunctionParameters(
    writer: *std.ArrayList(u8).Writer,
    params: []const AbiParameter,
) Allocator.Error!void {
    for (params) |param| {
        try writer.print("{s}: ", .{param.name});

        try convertToZigTypes(writer, param.type);
    }
}

fn writeFunctionReturns(
    writer: *std.ArrayList(u8).Writer,
    params: []const AbiParameter,
) Allocator.Error!void {
    for (params) |param| {
        switch (param.type) {
            .string,
            .bytes,
            => try writer.print("{s}: {s}", .{ param.name, @tagName(param.type) }),
        }
    }
}

fn convertToZigTypes(
    writer: *std.ArrayList(u8).Writer,
    param_type: zabi.abi.param_type.ParamType,
) Allocator.Error!void {
    switch (param_type) {
        .string,
        .bytes,
        => try writer.writeAll("[]const u8,"),
        .address,
        => try writer.writeAll("[20]u8,"),
        .bool,
        => try writer.writeAll("bool,"),
        .fixedBytes,
        => |bytes| try writer.print("[{d}]u8,", .{bytes}),
        .int,
        => |bytes| try writer.print("i{d},", .{bytes}),
        .uint,
        => |bytes| try writer.print("u{d},", .{bytes}),
        .fixedArray,
        => |arr_info| {
            try writer.print("[{d}]", .{arr_info.size});

            return convertToZigTypes(writer, arr_info.child.*);
        },
        .dynamicArray,
        => |arr_info| {
            try writer.writeAll("[]const ");

            return convertToZigTypes(writer, arr_info.*);
        },
        else => @panic("TODO"),
    }
}
