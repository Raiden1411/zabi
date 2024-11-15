const std = @import("std");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const encodeSSZ = @import("zabi").encoding.ssz.encodeSSZ;

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
