//! The code bellow is essentially a port of https://github.com/gballet/ssz.zig/tree/master
//! to the most recent version of zig with a couple of stylistic changes and support for
//! other zig types.

const std = @import("std");
const testing = std.testing;

// Types
const Allocator = std.mem.Allocator;

/// Performs ssz encoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).
/// Almost all zig types are supported.
///
/// Caller owns the memory
pub fn encodeSSZ(allocator: Allocator, value: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try encodeItem(value, &list);

    return try list.toOwnedSlice();
}

fn encodeItem(value: anytype, list: *std.ArrayList(u8)) !void {
    const info = @typeInfo(@TypeOf(value));
    var writer = list.writer();

    switch (info) {
        .Bool => try writer.writeInt(u8, @intFromBool(value), .little),
        .Int => |int_info| {
            switch (int_info.bits) {
                8, 16, 32, 64, 128, 256 => try writer.writeInt(@TypeOf(value), value, .little),
                else => @compileError(std.fmt.comptimePrint("Unsupported {d} bits for ssz encoding", .{int_info.bits})),
            }
        },
        .Null => return,
        .Optional => {
            if (value) |val| {
                try writer.writeInt(u8, 1, .little);
                return try encodeItem(val, list);
            } else try writer.writeInt(u8, 0, .little);
        },
        .Union => |union_info| {
            if (union_info.tag_type == null)
                @compileError("Untagged unions are not supported");

            inline for (union_info.fields, 0..) |field, i| {
                if (@intFromEnum(value) == i) {
                    try writer.writeInt(u8, i, .little);
                    return try encodeItem(@field(value, field.name), list);
                }
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeItem(value.*, list),
                .Slice => {
                    if (ptr_info.child == u8) {
                        try writer.writeAll(value);
                        return;
                    }

                    for (value) |val| {
                        try encodeItem(val, list);
                    }
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
            }
        },
        .Vector => |vec_info| {
            if (vec_info.child == bool) {
                var as_byte: u8 = 0;
                for (value, 0..) |val, i| {
                    if (val) {
                        as_byte |= @as(u8, 1) << @as(u3, @truncate(i));
                    }

                    if (i % 8 == 7) {
                        try writer.writeByte(as_byte);
                        as_byte = 0;
                    }
                }

                if (as_byte % 8 != 0)
                    try writer.writeByte(as_byte);

                return;
            }

            for (0..vec_info.len) |i| {
                try encodeItem(value[i], list);
            }
        },
        .Enum, .EnumLiteral => try writer.writeAll(@tagName(value)),
        .ErrorSet => try writer.writeAll(@errorName(value)),
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                try writer.writeAll(&value);
                return;
            }

            if (arr_info.child == bool) {
                var as_byte: u8 = 0;
                for (value, 0..) |val, i| {
                    if (val) {
                        as_byte |= @as(u8, 1) << @as(u3, @truncate(i));
                    }

                    if (i % 8 == 7) {
                        try writer.writeByte(as_byte);
                        as_byte = 0;
                    }
                }

                if (as_byte % 8 != 0)
                    try writer.writeByte(as_byte);

                return;
            }

            if (isStaticType(arr_info.child)) {
                for (value) |val| {
                    try encodeItem(val, list);
                }
                return;
            }

            var offset_start = list.items.len;

            for (value) |_| {
                try writer.writeInt(u32, 0, .little);
            }

            for (value) |val| {
                std.mem.writeInt(u32, list.items[offset_start .. offset_start + 4][0..4], @as(u32, @truncate(list.items.len)), .little);
                try encodeItem(val, list);
                offset_start += 4;
            }
        },
        .Struct => |struct_info| {
            comptime var start: usize = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Int, .Bool => start += @sizeOf(field.type),
                    else => start += 4,
                }
            }

            var accumulate: usize = start;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Int, .Bool => try encodeItem(@field(value, field.name), list),
                    else => {
                        try encodeItem(@as(u32, @truncate(accumulate)), list);
                        accumulate += sizeOfValue(@field(value, field.name));
                    },
                }
            }

            if (accumulate > start) {
                inline for (struct_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Bool, .Int => continue,
                        else => try encodeItem(@field(value, field.name), list),
                    }
                }
            }
        },
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
}

test "Bool" {
    {
        const encoded = try encodeSSZ(testing.allocator, true);
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x01};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, false);
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x00};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
}

test "Int" {
    {
        const encoded = try encodeSSZ(testing.allocator, @as(u8, 69));
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x45};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, @as(u16, 69));
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0x45, 0x00 };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, @as(u32, 69));
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0x45, 0x00, 0x00, 0x00 };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, @as(i32, -69));
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0xBB, 0xFF, 0xFF, 0xFF };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
}

test "Arrays" {
    {
        const encoded = try encodeSSZ(testing.allocator, [_]bool{ true, false, true, true, false, false, false });
        defer testing.allocator.free(encoded);

        const slice = [_]u8{0b00001101};

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, [_]bool{ true, false, true, true, false, false, false, true });
        defer testing.allocator.free(encoded);

        const slice = [_]u8{0b10001101};

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, [_]bool{ true, false, true, true, false, false, false, true, false, true, false, true });
        defer testing.allocator.free(encoded);

        const slice = [_]u8{ 0x8D, 0x0A };

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, [_]u16{ 0xABCD, 0xEF01 });
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0xCD, 0xAB, 0x01, 0xEF };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
}

test "Struct" {
    {
        const data = .{
            .uint8 = @as(u8, 1),
            .uint32 = @as(u32, 3),
            .boolean = true,
        };
        const encoded = try encodeSSZ(testing.allocator, data);
        defer testing.allocator.free(encoded);

        const slice = [_]u8{ 1, 3, 0, 0, 0, 1 };
        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const data = .{
            .name = "James",
            .age = @as(u8, 32),
            .company = "DEV Inc.",
        };
        const encoded = try encodeSSZ(testing.allocator, data);
        defer testing.allocator.free(encoded);

        const slice = [_]u8{ 9, 0, 0, 0, 32, 14, 0, 0, 0, 74, 97, 109, 101, 115, 68, 69, 86, 32, 73, 110, 99, 46 };
        try testing.expectEqualSlices(u8, &slice, encoded);
    }
}

// Decoding

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

            if (isStaticType(arr_info.child)) {
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

// Helpers
fn sizeOfValue(value: anytype) usize {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Array => return value.len,
        .Pointer => switch (info.Pointer.size) {
            .Slice => return value.len,
            else => return sizeOfValue(value.*),
        },
        .Optional => return if (value == null)
            @intCast(1)
        else
            1 + sizeOfValue(value.?),
        .Null => return @intCast(0),
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
    // It should never reach this
    unreachable;
}

inline fn isStaticType(comptime T: type) bool {
    const info = @typeInfo(T);

    switch (info) {
        .Bool, .Int, .Null => return true,
        .Array => return false,
        .Struct => inline for (info.Struct.fields) |field| {
            if (!isStaticType(field.type)) {
                return false;
            }
        },
        .Pointer => switch (info.Pointer.size) {
            .Many, .Slice, .C => return false,
            .One => return isStaticType(info.Pointer.child),
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
    // It should never reach this
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
