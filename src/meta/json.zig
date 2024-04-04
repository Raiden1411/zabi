const generator = @import("../generator.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../types/root.zig");

// Types
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Token = std.json.Token;
const Value = std.json.Value;

/// UnionParser used by `zls`. Usefull to use in `AbiItem`
/// https://github.com/zigtools/zls/blob/d1ad449a24ea77bacbeccd81d607fa0c11f87dd6/src/lsp.zig#L77
pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!T {
            const json_value = try Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!T {
            inline for (std.meta.fields(T)) |field| {
                if (std.json.parseFromValueLeaky(field.type, allocator, source, options)) |result| {
                    return @unionInit(T, field.name, result);
                } else |_| {}
            }
            return error.UnexpectedToken;
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}
/// Custom jsonParse that is mostly used to enable
/// the ability to parse hex string values into native `int` types,
/// since parsing hex values is not part of the JSON RFC we need to rely on
/// the hability of zig to create a custom jsonParse method for structs
pub fn RequestParser(comptime T: type) type {
    return struct {
        pub fn jsonStringify(self: T, writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
            const info = @typeInfo(T);

            try valueStart(writer_stream);
            writer_stream.next_punctuation = .the_beginning;

            try writer_stream.stream.writeByte('{');
            inline for (info.Struct.fields) |field| {
                var emit_field = true;
                if (@typeInfo(field.type) == .Optional) {
                    if (@field(self, field.name) == null and !writer_stream.options.emit_null_optional_fields) {
                        emit_field = false;
                    }
                }

                if (emit_field) {
                    try valueStart(writer_stream);
                    try std.json.encodeJsonString(field.name, .{}, writer_stream.stream);
                    writer_stream.next_punctuation = .colon;
                    try innerStringfy(@field(self, field.name), writer_stream);
                }
            }
            switch (writer_stream.next_punctuation) {
                .none, .comma => {},
                else => unreachable,
            }
            try writer_stream.stream.writeByte('}');
            writer_stream.next_punctuation = .comma;

            return;
        }

        fn innerStringfy(value: anytype, stream_writer: anytype) !void {
            const info = @typeInfo(@TypeOf(value));

            switch (info) {
                .Bool => {
                    try valueStart(stream_writer);
                    try stream_writer.stream.writeAll(if (value) "true" else "false");
                    stream_writer.next_punctuation = .comma;
                },
                .Int, .ComptimeInt => {
                    try valueStart(stream_writer);
                    try stream_writer.stream.writeByte('\"');
                    try stream_writer.stream.print("0x{x}", .{value});
                    try stream_writer.stream.writeByte('\"');
                    stream_writer.next_punctuation = .comma;
                },
                .Float, .ComptimeFloat => {
                    try valueStart(stream_writer);
                    try stream_writer.stream.print("{d}", .{value});
                    stream_writer.next_punctuation = .comma;
                },
                .Null => {
                    try valueStart(stream_writer);
                    try stream_writer.stream.writeAll("null");
                    stream_writer.next_punctuation = .comma;
                },
                .Optional => {
                    if (value) |val| {
                        return try innerStringfy(val, stream_writer);
                    } else return try innerStringfy(null, stream_writer);
                },
                .Enum, .EnumLiteral => {
                    try valueStart(stream_writer);
                    try std.json.encodeJsonString(@tagName(value), .{}, stream_writer.stream);
                    stream_writer.next_punctuation = .comma;
                },
                .ErrorSet => {
                    try valueStart(stream_writer);
                    try std.json.encodeJsonString(@errorName(value), .{}, stream_writer.stream);
                    stream_writer.next_punctuation = .comma;
                },
                .Array => |arr_info| {
                    try valueStart(stream_writer);
                    // We assume that we are dealying with hex bytes.
                    // Mostly usefull for the cases of wanting to hex addresses and hashes
                    if (arr_info.child == u8) {
                        switch (arr_info.len) {
                            20 => {
                                var buffer: [(arr_info.len * 2) + 2]u8 = undefined;
                                var hash_buffer: [Keccak256.digest_length]u8 = undefined;

                                const hexed = std.fmt.bytesToHex(value, .lower);
                                Keccak256.hash(&hexed, &hash_buffer, .{});

                                // Checksum the address
                                for (buffer[2..], 0..) |*c, i| {
                                    const char = hexed[i];
                                    switch (char) {
                                        'a'...'f' => {
                                            const mask: u8 = if (i % 2 == 0) 0x80 else 0x08;
                                            if ((hash_buffer[i / 2] & mask) > 7) {
                                                c.* = char & 0b11011111;
                                            } else c.* = char;
                                        },
                                        else => {
                                            c.* = char;
                                        },
                                    }
                                }
                                @memcpy(buffer[0..2], "0x");
                                try std.json.encodeJsonString(buffer[0..], .{}, stream_writer.stream);
                            },
                            40 => {
                                // We assume that this is a checksumed address with missing "0x" start.
                                var buffer: [arr_info.len + 2]u8 = undefined;
                                @memcpy(buffer[2..], value);
                                @memcpy(buffer[0..2], "0x");
                                try std.json.encodeJsonString(buffer[0..], .{}, stream_writer.stream);
                            },
                            42 => {
                                // we just write the checksumed address
                                try std.json.encodeJsonString(value[0..], .{}, stream_writer.stream);
                            },
                            else => {
                                // Treat the rest as a normal hex encoded value
                                var buffer: [(arr_info.len * 2) + 2]u8 = undefined;
                                const hexed = std.fmt.bytesToHex(value, .lower);
                                @memcpy(buffer[2..], hexed[0..]);
                                @memcpy(buffer[0..2], "0x");
                                try std.json.encodeJsonString(buffer[0..], .{}, stream_writer.stream);
                            },
                        }
                        stream_writer.next_punctuation = .comma;
                    } else {
                        stream_writer.next_punctuation = .none;
                        return try innerStringfy(&value, stream_writer);
                    }
                },
                .Pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => switch (@typeInfo(ptr_info.child)) {
                            .Array => {
                                const Slice = []const std.meta.Elem(ptr_info.child);
                                return try innerStringfy(@as(Slice, value), stream_writer);
                            },
                            else => return try innerStringfy(value.*, stream_writer),
                        },
                        .Many, .Slice => {
                            if (ptr_info.size == .Many and ptr_info.sentinel == null)
                                @compileError("Unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");

                            const slice = if (ptr_info.size == .Many) std.mem.span(value) else value;

                            try valueStart(stream_writer);
                            if (ptr_info.child == u8) {
                                if (ptr_info.is_const) {
                                    try std.json.encodeJsonString(value, .{}, stream_writer.stream);
                                } else {
                                    // We assume that non const u8 slices are to be hex encoded.
                                    try stream_writer.stream.writeByte('\"');
                                    try stream_writer.stream.writeAll("0x");

                                    var buf: [2]u8 = undefined;

                                    const charset = "0123456789abcdef";
                                    for (value) |c| {
                                        buf[0] = charset[c >> 4];
                                        buf[1] = charset[c & 15];
                                        try stream_writer.stream.writeAll(&buf);
                                    }

                                    try stream_writer.stream.writeByte('\"');
                                }
                                stream_writer.next_punctuation = .comma;
                            } else {
                                try stream_writer.stream.writeByte('[');
                                stream_writer.next_punctuation = .none;

                                for (slice) |span| {
                                    try innerStringfy(span, stream_writer);
                                }

                                switch (stream_writer.next_punctuation) {
                                    .none, .comma => {},
                                    else => unreachable,
                                }

                                try stream_writer.stream.writeByte(']');
                                stream_writer.next_punctuation = .comma;
                            }
                        },
                        else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
                    }
                },
                .Struct => |struct_info| {
                    if (struct_info.is_tuple) {
                        try valueStart(stream_writer);
                        try stream_writer.stream.writeByte('[');
                        stream_writer.next_punctuation = .none;
                        inline for (value) |val| {
                            try innerStringfy(val, stream_writer);
                        }
                        switch (stream_writer.next_punctuation) {
                            .none, .comma => {},
                            else => unreachable,
                        }
                        try stream_writer.stream.writeByte(']');
                        stream_writer.next_punctuation = .comma;
                        return;
                    } else if (@hasDecl(@TypeOf(value), "jsonStringify")) return value.jsonStringify(stream_writer) else @compileError("Unable to parse structs without jsonStringify custom declaration. TypeName: " ++ @typeName(@TypeOf(value)));
                },
                .Union => {
                    if (@hasDecl(@TypeOf(value), "jsonStringify")) return value.jsonStringify(stream_writer) else @compileError("Unable to parse unions without jsonStringify custom declaration. Typename: " ++ @typeName(@TypeOf(value)));
                },
                else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
            }
        }

        fn valueStart(stream_writer: anytype) !void {
            switch (stream_writer.next_punctuation) {
                .the_beginning, .none => {},
                .comma => try stream_writer.stream.writeByte(','),
                .colon => try stream_writer.stream.writeByte(':'),
            }
        }

        pub fn jsonParse(alloc: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!T {
            const info = @typeInfo(T);
            if (.object_begin != try source.next()) return error.UnexpectedToken;

            var result: T = undefined;
            var fields_seen = [_]bool{false} ** info.Struct.fields.len;

            while (true) {
                var name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };

                inline for (info.Struct.fields, 0..) |field, i| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        name_token = null;
                        @field(result, field.name) = try innerParseRequest(field.type, alloc, source, opts);
                        fields_seen[i] = true;
                        break;
                    }
                } else {
                    if (opts.ignore_unknown_fields) {
                        try source.skipValue();
                    } else {
                        return error.UnknownField;
                    }
                }
            }

            inline for (info.Struct.fields, 0..) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default_value| {
                        const default = @as(*align(1) const field.type, @ptrCast(default_value)).*;
                        @field(result, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
            }

            return result;
        }

        pub fn jsonParseFromValue(alloc: Allocator, source: Value, opts: ParseOptions) ParseFromValueError!T {
            const info = @typeInfo(T);
            if (source != .object) return error.UnexpectedToken;

            var result: T = undefined;
            var fields_seen = [_]bool{false} ** info.Struct.fields.len;

            var iter = source.object.iterator();

            while (iter.next()) |token| {
                const field_name = token.key_ptr.*;

                inline for (info.Struct.fields, 0..) |field, i| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        @field(result, field.name) = try innerParseValueRequest(field.type, alloc, token.value_ptr.*, opts);
                        fields_seen[i] = true;
                        break;
                    }
                } else {
                    if (!opts.ignore_unknown_fields)
                        return error.UnknownField;
                }
            }

            inline for (info.Struct.fields, 0..) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default_value| {
                        const default = @as(*align(1) const field.type, @ptrCast(default_value)).*;
                        @field(result, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
            }

            return result;
        }

        fn innerParseValueRequest(comptime TT: type, alloc: Allocator, source: anytype, opts: ParseOptions) ParseFromValueError!TT {
            switch (@typeInfo(TT)) {
                .Bool => {
                    switch (source) {
                        .bool => |val| return val,
                        .string => |val| return try std.fmt.parseInt(u1, val, 0) != 0,
                        else => return error.UnexpectedToken,
                    }
                },
                .Float, .ComptimeFloat => {
                    switch (source) {
                        .float => |f| return @as(TT, @floatCast(f)),
                        .integer => |i| return @as(TT, @floatFromInt(i)),
                        .number_string, .string => |s| return std.fmt.parseFloat(TT, s),
                        else => return error.UnexpectedToken,
                    }
                },
                .Int, .ComptimeInt => {
                    switch (source) {
                        .number_string, .string => |str| {
                            return try std.fmt.parseInt(TT, str, 0);
                        },
                        .float => |f| {
                            if (@round(f) != f) return error.InvalidNumber;
                            if (f > std.math.maxInt(TT)) return error.Overflow;
                            if (f < std.math.minInt(TT)) return error.Overflow;
                            return @as(TT, @intFromFloat(f));
                        },
                        .integer => |i| {
                            if (i > std.math.maxInt(TT)) return error.Overflow;
                            if (i < std.math.minInt(TT)) return error.Overflow;
                            return @as(TT, @intCast(i));
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .Optional => |opt_info| {
                    switch (source) {
                        .null => return null,
                        else => return try innerParseValueRequest(opt_info.child, alloc, source, opts),
                    }
                },
                .Enum => |enum_info| {
                    switch (source) {
                        .float => return error.InvalidEnumTag,
                        .integer => |num| return std.meta.intToEnum(TT, num),
                        .number_string, .string => |slice| {
                            if (std.meta.stringToEnum(TT, slice)) |result| return result;

                            const enum_number = std.fmt.parseInt(enum_info.tag_type, slice, 0) catch return error.InvalidEnumTag;
                            return std.meta.intToEnum(TT, enum_number);
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .Array => |arr_info| {
                    switch (source) {
                        .array => |arr| {
                            var result: TT = undefined;
                            for (arr.items, 0..) |item, i| {
                                result[i] = try innerParseValueRequest(arr_info.child, alloc, item, opts);
                            }

                            return result;
                        },
                        .string => |str| {
                            if (arr_info.child != u8)
                                return error.UnexpectedToken;

                            var result: TT = undefined;

                            const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                            if (std.fmt.hexToBytes(&result, slice)) |_| {
                                if (arr_info.len != slice.len / 2)
                                    return error.LengthMismatch;

                                return result;
                            } else |_| {
                                if (slice.len != result.len)
                                    return error.LengthMismatch;

                                @memcpy(result[0..], slice[0..]);
                            }
                            return result;
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .Pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => {
                            const result: *ptr_info.child = try alloc.create(ptr_info.child);
                            result.* = try innerParseRequest(ptr_info.child, alloc, source, opts);
                            return result;
                        },
                        .Slice => {
                            switch (source) {
                                .array => |array| {
                                    const arr = try alloc.alloc(ptr_info.child, array.items.len);
                                    for (array.items, arr) |item, *res| {
                                        res.* = try innerParseValueRequest(ptr_info.child, alloc, item, opts);
                                    }

                                    return arr;
                                },
                                .string => |str| {
                                    if (ptr_info.child != u8) return error.UnexpectedToken;

                                    if (ptr_info.is_const) return str;

                                    if (str.len & 1 != 0)
                                        return error.InvalidCharacter;

                                    const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                                    const result = try alloc.alloc(u8, @divExact(slice.len, 2));

                                    _ = std.fmt.hexToBytes(result, slice) catch return error.UnexpectedToken;

                                    return result;
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => @compileError("Unable to parse type " ++ @typeName(TT)),
                    }
                },
                .Struct => {
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(alloc, source, opts) else @compileError("Unable to parse structs without jsonParseFromValue custom declaration. Typename: " ++ @typeName(TT));
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(alloc, source, opts) else @compileError("Unable to parse unions without jsonParseFromValue custom declaration. Typename: " ++ @typeName(TT));
                },

                else => @compileError("Unable to parse type " ++ @typeName(TT)),
            }
        }

        fn innerParseRequest(comptime TT: type, alloc: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!TT {
            const info = @typeInfo(TT);

            switch (info) {
                .Bool => {
                    return switch (try source.next()) {
                        .true => true,
                        .false => false,
                        .string => |slice| try std.fmt.parseInt(u1, slice, 0) != 0,
                        else => error.UnexpectedToken,
                    };
                },
                .Int, .ComptimeInt => {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };

                    return try std.fmt.parseInt(TT, slice, 0);
                },
                .Float, .ComptimeFloat => {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };
                    return try std.fmt.parseFloat(TT, slice);
                },
                .Optional => |opt_info| {
                    switch (try source.peekNextTokenType()) {
                        .null => {
                            _ = try source.next();
                            return null;
                        },
                        else => return try innerParseRequest(opt_info.child, alloc, source, opts),
                    }
                },
                .Enum => |enum_info| {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    switch (token) {
                        inline .number, .allocated_number => |slice| {
                            const enum_number = std.fmt.parseInt(enum_info.tag_type, slice, 0) catch return error.InvalidEnumTag;
                            return std.meta.intToEnum(TT, enum_number);
                        },
                        inline .string, .allocated_string => |slice| return std.meta.stringToEnum(TT, slice) orelse error.InvalidEnumTag,

                        else => return error.UnexpectedToken,
                    }
                },
                .Array => |arr_info| {
                    switch (try source.peekNextTokenType()) {
                        .array_begin => {
                            _ = try source.next();

                            var result: TT = undefined;

                            var index: usize = 0;
                            while (index < arr_info.len) : (index += 1) {
                                result[index] = try innerParseRequest(arr_info.child, alloc, source, opts);
                            }

                            if (.array_end != try source.next())
                                return error.UnexpectedToken;

                            return result;
                        },
                        .string => {
                            if (arr_info.child != u8)
                                return error.UnexpectedToken;

                            var result: TT = undefined;

                            switch (try source.next()) {
                                .string => |str| {
                                    const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else return error.UnexpectedToken;
                                    if (std.fmt.hexToBytes(&result, slice)) |_| {
                                        return result;
                                    } else |_| {
                                        if (slice.len != result.len)
                                            return error.LengthMismatch;

                                        @memcpy(result[0..], slice[0..]);
                                    }
                                    return result;
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => return error.UnexpectedToken,
                    }
                },

                .Pointer => |ptrInfo| {
                    switch (ptrInfo.size) {
                        .Slice => {
                            switch (try source.peekNextTokenType()) {
                                .array_begin => {
                                    _ = try source.next();

                                    // Typical array.
                                    var arraylist = std.ArrayList(ptrInfo.child).init(alloc);
                                    while (true) {
                                        switch (try source.peekNextTokenType()) {
                                            .array_end => {
                                                _ = try source.next();
                                                break;
                                            },
                                            else => {},
                                        }

                                        try arraylist.ensureUnusedCapacity(1);
                                        arraylist.appendAssumeCapacity(try innerParseRequest(ptrInfo.child, alloc, source, opts));
                                    }

                                    return try arraylist.toOwnedSlice();
                                },
                                .string => {
                                    if (ptrInfo.child != u8)
                                        return error.UnexpectedToken;

                                    if (ptrInfo.is_const) {
                                        switch (try source.nextAllocMax(alloc, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |slice| {
                                                return slice;
                                            },
                                            else => unreachable,
                                        }
                                    } else {
                                        // Have to allocate to get a mutable copy.
                                        switch (try source.nextAllocMax(alloc, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |str| {
                                                if (str.len & 1 != 0)
                                                    return error.UnexpectedToken;

                                                const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                                                const result = try alloc.alloc(u8, @divExact(slice.len, 2));

                                                _ = std.fmt.hexToBytes(result, slice) catch return error.InvalidCharacter;

                                                return result;
                                            },
                                            else => unreachable,
                                        }
                                    }
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => @compileError("Unable to parse type " ++ @typeName(TT)),
                    }
                },
                .Struct => {
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(alloc, source, opts) else @compileError("Unable to parse structs without jsonParse custom declaration. Typename: " ++ @typeName(TT));
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(alloc, source, opts) else @compileError("Unable to parse unions without jsonParse custom declaration. Typename: " ++ @typeName(TT));
                },
                else => @compileError("Unable to parse type " ++ @typeName(TT)),
            }
        }
    };
}

test "Parse/Stringify Json" {
    {
        const gen = try generator.generateRandomData(types.block.Block, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.Block, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.block.BeaconBlock, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.BeaconBlock, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.block.BlobBlock, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.BlobBlock, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionEnvelope, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionEnvelope, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionEnvelopeSigned, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionEnvelopeSigned, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionReceipt, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionReceipt, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.Transaction, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.Transaction, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.log.Logs, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.log.Logs, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumResponse(u32), testing.allocator, 0, .{
            .slice_size = 20,
            .use_default_values = true,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumResponse(u32), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumErrorResponse, testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumErrorResponse, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumSubscribeEvents, testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumSubscribeEvents, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumSubscribeResponse(u64), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumSubscribeResponse(u64), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumRequest(struct { u64 }), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumRequest([1]u64), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated.params, parsed.value.params);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumRequest([2]u32), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumRequest([2]u32), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.FeeHistory, testing.allocator, 0, .{
            .slice_size = 20,
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.FeeHistory, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
}
