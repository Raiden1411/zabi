const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/abi.zig");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiEventParametersToPrimativeType = meta.AbiEventParametersToPrimativeType;
const AbiEventParameterToPrimativeType = meta.AbiEventParameterToPrimativeType;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const encodeLogs = @import("../encoding/logs.zig").encodeLogTopics;

/// Decode event log topics where the event is comptime know.
///
/// This doesn't support null hash values because the types are generated at comptime and it doesnt assume
/// null values. Use `decodeLogs` instead where you can provided the return type.
///
/// String, bytes array and tuple types are not decoded but instead their hashed
/// values are returned as we have no way to decode from the hash.
/// It follows the solidity spec defined [here](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding)
///
/// You will only need to free memory if the provided type that you desire is a pointer. So you must
/// call destroy on the tuple element.
///
/// Example:
///
/// const event = .{
///     .type = .event,
///     .inputs = &.{},
///     .name = "Transfer"
/// }
///
/// const encoded = try decodeLogs(testing.allocator, event, &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")});
///
/// Result: .{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}
pub fn decodeLogsComptime(comptime params: []const AbiEventParameter, encoded: []const ?Hash) !AbiEventParametersToPrimativeType(params) {
    var result: AbiEventParametersToPrimativeType(params) = undefined;

    result[0] = encoded[0] orelse return error.MissingEventSignature;

    if (encoded.len == 1)
        return result;

    var indexed_field = false;

    comptime var counter: usize = 1;
    inline for (params, 0..) |param, i| {
        const enc = encoded[i + 1];

        if (param.indexed) {
            indexed_field = true;
            result[counter] = try decodeLogComptime(param, enc orelse return error.UnsupportedNullValue);
            counter += 1;
        }
    }

    if (!indexed_field)
        return error.NoIndexedParams;

    return result;
}
/// Decode event log topics
///
/// The return type is expected to be a tuple.
///
/// String, bytes array and tuple types are not decoded but instead their hashed
/// values are returned as we have no way to decode from the hash.
/// It follows the solidity spec defined [here](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding)
///
/// You will only need to free memory if the provided type that you desire is a pointer. So you must
/// call destroy on the tuple element.
///
/// Example:
///
/// const event = .{
///     .type = .event,
///     .inputs = &.{},
///     .name = "Transfer"
/// }
///
/// const encoded = try decodeLogs(testing.allocator, event, &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")});
///
/// Result: .{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}
pub fn decodeLogs(allocator: Allocator, comptime T: type, params: []const AbiEventParameter, encoded: []const ?Hash) !T {
    const info = @typeInfo(T);

    if (info != .Struct or !info.Struct.is_tuple)
        @compileError("Expected return type to be a tuple");

    var result: T = undefined;
    // Just makes sure that the length is alligned.
    // This will get removed on non debug builds
    std.debug.assert(info.Struct.fields.len == encoded.len);

    if (info.Struct.fields[0].type != Hash)
        @compileError("Expected hash field member but found " ++ @typeName(info.Struct.fields[0].type));

    result[0] = encoded[0] orelse return error.MissingEventSignature;

    if (encoded.len == 1)
        return result;

    var indexed_field = false;
    const fields = info.Struct.fields[1..];

    inline for (fields, 1..) |field, i| {
        const enc = encoded[i];
        const param = params[i - 1];

        if (param.indexed) {
            if (enc) |enc_not_null| {
                indexed_field = true;
                result[i] = try decodeLog(allocator, field.type, param, enc_not_null);
            } else {
                const opt_info = @typeInfo(field.type);

                if (opt_info != .Optional)
                    return error.UnexpectedTupleFieldType;

                result[i] = null;
            }
        }
    }

    if (!indexed_field)
        return error.NoIndexedParams;

    return result;
}

fn decodeLogComptime(comptime param: AbiEventParameter, encoded: Hash) !AbiEventParameterToPrimativeType(param) {
    const info = @typeInfo(AbiEventParameterToPrimativeType(param));

    switch (info) {
        .Bool => switch (param.type) {
            .bool => {
                const decoded = std.mem.readInt(u256, &encoded, .big);

                return @as(u1, @truncate(decoded)) != 0;
            },
            else => return error.InvalidParamType,
        },
        .Int => |int_info| {
            switch (param.type) {
                .uint => {
                    if (int_info.signedness != .unsigned)
                        return error.ExpectedUnsignedInt;
                    const decoded = std.mem.readInt(u256, &encoded, .big);

                    return @as(AbiEventParameterToPrimativeType(param), @truncate(decoded));
                },
                .int => {
                    if (int_info.signedness != .signed)
                        return error.ExpectedSignedInt;

                    const decoded = std.mem.readInt(i256, &encoded, .big);

                    return @as(AbiEventParameterToPrimativeType(param), @truncate(decoded));
                },
                else => return error.InvalidParamType,
            }
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes, .dynamicArray, .fixedArray, .tuple => {
                        if (arr_info.len != 32)
                            return error.ExpectedHashSize;

                        return encoded;
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.ExpectedAddressSize;

                        return encoded[12..].*;
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len)
                            return error.InvalidFixedBufferSize;

                        return encoded[0..arr_info.len].*;
                    },
                    else => return error.InvalidParamType,
                }
            }

            @compileError("Non u8 arrays are not supported");
        },
        else => @compileError("Unsupported type " ++ @typeName(AbiEventParameterToPrimativeType(param))),
    }
}

fn decodeLog(allocator: Allocator, comptime T: type, param: AbiEventParameter, encoded: Hash) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => switch (param.type) {
            .bool => {
                const decoded = std.mem.readInt(u256, &encoded, .big);

                return @as(u1, @truncate(decoded)) != 0;
            },
            else => return error.InvalidParamType,
        },
        .Int => |int_info| {
            switch (param.type) {
                .uint => {
                    if (int_info.signedness != .unsigned)
                        return error.ExpectedUnsignedInt;
                    const decoded = std.mem.readInt(u256, &encoded, .big);

                    return @as(T, @truncate(decoded));
                },
                .int => {
                    if (int_info.signedness != .signed)
                        return error.ExpectedSignedInt;

                    const decoded = std.mem.readInt(i256, &encoded, .big);

                    return @as(T, @truncate(decoded));
                },
                else => return error.InvalidParamType,
            }
        },
        .Optional => |opt_info| return try decodeLog(allocator, opt_info.child, param, encoded),
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes, .dynamicArray, .fixedArray, .tuple => {
                        if (arr_info.len != 32)
                            return error.ExpectedHashSize;

                        return encoded;
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.ExpectedAddressSize;

                        return encoded[12..].*;
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len)
                            return error.InvalidFixedBufferSize;

                        return encoded[0..arr_info.len].*;
                    },
                    else => return error.InvalidParamType,
                }
            }

            @compileError("Non u8 arrays are not supported");
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const child = try allocator.create(ptr_info.child);
                    child.* = try decodeLog(allocator, ptr_info.child, param, encoded);

                    return child;
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(T)),
            }
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}

test "Decode empty inputs" {
    const event = .{ .type = .event, .inputs = &.{}, .name = "Transfer" };

    const encoded = try encodeLogs(testing.allocator, event, .{});
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};
    const decoded = try decodeLogs(testing.allocator, struct { Hash }, event.inputs, slice);
    const decoded_comptime = try decodeLogsComptime(event.inputs, slice);

    try testing.expectEqualDeep(.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}, decoded);
    try testing.expectEqualDeep(decoded_comptime, decoded);
}

test "Decode empty args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{});
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(testing.allocator, struct { Hash }, event.value.inputs, encoded);

    try testing.expectEqualDeep(.{try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")}, decoded);
}

test "Decode with args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ Hash, ?Hash, [20]u8 }), event.value.inputs, encoded);

    try testing.expectEqualDeep(.{ try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") }, decoded);
}
test "Comptime Encoding" {
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .uint = 256 },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const encoded = try encodeLogs(testing.allocator, event, .{69});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, u256 }, event.inputs, encoded);
        const decoded_comptime = try decodeLogsComptime(event.inputs, encoded);
        try testing.expectEqualDeep(decoded, decoded_comptime);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .int = 256 },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const encoded = try encodeLogs(testing.allocator, event, .{-69});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, i256 }, event.inputs, encoded);
        const decoded_comptime = try decodeLogsComptime(event.inputs, encoded);
        try testing.expectEqualDeep(decoded, decoded_comptime);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .string = {} },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };

        const encoded = try encodeLogs(testing.allocator, event, .{"foo"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, Hash }, event.inputs, encoded);
        const decoded_comptime = try decodeLogsComptime(event.inputs, encoded);
        try testing.expectEqualDeep(decoded, decoded_comptime);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .dynamicArray = &.{ .uint = 256 } },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };

        const value: []const u256 = &.{69};

        const encoded = try encodeLogs(testing.allocator, event, .{value});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, Hash }, event.inputs, encoded);
        const decoded_comptime = try decodeLogsComptime(event.inputs, encoded);
        try testing.expectEqualDeep(decoded, decoded_comptime);
    }
}

test "Decoded with args string/bytes" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ Hash, Hash }), event.value.inputs, encoded);

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ Hash, ?Hash }), event.value.inputs, encoded);

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ Hash, Hash }), event.value.inputs, encoded);

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
}

test "Decode Arrays" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, [20]u8 }, event.value.inputs, encoded);

        try testing.expectEqualDeep(.{ encoded[0], try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97") }, decoded);
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, [5]u8 }, event.value.inputs, encoded);

        try testing.expectEqualDeep(.{ encoded[0], "hello".* }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(testing.allocator, struct { Hash, *const [5]u8 }, event.value.inputs, encoded);
        defer testing.allocator.destroy(decoded[1]);

        try testing.expectEqualDeep(.{ encoded[0], "hello" }, decoded);
    }
}

test "Decode with remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ 69, -420, true });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ Hash, u256, i256, bool }), event.value.inputs, encoded);

    try testing.expectEqualDeep(.{
        try utils.hashToBytes("0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1"),
        @as(u256, @intCast(69)),
        @as(i256, @intCast(-420)),
        true,
    }, decoded);
}

test "Errors" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.ExpectedUnsignedInt, decodeLogs(testing.allocator, struct { Hash, i256 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(int indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{@as(i256, @intCast(69))});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.ExpectedSignedInt, decodeLogs(testing.allocator, struct { Hash, u256 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.ExpectedHashSize, decodeLogs(testing.allocator, struct { Hash, [2]u8 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.ExpectedAddressSize, decodeLogs(testing.allocator, struct { Hash, [2]u8 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.InvalidFixedBufferSize, decodeLogs(testing.allocator, struct { Hash, [6]u8 }, event.value.inputs, encoded));
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.InvalidParamType, decodeLogs(testing.allocator, struct { Hash, [6]u8 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.InvalidParamType, decodeLogs(testing.allocator, struct { Hash, [5]u8 }, event.value.inputs, encoded));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string a)");
        defer event.deinit();

        try testing.expectError(error.NoIndexedParams, decodeLogs(testing.allocator, struct { Hash, Hash }, event.value.inputs, &.{ [_]u8{0} ** 32, [_]u8{0} ** 32 }));
    }
}
