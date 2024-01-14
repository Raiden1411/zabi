const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

fn encodeRlp(alloc: Allocator, items: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(alloc);
    var writer = list.writer();

    inline for (items) |payload| {
        try encodeItem(payload, &writer);
    }

    return list.toOwnedSlice();
}
fn encodeItem(payload: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(payload));

    switch (info) {
        .Bool => if (payload) try writer.writeByte(0x01) else try writer.writeByte(0x80),
        .Int => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                const size = @divExact(@typeInfo(@TypeOf(payload)).Int.bits, 8);
                try writer.writeByte(0x80 + size);
                try writer.writeInt(@TypeOf(payload), payload, .big);
            }
        },
        .ComptimeInt => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                const size = comptime computeSize(payload);
                try writer.writeByte(0x80 + size);
                try writer.writeInt(@Type(.{ .Int = .{ .signedness = .unsigned, .bits = size * 8 } }), payload, .big);
            }
        },
        .Optional => {
            if (payload) |item| try encodeItem(item, writer) else try writer.writeByte(0x80);
        },
        .Enum => {
            try encodeItem(@tagName(payload), writer);
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
                    try writer.writeByte(@intCast(0x80 + payload.len));
                    try writer.writeAll(&payload);
                } else {
                    if (payload.len > std.math.maxInt(u64)) return error.Overflow;
                    var buffer: [8]u8 = undefined;
                    const size = formatInt(payload.len, &buffer);
                    try writer.writeByte(0xb7 + size);
                    try writer.writeAll(buffer[8 - size ..]);
                    try writer.writeAll(&payload);
                }
            } else {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    const nested_size = computeNestedSize(payload);
                    if (nested_size < 56) {
                        try writer.writeByte(@intCast(0xc0 + nested_size));
                        for (payload) |item| {
                            try encodeItem(item, writer);
                        }
                    } else {
                        var buffer: [8]u8 = undefined;
                        const size = formatInt(payload.len, &buffer);
                        try writer.writeByte(0x7b + size);
                        try writer.writeAll(buffer[8 - size ..]);
                        for (payload) |item| {
                            try encodeItem(item, writer);
                        }
                    }
                }
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    try encodeItem(payload.*, writer);
                },
                .Slice => {
                    if (ptr_info.child == u8) {
                        if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
                            try writer.writeByte(@intCast(0x80 + payload.len));
                            try writer.writeAll(payload);
                        } else {
                            if (payload.len > std.math.maxInt(u64)) return error.Overflow;
                            var buffer: [8]u8 = undefined;
                            const size = formatInt(payload.len, &buffer);
                            try writer.writeByte(0xb7 + size);
                            try writer.writeAll(buffer[8 - size ..]);
                            try writer.writeAll(payload);
                        }
                    } else {
                        if (payload.len == 0) try writer.writeByte(0xc0) else {
                            const nested_size = computeNestedSize(payload);
                            if (nested_size > std.math.maxInt(u64)) return error.Overflow;
                            if (nested_size < 56) {
                                try writer.writeByte(@intCast(0xc0 + nested_size));
                                for (payload) |item| {
                                    try encodeItem(item, writer);
                                }
                            } else {
                                var buffer: [8]u8 = undefined;
                                const size = formatInt(payload.len, &buffer);
                                try writer.writeByte(0x7b + size);
                                try writer.writeAll(buffer[8 - size ..]);
                                for (payload) |item| {
                                    try encodeItem(item, writer);
                                }
                            }
                        }
                    }
                },
                else => @compileError("Unable to parse type " ++ @typeName(@TypeOf(payload))),
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple) {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    const nested_size = computeNestedTupleSize(payload);
                    if (nested_size > std.math.maxInt(u64)) return error.Overflow;
                    if (nested_size < 56) {
                        try writer.writeByte(@intCast(0xc0 + nested_size));
                        inline for (payload) |item| {
                            try encodeItem(item, writer);
                        }
                    } else {
                        var buffer: [8]u8 = undefined;
                        const size = formatInt(payload.len, &buffer);
                        try writer.writeByte(0x7b + size);
                        try writer.writeAll(buffer[8 - size ..]);
                        inline for (payload) |item| {
                            try encodeItem(item, writer);
                        }
                    }
                }
            } else {
                inline for (struct_info.fields) |field| {
                    try encodeItem(@field(payload, field.name), writer);
                }
            }
        },
        else => @compileError("Unable to parse type " ++ @typeName(@TypeOf(payload))),
    }
}

fn computeNestedTupleSize(payload: anytype) u64 {
    var size: u64 = payload.len;

    switch (@typeInfo(@TypeOf(payload))) {
        .Array => |arr_info| {
            if (arr_info.child == u8) return 0;
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (ptr_info.child == u8) return 0;
                },
                else => {},
            }
        },
        else => {},
    }

    inline for (payload) |item| {
        const info = @typeInfo(@TypeOf(item));
        switch (info) {
            .Array => |arr_info| {
                if (arr_info.child != u8) size += computeNestedSize(item);
            },
            .Pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => {
                        size += computeNestedTupleSize(item.*);
                    },
                    .Slice => {
                        if (ptr_info.child != u8) size += computeNestedSize(item);
                    },
                    else => continue,
                }
            },
            .Struct => |struct_info| {
                if (!struct_info.is_tuple) @compileError("Only tuple types are supported for struct types");

                size += computeNestedTupleSize(item);
            },
            else => continue,
        }
    }

    return size;
}

fn computeNestedSize(payload: anytype) u64 {
    var size: u64 = payload.len;

    switch (@typeInfo(@TypeOf(payload))) {
        .Array => |arr_info| {
            if (arr_info.child == u8) return 0;
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (ptr_info.child == u8) return 0;
                },
                else => {},
            }
        },
        else => {},
    }

    for (payload) |item| {
        const info = @typeInfo(@TypeOf(item));
        switch (info) {
            .Array => |arr_info| {
                if (arr_info.child != u8) size += computeNestedSize(item) else size -= item.len;
            },
            .Pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => size += computeNestedSize(item.*),
                    .Slice => {
                        if (ptr_info.child != u8) size += computeNestedSize(item) else size -= item.len;
                    },
                    else => continue,
                }
            },
            .Struct => |struct_info| {
                if (!struct_info.is_tuple) @compileError("Only tuple types are supported for struct types");

                size += computeNestedTupleSize(item);
            },
            else => continue,
        }
    }

    return size;
}
fn formatInt(int: u64, buffer: *[8]u8) u8 {
    if (int < (1 << 8)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 1;
    }
    if (int < (1 << 16)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 2;
    }
    if (int < (1 << 24)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 3;
    }
    if (int < (1 << 32)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 4;
    }
    if (int < (1 << 40)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 5;
    }
    if (int < (1 << 48)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 6;
    }
    if (int < (1 << 56)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 7;
    }

    buffer.* = @bitCast(@byteSwap(int));
    return 8;
}

fn computeSize(int: u256) u8 {
    if (int < (1 << 8)) return 1;
    if (int < (1 << 16)) return 2;
    if (int < (1 << 24)) return 3;
    if (int < (1 << 32)) return 4;
    if (int < (1 << 40)) return 5;
    if (int < (1 << 48)) return 6;
    if (int < (1 << 56)) return 7;
    if (int < (1 << 64)) return 8;
    if (int < (1 << 72)) return 9;
    if (int < (1 << 80)) return 10;
    if (int < (1 << 88)) return 11;
    if (int < (1 << 96)) return 12;
    if (int < (1 << 104)) return 13;
    if (int < (1 << 112)) return 14;
    if (int < (1 << 120)) return 15;
    if (int < (1 << 128)) return 16;
    if (int < (1 << 136)) return 17;
    if (int < (1 << 144)) return 18;
    if (int < (1 << 152)) return 19;
    if (int < (1 << 160)) return 20;
    if (int < (1 << 168)) return 21;
    if (int < (1 << 176)) return 22;
    if (int < (1 << 184)) return 23;
    if (int < (1 << 192)) return 24;
    if (int < (1 << 200)) return 25;
    if (int < (1 << 208)) return 26;
    if (int < (1 << 216)) return 27;
    if (int < (1 << 224)) return 28;
    if (int < (1 << 232)) return 29;
    if (int < (1 << 240)) return 30;
    if (int < (1 << 248)) return 31;

    return 32;
}

test "Empty" {
    const empty = try encodeRlp(testing.allocator, .{ false, "", 0 });
    defer testing.allocator.free(empty);

    try testing.expectEqualSlices(u8, empty, &[_]u8{0x80} ** 3);
}

test "Int" {
    const low = try encodeRlp(testing.allocator, .{127});
    defer testing.allocator.free(low);

    try testing.expectEqualSlices(u8, low, &[_]u8{0x7f});

    const medium = try encodeRlp(testing.allocator, .{69420});
    defer testing.allocator.free(medium);

    try testing.expectEqualSlices(u8, medium, &[_]u8{ 0x83, 0x01, 0x0F, 0x2c });

    const big = try encodeRlp(testing.allocator, .{std.math.maxInt(u64)});
    defer testing.allocator.free(big);

    try testing.expectEqualSlices(u8, big, &[_]u8{0x88} ++ &[_]u8{0xFF} ** 8);
}

test "Strings < 56" {
    const str = try encodeRlp(testing.allocator, .{"dog"});
    defer testing.allocator.free(str);

    try testing.expectEqualSlices(u8, str, &[_]u8{ 0x83, 0x64, 0x6f, 0x67 });

    const multi = try encodeRlp(testing.allocator, .{ "dog", "cat" });
    defer testing.allocator.free(multi);

    try testing.expectEqualSlices(u8, multi, &[_]u8{ 0x83, 0x64, 0x6f, 0x67, 0x83, 0x63, 0x61, 0x74 });

    const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing eli"});
    defer testing.allocator.free(lorem);

    try testing.expectEqualSlices(u8, lorem, &[_]u8{0xB7} ++ "Lorem ipsum dolor sit amet, consectetur adipisicing eli");
}

test "Strings > 56" {
    const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing elit"});
    defer testing.allocator.free(lorem);

    try testing.expectEqualSlices(u8, lorem, &[_]u8{ 0xB8, 0x38 } ++ "Lorem ipsum dolor sit amet, consectetur adipisicing elit");

    const big: []const u8 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

    const encoded = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(encoded);
    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xB9, 0x03, 0x7F } ++ big);
}

test "Arrays" {
    const one: [2]bool = [_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xc2, 0x01, 0x01 });

    const nested: [2][]const bool = [2][]const bool{ &[_]bool{ true, false, true }, &[_]bool{true} };

    const enc_nested = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(enc_nested);

    try testing.expectEqualSlices(u8, enc_nested, &[_]u8{ 0xc6, 0xc3, 0x01, 0x80, 0x01, 0xc1, 0x01 });

    const set_theoretical_representation = try encodeRlp(testing.allocator, .{&.{ &.{}, &.{&.{}}, &.{ &.{}, &.{&.{}} } }});
    defer testing.allocator.free(set_theoretical_representation);

    try testing.expectEqualSlices(u8, set_theoretical_representation, &[_]u8{ 0xc7, 0xc0, 0xc1, 0xc0, 0xc3, 0xc0, 0xc1, 0xc0 });

    const big: [255]bool = [_]bool{true} ** 255;
    const enc_big = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(enc_big);

    try testing.expectEqualSlices(u8, enc_big, &[_]u8{ 0x7c, 0xFF } ++ &[_]u8{0x01} ** 255);
}
