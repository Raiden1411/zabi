//! The code bellow is essentially a port of https://github.com/gballet/ssz.zig/tree/master
//! to the most recent version of zig with a couple of stylistic changes and support for
//! other zig types.

const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

// Types
const Allocator = std.mem.Allocator;

/// Set of possible errors while performing ssz decoding.
pub const SSZDecodeErrors = Allocator.Error || error{ InvalidEnumType, IndexOutOfBounds };

/// Performs ssz decoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).
pub fn decodeSSZ(comptime T: type, serialized: []const u8) SSZDecodeErrors!T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => return serialized[0] != 0,
        .int => |int_info| return std.mem.readInt(T, serialized[0..@divExact(int_info.bits, 8)], .little),
        .optional => |opt_info| {
            const index = serialized[0];

            if (index != 0) {
                const result: opt_info.child = try decodeSSZ(opt_info.child, serialized[1..]);
                return result;
            } else return null;
        },
        .@"enum" => {
            const to_enum = std.meta.stringToEnum(T, serialized[0..]) orelse return error.InvalidEnumType;

            return to_enum;
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                return serialized[0..];
            }

            var result: T = undefined;

            if (arr_info.child == bool) {
                for (serialized, 0..) |byte, bindex| {
                    var index: u8 = 0;
                    var bit = byte;
                    while (bindex * 8 + index < arr_info.len and index < 8) : (index += 1) {
                        result[bindex * 8 + index] = bit & 1 == 1;
                        bit >>= 1;
                    }
                }

                return result;
            }

            if (utils.isStaticType(arr_info.child)) {
                comptime var index = 0;
                const size = @sizeOf(arr_info.child);

                inline while (index < arr_info.len) : (index += 1) {
                    result[index] = try decodeSSZ(arr_info.child, serialized[index * size .. (index + 1) * size]);
                }

                return result;
            }

            const size = std.mem.readInt(u32, serialized[0..4], .little) / @sizeOf(u32);
            const indices = std.mem.bytesAsSlice(u32, serialized[0 .. size * 4]);

            var index: usize = 0;
            while (index < size) : (index += 1) {
                const final = if (index < size - 1) indices[index + 1] else serialized.len;
                const start = indices[index];

                if (start >= serialized.len or final > serialized.len)
                    return error.IndexOutOfBounds;

                result[index] = try decodeSSZ(arr_info.child, serialized[start..final]);
            }

            return result;
        },
        .vector => |vec_info| {
            var result: T = undefined;

            if (vec_info.child == bool) {
                for (serialized, 0..) |byte, bindex| {
                    var index: u8 = 0;
                    var bit = byte;
                    while (bindex * 8 + index < vec_info.len and index < 8) : (index += 1) {
                        result[bindex * 8 + index] = bit & 1 == 1;
                        bit >>= 1;
                    }
                }

                return result;
            }

            comptime var index = 0;
            const size = @sizeOf(vec_info.child);

            inline while (index < vec_info.len) : (index += 1) {
                result[index] = try decodeSSZ(vec_info.child, serialized[index * size .. (index + 1) * size]);
            }

            return result;
        },
        .pointer => return serialized[0..],
        .@"union" => |union_info| {
            const union_index = try decodeSSZ(u8, serialized);

            inline for (union_info.fields, 0..) |field, i| {
                if (union_index == i) {
                    return @unionInit(T, field.name, try decodeSSZ(field.type, serialized[1..]));
                }
            }
        },
        .@"struct" => |struct_info| {
            comptime var num_fields = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .bool, .int => continue,
                    else => num_fields += 1,
                }
            }

            var indices: [num_fields]u32 = undefined;
            var result: T = undefined;

            comptime var index = 0;
            comptime var field_index = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .bool, .int => {
                        @field(result, field.name) = try decodeSSZ(field.type, serialized[index .. index + @sizeOf(field.type)]);
                        index += @sizeOf(field.type);
                    },
                    else => {
                        indices[field_index] = try decodeSSZ(u32, serialized[index .. index + 4]);
                        index += 4;
                        field_index += 1;
                    },
                }
            }

            comptime var final_index = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .bool, .int => continue,
                    else => {
                        const final = if (final_index == indices.len - 1) serialized.len else indices[final_index + 1];
                        @field(result, field.name) = try decodeSSZ(field.type, serialized[indices[final_index]..final]);
                        final_index += 1;
                    },
                }
            }

            return result;
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }

    // it should never be reached
    unreachable;
}
