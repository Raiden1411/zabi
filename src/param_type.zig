const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;

pub const FixedArray = struct {
    array: []const ParamType,
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
    array: []const ParamType,

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

fn typeToUnion(abitype: []const u8) !ParamType {
    const array_len = abitype.len - 1;
    if (abitype[array_len] == ']') {
        // Check if the array is dynamic
        if (abitype[array_len - 1] == '[') {
            return @unionInit(ParamType, "array", &.{try typeToUnion(abitype[0 .. abitype.len - 2])});
        }

        var counter: u8 = 1;
        if (std.ascii.isDigit(abitype[array_len - counter])) {
            while (std.ascii.isDigit(abitype[array_len - counter])) : (counter += 1) {}
            return @unionInit(ParamType, "fixedArray", .{ .array = &.{try typeToUnion(abitype[0 .. array_len - counter])}, .size = try std.fmt.parseInt(usize, abitype[array_len - counter + 1 .. array_len], 10) });
        }
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
        return @unionInit(ParamType, "int", try std.fmt.parseInt(usize, len, 10));
    }

    if (std.mem.startsWith(u8, abitype, "uint")) {
        const len = abitype[4..];
        return @unionInit(ParamType, "uint", try std.fmt.parseInt(usize, len, 10));
    }

    if (std.mem.startsWith(u8, abitype, "bytes")) {
        const len = abitype[5..];
        const alignment = try std.fmt.parseInt(usize, len, 10);

        if (alignment > 32) return error.InvalidBytesAligment;

        return @unionInit(ParamType, "fixedBytes", alignment);
    }

    return @unionInit(ParamType, "enum", 8);
}

test "ParamType address" {
    const param = try typeToUnion("address");

    try testing.expectEqual(ParamType{ .address = {} }, param);
}
test "ParamType bool" {
    const param = try typeToUnion("bool");

    try testing.expectEqual(ParamType{ .bool = {} }, param);
}
test "ParamType tuple" {
    const param = try typeToUnion("tuple");

    try testing.expectEqual(ParamType{ .tuple = {} }, param);
}
test "ParamType bytes" {
    const param = try typeToUnion("bytes");

    try testing.expectEqual(ParamType{ .bytes = {} }, param);
}
test "ParamType string" {
    const param = try typeToUnion("string");

    try testing.expectEqual(ParamType{ .string = {} }, param);
}

test "ParamType int" {
    const param = try typeToUnion("int");
    try testing.expectEqual(ParamType{ .int = 256 }, param);

    try testing.expectEqual(ParamType{ .int = 120 }, try typeToUnion("int120"));
    try testing.expectEqual(ParamType{ .int = 248 }, try typeToUnion("int248"));
    try testing.expectEqual(ParamType{ .int = 64 }, try typeToUnion("int64"));
    try testing.expectEqual(ParamType{ .int = 72 }, try typeToUnion("int72"));
    try testing.expectEqual(ParamType{ .int = 240 }, try typeToUnion("int240"));
}

test "ParamType uint" {
    const param = try typeToUnion("uint");

    try testing.expectEqual(ParamType{ .uint = 256 }, param);

    try testing.expectEqual(ParamType{ .uint = 120 }, try typeToUnion("uint120"));
    try testing.expectEqual(ParamType{ .uint = 248 }, try typeToUnion("uint248"));
    try testing.expectEqual(ParamType{ .uint = 64 }, try typeToUnion("uint64"));
    try testing.expectEqual(ParamType{ .uint = 72 }, try typeToUnion("uint72"));
    try testing.expectEqual(ParamType{ .uint = 240 }, try typeToUnion("uint240"));
}

test "ParamType fixed array" {
    const param = try typeToUnion("string[][5]");

    try testing.expect(param.fixedArray.size == 5);
    try testing.expectEqualSlices(ParamType, &[_]ParamType{.{ .string = {} }}, param.fixedArray.array[0].array);
}
