const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/meta.zig");
const testing = std.testing;
const utils = @import("../utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

pub const LogsEncoded = struct {
    arena: *ArenaAllocator,
    data: []const ?[]u8,

    pub fn deinit(self: @This()) void {
        const child_allocator = self.arena.child_allocator;
        self.arena.deinit();

        child_allocator.destroy(self.arena);
    }
};

pub fn encodeLogs(allocator: Allocator, params: AbiEvent, values: anytype) !LogsEncoded {
    var encoded_logs: LogsEncoded = .{ .arena = try allocator.create(ArenaAllocator), .data = undefined };
    errdefer allocator.destroy(encoded_logs.arena);

    encoded_logs.arena.* = ArenaAllocator.init(allocator);

    const child_allocator = encoded_logs.arena.allocator();

    encoded_logs.data = try encodeLogsLeaky(child_allocator, params, values);

    return encoded_logs;
}

/// Encode event log topics
/// **Currently indexed topics are not supported**
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
/// Result: \["0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"\]
pub fn encodeLogsLeaky(allocator: Allocator, event: AbiEvent, values: anytype) ![]const ?[]u8 {
    const info = @typeInfo(@TypeOf(values));

    if (info != .Struct or !info.Struct.is_tuple)
        @compileError("Expected tuple type but found " ++ @typeName(@TypeOf(values)));

    var list = try std.ArrayList(?[]u8).initCapacity(allocator, values.len + 1);
    errdefer list.deinit();

    try list.append(try event.encode(allocator));

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
                        const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        _ = try std.fmt.hexToBytes(buffer[12..], hex);

                        return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&buffer)});
                    },
                    .fixedBytes => |size| {
                        const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        _ = try std.fmt.hexToBytes(buffer[0..size], hex);

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
                            .address => {
                                const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                                var buffer: [32]u8 = [_]u8{0} ** 32;
                                _ = try std.fmt.hexToBytes(buffer[12..], hex);

                                return try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer)});
                            },
                            .fixedBytes => |size| {
                                const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                                var buffer: [32]u8 = [_]u8{0} ** 32;
                                _ = try std.fmt.hexToBytes(buffer[0..size], hex);

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

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, "0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC" });
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

// Decoding

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

pub fn decodeLogs(allocator: Allocator, comptime T: type, event: AbiEvent, encoded: []const ?[]u8) !DecodedLogs(T) {
    var decoded: DecodedLogs(T) = .{ .arena = try allocator.create(ArenaAllocator), .result = undefined };
    errdefer allocator.destroy(decoded.arena);

    decoded.arena.* = ArenaAllocator.init(allocator);

    const child_allocator = decoded.arena.allocator();

    decoded.result = try decodeLogsLeaky(child_allocator, T, event, encoded);

    return decoded;
}

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

                    return try std.fmt.parseInt(T, encoded, 0);
                },
                .int => {
                    if (int_info.signedness != .signed)
                        return error.ExpectedSignedInt;

                    const parsed = std.fmt.parseInt(T, encoded, 0) catch |err| {
                        switch (err) {
                            error.Overflow => {
                                const parsedUnsigned = try std.fmt.parseInt(u256, encoded, 0);
                                const negative = std.math.cast(T, (std.math.maxInt(u256) - parsedUnsigned) + 1) orelse return err;
                                return -negative;
                            },
                            inline else => return err,
                        }
                    };

                    return parsed;
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
                            @compileError("Expect array size of 32");

                        if (!utils.isHash(encoded))
                            return error.ExpectedHashString;

                        var buffer: [32]u8 = undefined;
                        _ = try std.fmt.hexToBytes(&buffer, encoded[2..]);

                        return buffer;
                    },
                    .address => {
                        if (arr_info.len != 20)
                            @compileError("Invalid array size. Expected to have a size of 20");

                        if (!utils.isHash(encoded))
                            return error.ExpectedEncodedAddress;

                        const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else &encoded;
                        const addr = slice[24..];

                        const checksumed = try utils.toChecksum(allocator, addr);
                        var buffer: T = undefined;
                        _ = try std.fmt.hexToBytes(&buffer, checksumed[2..]);

                        return buffer;
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len)
                            return error.InvalidFixedBufferSize;

                        if (!utils.isHash(encoded))
                            return error.ExpectedEncodedBytes;

                        var buffer: [32]u8 = undefined;
                        const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else &encoded;
                        _ = try std.fmt.hexToBytes(&buffer, slice);

                        return buffer[0..size].*;
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
                            .address => {
                                if (!utils.isHash(encoded))
                                    return error.ExpectedEncodedAddress;

                                const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded;
                                const addr = slice[24..];

                                return try utils.toChecksum(allocator, addr);
                            },
                            .fixedBytes => |size| {
                                if (!utils.isHash(encoded))
                                    return error.ExpectedEncodedBytes;

                                var buffer: [32]u8 = undefined;
                                const slice = if (std.mem.startsWith(u8, encoded, "0x")) encoded[2..] else encoded;
                                _ = try std.fmt.hexToBytes(&buffer, slice);

                                const hexed = try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..size])});

                                return hexed;
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

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, "0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC" });
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{ @constCast("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, @constCast("0x000000000000000000000000a5cc3c03994db5b0d9a5eedd10cabab0813678ac") };

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, ?[]const u8, []const u8 }), event.value, slice);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{ "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", null, "0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC" }, decoded.result);
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
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer encoded.deinit();

        const slice: []const ?[]u8 = &.{ @constCast("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), @constCast("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, []const u8 }), event.value, slice);
        defer decoded.deinit();

        try testing.expectEqualDeep(.{ "0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48", "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8" }, decoded.result);
    }
}

test "Decode with remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ 69, -420, true });
    defer encoded.deinit();

    const slice: []const ?[]u8 = &.{ @constCast("0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1"), @constCast("0x0000000000000000000000000000000000000000000000000000000000000045"), @constCast("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe5c"), @constCast("0x0000000000000000000000000000000000000000000000000000000000000001") };

    const decoded = try decodeLogs(testing.allocator, std.meta.Tuple(&[_]type{ []const u8, u256, i256, bool }), event.value, slice);
    defer decoded.deinit();

    try testing.expectEqualDeep(.{ "0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1", 69, -420, true }, decoded.result);
}
