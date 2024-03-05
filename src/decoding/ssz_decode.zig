//! The code bellow is essentially a port of https://github.com/gballet/ssz.zig/tree/master
//! to the most recent version of zig with a couple of stylistic changes and support for
//! other zig types.

const std = @import("std");
const testing = std.testing;
const utils = @import("../utils.zig");

// Types
const Allocator = std.mem.Allocator;
const encodeSSZ = @import("../encoding/ssz.zig").encodeSSZ;

/// Performs ssz decoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).
pub fn decodeSSZ(comptime T: type, serialized: []const u8) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => return serialized[0] != 0,
        .Int => |int_info| return std.mem.readInt(T, serialized[0..@divExact(int_info.bits, 8)], .little),
        .Optional => |opt_info| {
            const index = serialized[0];

            if (index != 0) {
                const result: opt_info.child = try decodeSSZ(opt_info.child, serialized[1..]);
                return result;
            } else return null;
        },
        .Enum => {
            const to_enum = std.meta.stringToEnum(T, serialized[0..]) orelse return error.InvalidEnumType;

            return to_enum;
        },
        .Array => |arr_info| {
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
        .Vector => |vec_info| {
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
        .Pointer => return serialized[0..],
        .Union => |union_info| {
            const union_index = try decodeSSZ(u8, serialized);

            inline for (union_info.fields, 0..) |field, i| {
                if (union_index == i) {
                    return @unionInit(T, field.name, try decodeSSZ(field.type, serialized[1..]));
                }
            }
        },
        .Struct => |struct_info| {
            comptime var num_fields = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool, .Int => continue,
                    else => num_fields += 1,
                }
            }

            var indices: [num_fields]u32 = undefined;
            var result: T = undefined;

            comptime var index = 0;
            comptime var field_index = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool, .Int => {
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
                    .Bool, .Int => continue,
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

test "Decoded Bool" {
    {
        const decoded = try decodeSSZ(bool, &[_]u8{0x01});

        try testing.expect(decoded);
    }
    {
        const decoded = try decodeSSZ(bool, &[_]u8{0x00});

        try testing.expect(!decoded);
    }
}

test "Decoded Int" {
    {
        const decoded = try decodeSSZ(u8, &[_]u8{0x45});
        try testing.expectEqual(69, decoded);
    }
    {
        const decoded = try decodeSSZ(u16, &[_]u8{ 0x45, 0x00 });
        try testing.expectEqual(69, decoded);
    }
    {
        const decoded = try decodeSSZ(u32, &[_]u8{ 0x45, 0x00, 0x00, 0x00 });
        try testing.expectEqual(69, decoded);
    }
    {
        const decoded = try decodeSSZ(i32, &[_]u8{ 0xBB, 0xFF, 0xFF, 0xFF });
        try testing.expectEqual(-69, decoded);
    }
}

test "Decoded String" {
    {
        const slice: []const u8 = "FOO";

        const decoded = try decodeSSZ([]const u8, slice);

        try testing.expectEqualStrings(slice, decoded);
    }
    {
        const slice = "FOO";

        const decoded = try decodeSSZ([]const u8, slice);

        try testing.expectEqualStrings(slice, decoded);
    }
    {
        const Enum = enum { foo, bar };

        const encode = try encodeSSZ(testing.allocator, Enum.foo);
        defer testing.allocator.free(encode);

        const decoded = try decodeSSZ(Enum, encode);

        try testing.expectEqual(Enum.foo, decoded);
    }
}

test "Decoded Array" {
    {
        const encoded = [_]bool{ true, false, true, true, false, false, false, true, false, true, false, true };

        const slice = [_]u8{ 0x8D, 0x0A };

        const decoded = try decodeSSZ([12]bool, &slice);

        try testing.expectEqualSlices(bool, &encoded, &decoded);
    }
    {
        const encoded = [_]u16{ 0xABCD, 0xEF01 };

        const slice = &[_]u8{ 0xCD, 0xAB, 0x01, 0xEF };

        const decoded = try decodeSSZ([2]u16, slice);

        try testing.expectEqualSlices(u16, &encoded, &decoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, pastries);
        defer testing.allocator.free(encoded);
        const decoded = try decodeSSZ([2]Pastry, encoded);

        try testing.expectEqualDeep(pastries, decoded);
    }
}

const Pastry = struct {
    name: []const u8,
    weight: u16,
};

const pastries = [_]Pastry{
    Pastry{
        .name = "croissant",
        .weight = 20,
    },
    Pastry{
        .name = "Herrentorte",
        .weight = 500,
    },
};

test "Decode Struct" {
    const pastry = Pastry{
        .name = "croissant",
        .weight = 20,
    };

    const encoded = try encodeSSZ(testing.allocator, pastry);
    defer testing.allocator.free(encoded);

    const decoded = try decodeSSZ(Pastry, encoded);

    try testing.expectEqualDeep(pastry, decoded);
}

test "Decode Union" {
    const Union = union(enum) {
        foo: u32,
        bar: bool,
    };

    {
        const un = Union{ .foo = 69 };
        const encoded = try encodeSSZ(testing.allocator, un);
        defer testing.allocator.free(encoded);

        const decoded = try decodeSSZ(Union, encoded);

        try testing.expectEqualDeep(un, decoded);
    }
    {
        const un = Union{ .bar = true };
        const encoded = try encodeSSZ(testing.allocator, un);
        defer testing.allocator.free(encoded);

        const decoded = try decodeSSZ(Union, encoded);

        try testing.expectEqualDeep(un, decoded);
    }
}

test "Decode Optional" {
    const foo: ?u32 = 69;

    const encoded = try encodeSSZ(testing.allocator, foo);
    defer testing.allocator.free(encoded);

    const decoded = try decodeSSZ(?u32, encoded);

    try testing.expectEqualDeep(foo, decoded);
}

test "Decode Vector" {
    {
        const encoded: @Vector(12, bool) = .{ true, false, true, true, false, false, false, true, false, true, false, true };
        const slice = [_]u8{ 0x8D, 0x0A };

        const decoded = try decodeSSZ(@Vector(12, bool), &slice);

        try testing.expectEqualDeep(encoded, decoded);
    }
    {
        const encoded: @Vector(2, u16) = .{ 0xABCD, 0xEF01 };
        const slice = &[_]u8{ 0xCD, 0xAB, 0x01, 0xEF };

        const decoded = try decodeSSZ(@Vector(2, u16), slice);

        try testing.expectEqualDeep(encoded, decoded);
    }
}
