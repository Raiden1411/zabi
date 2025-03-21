const abitypes = zabi.abi.abitypes;
const abi_param = zabi.abi.abi_parameter;
const std = @import("std");
const utils = zabi.utils;
const zabi = @import("zabi");

const Abi = abitypes.Abi;
const AbiParameter = abi_param.AbiParameter;
const Allocator = std.mem.Allocator;
const ArrayListWriter = std.ArrayList(u8).Writer;
const ParamType = zabi.abi.param_type.ParamType;

const CliOptions = struct {
    json_abi: []const u8,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator, const is_debug = alloc: {
        break :alloc switch (@import("builtin").mode) {
            .Debug,
            .ReleaseSafe,
            => .{ debug_allocator.allocator(), true },
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
            break :file try std.fs.openFileAbsolute(parsed.json_abi, .{});

        break :file try std.fs.cwd().openFile(parsed.json_abi, .{});
    };
    defer file.close();

    var reader = std.json.reader(allocator, file.reader());
    defer reader.deinit();

    const abi_parsed = try std.json.parseFromTokenSource(Abi, allocator, &reader, .{});
    defer abi_parsed.deinit();

    const source = try generateSourceFromAbi(allocator, abi_parsed.value);
    defer allocator.free(source);

    try std.io.getStdErr().writeAll("\n");
    try std.io.getStdErr().writeAll(source);
    try std.io.getStdErr().writeAll("\n");
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
            try writer.writeAll(") ");

            switch (function.stateMutability) {
                .view,
                .pure,
                => try writeFunctionReturns(&writer, function.outputs),
                .payable,
                .nonpayable,
                => try writer.writeAll("![32]u8"),
            }
            try writer.writeByte('\n');

            // TODO: Create the function body based on the mutability
            // Same applies for the return type
        },
        .abiConstructor => |constructor| {
            try writer.writeAll("pub fn deployContract(");
            try writeFunctionParameters(&writer, constructor.inputs);
            try writer.writeAll(") ![32]u8");
            try writer.writeByte('\n');
        },
        inline else => continue,
    };

    return list.toOwnedSlice();
}

fn writeFunctionReturns(
    writer: *ArrayListWriter,
    params: []const AbiParameter,
) Allocator.Error!void {
    try writer.writeAll("!AbiDecoded(struct{ ");

    for (params) |param| switch (param.type) {
        .bool,
        .string,
        .bytes,
        .address,
        .int,
        .uint,
        .fixedBytes,
        .fixedArray,
        .dynamicArray,
        => try convertToZigTypes(writer, param.type),

        .@"enum",
        => try writer.writeAll("u8, "),
        .tuple,
        => {
            try writer.writeAll("struct { ");

            if (param.components) |components|
                try writeFunctionParameters(writer, components);

            try writer.writeAll("}");
        },
    };

    try writer.writeAll("})");
}

fn writeFunctionParameters(
    writer: *ArrayListWriter,
    params: []const AbiParameter,
) Allocator.Error!void {
    for (params) |param| switch (param.type) {
        .bool,
        .string,
        .bytes,
        .address,
        .int,
        .uint,
        .fixedBytes,
        .fixedArray,
        .dynamicArray,
        => {
            const name: []const u8 = blk: {
                if (param.name.len != 0)
                    break :blk param.name;

                // TODO: Change this later
                var buffer: [8]u8 = undefined;

                var prng: std.Random.DefaultPrng = .init(0);
                var rand: std.Random = prng.random();

                inline for (0..7) |i|
                    buffer[i] = rand.intRangeAtMost(u8, 'a', 'z');

                break :blk buffer[0..];
            };

            try writer.print("{s}: ", .{name});
            try convertToZigTypes(writer, param.type);
        },
        .@"enum",
        => try writer.print("{s}: u8", .{param.name}),
        .tuple,
        => {
            try writer.print("{s}: struct", .{param.name});
            try writer.writeAll(" {");

            if (param.components) |components|
                try writeFunctionParameters(writer, components);

            try writer.writeAll("}");
        },
    };
}

fn convertToZigTypes(
    writer: *ArrayListWriter,
    param_type: ParamType,
) Allocator.Error!void {
    switch (param_type) {
        .string,
        .bytes,
        => try writer.writeAll("[]const u8, "),
        .address,
        => try writer.writeAll("[20]u8, "),
        .bool,
        => try writer.writeAll("bool, "),
        .fixedBytes,
        => |bytes| try writer.print("[{d}]u8, ", .{bytes}),
        .int,
        => |bytes| try writer.print("i{d}, ", .{bytes}),
        .uint,
        => |bytes| try writer.print("u{d}, ", .{bytes}),
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
        inline else => unreachable, // Doesnt get handled here
    }
}
