const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/abi.zig");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const encodeLogs = @import("../encoding/logs.zig").encodeLogs;

/// Decoded logs return type.
pub fn DecodedLogs(comptime T: type) type {
    return struct {
        result: T,
        arena: *ArenaAllocator,

        pub fn deinit(self: @This()) void {
            const child_allocator = self.arena.child_allocator;
            self.arena.deinit();

            child_allocator.destroy(self.arena);
        }
    };
}
/// Decode event log topics
/// **Currently non indexed topics are not supported**
///
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
/// const encoded = decodeLogs(testing.allocator, event, &.{@constCast("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")});
///
/// Result: .{"0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"}
pub fn decodeLogs(allocator: Allocator, comptime T: type, event: AbiEvent, encoded: []const ?[]u8) !DecodedLogs(T) {
    var decoded: DecodedLogs(T) = .{ .arena = try allocator.create(ArenaAllocator), .result = undefined };
    errdefer allocator.destroy(decoded.arena);

    decoded.arena.* = ArenaAllocator.init(allocator);

    const child_allocator = decoded.arena.allocator();
    errdefer decoded.arena.deinit();

    decoded.result = try decodeLogsLeaky(child_allocator, T, event, encoded);

    return decoded;
}
/// Recommened to use an ArenaAllocator or a similar allocator as not allocations
/// will be freed. Caller owns the memory
pub fn decodeLogsLeaky(allocator: Allocator, comptime T: type, event: AbiEvent, encoded: []const ?[]u8) !T {
    const info = @typeInfo(T);

    if (info != .Struct or !info.Struct.is_tuple)
        @compileError("Expected return type to be a tuple");

    var result: T = undefined;
    const params = event.inputs;

    // Just makes sure that the length is alligned.
    // This will get removed on non debug builds
    std.debug.assert(info.Struct.fields.len == encoded.len);

    if (info.Struct.fields[0].type != []const u8)
        @compileError("Expected []const u8 field member but found " ++ @typeName(info.Struct.fields[0].type));

    result[0] = encoded[0] orelse return error.MissingEventSignature;

    if (encoded.len == 1)
        return result;

    var indexed = std.ArrayList(AbiEventParameter).init(allocator);
    errdefer indexed.deinit();

    for (params) |param| {
        if (param.indexed) {
            try indexed.append(param);
        }
    }

    const indexed_slice = try indexed.toOwnedSlice();
    defer allocator.free(indexed_slice);

    if (indexed_slice.len == 0)
        return error.NoIndexedParams;

    // Just makes sure that the length is alligned.
    // This will get removed on non debug builds
    std.debug.assert(indexed_slice.len == encoded.len - 1);

    const fields = info.Struct.fields[1..];

    inline for (fields, 1..) |field, i| {
        const enc = encoded[i];
        const param = params[i - 1];

        if (enc) |enc_not_null| {
            result[i] = try decodeLog(allocator, field.type, param, enc_not_null);
        } else {
            const opt_info = @typeInfo(field.type);

            if (opt_info != .Optional)
                return error.UnexpectedTupleFieldType;

            result[i] = null;
        }
    }

    return result;
}

fn decodeLog(allocator: Allocator, comptime T: type, param: AbiEventParameter, encoded: []u8) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => return switch (param.type) {
            .bool => try std.fmt.parseInt(u1, encoded, 0) != 0,
            else => error.InvalidParamType,
        },
        .Int => |int_info| {
            switch (param.type) {
                .uint => {
                    if (int_info.signedness != .unsigned)
                        return error.ExpectedUnsignedInt;

                    const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded;
                    var buffer: [32]u8 = undefined;
                    _ = try std.fmt.hexToBytes(&buffer, slice);

                    const decoded = std.mem.readInt(u256, &buffer, .big);

                    return @as(T, @truncate(decoded));
                },
                .int => {
                    if (int_info.signedness != .signed)
                        return error.ExpectedSignedInt;

                    const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded;
                    var buffer: [32]u8 = undefined;
                    _ = try std.fmt.hexToBytes(&buffer, slice);

                    const decoded = std.mem.readInt(i256, &buffer, .big);

                    return @as(T, @truncate(decoded));
                },
                else => return error.InvalidParamType,
            }
        },
        .Optional => |opt_info| return try decodeLog(allocator, opt_info.child, param, encoded),
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes => {
                        if (arr_info.len != 32)
                            return error.ExpectedHashSize;

                        if (!utils.isHash(encoded))
                            return error.ExpectedHashString;

                        var buffer: [32]u8 = undefined;
                        _ = try std.fmt.hexToBytes(&buffer, encoded[2..]);

                        return buffer;
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.ExpectedAddressSize;

                        if (!utils.isHash(encoded))
                            return error.ExpectedEncodedAddress;

                        const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded[0..];
                        const addr = slice[24..];

                        return try utils.addressToBytes(addr);
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len)
                            return error.InvalidFixedBufferSize;

                        if (!utils.isHash(encoded))
                            return error.ExpectedEncodedBytes;

                        var buffer: [32]u8 = undefined;
                        const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded[0..];
                        _ = try std.fmt.hexToBytes(&buffer, slice);

                        return buffer[0..arr_info.len].*;
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
                .Slice => {
                    if (ptr_info.child == u8) {
                        switch (param.type) {
                            .string, .bytes => {
                                if (!utils.isHash(encoded))
                                    return error.ExpectedHashString;

                                return encoded;
                            },
                            else => return error.InvalidParamType,
                        }
                    }

                    @compileError("Non u8 slices are not supported");
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
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{@constCast("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};
    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{[]const u8}), event, slice);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{"0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"}, decoded.result);
}

test "Decode empty args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{});
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{@constCast("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")};

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{[]const u8}), event.value, slice);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{"0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"}, decoded.result);
}

test "Decode with args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{ @constCast("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, @constCast("0x000000000000000000000000a5cc3c03994db5b0d9a5eedd10cabab0813678ac") };

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, ?[]const u8, [20]u8 }), event.value, slice);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{ "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") }, decoded.result);
}

test "Decoded with args string/bytes" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, []const u8 }), event.value, slice);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ "0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a", "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8" }, decoded.result);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, ?[]const u8 }), event.value, slice);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ "0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a", "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8" }, decoded.result);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, []const u8 }), event.value, slice);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ "0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48", "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8" }, decoded.result);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, [32]u8 }), event.value, slice);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ "0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48", try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded.result);
    }
}

test "Decode Arrays" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer encoded.deinit();

        const decoded = try decodeLogs(testing.allocator, struct { []const u8, [20]u8 }, event.value, encoded.data);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ encoded.data[0], try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97") }, decoded.result);
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const decoded = try decodeLogs(testing.allocator, struct { []const u8, [5]u8 }, event.value, encoded.data);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ encoded.data[0], @constCast("hello").* }, decoded.result);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const decoded = try decodeLogs(testing.allocator, struct { []const u8, *const [5]u8 }, event.value, encoded.data);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ encoded.data[0], "hello" }, decoded.result);
    }
}

test "Decode with remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ 69, -420, true });
    defer encoded.deinit();

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, u256, i256, bool }), event.value, encoded.data);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{ "0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1", 69, -420, true }, decoded.result);
}

test "Errors" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedUnsignedInt, decodeLogs(testing.allocator, struct { []const u8, i256 }, event.value, encoded.data));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(int indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedSignedInt, decodeLogs(testing.allocator, struct { []const u8, u256 }, event.value, encoded.data));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedHashString, decodeLogs(testing.allocator, struct { []const u8, [32]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedHashSize, decodeLogs(testing.allocator, struct { []const u8, [2]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedEncodedAddress, decodeLogs(testing.allocator, struct { []const u8, [20]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedAddressSize, decodeLogs(testing.allocator, struct { []const u8, [2]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedEncodedBytes, decodeLogs(testing.allocator, struct { []const u8, [5]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        try testing.expectError(error.InvalidFixedBufferSize, decodeLogs(testing.allocator, struct { []const u8, [6]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer encoded.deinit();

        try testing.expectError(error.InvalidParamType, decodeLogs(testing.allocator, struct { []const u8, [6]u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{69});
        defer encoded.deinit();

        try testing.expectError(error.InvalidParamType, decodeLogs(testing.allocator, struct { []const u8, []const u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"FOOO"});
        defer encoded.deinit();

        try testing.expectError(error.ExpectedHashString, decodeLogs(testing.allocator, struct { []const u8, []const u8 }, event.value, &.{ encoded.data[0], @constCast("hello") }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string a)");
        defer event.deinit();

        try testing.expectError(error.NoIndexedParams, decodeLogs(testing.allocator, struct { []const u8, []const u8 }, event.value, &.{ "", "" }));
    }
}
