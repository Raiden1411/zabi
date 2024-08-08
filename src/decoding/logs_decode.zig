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
const Endian = std.builtin.Endian;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

// Functions
const encodeLogs = @import("../encoding/logs.zig").encodeLogTopics;

/// Set of options that can alter the decoder behaviour.
pub const LogDecoderOptions = struct {
    /// Optional allocation in the case that you want to create a pointer
    /// That pointer must be destroyed later.
    allocator: ?Allocator = null,
    /// Tells the endianess of the bytes that you want to decode
    /// Addresses are encoded in big endian and bytes1..32 are encoded in little endian.
    /// There might be some cases where you will need to decode a bytes20 and address at the same time.
    /// Since they can represent the same type it's advised to decode the address as `u160` and change this value to `little`.
    /// since it already decodes as big-endian and then `std.mem.writeInt` the value to the expected endianess.
    bytes_endian: Endian = .big,
};

/// Decodes the abi encoded slice. This will ensure that the provided type
/// is always a tuple struct type and that the first member type is a [32]u8 type.
/// No allocations are made unless you want to create a pointer type and provide the optional
/// allocator.
///
/// **Example:**
/// ```zig
/// const encodeds = try decodeLogs(
///     struct { [32]u8 },
///     &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")},
///     .{},
/// );
/// ```
pub fn decodeLogs(comptime T: type, encoded: []const ?Hash, options: LogDecoderOptions) !T {
    const info = @typeInfo(T);
    comptime {
        std.debug.assert(info == .Struct and info.Struct.is_tuple); // Must be a struct type and tuple struct type.
        std.debug.assert(info.Struct.fields[0].type == Hash); // The first member must always be a [32]u8 type.
    }

    if (encoded.len == 0)
        return error.InvalidLength;

    var result: T = undefined;

    const fields = info.Struct.fields;

    inline for (fields, encoded, 0..) |field, enc, i| {
        if (enc) |non_null| {
            result[i] = try decodeLog(field.type, non_null, options);
        } else {
            const opt_info = @typeInfo(field.type);

            if (opt_info != .Optional)
                return error.UnexpectedTupleFieldType;

            result[i] = null;
        }
    }

    return result;
}

/// Decodes the abi encoded bytes. Not all types are supported.
/// Bellow there is a list of supported types.
///
/// Supported:
///     - Bool, Int, Optional, Arrays, Pointer.
///
/// For Arrays only u8 child types are supported and must be 32 or lower of length.
/// For Pointer types the pointers on `One` size are supported. All other are unsupported.
///
/// **Example:**
/// ```zig
/// const decoded = try decodeLog(u256, try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"), .{});
/// ```
pub fn decodeLog(comptime T: type, encoded: Hash, options: LogDecoderOptions) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => {
            const value = std.mem.readInt(u256, &encoded, .big);

            return @as(u1, @truncate(value)) != 0;
        },
        .Int => |int_value| {
            const IntType = switch (int_value.signedness) {
                .signed => i256,
                .unsigned => u256,
            };

            const value = std.mem.readInt(IntType, &encoded, .big);

            return @as(T, @truncate(value));
        },
        .Optional => |opt_info| return try decodeLog(opt_info.child, encoded, options),
        .Array => |arr_info| {
            if (arr_info.child != u8)
                @compileError("Only u8 arrays are supported. Found: " ++ @typeName(T));

            if (arr_info.len > 32)
                @compileError("Only [32]u8 arrays and lower are supported. Found: " ++ @typeName(T));

            const AsInt = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = arr_info.len * 8 } });

            var result: T = undefined;

            const as_number = std.mem.readInt(u256, &encoded, options.bytes_endian);
            std.mem.writeInt(AsInt, &result, @truncate(as_number), options.bytes_endian);

            return result;
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const allocator = options.allocator orelse return error.ExpectedAllocator;

                    const pointer = try allocator.create(ptr_info.child);
                    errdefer allocator.destroy(pointer);

                    pointer.* = try decodeLog(ptr_info.child, encoded, options);

                    return pointer;
                },
                else => @compileError("Unsupported pointer type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => @compileError("Unsupported pointer type '" ++ @typeName(T) ++ "'"),
    }
}

test "Decode empty inputs" {
    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};
    const decoded = try decodeLogs(struct { Hash }, slice, .{});

    try testing.expectEqualDeep(.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}, decoded);
}

test "Decode empty args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{});
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(struct { Hash }, encoded, .{});

    try testing.expectEqualDeep(.{try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")}, decoded);
}

test "Decode with args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(struct { Hash, ?Hash, [20]u8 }, encoded, .{});

    try testing.expectEqualDeep(.{ try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") }, decoded);
}

test "Decoded with args string/bytes" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, ?Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
}

test "Decode Arrays" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, [20]u8 }, encoded, .{});

        try testing.expectEqualDeep(.{ encoded[0], try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97") }, decoded);
    }

    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, [5]u8 }, encoded, .{ .bytes_endian = .little });

        try testing.expectEqualDeep(.{ encoded[0], "hello".* }, decoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, *const [5]u8 }, encoded, .{ .allocator = testing.allocator, .bytes_endian = .little });
        defer testing.allocator.destroy(decoded[1]);

        try testing.expectEqualDeep(.{ encoded[0], "hello" }, decoded);
    }
}

test "Decode with remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value, .{ 69, -420, true });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, u256, i256, bool }), encoded, .{});

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

        try testing.expectError(error.ExpectedAllocator, decodeLogs(struct { Hash, *const [5]u8 }, encoded, .{ .bytes_endian = .little }));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value, .{null});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.UnexpectedTupleFieldType, decodeLogs(struct { Hash, [5]u8 }, encoded, .{ .bytes_endian = .little }));
    }
}
