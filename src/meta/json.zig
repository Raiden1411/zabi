const generator = @import("../tests/generator.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../types/root.zig");
const meta_utils = @import("../meta/utils.zig");

// Types
const Allocator = std.mem.Allocator;
const ConvertToEnum = meta_utils.ConvertToEnum;
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

        pub fn jsonParse(allocator: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!T {
            const info = @typeInfo(T);
            if (.object_begin != try source.next()) return error.UnexpectedToken;

            var result: T = undefined;
            var seen: std.enums.EnumFieldStruct(ConvertToEnum(T), u32, 0) = .{};

            while (true) {
                var name_token: ?Token = try source.nextAllocMax(allocator, .alloc_if_needed, opts.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };

                inline for (info.Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        name_token = null;

                        if (@field(seen, field.name) == 1) {
                            switch (opts.duplicate_field_behavior) {
                                .@"error" => return error.DuplicateField,
                                .use_last => {},
                                .use_first => {
                                    _ = try innerParseRequest(field.type, allocator, source, opts);

                                    break;
                                },
                            }
                        }
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try innerParseRequest(field.type, allocator, source, opts);
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

            inline for (info.Struct.fields) |field| {
                switch (@field(seen, field.name)) {
                    0 => if (field.default_value) |default_value| {
                        @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default_value))).*;
                    } else return error.MissingField,
                    1 => {},
                    else => {
                        switch (opts.duplicate_field_behavior) {
                            .@"error" => return error.DuplicateField,
                            else => {},
                        }
                    },
                }
            }

            return result;
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, opts: ParseOptions) ParseFromValueError!T {
            const info = @typeInfo(T);
            if (source != .object) return error.UnexpectedToken;

            var result: T = undefined;
            var seen: std.enums.EnumFieldStruct(ConvertToEnum(T), u32, 0) = .{};

            var iter = source.object.iterator();

            while (iter.next()) |token| {
                const field_name = token.key_ptr.*;

                inline for (info.Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        if (@field(seen, field.name) == 1) {
                            switch (opts.duplicate_field_behavior) {
                                .@"error" => return error.DuplicateField,
                                .use_last => {},
                                .use_first => {
                                    _ = try innerParseValueRequest(field.type, allocator, source, opts);

                                    break;
                                },
                            }
                        }
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try innerParseValueRequest(field.type, allocator, token.value_ptr.*, opts);
                        break;
                    }
                } else {
                    if (!opts.ignore_unknown_fields)
                        return error.UnknownField;
                }
            }

            inline for (info.Struct.fields) |field| {
                switch (@field(seen, field.name)) {
                    0 => if (field.default_value) |default_value| {
                        @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default_value))).*;
                    } else return error.MissingField,
                    1 => {},
                    else => {
                        switch (opts.duplicate_field_behavior) {
                            .@"error" => return error.DuplicateField,
                            else => {},
                        }
                    },
                }
            }

            return result;
        }

        fn innerParseValueRequest(comptime TT: type, allocator: Allocator, source: anytype, opts: ParseOptions) ParseFromValueError!TT {
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
                        else => return try innerParseValueRequest(opt_info.child, allocator, source, opts),
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
                                result[i] = try innerParseValueRequest(arr_info.child, allocator, item, opts);
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
                            const result: *ptr_info.child = try allocator.create(ptr_info.child);
                            result.* = try innerParseRequest(ptr_info.child, allocator, source, opts);
                            return result;
                        },
                        .Slice => {
                            switch (source) {
                                .array => |array| {
                                    const arr = try allocator.alloc(ptr_info.child, array.items.len);
                                    for (array.items, arr) |item, *res| {
                                        res.* = try innerParseValueRequest(ptr_info.child, allocator, item, opts);
                                    }

                                    return arr;
                                },
                                .string => |str| {
                                    if (ptr_info.child != u8)
                                        return error.UnexpectedToken;

                                    if (ptr_info.is_const)
                                        return str;

                                    if (str.len & 1 != 0)
                                        return error.InvalidCharacter;

                                    const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                                    const result = try allocator.alloc(u8, @divExact(slice.len, 2));

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
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(allocator, source, opts) else @compileError("Unable to parse structs without jsonParseFromValue custom declaration. Typename: " ++ @typeName(TT));
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(allocator, source, opts) else @compileError("Unable to parse unions without jsonParseFromValue custom declaration. Typename: " ++ @typeName(TT));
                },

                else => @compileError("Unable to parse type " ++ @typeName(TT)),
            }
        }

        fn innerParseRequest(comptime TT: type, allocator: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!TT {
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
                    const token = try source.nextAllocMax(allocator, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };

                    return try std.fmt.parseInt(TT, slice, 0);
                },
                .Float, .ComptimeFloat => {
                    const token = try source.nextAllocMax(allocator, .alloc_if_needed, opts.max_value_len.?);
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
                        else => return try innerParseRequest(opt_info.child, allocator, source, opts),
                    }
                },
                .Enum => |enum_info| {
                    const token = try source.nextAllocMax(allocator, .alloc_if_needed, opts.max_value_len.?);
                    switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| {
                            if (std.meta.stringToEnum(TT, slice)) |converted| return converted;

                            const enum_number = std.fmt.parseInt(enum_info.tag_type, slice, 0) catch return error.InvalidEnumTag;
                            return std.meta.intToEnum(TT, enum_number);
                        },

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
                                result[index] = try innerParseRequest(arr_info.child, allocator, source, opts);
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
                                    var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                                    while (true) {
                                        switch (try source.peekNextTokenType()) {
                                            .array_end => {
                                                _ = try source.next();
                                                break;
                                            },
                                            else => {},
                                        }

                                        try arraylist.ensureUnusedCapacity(1);
                                        arraylist.appendAssumeCapacity(try innerParseRequest(ptrInfo.child, allocator, source, opts));
                                    }

                                    return try arraylist.toOwnedSlice();
                                },
                                .string => {
                                    if (ptrInfo.child != u8)
                                        return error.UnexpectedToken;

                                    if (ptrInfo.is_const) {
                                        switch (try source.nextAllocMax(allocator, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |slice| {
                                                return slice;
                                            },
                                            else => unreachable,
                                        }
                                    } else {
                                        // Have to allocate to get a mutable copy.
                                        switch (try source.nextAllocMax(allocator, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |str| {
                                                if (str.len & 1 != 0)
                                                    return error.UnexpectedToken;

                                                const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                                                const result = try allocator.alloc(u8, @divExact(slice.len, 2));

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
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(allocator, source, opts) else @compileError("Unable to parse structs without jsonParse custom declaration. Typename: " ++ @typeName(TT));
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(allocator, source, opts) else @compileError("Unable to parse unions without jsonParse custom declaration. Typename: " ++ @typeName(TT));
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
    {
        const gen = try generator.generateRandomData(types.transactions.FeeHistory, testing.allocator, 0, .{
            .slice_size = 20,
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        try testing.expectError(error.UnknownField, std.json.parseFromSlice(types.transactions.LegacyEthCall, testing.allocator, as_slice, .{}));
    }
    {
        const slice =
            \\{"transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","from":"0xb2552eb7460f77f34ce3e33ecfc99d6669c38033","to":"0x9aed3a8896a85fe9a8cac52c9b402d092b629a30","cumulativeGasUsed":"0x506f4c","gasUsed":"0x20fec2","contractAddress":null,"logs":[{"address":"0xff970a61a04b1ca14834a43f5de4533ebddb5cc8","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","0x000000000000000000000000eff23b4be1091b53205e35f3afcd9c7182bf3062"],"data":"0x00000000000000000000000000000000000000000000000000000000004c4b40","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0x9","removed":false},{"address":"0xff970a61a04b1ca14834a43f5de4533ebddb5cc8","topics":["0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb3b4bf","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xa","removed":false},{"address":"0x82af49447d8a07e3bd95bd0d56f35241523fbab1","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x000000000000000000000000eff23b4be1091b53205e35f3afcd9c7182bf3062","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0x0000000000000000000000000000000000000000000000000009b2c08c45f8c6","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xb","removed":false},{"address":"0xeff23b4be1091b53205e35f3afcd9c7182bf3062","topics":["0x0e8e403c2d36126272b08c75823e988381d9dc47f2f0a9a080d95f891d95c469","0x000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8","0x00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0x00000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000009b2c08c45f8c60000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c3803300000000000000000000000000000000000000000000000000000000004c4b4000000000000000000000000000000000000000000000000000000000000004e2","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xc","removed":false},{"address":"0x82af49447d8a07e3bd95bd0d56f35241523fbab1","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30","0x0000000000000000000000000000000000000000000000000000000000000000"],"data":"0x0000000000000000000000000000000000000000000000000009b2c08c45f8c6","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xd","removed":false},{"address":"0x9aed3a8896a85fe9a8cac52c9b402d092b629a30","topics":["0x27c98e911efdd224f4002f6cd831c3ad0d2759ee176f9ee8466d95826af22a1c","0x000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8","0x000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033"],"data":"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000009b2c08c45f8c6000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xe","removed":false}],"status":"0x1","logsBloom":"0x08000000000000000000800000000000000000000000000000000000000000100000000000000000000000000000000100004000000000020010400000200000000000010001000000000008000000010100000000040000000000000000000000000001020000080000000400000800000000000000000000000010400000010000000000000000000000000000000000000000000000000000000000000000061000000000000000000100800000000000010000000010000000200000000000000002000048000000000000100000000000000000200000000000000020000010000000000000020820000002000000000000000200800000000000200000","type":"0x0","effectiveGasPrice":"0x5f5e100","deposit_nonce":null,"gasUsedForL1":"0x1d79d2","l1BlockNumber":"0x106028d"}
        ;

        const parsed = try std.json.parseFromSlice(types.transactions.ArbitrumReceipt, testing.allocator, slice, .{});
        defer parsed.deinit();
    }
    {
        const slice =
            \\{
            \\  "pending":{
            \\     "0x0216d5032f356960cd3749c31ab34eeff21b3395":{
            \\        "806":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x0216d5032f356960cd3749c31ab34eeff21b3395",
            \\           "gas":"0x5208",
            \\           "gasPrice":"0xba43b7400",
            \\           "hash":"0xaf953a2d01f55cfe080c0c94150a60105e8ac3d51153058a1f03dd239dd08586",
            \\           "input":"0x",
            \\           "nonce":"0x326",
            \\           "to":"0x7f69a91a3cf4be60020fb58b893b7cbb65376db8",
            \\           "transactionIndex":null,
            \\           "value":"0x19a99f0cf456000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     },
            \\     "0x24d407e5a0b506e1cb2fae163100b5de01f5193c":{
            \\        "34":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x24d407e5a0b506e1cb2fae163100b5de01f5193c",
            \\           "gas":"0x44c72",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0xb5b8b853af32226755a65ba0602f7ed0e8be2211516153b75e9ed640a7d359fe",
            \\           "input":"0xb61d27f600000000000000000000000024d407e5a0b506e1cb2fae163100b5de01f5193c00000000000000000000000000000000000000000000000053444835ec580000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            \\           "nonce":"0x22",
            \\           "to":"0x7320785200f74861b69c49e4ab32399a71b34f1a",
            \\           "transactionIndex":null,
            \\           "value":"0x0",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     }
            \\  },
            \\  "queued":{
            \\     "0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c":{
            \\        "3":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0x57b30c59fc39a50e1cba90e3099286dfa5aaf60294a629240b5bbec6e2e66576",
            \\           "input":"0x",
            \\           "nonce":"0x3",
            \\           "to":"0x346fb27de7e7370008f5da379f74dd49f5f2f80f",
            \\           "transactionIndex":null,
            \\           "value":"0x1f161421c8e0000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     },
            \\     "0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a":{
            \\        "2":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0xba43b7400",
            \\           "hash":"0x3a3c0698552eec2455ed3190eac3996feccc806970a4a056106deaf6ceb1e5e3",
            \\           "input":"0x",
            \\           "nonce":"0x2",
            \\           "to":"0x24a461f25ee6a318bdef7f33de634a67bb67ac9d",
            \\           "transactionIndex":null,
            \\           "value":"0xebec21ee1da40000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        },
            \\        "6":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0xbbcd1e45eae3b859203a04be7d6e1d7b03b222ec1d66dfcc8011dd39794b147e",
            \\           "input":"0x",
            \\           "nonce":"0x6",
            \\           "to":"0x6368f3f8c2b42435d6c136757382e4a59436a681",
            \\           "transactionIndex":null,
            \\           "value":"0xf9a951af55470000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     }
            \\  }
            \\}
            \\
        ;
        const parsed = try std.json.parseFromSlice(@import("../types/txpool.zig").TxPoolContent, testing.allocator, slice, .{});
        defer parsed.deinit();

        const all = try std.json.stringifyAlloc(testing.allocator, parsed.value, .{});
        defer testing.allocator.free(all);
    }
    {
        const slice =
            \\{
            \\  "pending":{
            \\     "0x26588a9301b0428d95e6fc3a5024fce8bec12d51":{
            \\        "31813":"0x3375ee30428b2a71c428afa5e89e427905f95f7e: 0 wei + 500000 × 20000000000 wei"
            \\     },
            \\     "0x2a65aca4d5fc5b5c859090a6c34d164135398226":{
            \\        "563662":"0x958c1fa64b34db746925c6f8a3dd81128e40355e: 1051546810000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563663":"0x77517b1491a0299a44d668473411676f94e97e34: 1051190740000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563664":"0x3e2a7fe169c8f8eee251bb00d9fb6d304ce07d3a: 1050828950000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563665":"0xaf6c4695da477f8c663ea2d8b768ad82cb6a8522: 1050544770000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563666":"0x139b148094c50f4d20b01caf21b85edb711574db: 1048598530000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563667":"0x48b3bd66770b0d1eecefce090dafee36257538ae: 1048367260000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563668":"0x468569500925d53e06dd0993014ad166fd7dd381: 1048126690000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563669":"0x3dcb4c90477a4b8ff7190b79b524773cbe3be661: 1047965690000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563670":"0x6dfef5bc94b031407ffe71ae8076ca0fbf190963: 1047859050000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0x9174e688d7de157c5c0583df424eaab2676ac162":{
            \\        "3":"0xbb9bc244d798123fde783fcc1c72d3bb8c189413: 30000000000000000000 wei + 85000 gas × 21000000000 wei"
            \\     },
            \\     "0xb18f9d01323e150096650ab989cfecd39d757aec":{
            \\        "777":"0xcd79c72690750f079ae6ab6ccd7e7aedc03c7720: 0 wei + 1000000 gas × 20000000000 wei"
            \\     },
            \\     "0xb2916c870cf66967b6510b76c07e9d13a5d23514":{
            \\        "2":"0x576f25199d60982a8f31a8dff4da8acb982e6aba: 26000000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0xbc0ca4f217e052753614d6b019948824d0d8688b":{
            \\        "0":"0x2910543af39aba0cd09dbb2d50200b3e800a63d2: 1000000000000000000 wei + 50000 gas × 1171602790622 wei"
            \\     },
            \\     "0xea674fdde714fd979de3edf0f56aa9716b898ec8":{
            \\        "70148":"0xe39c55ead9f997f7fa20ebe40fb4649943d7db66: 1000767667434026200 wei + 90000 gas × 20000000000 wei"
            \\     }
            \\  },
            \\  "queued":{
            \\     "0x0f6000de1578619320aba5e392706b131fb1de6f":{
            \\        "6":"0x8383534d0bcd0186d326c993031311c0ac0d9b2d: 9000000000000000000 wei + 21000 gas × 20000000000 wei"
            \\     },
            \\     "0x5b30608c678e1ac464a8994c3b33e5cdf3497112":{
            \\        "6":"0x9773547e27f8303c87089dc42d9288aa2b9d8f06: 50000000000000000000 wei + 90000 gas × 50000000000 wei"
            \\     },
            \\     "0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c":{
            \\        "3":"0x346fb27de7e7370008f5da379f74dd49f5f2f80f: 140000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a":{
            \\        "2":"0x24a461f25ee6a318bdef7f33de634a67bb67ac9d: 17000000000000000000 wei + 90000 gas × 50000000000 wei",
            \\        "6":"0x6368f3f8c2b42435d6c136757382e4a59436a681: 17990000000000000000 wei + 90000 gas × 20000000000 wei",
            \\        "7":"0x6368f3f8c2b42435d6c136757382e4a59436a681: 17900000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     }
            \\  }
            \\}
        ;

        const parsed = try std.json.parseFromSlice(@import("../types/txpool.zig").TxPoolInspect, testing.allocator, slice, .{});
        defer parsed.deinit();

        const all = try std.json.stringifyAlloc(testing.allocator, parsed.value, .{});
        defer testing.allocator.free(all);
    }
}
