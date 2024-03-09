const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/meta.zig");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Return type for logs encoded.
pub const LogsEncoded = struct {
    arena: *ArenaAllocator,
    data: []const ?[]u8,

    pub fn deinit(self: @This()) void {
        const child_allocator = self.arena.child_allocator;
        self.arena.deinit();

        child_allocator.destroy(self.arena);
    }
};
/// Encode event log topics
/// **Currently non indexed topics are not supported**
///
/// `values` is expected to be a tuple of the values to encode.
/// By default the log encoding definition doesn't support ABI array types and tuple types.
///
/// Example:
///
/// const event = .{
///     .type = .event,
///     .inputs = &.{},
///     .name = "Transfer"
/// }
///
/// const encoded = encodeLogs(testing.allocator, event, .{});
///
/// Result: &.{"0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"}
pub fn encodeLogs(allocator: Allocator, params: AbiEvent, values: anytype) !LogsEncoded {
    var encoded_logs: LogsEncoded = .{ .arena = try allocator.create(ArenaAllocator), .data = undefined };
    errdefer allocator.destroy(encoded_logs.arena);

    encoded_logs.arena.* = ArenaAllocator.init(allocator);

    const child_allocator = encoded_logs.arena.allocator();
    errdefer encoded_logs.arena.deinit();

    encoded_logs.data = try encodeLogsLeaky(child_allocator, params, values);

    return encoded_logs;
}
/// Recommened to use an ArenaAllocator or a similar allocator as not allocations
/// will be freed. Caller owns the memory
pub fn encodeLogsLeaky(allocator: Allocator, event: AbiEvent, values: anytype) ![]const ?[]u8 {
    const info = @typeInfo(@TypeOf(values));

    if (info != .Struct or !info.Struct.is_tuple)
        @compileError("Expected tuple type but found " ++ @typeName(@TypeOf(values)));

    var list = try std.ArrayList(?[]u8).initCapacity(allocator, values.len + 1);
    errdefer list.deinit();

    const hash = try event.encode(allocator);
    const hash_hex = try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});

    try list.append(hash_hex);

    if (values.len > 0) {
        std.debug.assert(event.inputs.len >= values.len);

        inline for (values, 0..) |value, i| {
            const param = event.inputs[i];

            if (!param.indexed)
                return error.EncodingNonIndexedParameter;

            const encoded = try encodeLog(allocator, param, value);
            try list.append(encoded);
        }
    }

    return try list.toOwnedSlice();
}

fn encodeLog(allocator: Allocator, param: AbiEventParameter, value: anytype) !?[]u8 {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Bool => {
            switch (param.type) {
                .bool => {
                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(u256, &buffer, @intFromBool(value), .big);

                    return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                },
                else => return error.InvalidParamType,
            }
        },
        .Int, .ComptimeInt => {
            if (value > std.math.maxInt(u256))
                return error.Overflow;

            switch (param.type) {
                .uint => {
                    if (value < 0)
                        return error.NegativeNumber;

                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(u256, &buffer, value, .big);

                    return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                },
                .int => {
                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(i256, &buffer, value, .big);

                    return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                },
                else => return error.InvalidParamType,
            }
        },
        .Null => return null,
        .Optional => {
            if (value) |val| return try encodeLog(allocator, param, val) else return null;
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes => {
                        var buffer: [32]u8 = undefined;
                        Keccak256.hash(&value, &buffer, .{});
                        return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.InvalidAddressType;

                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buffer[12..], value[0..]);

                        return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len or arr_info.len > 32)
                            return error.InvalidFixedBytesType;

                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buffer[0..arr_info.len], value[0..arr_info.len]);

                        return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                    },
                    else => return error.InvalidParamType,
                }
            }

            @compileError("Unsupported type " ++ @typeName(value));
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeLog(allocator, param, value.*),
                .Slice => {
                    if (ptr_info.child == u8) {
                        switch (param.type) {
                            .string, .bytes => {
                                var buffer: [32]u8 = undefined;
                                Keccak256.hash(value, &buffer, .{});
                                return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer)});
                            },
                            else => return error.InvalidParamType,
                        }
                    }

                    @compileError("Unsupported type " ++ @typeName(value));
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(value)),
            }
        },
        else => @compileError("Unsupported pointer type " ++ @typeName(value)),
    }
}

test "Empty inputs" {
    const event = .{ .type = .event, .inputs = &.{}, .name = "Transfer" };

    const encoded = try encodeLogs(testing.allocator, event, .{});
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{@constCast("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};

    try testing.expectEqualDeep(slice, encoded.data);
}

test "Empty args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{});
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{@constCast("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")};

    try testing.expectEqualDeep(slice, encoded.data);
}

test "With args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{ @constCast("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, @constCast("0x000000000000000000000000a5cc3c03994db5b0d9a5eedd10cabab0813678ac") };

    try testing.expectEqualDeep(slice, encoded.data);
}

test "With args string/bytes" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded.data);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded.data);
    }
}

test "With remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ 69, -420, true });
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{ @constCast("0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1"), @constCast("0x0000000000000000000000000000000000000000000000000000000000000045"), @constCast("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe5c"), @constCast("0x0000000000000000000000000000000000000000000000000000000000000001") };

    try testing.expectEqualDeep(slice, encoded.data);
}
