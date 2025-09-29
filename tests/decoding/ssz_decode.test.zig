const std = @import("std");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const encodeSSZ = @import("zabi").encoding.ssz.encodeSSZ;
const decodeSSZ = @import("zabi").decoding.ssz.decodeSSZ;

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
    const encoded: @Vector(2, u16) = .{ 0xABCD, 0xEF01 };
    const slice = &[_]u8{ 0xCD, 0xAB, 0x01, 0xEF };

    const decoded = try decodeSSZ(@Vector(2, u16), slice);

    try testing.expectEqualDeep(encoded, decoded);
}
