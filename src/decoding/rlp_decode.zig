const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const Allocator = std.mem.Allocator;
const encodeRlp = @import("../encoding/rlp.zig").encodeRlp;

pub const RlpDecodeErrors = error{ UnexpectedValue, InvalidEnumTag } || Allocator.Error || std.fmt.ParseIntError;

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

    std.debug.assert(encoded.len > 0); // Cannot decode 0 length;

    switch (info) {
        .Bool => {
            switch (encoded[position]) {
                0x80 => return .{ .consumed = 1, .data = false },
                0x01 => return .{ .consumed = 1, .data = true },
                else => return error.UnexpectedValue,
            }
        },
        .Int => {
            if (info.Int.signedness == .signed)
                @compileError("Signed integers are not supported for RLP decoding");

            if (encoded[position] < 0x80) return .{ .consumed = 1, .data = @intCast(encoded[position]) };
            const len = encoded[position] - 0x80;
            const hex_number = encoded[position + 1 .. position + len + 1];

            const hexed = std.fmt.fmtSliceHexLower(hex_number);
            const slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});

            defer alloc.free(slice);

            return .{ .consumed = len + 1, .data = if (slice.len != 0) try std.fmt.parseInt(T, slice, 16) else @intCast(0) };
        },
        .Float => {
            if (encoded[position] < 0x80) return .{ .consumed = 1, .data = @as(T, @floatFromInt(encoded[position])) };
            const len = encoded[position] - 0x80;
            const hex_number = encoded[position + 1 .. position + len + 1];

            const hexed = std.fmt.fmtSliceHexLower(hex_number);
            const slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
            defer alloc.free(slice);

            const bits = info.Float.bits;
            const AsInt = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bits } });
            const parsed = try std.fmt.parseInt(AsInt, slice, 16);
            return .{ .consumed = len + 1, .data = if (slice.len != 0) @as(T, @floatFromInt(parsed)) else @floatCast(0) };
        },
        .Null => if (encoded[position] != 0x80) return error.UnexpectedValue else return .{ .consumed = 1, .data = null },
        .Optional => |opt_info| {
            if (encoded[position] == 0x80) return .{ .consumed = 1, .data = null };

            const opt = try decodeItem(alloc, opt_info.child, encoded, position);
            return .{ .consumed = opt.consumed, .data = opt.data };
        },
        .Enum, .EnumLiteral => {
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

                    if (slice.len != arr_info.len)
                        return error.LengthMissmatch;

                    var result: T = undefined;
                    @memcpy(result[0..], slice[0..arr_info.len]);

                    return .{ .consumed = str_len + 1, .data = result };
                }
                const len_size = size - 0xb7;
                const len = encoded[position + 1 .. position + len_size + 1];
                const hexed = std.fmt.fmtSliceHexLower(len);
                const len_slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});
                defer alloc.free(len_slice);

                const parsed = try std.fmt.parseInt(usize, len_slice, 16);
                const slice = encoded[position + 1 + len_size .. position + parsed + 1 + len_size];

                if (slice.len != arr_info.len)
                    return error.LengthMissmatch;

                var result: T = undefined;
                @memcpy(result[0..], slice[0..arr_info.len]);

                return .{ .consumed = 2 + len_size + parsed, .data = result };
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

                        var read: usize = 0;
                        while (true) {
                            if (read >= arr_len)
                                break;

                            const decoded = try decodeItem(alloc, ptr_info.child, encoded[read + position + 1 ..], 0);
                            try result.append(decoded.data);
                            read += decoded.consumed;
                        }

                        std.debug.assert(read == arr_len);

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
                else => @compileError("Unable to parse pointer type " ++ @typeName(T)),
            }
        },
        .Vector => |vec_info| {
            const arr_size = encoded[position];

            if (arr_size <= 0xf7) {
                var result: T = undefined;

                var cur_pos = position + 1;
                for (0..vec_info.len) |i| {
                    const decoded = try decodeItem(alloc, vec_info.child, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = vec_info.len + 1, .data = result };
            }

            const arr_len = arr_size - 0xf7;
            var result: T = undefined;

            var cur_pos = position + arr_len + 1;
            for (0..vec_info.len) |i| {
                const decoded = try decodeItem(alloc, vec_info.child, encoded[cur_pos..], 0);
                result[i] = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = vec_info.len + 1, .data = result };
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
test "Decoded Float" {
    const low = try encodeRlp(testing.allocator, .{127});
    defer testing.allocator.free(low);
    const decoded_low = try decodeRlp(testing.allocator, f16, low);

    const float: f16 = 127;
    try testing.expectEqual(float, decoded_low);

    const medium = try encodeRlp(testing.allocator, .{69420});
    defer testing.allocator.free(medium);
    const decoded_medium = try decodeRlp(testing.allocator, f32, medium);

    const float_med: f32 = 69420;
    try testing.expectEqual(float_med, decoded_medium);
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
    {
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
    {
        const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing elit"});
        defer testing.allocator.free(lorem);
        const decoded_lorem = try decodeRlp(testing.allocator, [56]u8, lorem);

        try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", &decoded_lorem);

        const big = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

        const encoded = try encodeRlp(testing.allocator, .{big});
        defer testing.allocator.free(encoded);
        const decoded_big = try decodeRlp(testing.allocator, [895]u8, encoded);

        try testing.expectEqualStrings(big, &decoded_big);
    }
}

test "Decoded Vector" {
    {
        const one: @Vector(2, bool) = .{ true, true };
        const decoded_one = try decodeRlp(testing.allocator, @Vector(2, bool), &[_]u8{ 0xc2, 0x01, 0x01 });

        try testing.expectEqualDeep(&one, &decoded_one);
    }
    {
        const bigs: @Vector(256, u32) = [_]u32{0xf8} ** 256;
        const enc_bigs = try encodeRlp(testing.allocator, .{bigs});
        defer testing.allocator.free(enc_bigs);
        const decoded_bigs = try decodeRlp(testing.allocator, @Vector(256, u32), enc_bigs);

        try testing.expectEqualDeep(bigs, decoded_bigs);
    }
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
    {
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
    {
        const Enum = enum { qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh };
        const tuple: std.meta.Tuple(&[_]type{Enum}) = .{.qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh};

        const encoded = try encodeRlp(testing.allocator, tuple);
        defer testing.allocator.free(encoded);
        const decoded = try decodeRlp(testing.allocator, Enum, encoded);

        try testing.expectEqual(Enum.qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh, decoded);
    }
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

test "Errors" {
    try testing.expectError(error.UnexpectedValue, decodeRlp(testing.allocator, bool, &[_]u8{0x02}));

    {
        const lorem = try encodeRlp(testing.allocator, .{"Lorem ipsum dolor sit amet, consectetur adipisicing elit"});
        defer testing.allocator.free(lorem);
        const decoded_lorem = try decodeRlp(testing.allocator, [56]u8, lorem);

        try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", &decoded_lorem);

        const big = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

        const encoded = try encodeRlp(testing.allocator, .{big});
        defer testing.allocator.free(encoded);
        try testing.expectError(error.LengthMissmatch, decodeRlp(testing.allocator, [894]u8, encoded));
    }
}
