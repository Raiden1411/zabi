const std = @import("std");
const testing = std.testing;

// Types
const Allocator = std.mem.Allocator;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;

pub const ParamErrors = error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Allocator.Error;

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
    pub fn freeArrayParamType(self: @This(), alloc: Allocator) void {
        switch (self) {
            .dynamicArray => |val| {
                val.freeArrayParamType(alloc);
                alloc.destroy(val);
            },
            .fixedArray => |val| {
                val.child.freeArrayParamType(alloc);
                alloc.destroy(val.child);
            },
            inline else => {},
        }
    }

    /// Overrides the `jsonParse` from `std.json`.
    ///
    /// We do this because a union is treated as expecting a object string in Zig.
    ///
    /// But since we are expecting a string that contains the type value
    /// we override this so we handle the parsing properly and still leverage the union type.
    pub fn jsonParse(alloc: Allocator, source: *Scanner, opts: ParserOptions) !ParamType {
        const name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        return typeToUnion(field_name, alloc);
    }

    pub fn jsonParseFromValue(alloc: Allocator, source: std.json.Value, opts: ParserOptions) !ParamType {
        _ = opts;

        const field_name = source.string;
        return typeToUnion(field_name, alloc);
    }

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        // Cursed hack. There should be a better way
        var out_buf: [256]u8 = undefined;
        var slice_stream = std.io.fixedBufferStream(&out_buf);
        const out = slice_stream.writer();
        try self.typeToJsonStringify(out);

        try stream.write(slice_stream.getWritten());
    }

    pub fn typeToJsonStringify(self: @This(), writer: anytype) !void {
        switch (self) {
            .string,
            .bytes,
            .bool,
            .address,
            .tuple,
            => try writer.print("{s}", .{@tagName(self)}),
            .int,
            .uint,
            => |val| try writer.print("{s}{d}", .{ @tagName(self), val }),
            .fixedBytes => |val| try writer.print("bytes{d}", .{val}),
            .dynamicArray => |val| {
                try val.typeToJsonStringify(writer);
                try writer.print("[]", .{});
            },
            .fixedArray => |val| {
                try val.child.typeToJsonStringify(writer);
                try writer.print("[{d}]", .{val.size});
            },
            inline else => try writer.print("", .{}),
        }
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
            => |val| try writer.print("{s}{d}", .{ @tagName(self), val }),
            .fixedBytes => |val| try writer.print("bytes{d}", .{val}),
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
    pub fn typeToUnion(abitype: []const u8, alloc: Allocator) !ParamType {
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

            if (alignment % 8 != 0 or alignment > 256) return error.LengthMismatch;
            return .{ .int = alignment };
        }

        if (std.mem.startsWith(u8, abitype, "uint")) {
            const len = abitype[4..];
            const alignment = try std.fmt.parseInt(usize, len, 10);

            if (alignment % 8 != 0 or alignment > 256) return error.LengthMismatch;
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
