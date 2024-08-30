const abi = @import("../../abi/abi.zig");
const std = @import("std");
const testing = std.testing;

const AbiEventParameterToPrimativeType = @import("../../meta/abi.zig").AbiEventParameterToPrimativeType;
const AbiEventParametersToPrimativeType = @import("../../meta/abi.zig").AbiEventParametersToPrimativeType;
const AbiParametersToPrimative = @import("../../meta/abi.zig").AbiParametersToPrimative;
const AbiParameterToPrimative = @import("../../meta/abi.zig").AbiParameterToPrimative;

test "Meta" {
    try testing.expectEqual(AbiParametersToPrimative(&.{}), void);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .string = {} }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedBytes = 31 }, .name = "foo" }), [31]u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .uint = 120 }, .name = "foo" }), u120);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .int = 48 }, .name = "foo" }), i48);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bytes = {} }, .name = "foo" }), []u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .address = {} }, .name = "foo" }), [20]u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bool = {} }, .name = "foo" }), bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .dynamicArray = &.{ .bool = {} } }, .name = "foo" }), []const bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedArray = .{ .child = &.{ .bool = {} }, .size = 2 } }, .name = "foo" }), [2]bool);

    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .string = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .bytes = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .tuple = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .dynamicArray = &.{ .bool = {} } }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .fixedArray = .{ .child = &.{ .bool = {} }, .size = 2 } }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .bool = {} }, .name = "foo", .indexed = true }), bool);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .address = {} }, .name = "foo", .indexed = true }), [20]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .uint = 64 }, .name = "foo", .indexed = true }), u64);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .int = 16 }, .name = "foo", .indexed = true }), i16);

    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }), struct { bar: bool });
    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }), struct { bar: struct { baz: bool } });
}

test "EventParameters" {
    const event: abi.Event = .{
        .type = .event,
        .name = "Foo",
        .inputs = &.{
            .{
                .type = .{ .uint = 256 },
                .name = "bar",
                .indexed = true,
            },
        },
    };

    const ParamsTypes = AbiEventParametersToPrimativeType(event.inputs);

    try expectEqualStructs(ParamsTypes, struct { [32]u8, u256 });
    try expectEqualStructs(AbiEventParametersToPrimativeType(&.{}), struct { [32]u8 });
}

fn expectEqualStructs(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).@"struct";
    const actualInfo = @typeInfo(actual).@"struct";

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);
    try testing.expectEqual(expectInfo.is_tuple, actualInfo.is_tuple);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .@"struct") return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .@"union") return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}

fn expectEqualUnions(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).@"union";
    const actualInfo = @typeInfo(actual).@"union";

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .@"struct") return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .@"union") return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}
