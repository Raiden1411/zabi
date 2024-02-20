const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const RlpEncodeErrors = error{ NegativeNumber, Overflow } || Allocator.Error;

pub const RlpDecodeErrors = error{ UnexpectedValue, InvalidEnumTag } || Allocator.Error || std.fmt.ParseIntError;

/// RLP Encoding. Items is expected to be a tuple of values.
/// Compilation will fail if you pass in any other type.
/// Caller owns the memory so it must be freed.
pub fn encodeRlp(alloc: Allocator, items: anytype) ![]u8 {
    const info = @typeInfo(@TypeOf(items));

    if (info != .Struct) @compileError("Expected tuple type instead found " ++ @typeName(@TypeOf(items)));
    if (!info.Struct.is_tuple) @compileError("Expected tuple type instead found " ++ @typeName(@TypeOf(items)));

    var list = std.ArrayList(u8).init(alloc);
    var writer = list.writer();

    inline for (items) |payload| {
        try encodeItem(alloc, payload, &writer);
    }

    return list.toOwnedSlice();
}
/// Reflects on the items and encodes based on it's type.
fn encodeItem(alloc: Allocator, payload: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(payload));

    switch (info) {
        .Bool => if (payload) try writer.writeByte(0x01) else try writer.writeByte(0x80),
        .Int => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                var buffer: [32]u8 = undefined;
                const size_slice = formatInt(@intCast(payload), &buffer);
                try writer.writeByte(0x80 + size_slice);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .ComptimeInt => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                const size = comptime computeSize(@intCast(payload));
                try writer.writeByte(0x80 + size);
                var buffer: [32]u8 = undefined;
                const size_slice = formatInt(@intCast(payload), &buffer);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .Float => |float_info| {
            if (payload < 0)
                return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
                const bits = float_info.bits;
                const IntType = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bits } });
                const as_int = @as(IntType, @bitCast(payload));
                var buffer: [32]u8 = undefined;
                const size_slice = formatInt(as_int, &buffer);
                try writer.writeByte(0x80 + size_slice);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .ComptimeFloat => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
                if (payload > std.math.maxInt(u256))
                    @compileError("Cannot fit " ++ payload ++ " as u256");

                const size = comptime computeSize(@intFromFloat(payload));
                try writer.writeByte(0x80 + size);
                var buffer: [32]u8 = undefined;
                const size_slice = formatInt(@intFromFloat(payload), &buffer);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .Optional => {
            if (payload) |item| try encodeItem(alloc, item, writer) else try writer.writeByte(0x80);
        },
        .Enum, .EnumLiteral => try encodeItem(alloc, @tagName(payload), writer),
        .ErrorSet => try encodeItem(alloc, @errorName(payload), writer),
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                const slice = slice: {
                    if (payload.len == 0) break :slice payload[0..];

                    if (std.mem.startsWith(u8, payload[0..], "0x")) {
                        break :slice payload[2..];
                    }

                    break :slice payload[0..];
                };
                const buf = try alloc.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);
                defer alloc.free(buf);

                const bytes = if (std.fmt.hexToBytes(buf, slice)) |result| result else |_| slice;

                if (bytes.len == 0) try writer.writeByte(0x80) else if (bytes.len < 56) {
                    try writer.writeByte(@intCast(0x80 + bytes.len));
                    try writer.writeAll(bytes);
                } else {
                    if (bytes.len > std.math.maxInt(u64)) return error.Overflow;
                    var buffer: [32]u8 = undefined;
                    const size = formatInt(bytes.len, &buffer);
                    try writer.writeByte(0xb7 + size);
                    try writer.writeAll(buffer[32 - size ..]);
                    try writer.writeAll(bytes);
                }
            } else {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    var arr = std.ArrayList(u8).init(alloc);
                    errdefer arr.deinit();
                    const arr_writer = arr.writer();

                    for (payload) |item| {
                        try encodeItem(alloc, item, &arr_writer);
                    }

                    const bytes = try arr.toOwnedSlice();
                    defer alloc.free(bytes);

                    if (bytes.len > std.math.maxInt(u64)) return error.Overflow;

                    if (bytes.len < 56) {
                        try writer.writeByte(@intCast(0xc0 + bytes.len));
                        try writer.writeAll(bytes);
                    } else {
                        var buffer: [32]u8 = undefined;
                        const size = formatInt(bytes.len, &buffer);
                        try writer.writeByte(0xf7 + size);
                        try writer.writeAll(buffer[32 - size ..]);
                        try writer.writeAll(bytes);
                    }
                }
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    try encodeItem(alloc, payload.*, writer);
                },
                .Slice, .Many => {
                    if (ptr_info.child == u8) {
                        const slice = slice: {
                            if (payload.len == 0) break :slice payload;

                            if (std.mem.startsWith(u8, payload, "0x")) {
                                break :slice payload[2..];
                            }

                            break :slice payload;
                        };

                        const buf = try alloc.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);
                        defer alloc.free(buf);

                        const bytes = if (std.fmt.hexToBytes(buf, slice)) |result| result else |_| slice;

                        if (bytes.len == 0) try writer.writeByte(0x80) else if (bytes.len < 56) {
                            try writer.writeByte(@intCast(0x80 + bytes.len));
                            try writer.writeAll(bytes);
                        } else {
                            if (bytes.len > std.math.maxInt(u64)) return error.Overflow;
                            var buffer: [32]u8 = undefined;
                            const size = formatInt(bytes.len, &buffer);
                            try writer.writeByte(0xb7 + size);
                            try writer.writeAll(buffer[32 - size ..]);
                            try writer.writeAll(bytes);
                        }
                    } else {
                        if (payload.len == 0) try writer.writeByte(0xc0) else {
                            var slice = std.ArrayList(u8).init(alloc);
                            errdefer slice.deinit();
                            const slice_writer = slice.writer();

                            for (payload) |item| {
                                try encodeItem(alloc, item, &slice_writer);
                            }

                            const bytes = try slice.toOwnedSlice();
                            defer alloc.free(bytes);

                            if (bytes.len > std.math.maxInt(u64)) return error.Overflow;

                            if (bytes.len < 56) {
                                try writer.writeByte(@intCast(0xc0 + bytes.len));
                                try writer.writeAll(bytes);
                            } else {
                                var buffer: [32]u8 = undefined;
                                const size = formatInt(bytes.len, &buffer);
                                try writer.writeByte(0xf7 + size);
                                try writer.writeAll(buffer[32 - size ..]);
                                try writer.writeAll(bytes);
                            }
                        }
                    }
                },
                else => @compileError("Unable to parse pointer type " ++ @typeName(@TypeOf(payload))),
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple) {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    var tuple = std.ArrayList(u8).init(alloc);
                    errdefer tuple.deinit();
                    const tuple_writer = tuple.writer();

                    inline for (payload) |item| {
                        try encodeItem(alloc, item, &tuple_writer);
                    }

                    const bytes = try tuple.toOwnedSlice();
                    defer alloc.free(bytes);

                    if (bytes.len > std.math.maxInt(u64)) return error.Overflow;

                    if (bytes.len < 56) {
                        try writer.writeByte(@intCast(0xc0 + bytes.len));
                        try writer.writeAll(bytes);
                    } else {
                        var buffer: [32]u8 = undefined;
                        const size = formatInt(bytes.len, &buffer);
                        try writer.writeByte(0xf7 + size);
                        try writer.writeAll(buffer[32 - size ..]);
                        try writer.writeAll(bytes);
                    }
                }
            } else {
                inline for (struct_info.fields) |field| {
                    try encodeItem(alloc, @field(payload, field.name), writer);
                }
            }
        },
        .Union => |union_info| {
            if (union_info.tag_type) |TagType| {
                inline for (union_info.fields) |u_field| {
                    if (payload == @field(TagType, u_field.name)) {
                        if (u_field.type == void) {
                            try encodeItem(alloc, u_field.name, writer);
                        } else try encodeItem(alloc, @field(payload, u_field.name), writer);
                    }
                }
            } else try encodeItem(alloc, @tagName(payload), writer);
        },
        .Vector => {
            if (payload.len == 0) try writer.writeByte(0xc0) else {
                var slice = std.ArrayList(u8).init(alloc);
                errdefer slice.deinit();
                const slice_writer = slice.writer();

                for (payload) |item| {
                    try encodeItem(alloc, item, &slice_writer);
                }

                const bytes = try slice.toOwnedSlice();
                defer alloc.free(bytes);

                if (bytes.len > std.math.maxInt(u64)) return error.Overflow;

                if (bytes.len < 56) {
                    try writer.writeByte(@intCast(0xc0 + bytes.len));
                    try writer.writeAll(bytes);
                } else {
                    var buffer: [32]u8 = undefined;
                    const size = formatInt(bytes.len, &buffer);
                    try writer.writeByte(0xf7 + size);
                    try writer.writeAll(buffer[32 - size ..]);
                    try writer.writeAll(bytes);
                }
            }
        },

        else => @compileError("Unable to parse type " ++ @typeName(@TypeOf(payload))),
    }
}
/// Computes the array or slice type size for RLP encoding
fn computePayloadSize(payload: anytype) u64 {
    var size: u64 = 0;
    const info = @typeInfo(@TypeOf(payload));

    switch (info) {
        .Array => {
            size += payload.len;
            for (payload) |item| {
                size += computePayloadSize(item);
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => size += computePayloadSize(payload.*),
                .Slice => {
                    size += payload.len;
                    for (payload) |item| {
                        size += computePayloadSize(item);
                    }
                },
                else => {},
            }
        },
        .Optional => {
            size += if (payload) |item| computePayloadSize(item) else 0;
        },
        .Struct => |struct_info| {
            if (!struct_info.is_tuple) @compileError("Only tuple types are supported for struct types");
            size += payload.len;

            inline for (payload) |item| {
                size += computePayloadSize(item);
            }
        },
        else => {},
    }

    return size;
}
/// Finds the size of an int and writes to the buffer accordingly.
inline fn formatInt(int: u256, buffer: *[32]u8) u8 {
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
    if (int < (1 << 64)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 8;
    }
    if (int < (1 << 72)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 9;
    }

    if (int < (1 << 80)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 10;
    }

    if (int < (1 << 88)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 11;
    }

    if (int < (1 << 96)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 12;
    }

    if (int < (1 << 104)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 13;
    }

    if (int < (1 << 112)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 14;
    }

    if (int < (1 << 120)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 15;
    }

    if (int < (1 << 128)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 16;
    }

    if (int < (1 << 136)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 17;
    }

    if (int < (1 << 144)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 18;
    }

    if (int < (1 << 152)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 19;
    }

    if (int < (1 << 160)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 20;
    }

    if (int < (1 << 168)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 21;
    }

    if (int < (1 << 176)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 22;
    }

    if (int < (1 << 184)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 23;
    }

    if (int < (1 << 192)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 24;
    }

    if (int < (1 << 200)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 25;
    }

    if (int < (1 << 208)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 26;
    }

    if (int < (1 << 216)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 27;
    }

    if (int < (1 << 224)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 28;
    }

    if (int < (1 << 232)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 29;
    }

    if (int < (1 << 240)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 30;
    }

    if (int < (1 << 248)) {
        buffer.* = @bitCast(@byteSwap(int));
        return 31;
    }

    buffer.* = @bitCast(@byteSwap(int));
    return 32;
}
/// Computes the size of a given int
inline fn computeSize(int: u256) u8 {
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

test "Float" {
    const low = try encodeRlp(testing.allocator, .{127.4});
    defer testing.allocator.free(low);

    try testing.expectEqualSlices(u8, low, &[_]u8{0x7f});

    const medium = try encodeRlp(testing.allocator, .{69420.45});
    defer testing.allocator.free(medium);

    try testing.expectEqualSlices(u8, medium, &[_]u8{ 0x83, 0x01, 0x0F, 0x2c });

    const big = try encodeRlp(testing.allocator, .{std.math.floatMax(f64)});
    defer testing.allocator.free(big);

    try testing.expectEqualSlices(u8, big, &[_]u8{ 0x88, 0x7F, 0xEF } ++ &[_]u8{0xFF} ** 6);
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

    try testing.expectEqualSlices(u8, enc_big, &[_]u8{ 0xf8, 0xFF } ++ &[_]u8{0x01} ** 255);

    const bigs: [255]u16 = [_]u16{0xf8} ** 255;
    const enc_bigs = try encodeRlp(testing.allocator, .{bigs});
    defer testing.allocator.free(enc_bigs);

    try testing.expectEqualSlices(u8, enc_bigs, &[_]u8{ 0xf9, 0x01, 0xFE } ++ &[_]u8{ 0x81, 0xf8 } ** 255);
}

test "Slices" {
    const one: []const bool = &[_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xc2, 0x01, 0x01 });

    const nested: []const [2]bool = &[_][2]bool{ [2]bool{ true, false }, [2]bool{ true, true }, [2]bool{ false, false } };

    const enc_nested = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(enc_nested);

    try testing.expectEqualSlices(u8, enc_nested, &[_]u8{ 0xc9, 0xc2, 0x01, 0x80, 0xc2, 0x01, 0x01, 0xc2, 0x80, 0x80 });

    const big: []const bool = &[_]bool{true} ** 256;
    const enc_big = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(enc_big);

    try testing.expectEqualSlices(u8, enc_big, &[_]u8{ 0xf9, 0x01, 0x00 } ++ &[_]u8{0x01} ** 256);
}

test "Tuples" {
    const one: std.meta.Tuple(&[_]type{i8}) = .{127};
    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xc1, 0x7f });

    const multi: std.meta.Tuple(&[_]type{ i8, bool, []const u8 }) = .{ 127, false, "foobar" };
    const enc_multi = try encodeRlp(testing.allocator, .{multi});
    defer testing.allocator.free(enc_multi);

    try testing.expectEqualSlices(u8, enc_multi, &[_]u8{ 0xc9, 0x7f, 0x80, 0x86 } ++ "foobar");

    const nested: std.meta.Tuple(&[_]type{[]const u64}) = .{&[_]u64{ 69, 420 }};
    const nested_enc = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(nested_enc);

    try testing.expectEqualSlices(u8, nested_enc, &[_]u8{ 0xc5, 0xc4, 0x45, 0x82, 0x01, 0xa4 });
}

test "Structs" {
    const Simple = struct { one: bool = true, two: i8 = 69, three: []const u8 = "foobar" };
    const ex: Simple = .{};
    const encoded = try encodeRlp(testing.allocator, .{ex});
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0x01, 0x45, 0x86 } ++ "foobar");

    const Nested = struct { one: bool = true, two: i8 = 69, three: []const u8 = "foobar", four: struct { five: u8 = 14 } = .{} };
    const nested_ex: Nested = .{};
    const encoded_nest = try encodeRlp(testing.allocator, .{nested_ex});
    defer testing.allocator.free(encoded_nest);

    try testing.expectEqualSlices(u8, encoded_nest, &[_]u8{ 0x01, 0x45, 0x86 } ++ "foobar" ++ &[_]u8{0x0E});
}

test "Enums" {
    const Enum = enum {
        foo,
        bar,
        baz,
    };
    {
        const tuple: std.meta.Tuple(&[_]type{Enum}) = .{.foo};

        const encoded = try encodeRlp(testing.allocator, tuple);
        defer testing.allocator.free(encoded);

        try testing.expectEqualSlices(u8, encoded, &[_]u8{0x83} ++ "foo");
    }
    // Enum literal
    {
        const encoded = try encodeRlp(testing.allocator, .{.foo});
        defer testing.allocator.free(encoded);

        try testing.expectEqualSlices(u8, encoded, &[_]u8{0x83} ++ "foo");
    }
}

test "ErrorSet" {
    const ErrorSet = error{
        foo,
        bar,
        baz,
    };
    const tuple: std.meta.Tuple(&[_]type{ErrorSet}) = .{error.foo};

    const encoded = try encodeRlp(testing.allocator, tuple);
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{0x83} ++ "foo");
}

test "Unions" {
    const Union = union(enum) {
        foo: i32,
        bar: bool,
        baz: []const u8,
    };
    {
        const tuple: std.meta.Tuple(&[_]type{Union}) = .{.{ .foo = 69 }};

        const encoded = try encodeRlp(testing.allocator, tuple);
        defer testing.allocator.free(encoded);

        try testing.expectEqualSlices(u8, encoded, &[_]u8{0x45});
    }

    {
        const tuple: std.meta.Tuple(&[_]type{Union}) = .{.{ .bar = true }};

        const encoded = try encodeRlp(testing.allocator, tuple);
        defer testing.allocator.free(encoded);

        try testing.expectEqualSlices(u8, encoded, &[_]u8{0x01});
    }

    {
        const tuple: std.meta.Tuple(&[_]type{Union}) = .{.{ .baz = "foo" }};

        const encoded = try encodeRlp(testing.allocator, tuple);
        defer testing.allocator.free(encoded);

        try testing.expectEqualSlices(u8, encoded, &[_]u8{0x83} ++ "foo");
    }
}

test "Optionals" {
    const Enum = enum {
        foo,
        bar,
        baz,
    };
    const tuple: std.meta.Tuple(&[_]type{ Enum, ?Enum }) = .{ .foo, null };

    const encoded = try encodeRlp(testing.allocator, tuple);
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{0x83} ++ "foo" ++ &[_]u8{0x80});
}

// Decode RLP

/// RLP decoding. Encoded string must follow the RLP specs.
pub fn decodeRlp(alloc: Allocator, comptime T: type, encoded: []const u8) !T {
    const decoded = try decodeItem(alloc, T, encoded, 0);

    return decoded.data;
}

fn DecodedResult(comptime T: type) type {
    return struct { consumed: u64, data: T };
}

fn decodeItem(alloc: Allocator, comptime T: type, encoded: []const u8, position: u64) !DecodedResult(T) {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => {
            switch (encoded[position]) {
                0x80 => return .{ .consumed = 1, .data = false },
                0x01 => return .{ .consumed = 1, .data = true },
                else => return error.UnexpectedValue,
            }
        },
        .Int => {
            if (encoded[position] < 0x80) return .{ .consumed = 1, .data = @intCast(encoded[position]) };
            const len = encoded[position] - 0x80;
            const hex_number = encoded[position + 1 .. position + len + 1];

            const hexed = std.fmt.fmtSliceHexLower(hex_number);
            const slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
            defer alloc.free(slice);

            if (info.Int.signedness == .signed) @compileError("Signed integers are not supported for RLP decoding");
            return .{ .consumed = len + 1, .data = if (slice.len != 0) try std.fmt.parseInt(T, slice, 16) else @intCast(0) };
        },
        .Optional => |opt_info| {
            if (encoded[position] == 0x80) return .{ .consumed = 1, .data = null };

            const opt = try decodeItem(alloc, opt_info.child, encoded, position);
            return .{ .consumed = opt.consumed, .data = opt.data };
        },
        .Enum => {
            const size = encoded[position];

            if (size <= 0xb7) {
                const str_len = size - 0x80;
                const slice = encoded[position + 1 .. position + str_len + 1];
                const e = std.meta.stringToEnum(T, slice) orelse return error.InvalidEnumTag;

                return .{ .consumed = str_len + 1, .data = e };
            }
            const len_size = size - 0xb7;
            const len = encoded[position + 1 .. position + len_size + 1];
            const hexed = std.fmt.fmtSliceHexLower(len);
            const len_slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
            defer alloc.free(len_slice);

            const parsed = try std.fmt.parseInt(usize, len_slice, 16);
            const e = std.meta.stringToEnum(T, encoded[position + len_size + 1 .. position + parsed + 1 + len_size]) orelse return error.InvalidEnumTag;

            return .{ .consumed = 2 + len_size + parsed, .data = e };
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                const size = encoded[position];

                if (size <= 0xb7) {
                    const str_len = size - 0x80;
                    const slice = encoded[position + 1 .. position + str_len + 1];

                    return .{ .consumed = str_len + 1, .data = slice };
                }
                const len_size = size - 0xb7;
                const len = encoded[position + 1 .. position + len_size + 1];
                const hexed = std.fmt.fmtSliceHexLower(len);
                const len_slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
                defer alloc.free(len_slice);

                const parsed = try std.fmt.parseInt(usize, len_slice, 16);

                return .{ .consumed = 2 + len_size + parsed, .data = encoded[position + 1 + len_size .. position + parsed + 1 + len_size] };
            }

            const arr_size = encoded[position];

            if (arr_size <= 0xf7) {
                var result: T = undefined;

                var cur_pos = position + 1;
                for (0..arr_info.len) |i| {
                    const decoded = try decodeItem(alloc, arr_info.child, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = arr_info.len + 1, .data = result };
            }

            const arr_len = arr_size - 0xf7;
            var result: T = undefined;

            var cur_pos = position + arr_len + 1;
            for (0..arr_info.len) |i| {
                const decoded = try decodeItem(alloc, arr_info.child, encoded[cur_pos..], 0);
                result[i] = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = arr_info.len + 1, .data = result };
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const res: *ptr_info.child = try alloc.create(ptr_info.child);
                    const decoded = try decodeItem(alloc, ptr_info.child, encoded, position);
                    res.* = decoded.data;

                    return .{ .consumed = decoded.consumed, .data = res };
                },
                .Slice => {
                    if (ptr_info.child == u8) {
                        const size = encoded[position];

                        if (size <= 0xb7) {
                            const str_len = size - 0x80;
                            const slice = encoded[position + 1 .. position + str_len + 1];

                            return .{ .consumed = str_len + 1, .data = slice };
                        }
                        const len_size = size - 0xb7;
                        const len = encoded[position + 1 .. position + len_size + 1];
                        const hexed = std.fmt.fmtSliceHexLower(len);
                        const len_slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
                        defer alloc.free(len_slice);

                        const parsed = try std.fmt.parseInt(usize, len_slice, 16);

                        return .{ .consumed = 2 + len_size + parsed, .data = encoded[position + 1 + len_size .. position + parsed + 1 + len_size] };
                    }
                    const arr_size = encoded[position];

                    if (arr_size <= 0xf7) {
                        const arr_len = arr_size - 0xC0;
                        var result = std.ArrayList(ptr_info.child).init(alloc);
                        errdefer result.deinit();

                        var cur_pos = position + 1;
                        for (0..arr_len) |_| {
                            if (cur_pos >= encoded.len) break;
                            const decoded = try decodeItem(alloc, ptr_info.child, encoded[cur_pos..], 0);
                            try result.append(decoded.data);
                            cur_pos += decoded.consumed;
                        }

                        return .{ .consumed = arr_len + 1, .data = try result.toOwnedSlice() };
                    }

                    const arr_len = arr_size - 0xf7;
                    const len = encoded[position + 1 .. position + arr_len + 1];
                    const hexed = std.fmt.fmtSliceHexLower(len);
                    const len_slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
                    defer alloc.free(len_slice);

                    const parsed_len = try std.fmt.parseInt(usize, len_slice, 16);
                    var result = std.ArrayList(ptr_info.child).init(alloc);
                    errdefer result.deinit();

                    var cur_pos = position + arr_len + 1;
                    for (0..parsed_len) |_| {
                        if (cur_pos >= encoded.len) break;
                        const decoded = try decodeItem(alloc, ptr_info.child, encoded[cur_pos..], 0);
                        try result.append(decoded.data);
                        cur_pos += decoded.consumed;
                    }

                    return .{ .consumed = cur_pos, .data = try result.toOwnedSlice() };
                },
                else => @compileError("Unable to parse type " ++ @typeName(T)),
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple) {
                const arr_size = encoded[position];
                if (arr_size <= 0xf7) {
                    var result: T = undefined;

                    var cur_pos = position + 1;
                    inline for (struct_info.fields, 0..) |field, i| {
                        const decoded = try decodeItem(alloc, field.type, encoded, cur_pos);
                        result[i] = decoded.data;
                        cur_pos += decoded.consumed;
                    }

                    return .{ .consumed = cur_pos, .data = result };
                }

                const arr_len = arr_size - 0xf7;
                var result: T = undefined;

                var cur_pos = position + arr_len + 1;
                inline for (struct_info.fields, 0..) |field, i| {
                    const decoded = try decodeItem(alloc, field.type, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = cur_pos, .data = result };
            }

            var result: T = undefined;

            var cur_pos = position;
            inline for (struct_info.fields) |field| {
                const decoded = try decodeItem(alloc, field.type, encoded, cur_pos);
                @field(result, field.name) = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = cur_pos, .data = result };
        },
        else => @compileError("Unable to parse type " ++ @typeName(T)),
    }
}

test "Decoded bool" {
    const t = try decodeRlp(testing.allocator, bool, &[_]u8{0x01});
    try testing.expect(t);

    const f = try decodeRlp(testing.allocator, bool, &[_]u8{0x80});
    try testing.expect(!f);
}

test "Decoded Int" {
    const low = try encodeRlp(testing.allocator, .{127});
    defer testing.allocator.free(low);
    const decoded_low = try decodeRlp(testing.allocator, u8, low);

    try testing.expectEqual(127, decoded_low);

    const medium = try encodeRlp(testing.allocator, .{69420});
    defer testing.allocator.free(medium);
    const decoded_medium = try decodeRlp(testing.allocator, u24, medium);

    try testing.expectEqual(69420, decoded_medium);

    const big = try encodeRlp(testing.allocator, .{std.math.maxInt(u64)});
    defer testing.allocator.free(big);
    const decoded_big = try decodeRlp(testing.allocator, u64, big);

    try testing.expectEqual(std.math.maxInt(u64), decoded_big);
}

test "Decoded Strings < 56" {
    const str = try encodeRlp(testing.allocator, .{"dog"});
    defer testing.allocator.free(str);
    const decoded_str = try decodeRlp(testing.allocator, []const u8, str);

    try testing.expectEqualStrings("dog", decoded_str);

    const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing eli"});
    defer testing.allocator.free(lorem);
    const decoded_lorem = try decodeRlp(testing.allocator, []const u8, lorem);

    try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing eli", decoded_lorem);
}

test "Decoded Strings > 56" {
    const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing elit"});
    defer testing.allocator.free(lorem);
    const decoded_lorem = try decodeRlp(testing.allocator, []const u8, lorem);

    try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", decoded_lorem);

    const big: []const u8 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

    const encoded = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(encoded);
    const decoded_big = try decodeRlp(testing.allocator, []const u8, encoded);

    try testing.expectEqualStrings(big, decoded_big);
}

test "Decoded Arrays" {
    const one: [2]bool = [_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);
    const decoded_one = try decodeRlp(testing.allocator, [2]bool, encoded);

    try testing.expectEqualSlices(bool, &one, &decoded_one);

    const nested: [2][]const bool = [2][]const bool{ &[_]bool{ true, false, true }, &[_]bool{true} };

    const enc_nested = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(enc_nested);
    const decoded_nested = try decodeRlp(testing.allocator, [2][]const bool, enc_nested);
    defer testing.allocator.free(decoded_nested[0]);
    defer testing.allocator.free(decoded_nested[1]);

    try testing.expectEqualSlices(bool, nested[0], decoded_nested[0]);
    try testing.expectEqualSlices(bool, nested[1], decoded_nested[1]);

    const big: [256]bool = [_]bool{true} ** 256;
    const enc_big = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(enc_big);
    const decoded_big = try decodeRlp(testing.allocator, [256]bool, enc_big);

    try testing.expectEqualSlices(bool, &big, &decoded_big);

    const bigs: [256]u32 = [_]u32{0xf8} ** 256;
    const enc_bigs = try encodeRlp(testing.allocator, .{bigs});
    defer testing.allocator.free(enc_bigs);
    const decoded_bigs = try decodeRlp(testing.allocator, [256]u32, enc_bigs);

    try testing.expectEqualSlices(u32, &bigs, &decoded_bigs);

    const strings: [2][]const u8 = [2][]const u8{ "foo", "bar" };
    const enc_str = try encodeRlp(testing.allocator, .{strings});
    defer testing.allocator.free(enc_str);

    const dec_str = try decodeRlp(testing.allocator, [2][]const u8, enc_str);

    try testing.expectEqualStrings(strings[0], dec_str[0]);
    try testing.expectEqualStrings(strings[1], dec_str[1]);
}

test "Decoded Slices" {
    const one: []const bool = &[_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);
    const decoded_one = try decodeRlp(testing.allocator, []const bool, encoded);
    defer testing.allocator.free(decoded_one);

    try testing.expectEqualSlices(bool, one, decoded_one);

    const nested: []const [2]bool = &[_][2]bool{ [2]bool{ true, false }, [2]bool{ true, true }, [2]bool{ false, false } };

    const enc_nested = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(enc_nested);
    const decoded_nested = try decodeRlp(testing.allocator, []const [2]bool, enc_nested);
    defer testing.allocator.free(decoded_nested);

    try testing.expectEqualSlices(u8, enc_nested, &[_]u8{ 0xc9, 0xc2, 0x01, 0x80, 0xc2, 0x01, 0x01, 0xc2, 0x80, 0x80 });

    const big: []const u32 = &[_]u32{0x69} ** 256;
    const enc_big = try encodeRlp(testing.allocator, .{big});
    defer testing.allocator.free(enc_big);

    const decoded_big = try decodeRlp(testing.allocator, []const u32, enc_big);
    defer testing.allocator.free(decoded_big);

    try testing.expectEqualSlices(u32, big, decoded_big);

    const strings: []const []const u8 = &.{ "foo", "bar" };
    const enc_str = try encodeRlp(testing.allocator, .{strings});
    defer testing.allocator.free(enc_str);

    const dec_str = try decodeRlp(testing.allocator, []const []const u8, enc_str);
    defer testing.allocator.free(dec_str);

    try testing.expectEqualStrings(strings[0], dec_str[0]);
    try testing.expectEqualStrings(strings[1], dec_str[1]);
}

test "Decoded Enums" {
    const Enum = enum {
        foo,
        bar,
        baz,
    };
    const tuple: std.meta.Tuple(&[_]type{Enum}) = .{.foo};

    const encoded = try encodeRlp(testing.allocator, tuple);
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(testing.allocator, Enum, encoded);

    try testing.expectEqual(Enum.foo, decoded);
}

test "Decoded Optionals" {
    const Enum = enum {
        foo,
        bar,
        baz,
    };
    const tuple: std.meta.Tuple(&[_]type{?Enum}) = .{null};

    const encoded = try encodeRlp(testing.allocator, tuple);
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(testing.allocator, ?Enum, encoded);

    try testing.expectEqual(null, decoded);
}

test "Decoded Structs" {
    const Simple = struct { one: bool = true, two: u8 = 69, three: []const u8 = "foobar" };
    const ex: Simple = .{};
    const encoded = try encodeRlp(testing.allocator, .{ex});
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(testing.allocator, Simple, encoded);

    try testing.expectEqual(ex.one, decoded.one);
    try testing.expectEqual(ex.two, decoded.two);
    try testing.expectEqualStrings(ex.three, decoded.three);

    const Nested = struct { one: bool = true, two: u8 = 69, three: []const u8 = "foobar", four: struct { five: u8 = 14 } = .{} };
    const nested_ex: Nested = .{};
    const encoded_nest = try encodeRlp(testing.allocator, .{nested_ex});
    defer testing.allocator.free(encoded_nest);
    const decoded_nested = try decodeRlp(testing.allocator, Nested, encoded_nest);

    try testing.expectEqual(nested_ex.one, decoded_nested.one);
    try testing.expectEqual(nested_ex.two, decoded_nested.two);
    try testing.expectEqualStrings(nested_ex.three, decoded_nested.three);
    try testing.expectEqual(nested_ex.four, decoded_nested.four);
}

test "Decoded Tuples" {
    const one: std.meta.Tuple(&[_]type{u8}) = .{127};
    const encoded = try encodeRlp(testing.allocator, .{one});
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{u8}), encoded);

    try testing.expectEqual(one, decoded);

    const multi: std.meta.Tuple(&[_]type{ u8, bool, []const u8 }) = .{ 127, false, "foobar" };
    const enc_multi = try encodeRlp(testing.allocator, .{multi});
    defer testing.allocator.free(enc_multi);
    const decoded_multi = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{ u8, bool, []const u8 }), enc_multi);

    try testing.expectEqual(multi[0], decoded_multi[0]);
    try testing.expectEqual(multi[1], decoded_multi[1]);
    try testing.expectEqualStrings(multi[2], decoded_multi[2]);

    const nested: std.meta.Tuple(&[_]type{[]const u64}) = .{&[_]u64{ 69, 420 }};
    const nested_enc = try encodeRlp(testing.allocator, .{nested});
    defer testing.allocator.free(nested_enc);
    const decoded_nested = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{[]const u64}), nested_enc);
    defer testing.allocator.free(decoded_nested[0]);

    try testing.expectEqualSlices(u64, nested[0], decoded_nested[0]);
}

test "Decoded Pointer" {
    const big = try encodeRlp(testing.allocator, .{&std.math.maxInt(u64)});
    defer testing.allocator.free(big);
    const decoded_big = try decodeRlp(testing.allocator, *u64, big);
    defer testing.allocator.destroy(decoded_big);

    try testing.expectEqual(std.math.maxInt(u64), decoded_big.*);
}
