const std = @import("std");
const testing = std.testing;

// Types
const Allocator = std.mem.Allocator;

pub fn encodeSSZ(allocator: Allocator, values: anytype) ![]u8 {
    const info = @typeInfo(@TypeOf(values));

    if (info != .Struct or !info.Struct.is_tuple)
        @compileError("Expected values to be a tuple type");

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    inline for (values) |value| {
        try encodeItem(value, &list);
    }

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

fn isStaticType(comptime T: type) bool {
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

test "Bool" {
    {
        const encoded = try encodeSSZ(testing.allocator, .{true});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x01};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{false});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x00};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
}

test "Int" {
    {
        const encoded = try encodeSSZ(testing.allocator, .{@as(u8, 69)});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{0x45};

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{@as(u16, 69)});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0x45, 0x00 };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{@as(u32, 69)});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0x45, 0x00, 0x00, 0x00 };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{@as(i32, -69)});
        defer testing.allocator.free(encoded);

        const slice = &[_]u8{ 0xBB, 0xFF, 0xFF, 0xFF };

        try testing.expectEqualSlices(u8, slice, encoded);
    }
}

test "Arrays" {
    {
        const encoded = try encodeSSZ(testing.allocator, .{[_]bool{ true, false, true, true, false, false, false }});
        defer testing.allocator.free(encoded);

        const slice = [_]u8{0b00001101};

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{[_]bool{ true, false, true, true, false, false, false, true }});
        defer testing.allocator.free(encoded);

        const slice = [_]u8{0b10001101};

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{[_]bool{ true, false, true, true, false, false, false, true, false, true, false, true }});
        defer testing.allocator.free(encoded);

        const slice = [_]u8{ 0x8D, 0x0A };

        try testing.expectEqualSlices(u8, &slice, encoded);
    }
    {
        const encoded = try encodeSSZ(testing.allocator, .{[_]u16{ 0xABCD, 0xEF01 }});
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
        const encoded = try encodeSSZ(testing.allocator, .{data});
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
        const encoded = try encodeSSZ(testing.allocator, .{data});
        defer testing.allocator.free(encoded);

        const slice = [_]u8{ 9, 0, 0, 0, 32, 14, 0, 0, 0, 74, 97, 109, 101, 115, 68, 69, 86, 32, 73, 110, 99, 46 };
        try testing.expectEqualSlices(u8, &slice, encoded);
    }
}
