const param_type = @import("zabi-abi").param_type;
const std = @import("std");
const testing = std.testing;

const FixedArray = param_type.FixedArray;
const ParamType = param_type.ParamType;

test "ParamType common" {
    try expectEqualParamType(ParamType{ .string = {} }, try ParamType.typeToUnion("string", testing.allocator));
    try expectEqualParamType(ParamType{ .address = {} }, try ParamType.typeToUnion("address", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 256 }, try ParamType.typeToUnion("int", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 256 }, try ParamType.typeToUnion("uint", testing.allocator));
    try expectEqualParamType(ParamType{ .bytes = {} }, try ParamType.typeToUnion("bytes", testing.allocator));
    try expectEqualParamType(ParamType{ .bool = {} }, try ParamType.typeToUnion("bool", testing.allocator));
    try expectEqualParamType(ParamType{ .tuple = {} }, try ParamType.typeToUnion("tuple", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 32 }, try ParamType.typeToUnion("bytes32", testing.allocator));

    const dynamic = try ParamType.typeToUnion("int[]", testing.allocator);
    defer dynamic.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 256 } }, dynamic);

    const fixed = try ParamType.typeToUnion("int[5]", testing.allocator);
    defer fixed.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } }, fixed);
}

test "ParamType int variants" {
    try expectEqualParamType(ParamType{ .int = 120 }, try ParamType.typeToUnion("int120", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 248 }, try ParamType.typeToUnion("int248", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 64 }, try ParamType.typeToUnion("int64", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 72 }, try ParamType.typeToUnion("int72", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 240 }, try ParamType.typeToUnion("int240", testing.allocator));

    const dynamic = try ParamType.typeToUnion("int120[]", testing.allocator);
    defer dynamic.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 120 } }, dynamic);

    const fixed = try ParamType.typeToUnion("int24[5]", testing.allocator);
    defer fixed.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 24 }, .size = 5 } }, fixed);
}

test "ParamType uint variants" {
    try expectEqualParamType(ParamType{ .uint = 120 }, try ParamType.typeToUnion("uint120", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 248 }, try ParamType.typeToUnion("uint248", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 64 }, try ParamType.typeToUnion("uint64", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 72 }, try ParamType.typeToUnion("uint72", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 240 }, try ParamType.typeToUnion("uint240", testing.allocator));

    const dynamic = try ParamType.typeToUnion("uint120[]", testing.allocator);
    defer dynamic.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .uint = 120 } }, dynamic);

    const fixed = try ParamType.typeToUnion("uint24[5]", testing.allocator);
    defer fixed.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .uint = 24 }, .size = 5 } }, fixed);
}

test "ParamType bytes variants" {
    try expectEqualParamType(ParamType{ .fixedBytes = 14 }, try ParamType.typeToUnion("bytes14", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 8 }, try ParamType.typeToUnion("bytes8", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 31 }, try ParamType.typeToUnion("bytes31", testing.allocator));

    const dynamic = try ParamType.typeToUnion("bytes3[]", testing.allocator);
    defer dynamic.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedBytes = 3 } }, dynamic);

    const fixed = try ParamType.typeToUnion("bytes24[5]", testing.allocator);
    defer fixed.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .fixedBytes = 24 }, .size = 5 } }, fixed);
}

test "ParamType 2d dynamic/fixed array" {
    const two_dd = try ParamType.typeToUnion("int[][]", testing.allocator);
    defer two_dd.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .dynamicArray = &.{ .int = 256 } } }, two_dd);

    const two_fd = try ParamType.typeToUnion("int[5][]", testing.allocator);
    defer two_fd.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } } }, two_fd);

    const two_df = try ParamType.typeToUnion("int[][9]", testing.allocator);
    defer two_df.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .dynamicArray = &.{ .int = 256 } }, .size = 9 } }, two_df);

    const two_ff = try ParamType.typeToUnion("int[6][9]", testing.allocator);
    defer two_ff.freeArrayParamType(testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 6 } }, .size = 9 } }, two_ff);
}

test "ParamType errors" {
    // Invalid alignment
    try testing.expectError(error.LengthMismatch, ParamType.typeToUnion("int13", testing.allocator));
    try testing.expectError(error.LengthMismatch, ParamType.typeToUnion("int135", testing.allocator));
    try testing.expectError(error.LengthMismatch, ParamType.typeToUnion("uint7", testing.allocator));
    try testing.expectError(error.LengthMismatch, ParamType.typeToUnion("uint29", testing.allocator));
    try testing.expectError(error.LengthMismatch, ParamType.typeToUnion("bytes40", testing.allocator));

    //Invalid array
    try testing.expectError(error.InvalidCharacter, ParamType.typeToUnion("int[n]", testing.allocator));
    try testing.expectError(error.InvalidCharacter, ParamType.typeToUnion("int[1n]", testing.allocator));
    try testing.expectError(error.InvalidCharacter, ParamType.typeToUnion("int[n1]", testing.allocator));
    try testing.expectError(error.InvalidCharacter, ParamType.typeToUnion("[]", testing.allocator));
    try testing.expectError(error.InvalidCharacter, ParamType.typeToUnion("[][]", testing.allocator));

    //Empty type
    try testing.expectError(error.InvalidEnumTag, ParamType.typeToUnion("", testing.allocator));
}

fn expectEqualParamType(comptime expected: ParamType, actual: ParamType) !void {
    switch (expected) {
        .string, .address, .tuple, .bytes, .bool => |val| try testing.expectEqual(val, @field(actual, @tagName(expected))),
        .int, .uint, .@"enum", .fixedBytes => |val| try testing.expectEqual(val, @field(actual, @tagName(expected))),
        .dynamicArray => try expectEqualParamType(expected.dynamicArray.*, actual.dynamicArray.*),
        .fixedArray => {
            try testing.expectEqual(expected.fixedArray.size, actual.fixedArray.size);
            try expectEqualParamType(expected.fixedArray.child.*, actual.fixedArray.child.*);
        },
    }
}
