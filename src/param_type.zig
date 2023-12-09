const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;

pub const FixedArray = struct {
    child: *const ParamType,
    size: usize,
};

pub const ParamType = union(enum) {
    address,
    string,
    bool,
    bytes,
    tuple,
    uint: usize,
    int: usize,
    fixedBytes: usize,
    @"enum": usize,
    fixedArray: FixedArray,
    dynamicArray: *const ParamType,

    pub fn freeArrayParamType(param: ParamType, alloc: Alloc) void {
        switch (param) {
            .dynamicArray => |val| {
                freeArrayParamType(val.*, alloc);
                alloc.destroy(val);
            },
            .fixedArray => |val| {
                freeArrayParamType(val.child.*, alloc);
                alloc.destroy(val.child);
            },
            inline else => return,
        }
    }
    pub fn jsonParse(alloc: Alloc, source: *Scanner, opts: ParserOptions) !ParamType {
        var name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => {
                return error.UnexpectedToken;
            },
        };

        const info = @typeInfo(ParamType);

        var result: ?ParamType = null;
        inline for (info.Union.fields) |union_field| {
            if (std.mem.eql(u8, union_field.name, field_name)) {
                name_token = null;
                if (union_field.type == void) {
                    result = @unionInit(ParamType, union_field.name, {});
                    break;
                }
                if (union_field.type == usize) {
                    result = @unionInit(ParamType, union_field.name, 256);
                    break;
                }
            }

            const array_len = field_name.len - 1;
            if (field_name[array_len] == ']') {
                // Check if the array is dynamic
                if (field_name[array_len - 1] == '[') {
                    result = @unionInit(ParamType, "array", &.{.{ .int = 256 }});
                    break;
                }
            }
        }

        return result.?;
    }
};

fn typeToUnion(abitype: []const u8, alloc: Alloc) !ParamType {
    if (abitype.len == 0) return error.EmptyParamType;

    if (abitype[abitype.len - 1] == ']') {
        const end = abitype.len - 1;
        for (2..abitype.len) |i| {
            const start = abitype.len - i;
            if (abitype[start] == '[') {
                const inside = abitype[start + 1 .. end];
                const child = try alloc.create(ParamType);
                errdefer alloc.destroy(child);
                child.* = try typeToUnion(abitype[0..start], alloc);

                if (inside.len == 0) {
                    return .{
                        .dynamicArray = child,
                    };
                } else {
                    return .{ .fixedArray = .{
                        .size = try std.fmt.parseInt(usize, inside, 10),
                        .child = child,
                    } };
                }
            }
        }

        return error.InvalidArrayType;
    }

    const info = @typeInfo(ParamType);

    inline for (info.Union.fields) |union_field| {
        if (std.mem.eql(u8, union_field.name, abitype)) {
            if (union_field.type == void) {
                return @unionInit(ParamType, union_field.name, {});
            }
            if (union_field.type == usize) {
                return @unionInit(ParamType, union_field.name, 256);
            }
        }
    }

    if (std.mem.startsWith(u8, abitype, "int")) {
        const len = abitype[3..];
        return .{ .int = try std.fmt.parseInt(usize, len, 10) };
    }

    if (std.mem.startsWith(u8, abitype, "uint")) {
        const len = abitype[4..];
        return .{ .uint = try std.fmt.parseInt(usize, len, 10) };
    }

    if (std.mem.startsWith(u8, abitype, "bytes")) {
        const len = abitype[5..];
        const alignment = try std.fmt.parseInt(usize, len, 10);

        if (alignment > 32) return error.InvalidBytesAligment;

        return .{ .fixedBytes = try std.fmt.parseInt(usize, len, 10) };
    }

    // Default into a enum type. Enums in solidity are u8 typed;
    return .{ .@"enum" = 8 };
}

test "ParamType common" {
    try expectEqualParamType(ParamType{ .string = {} }, try typeToUnion("string", testing.allocator));
    try expectEqualParamType(ParamType{ .address = {} }, try typeToUnion("address", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 256 }, try typeToUnion("int", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 256 }, try typeToUnion("uint", testing.allocator));
    try expectEqualParamType(ParamType{ .bytes = {} }, try typeToUnion("bytes", testing.allocator));
    try expectEqualParamType(ParamType{ .bool = {} }, try typeToUnion("bool", testing.allocator));
    try expectEqualParamType(ParamType{ .tuple = {} }, try typeToUnion("tuple", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 32 }, try typeToUnion("bytes32", testing.allocator));

    const dynamic = try typeToUnion("int[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 256 } }, dynamic);

    const fixed = try typeToUnion("int[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } }, fixed);
}

test "ParamType int variants" {
    try expectEqualParamType(ParamType{ .int = 120 }, try typeToUnion("int120", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 248 }, try typeToUnion("int248", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 64 }, try typeToUnion("int64", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 72 }, try typeToUnion("int72", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 240 }, try typeToUnion("int240", testing.allocator));

    const dynamic = try typeToUnion("int120[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 120 } }, dynamic);

    const fixed = try typeToUnion("int24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 24 }, .size = 5 } }, fixed);
}

test "ParamType uint variants" {
    try expectEqualParamType(ParamType{ .uint = 120 }, try typeToUnion("uint120", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 248 }, try typeToUnion("uint248", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 64 }, try typeToUnion("uint64", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 72 }, try typeToUnion("uint72", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 240 }, try typeToUnion("uint240", testing.allocator));

    const dynamic = try typeToUnion("uint120[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .uint = 120 } }, dynamic);

    const fixed = try typeToUnion("uint24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .uint = 24 }, .size = 5 } }, fixed);
}

test "ParamType bytes variants" {
    try expectEqualParamType(ParamType{ .fixedBytes = 14 }, try typeToUnion("bytes14", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 8 }, try typeToUnion("bytes8", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 31 }, try typeToUnion("bytes31", testing.allocator));

    const dynamic = try typeToUnion("bytes3[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedBytes = 3 } }, dynamic);

    const fixed = try typeToUnion("bytes24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .fixedBytes = 24 }, .size = 5 } }, fixed);
}

test "ParamType 2d dynamic/fixed array" {
    const two_dd = try typeToUnion("int[][]", testing.allocator);
    defer ParamType.freeArrayParamType(two_dd, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .dynamicArray = &.{ .int = 256 } } }, two_dd);

    const two_fd = try typeToUnion("int[5][]", testing.allocator);
    defer ParamType.freeArrayParamType(two_fd, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } } }, two_fd);

    const two_df = try typeToUnion("int[][9]", testing.allocator);
    defer ParamType.freeArrayParamType(two_df, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .dynamicArray = &.{ .int = 256 } }, .size = 9 } }, two_df);

    const two_ff = try typeToUnion("int[6][9]", testing.allocator);
    defer ParamType.freeArrayParamType(two_ff, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 6 } }, .size = 9 } }, two_ff);
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
