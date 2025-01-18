const std = @import("std");
const abi = @import("zabi-abi").abitypes;
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

// Types
const AbiEvent = abi.Event;
const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;
const Hash = types.Hash;

/// Set of possible errors while performing logs decoding.
pub const LogsDecoderErrors = Allocator.Error || error{ InvalidLength, UnexpectedTupleFieldType, ExpectedAllocator };

/// Set of possible errors while performing logs decoding.
pub const LogDecoderErrors = Allocator.Error || error{ExpectedAllocator};

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
pub fn decodeLogs(comptime T: type, encoded: []const ?Hash, options: LogDecoderOptions) LogsDecoderErrors!T {
    const info = @typeInfo(T);
    comptime {
        std.debug.assert(info == .@"struct" and info.@"struct".is_tuple); // Must be a struct type and tuple struct type.
        std.debug.assert(info.@"struct".fields[0].type == Hash); // The first member must always be a [32]u8 type.
    }

    if (encoded.len == 0)
        return error.InvalidLength;

    var result: T = undefined;

    const fields = info.@"struct".fields;

    inline for (fields, encoded, 0..) |field, enc, i| {
        if (enc) |non_null| {
            result[i] = try decodeLog(field.type, non_null, options);
        } else {
            const opt_info = @typeInfo(field.type);

            if (opt_info != .optional)
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
pub fn decodeLog(comptime T: type, encoded: Hash, options: LogDecoderOptions) LogDecoderErrors!T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            const value = std.mem.readInt(u256, &encoded, .big);

            return @as(u1, @truncate(value)) != 0;
        },
        .int => |int_value| {
            const IntType = switch (int_value.signedness) {
                .signed => i256,
                .unsigned => u256,
            };

            const value = std.mem.readInt(IntType, &encoded, .big);

            return @as(T, @truncate(value));
        },
        .optional => |opt_info| return try decodeLog(opt_info.child, encoded, options),
        .array => |arr_info| {
            if (arr_info.child != u8)
                @compileError("Only u8 arrays are supported. Found: " ++ @typeName(T));

            if (arr_info.len > 32)
                @compileError("Only [32]u8 arrays and lower are supported. Found: " ++ @typeName(T));

            const AsInt = @Type(.{ .int = .{ .signedness = .unsigned, .bits = arr_info.len * 8 } });

            var result: T = undefined;

            const as_number = std.mem.readInt(u256, &encoded, options.bytes_endian);
            std.mem.writeInt(AsInt, &result, @truncate(as_number), options.bytes_endian);

            return result;
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
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
