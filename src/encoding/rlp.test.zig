const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

const encodeRlp = @import("rlp.zig").encodeRlp;

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

test "Vector" {
    const One = @Vector(2, bool);

    const encoded = try encodeRlp(testing.allocator, .{One{ true, true }});
    defer testing.allocator.free(encoded);

    try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xc2, 0x01, 0x01 });

    const Two = @Vector(255, bool);

    const vec: Two = [_]bool{true} ** 255;
    const encoded_big = try encodeRlp(testing.allocator, .{vec});
    defer testing.allocator.free(encoded_big);

    try testing.expectEqualSlices(u8, encoded_big, &[_]u8{ 0xf8, 0xFF } ++ &[_]u8{0x01} ** 255);
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

test "Errors" {
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{-69}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{-69.420}));

    const negative: i8 = -69;
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{negative}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{@as(f16, @floatFromInt(negative))}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{[_]i8{negative}}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{.{negative}}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{@Vector(1, i8){negative}}));
    try testing.expectError(error.NegativeNumber, encodeRlp(testing.allocator, .{&[_]i8{negative}}));
}
