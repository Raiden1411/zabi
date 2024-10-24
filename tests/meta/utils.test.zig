const std = @import("std");
const testing = std.testing;

const MergeStructs = @import("zabi-meta").utils.MergeStructs;
const MergeTupleStructs = @import("zabi-meta").utils.MergeTupleStructs;
const Omit = @import("zabi-meta").utils.Omit;
const StructToTupleType = @import("zabi-meta").utils.StructToTupleType;

test "Meta" {
    try expectEqualStructs(struct { foo: u32, jazz: bool }, MergeStructs(struct { foo: u32 }, struct { jazz: bool }));
    try expectEqualStructs(struct { u32, bool }, MergeTupleStructs(struct { u32 }, struct { bool }));
    try expectEqualStructs(struct { foo: u32, jazz: bool }, Omit(struct { foo: u32, bar: u256, baz: i64, jazz: bool }, &.{ "bar", "baz" }));
    try expectEqualStructs(std.meta.Tuple(&[_]type{ u64, std.meta.Tuple(&[_]type{ u64, u256 }) }), StructToTupleType(struct { foo: u64, bar: struct { baz: u64, jazz: u256 } }));
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
        if (@typeInfo(e.type) == .@"struct") return try expectEqualUnions(e.type, a.type);
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
