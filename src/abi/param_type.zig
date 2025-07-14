const std = @import("std");
const testing = std.testing;
const tokens = @import("zabi-human").tokens;

// Types
const Allocator = std.mem.Allocator;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const TokenTags = tokens.Tag.SoliditySyntax;

/// Set of errors when converting `[]const u8` into `ParamType`.
pub const ParamErrors = error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Allocator.Error;

/// Representation of the solidity fixed array type.
pub const FixedArray = struct {
    child: *const ParamType,
    size: usize,
};

/// Type that represents solidity types in zig.
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

    /// Converts a human readable token into `ParamType`.
    pub fn fromHumanReadableTokenTag(tag: TokenTags) ?ParamType {
        return switch (tag) {
            .Address => .{ .address = {} },
            .Bool => .{ .bool = {} },
            .Tuple => .{ .tuple = {} },
            .String => .{ .string = {} },
            .Bytes => .{ .bytes = {} },

            .Bytes1 => .{ .fixedBytes = 1 },
            .Bytes2 => .{ .fixedBytes = 2 },
            .Bytes3 => .{ .fixedBytes = 3 },
            .Bytes4 => .{ .fixedBytes = 4 },
            .Bytes5 => .{ .fixedBytes = 5 },
            .Bytes6 => .{ .fixedBytes = 6 },
            .Bytes7 => .{ .fixedBytes = 7 },
            .Bytes8 => .{ .fixedBytes = 8 },
            .Bytes9 => .{ .fixedBytes = 9 },
            .Bytes10 => .{ .fixedBytes = 10 },
            .Bytes11 => .{ .fixedBytes = 11 },

            .Bytes12 => .{ .fixedBytes = 12 },
            .Bytes13 => .{ .fixedBytes = 13 },
            .Bytes14 => .{ .fixedBytes = 14 },
            .Bytes15 => .{ .fixedBytes = 15 },
            .Bytes16 => .{ .fixedBytes = 16 },
            .Bytes17 => .{ .fixedBytes = 17 },
            .Bytes18 => .{ .fixedBytes = 18 },
            .Bytes19 => .{ .fixedBytes = 19 },
            .Bytes20 => .{ .fixedBytes = 20 },
            .Bytes21 => .{ .fixedBytes = 21 },
            .Bytes22 => .{ .fixedBytes = 22 },
            .Bytes23 => .{ .fixedBytes = 23 },
            .Bytes24 => .{ .fixedBytes = 24 },
            .Bytes25 => .{ .fixedBytes = 25 },
            .Bytes26 => .{ .fixedBytes = 26 },
            .Bytes27 => .{ .fixedBytes = 27 },
            .Bytes28 => .{ .fixedBytes = 28 },
            .Bytes29 => .{ .fixedBytes = 29 },
            .Bytes30 => .{ .fixedBytes = 30 },
            .Bytes31 => .{ .fixedBytes = 31 },
            .Bytes32 => .{ .fixedBytes = 32 },

            .Uint => .{ .uint = 256 },
            .Uint8 => .{ .uint = 8 },
            .Uint16 => .{ .uint = 16 },
            .Uint24 => .{ .uint = 24 },
            .Uint32 => .{ .uint = 32 },
            .Uint40 => .{ .uint = 40 },
            .Uint48 => .{ .uint = 48 },
            .Uint56 => .{ .uint = 56 },
            .Uint64 => .{ .uint = 64 },
            .Uint72 => .{ .uint = 72 },
            .Uint80 => .{ .uint = 80 },
            .Uint88 => .{ .uint = 88 },
            .Uint96 => .{ .uint = 96 },
            .Uint104 => .{ .uint = 104 },
            .Uint112 => .{ .uint = 112 },
            .Uint120 => .{ .uint = 120 },
            .Uint128 => .{ .uint = 128 },
            .Uint136 => .{ .uint = 136 },
            .Uint144 => .{ .uint = 144 },
            .Uint152 => .{ .uint = 152 },
            .Uint160 => .{ .uint = 160 },
            .Uint168 => .{ .uint = 168 },
            .Uint176 => .{ .uint = 176 },
            .Uint184 => .{ .uint = 184 },
            .Uint192 => .{ .uint = 192 },
            .Uint200 => .{ .uint = 200 },
            .Uint208 => .{ .uint = 208 },
            .Uint216 => .{ .uint = 216 },
            .Uint224 => .{ .uint = 224 },
            .Uint232 => .{ .uint = 232 },
            .Uint240 => .{ .uint = 240 },
            .Uint248 => .{ .uint = 248 },
            .Uint256 => .{ .uint = 256 },

            .Int => .{ .int = 256 },
            .Int8 => .{ .int = 8 },
            .Int16 => .{ .int = 16 },
            .Int24 => .{ .int = 24 },
            .Int32 => .{ .int = 32 },
            .Int40 => .{ .int = 40 },
            .Int48 => .{ .int = 48 },
            .Int56 => .{ .int = 56 },
            .Int64 => .{ .int = 64 },
            .Int72 => .{ .int = 72 },
            .Int80 => .{ .int = 80 },
            .Int88 => .{ .int = 88 },
            .Int96 => .{ .int = 96 },
            .Int104 => .{ .int = 104 },
            .Int112 => .{ .int = 112 },
            .Int120 => .{ .int = 120 },
            .Int128 => .{ .int = 128 },
            .Int136 => .{ .int = 136 },
            .Int144 => .{ .int = 144 },
            .Int152 => .{ .int = 152 },
            .Int160 => .{ .int = 160 },
            .Int168 => .{ .int = 168 },
            .Int176 => .{ .int = 176 },
            .Int184 => .{ .int = 184 },
            .Int192 => .{ .int = 192 },
            .Int200 => .{ .int = 200 },
            .Int208 => .{ .int = 208 },
            .Int216 => .{ .int = 216 },
            .Int224 => .{ .int = 224 },
            .Int232 => .{ .int = 232 },
            .Int240 => .{ .int = 240 },
            .Int248 => .{ .int = 248 },
            .Int256 => .{ .int = 256 },
            inline else => null,
        };
    }

    /// User must call this if the union type contains a fixedArray or dynamicArray field.
    /// They create pointers so they must be destroyed after.
    pub fn freeArrayParamType(
        self: @This(),
        alloc: Allocator,
    ) void {
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
    pub fn jsonParse(
        alloc: Allocator,
        source: *Scanner,
        opts: ParserOptions,
    ) ParseError(@TypeOf(source.*))!ParamType {
        const name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        return typeToUnion(field_name, alloc);
    }

    pub fn jsonParseFromValue(
        alloc: Allocator,
        source: std.json.Value,
        opts: ParserOptions,
    ) ParseFromValueError!ParamType {
        _ = opts;

        const field_name = source.string;
        return typeToUnion(field_name, alloc);
    }

    pub fn jsonStringify(
        self: @This(),
        stream: anytype,
    ) @TypeOf(stream.*).Error!void {
        // Cursed hack. There should be a better way
        var out_buf: [256]u8 = undefined;
        var slice_stream = std.io.fixedBufferStream(&out_buf);
        const out = slice_stream.writer();
        try self.typeToJsonStringify(out);

        try stream.write(slice_stream.getWritten());
    }

    /// Converts the tagname of `self` into a writer.
    pub fn typeToJsonStringify(
        self: @This(),
        writer: anytype,
    ) !void {
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
    /// Converts `self` into its tagname.
    pub fn typeToString(
        self: @This(),
        writer: anytype,
    ) !void {
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
    pub fn typeToUnion(
        abitype: []const u8,
        alloc: Allocator,
    ) ParamErrors!ParamType {
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

        inline for (info.@"union".fields) |union_field| {
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

    pub fn typeToUnionWithTag(
        allocator: Allocator,
        abitype: []const u8,
        token_tag: TokenTags,
    ) ParamErrors!ParamType {
        if (abitype.len == 0) return error.InvalidEnumTag;

        if (abitype[abitype.len - 1] == ']') {
            const end = abitype.len - 1;
            for (2..abitype.len) |i| {
                const start = abitype.len - i;
                if (abitype[start] == '[') {
                    const inside = abitype[start + 1 .. end];
                    const child = try allocator.create(ParamType);
                    errdefer allocator.destroy(child);

                    child.* = try typeToUnionWithTag(allocator, abitype[0..start], token_tag);

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

        const from_tag = fromHumanReadableTokenTag(token_tag) orelse return error.InvalidEnumTag;

        return from_tag;
    }
};
