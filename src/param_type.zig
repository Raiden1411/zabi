const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
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

pub const AbiParamenter = struct {
    name: []const u8,
    type: ParamType,
    internal_type: ?[]const u8 = null,
};

test "ParamType" {
    const a = try typeToUnion("string[][5]");

    try testing.expect(a.fixedArray.size == 5);
}
