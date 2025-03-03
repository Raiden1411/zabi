const std = @import("std");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const encodeRlp = @import("zabi").encoding.rlp.encodeRlp;
const decodeRlp = @import("zabi").decoding.rlp.decodeRlp;

test "Decoded bool" {
    const t = try decodeRlp(bool, testing.allocator, &[_]u8{0x01});
    try testing.expect(t);

    const f = try decodeRlp(bool, testing.allocator, &[_]u8{0x80});
    try testing.expect(!f);
}

test "Decoded Int" {
    const low = try encodeRlp(testing.allocator, 127);
    defer testing.allocator.free(low);
    const decoded_low = try decodeRlp(u8, testing.allocator, low);

    try testing.expectEqual(127, decoded_low);

    const medium = try encodeRlp(testing.allocator, 69420);
    defer testing.allocator.free(medium);
    const decoded_medium = try decodeRlp(u24, testing.allocator, medium);

    try testing.expectEqual(69420, decoded_medium);

    const big = try encodeRlp(testing.allocator, std.math.maxInt(u64));
    defer testing.allocator.free(big);
    const decoded_big = try decodeRlp(u64, testing.allocator, big);

    try testing.expectEqual(std.math.maxInt(u64), decoded_big);
}

test "Decoded Strings < 56" {
    const str = try encodeRlp(testing.allocator, "dog");
    defer testing.allocator.free(str);
    const decoded_str = try decodeRlp([]const u8, testing.allocator, str);

    try testing.expectEqualStrings("dog", decoded_str);

    const lorem = try encodeRlp(testing.allocator, "Lorem ipsum dolor sit amet, consectetur adipisicing eli");
    defer testing.allocator.free(lorem);
    const decoded_lorem = try decodeRlp([]const u8, testing.allocator, lorem);

    try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing eli", decoded_lorem);
}

test "Decoded Strings > 56" {
    {
        const lorem = try encodeRlp(testing.allocator, "Lorem ipsum dolor sit amet, consectetur adipisicing elit");
        defer testing.allocator.free(lorem);
        const decoded_lorem = try decodeRlp([]const u8, testing.allocator, lorem);

        try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", decoded_lorem);

        const big: []const u8 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

        const encoded = try encodeRlp(testing.allocator, big);
        defer testing.allocator.free(encoded);
        const decoded_big = try decodeRlp([]const u8, testing.allocator, encoded);

        try testing.expectEqualStrings(big, decoded_big);
    }
    {
        const lorem = try encodeRlp(testing.allocator, "Lorem ipsum dolor sit amet, consectetur adipisicing elit");
        defer testing.allocator.free(lorem);
        const decoded_lorem = try decodeRlp([56]u8, testing.allocator, lorem);

        try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", &decoded_lorem);

        const big = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

        const encoded = try encodeRlp(testing.allocator, big);
        defer testing.allocator.free(encoded);
        const decoded_big = try decodeRlp([895]u8, testing.allocator, encoded);

        try testing.expectEqualStrings(big, &decoded_big);
    }
}

test "Decoded Arrays" {
    const one: [2]bool = [_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, one);
    defer testing.allocator.free(encoded);
    const decoded_one = try decodeRlp([2]bool, testing.allocator, encoded);

    try testing.expectEqualSlices(bool, &one, &decoded_one);

    const nested: [2][]const bool = [2][]const bool{ &[_]bool{ true, false, true }, &[_]bool{true} };

    const enc_nested = try encodeRlp(testing.allocator, nested);
    defer testing.allocator.free(enc_nested);
    const decoded_nested = try decodeRlp([2][]const bool, testing.allocator, enc_nested);
    defer testing.allocator.free(decoded_nested[0]);
    defer testing.allocator.free(decoded_nested[1]);

    try testing.expectEqualSlices(bool, nested[0], decoded_nested[0]);
    try testing.expectEqualSlices(bool, nested[1], decoded_nested[1]);

    const big: [256]bool = [_]bool{true} ** 256;
    const enc_big = try encodeRlp(testing.allocator, big);
    defer testing.allocator.free(enc_big);
    const decoded_big = try decodeRlp([256]bool, testing.allocator, enc_big);

    try testing.expectEqualSlices(bool, &big, &decoded_big);

    const bigs: [256]u32 = [_]u32{0xf8} ** 256;
    const enc_bigs = try encodeRlp(testing.allocator, bigs);
    defer testing.allocator.free(enc_bigs);
    const decoded_bigs = try decodeRlp([256]u32, testing.allocator, enc_bigs);

    try testing.expectEqualSlices(u32, &bigs, &decoded_bigs);

    const strings: [2][]const u8 = [2][]const u8{ "foo", "bar" };
    const enc_str = try encodeRlp(testing.allocator, strings);
    defer testing.allocator.free(enc_str);

    const dec_str = try decodeRlp([2][]const u8, testing.allocator, enc_str);

    try testing.expectEqualStrings(strings[0], dec_str[0]);
    try testing.expectEqualStrings(strings[1], dec_str[1]);
}

test "Decoded Slices" {
    const one: []const bool = &[_]bool{ true, true };

    const encoded = try encodeRlp(testing.allocator, one);
    defer testing.allocator.free(encoded);
    const decoded_one = try decodeRlp([]const bool, testing.allocator, encoded);
    defer testing.allocator.free(decoded_one);

    try testing.expectEqualSlices(bool, one, decoded_one);

    const nested: []const [2]bool = &[_][2]bool{ [2]bool{ true, false }, [2]bool{ true, true }, [2]bool{ false, false } };

    const enc_nested = try encodeRlp(testing.allocator, nested);
    defer testing.allocator.free(enc_nested);
    const decoded_nested = try decodeRlp([]const [2]bool, testing.allocator, enc_nested);
    defer testing.allocator.free(decoded_nested);

    try testing.expectEqualSlices(u8, enc_nested, &[_]u8{ 0xc9, 0xc2, 0x01, 0x80, 0xc2, 0x01, 0x01, 0xc2, 0x80, 0x80 });

    const big: []const u32 = &[_]u32{0x69} ** 256;
    const enc_big = try encodeRlp(testing.allocator, big);
    defer testing.allocator.free(enc_big);

    const decoded_big = try decodeRlp([]const u32, testing.allocator, enc_big);
    defer testing.allocator.free(decoded_big);

    try testing.expectEqualSlices(u32, big, decoded_big);

    const strings: []const []const u8 = &.{ "foo", "bar" };
    const enc_str = try encodeRlp(testing.allocator, strings);
    defer testing.allocator.free(enc_str);

    const dec_str = try decodeRlp([]const []const u8, testing.allocator, enc_str);
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

        const encoded = try encodeRlp(testing.allocator, Enum.foo);
        defer testing.allocator.free(encoded);
        const decoded = try decodeRlp(Enum, testing.allocator, encoded);

        try testing.expectEqual(Enum.foo, decoded);
    }
    {
        const Enum = enum { qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh };

        const encoded = try encodeRlp(testing.allocator, Enum.qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh);
        defer testing.allocator.free(encoded);
        const decoded = try decodeRlp(Enum, testing.allocator, encoded);

        try testing.expectEqual(Enum.qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmasdfghjklwertyuiopzxcvbnmasdfghdsafgsadffbgnbhbfvgfjhdshsfghdfhbhgfjdvdsfhbfgh, decoded);
    }
}

test "Decoded Optionals" {
    const Enum = enum {
        foo,
        bar,
        baz,
    };
    const value: ?Enum = null;

    const encoded = try encodeRlp(testing.allocator, value);
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(?Enum, testing.allocator, encoded);

    try testing.expectEqual(null, decoded);
}

test "Decoded Structs" {
    const Simple = struct { one: bool = true, two: u8 = 69, three: []const u8 = "foobar" };
    const ex: Simple = .{};
    const encoded = try encodeRlp(testing.allocator, ex);
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(Simple, testing.allocator, encoded);

    try testing.expectEqual(ex.one, decoded.one);
    try testing.expectEqual(ex.two, decoded.two);
    try testing.expectEqualStrings(ex.three, decoded.three);

    const Nested = struct { one: bool = true, two: u8 = 69, three: []const u8 = "foobar", four: struct { five: u8 = 14 } = .{} };
    const nested_ex: Nested = .{};
    const encoded_nest = try encodeRlp(testing.allocator, nested_ex);
    defer testing.allocator.free(encoded_nest);
    const decoded_nested = try decodeRlp(Nested, testing.allocator, encoded_nest);

    try testing.expectEqual(nested_ex.one, decoded_nested.one);
    try testing.expectEqual(nested_ex.two, decoded_nested.two);
    try testing.expectEqualStrings(nested_ex.three, decoded_nested.three);
    try testing.expectEqual(nested_ex.four, decoded_nested.four);
}

test "Decoded Tuples" {
    const one: std.meta.Tuple(&[_]type{u8}) = .{127};
    const encoded = try encodeRlp(testing.allocator, one);
    defer testing.allocator.free(encoded);
    const decoded = try decodeRlp(std.meta.Tuple(&[_]type{u8}), testing.allocator, encoded);

    try testing.expectEqual(one, decoded);

    const multi: std.meta.Tuple(&[_]type{ u8, bool, []const u8 }) = .{ 127, false, "foobar" };
    const enc_multi = try encodeRlp(testing.allocator, multi);
    defer testing.allocator.free(enc_multi);
    const decoded_multi = try decodeRlp(std.meta.Tuple(&[_]type{ u8, bool, []const u8 }), testing.allocator, enc_multi);

    try testing.expectEqual(multi[0], decoded_multi[0]);
    try testing.expectEqual(multi[1], decoded_multi[1]);
    try testing.expectEqualStrings(multi[2], decoded_multi[2]);

    const nested: std.meta.Tuple(&[_]type{[]const u64}) = .{&[_]u64{ 69, 420 }};
    const nested_enc = try encodeRlp(testing.allocator, nested);
    defer testing.allocator.free(nested_enc);
    const decoded_nested = try decodeRlp(std.meta.Tuple(&[_]type{[]const u64}), testing.allocator, nested_enc);
    defer testing.allocator.free(decoded_nested[0]);

    try testing.expectEqualSlices(u64, nested[0], decoded_nested[0]);
}

test "Decoded Pointer" {
    const big = try encodeRlp(testing.allocator, &std.math.maxInt(u64));
    defer testing.allocator.free(big);
    const decoded_big = try decodeRlp(*u64, testing.allocator, big);
    defer testing.allocator.destroy(decoded_big);

    try testing.expectEqual(std.math.maxInt(u64), decoded_big.*);
}

test "Errors" {
    try testing.expectError(error.UnexpectedValue, decodeRlp(bool, testing.allocator, &[_]u8{0x02}));

    {
        const lorem = try encodeRlp(testing.allocator, "Lorem ipsum dolor sit amet, consectetur adipisicing elit");
        defer testing.allocator.free(lorem);
        const decoded_lorem = try decodeRlp([56]u8, testing.allocator, lorem);

        try testing.expectEqualStrings("Lorem ipsum dolor sit amet, consectetur adipisicing elit", &decoded_lorem);

        const big = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Maecenas vitae nibh fermentum, pretium urna sit amet, eleifend nunc. Integer pulvinar metus turpis, id euismod felis ullamcorper eu. Etiam at diam vel massa cursus venenatis eget quis lectus. Nullam commodo enim ut ex facilisis mattis. Donec convallis arcu molestie metus vestibulum, et laoreet neque vestibulum. Mauris felis velit, convallis vel pulvinar eget, ultrices eget sapien. Curabitur ut ultrices lectus. Maecenas condimentum erat lorem, dictum finibus orci commodo a. In pretium velit in sem lobortis condimentum quis a turpis. Suspendisse dignissim ullamcorper semper. Etiam lobortis nibh ac nibh porttitor imperdiet. Donec erat nisi, ullamcorper non metus fringilla, vehicula convallis tortor. Nullam egestas arcu ac nisl scelerisque molestie. Phasellus facilisis augue sit amet pretium congue. Etiam a erat maximus, mattis ex";

        const encoded = try encodeRlp(testing.allocator, big);
        defer testing.allocator.free(encoded);
        try testing.expectError(error.LengthMissmatch, decodeRlp([894]u8, testing.allocator, encoded));
    }
}
