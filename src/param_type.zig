const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;

pub const ParamErrors = error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Alloc.Error;

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

    /// User must call this if the union type contains a fixedArray or dynamicArray field.
    /// They create pointers so they must be destroyed after.
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

    /// Overrides the `jsonParse` from `std.json`.
    ///
    /// We do this because a union is treated as expecting a object string in Zig.
    ///
    /// But since we are expecting a string that contains the type value
    /// we override this so we handle the parsing properly and still leverage the union type.
    pub fn jsonParse(alloc: Alloc, source: *Scanner, opts: ParserOptions) !ParamType {
        const name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        return typeToUnion(field_name, alloc);
    }

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        try self.typeToString(stream);
    }

    pub fn typeToString(self: @This(), writer: anytype) !void {
        switch (self) {
            .string,
            .bytes,
            .bool,
            .address,
            => try writer.print("{s}", .{@tagName(self)}),
            .int,
            .uint,
            .fixedBytes,
            => |val| try writer.print("{s}{d}", .{ @tagName(self), val }),
            .dynamicArray => |val| {
                try val.typeToString(writer);
                try writer.print("[]", .{});
            },
            .fixedArray => |val| {
                try val.child.typeToString(writer);
                try writer.print("[{d}]", .{val.size});
            },
            inline else => try writer.print("", .{}),
        }
    }

    /// Helper function that is used to convert solidity types into zig unions,
    /// the function will allocate if a array or a fixed array is used.
    ///
    /// Consider using `freeArrayParamType` to destroy the pointers
    /// or call the destroy method on your allocator manually
    pub fn typeToUnion(abitype: []const u8, alloc: Alloc) !ParamType {
        if (abitype.len == 0) return error.InvalidEnumTag;

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

            return error.InvalidCharacter;
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
            const alignment = try std.fmt.parseInt(usize, len, 10);

            if (alignment % 8 != 0) return error.LengthMismatch;
            return .{ .int = alignment };
        }

        if (std.mem.startsWith(u8, abitype, "uint")) {
            const len = abitype[4..];
            const alignment = try std.fmt.parseInt(usize, len, 10);

            if (alignment % 8 != 0) return error.LengthMismatch;
            return .{ .uint = alignment };
        }

        if (std.mem.startsWith(u8, abitype, "bytes")) {
            const len = abitype[5..];
            const alignment = try std.fmt.parseInt(usize, len, 10);

            if (alignment > 32) return error.LengthMismatch;

            return .{ .fixedBytes = try std.fmt.parseInt(usize, len, 10) };
        }

        return error.InvalidEnumTag;
    }
};

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
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 256 } }, dynamic);

    const fixed = try ParamType.typeToUnion("int[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } }, fixed);
}

test "ParamType int variants" {
    try expectEqualParamType(ParamType{ .int = 120 }, try ParamType.typeToUnion("int120", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 248 }, try ParamType.typeToUnion("int248", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 64 }, try ParamType.typeToUnion("int64", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 72 }, try ParamType.typeToUnion("int72", testing.allocator));
    try expectEqualParamType(ParamType{ .int = 240 }, try ParamType.typeToUnion("int240", testing.allocator));

    const dynamic = try ParamType.typeToUnion("int120[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 120 } }, dynamic);

    const fixed = try ParamType.typeToUnion("int24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 24 }, .size = 5 } }, fixed);
}

test "ParamType uint variants" {
    try expectEqualParamType(ParamType{ .uint = 120 }, try ParamType.typeToUnion("uint120", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 248 }, try ParamType.typeToUnion("uint248", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 64 }, try ParamType.typeToUnion("uint64", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 72 }, try ParamType.typeToUnion("uint72", testing.allocator));
    try expectEqualParamType(ParamType{ .uint = 240 }, try ParamType.typeToUnion("uint240", testing.allocator));

    const dynamic = try ParamType.typeToUnion("uint120[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .uint = 120 } }, dynamic);

    const fixed = try ParamType.typeToUnion("uint24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .uint = 24 }, .size = 5 } }, fixed);
}

test "ParamType bytes variants" {
    try expectEqualParamType(ParamType{ .fixedBytes = 14 }, try ParamType.typeToUnion("bytes14", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 8 }, try ParamType.typeToUnion("bytes8", testing.allocator));
    try expectEqualParamType(ParamType{ .fixedBytes = 31 }, try ParamType.typeToUnion("bytes31", testing.allocator));

    const dynamic = try ParamType.typeToUnion("bytes3[]", testing.allocator);
    defer ParamType.freeArrayParamType(dynamic, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedBytes = 3 } }, dynamic);

    const fixed = try ParamType.typeToUnion("bytes24[5]", testing.allocator);
    defer ParamType.freeArrayParamType(fixed, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .fixedBytes = 24 }, .size = 5 } }, fixed);
}

test "ParamType 2d dynamic/fixed array" {
    const two_dd = try ParamType.typeToUnion("int[][]", testing.allocator);
    defer ParamType.freeArrayParamType(two_dd, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .dynamicArray = &.{ .int = 256 } } }, two_dd);

    const two_fd = try ParamType.typeToUnion("int[5][]", testing.allocator);
    defer ParamType.freeArrayParamType(two_fd, testing.allocator);
    try expectEqualParamType(ParamType{ .dynamicArray = &.{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } } }, two_fd);

    const two_df = try ParamType.typeToUnion("int[][9]", testing.allocator);
    defer ParamType.freeArrayParamType(two_df, testing.allocator);
    try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .dynamicArray = &.{ .int = 256 } }, .size = 9 } }, two_df);

    const two_ff = try ParamType.typeToUnion("int[6][9]", testing.allocator);
    defer ParamType.freeArrayParamType(two_ff, testing.allocator);
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

// test "Format" {
//     const param = try ParamType.typeToUnion("bool[5][9]", testing.allocator);
//     defer ParamType.freeArrayParamType(param, testing.allocator);
//
//     const stdout = std.io.getStdErr().writer();
//
//     try param.jsonStringify(&stdout);
//     try stdout.print("\n\n", .{});
// }

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
