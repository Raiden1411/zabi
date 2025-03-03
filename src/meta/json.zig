const meta_utils = @import("utils.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("zabi-types");

const Allocator = std.mem.Allocator;
const ConvertToEnum = meta_utils.ConvertToEnum;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Token = std.json.Token;
const Value = std.json.Value;

/// Custom jsonParse that is mostly used to enable
/// the ability to parse hex string values into native `int` types,
/// since parsing hex values is not part of the JSON RFC we need to rely on
/// the hability of zig to create a custom jsonParse method for structs.
pub fn jsonParse(
    comptime T: type,
    allocator: Allocator,
    source: anytype,
    options: ParseOptions,
) ParseError(@TypeOf(source.*))!T {
    const json_value = try Value.jsonParse(allocator, source, options);
    return jsonParseFromValue(T, allocator, json_value, options);
}

/// Custom jsonParseFromValue that is mostly used to enable
/// the ability to parse hex string values into native `int` types,
/// since parsing hex values is not part of the JSON RFC we need to rely on
/// the hability of zig to create a custom jsonParseFromValue method for structs.
pub fn jsonParseFromValue(
    comptime T: type,
    allocator: Allocator,
    source: Value,
    options: ParseOptions,
) ParseFromValueError!T {
    const info = @typeInfo(T);
    if (source != .object) return error.UnexpectedToken;

    var result: T = undefined;
    var seen: std.enums.EnumFieldStruct(ConvertToEnum(T), u32, 0) = .{};

    var iter = source.object.iterator();

    while (iter.next()) |token| {
        const field_name = token.key_ptr.*;

        inline for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                if (@field(seen, field.name) == 1) {
                    switch (options.duplicate_field_behavior) {
                        .@"error" => return error.DuplicateField,
                        .use_last => {},
                        .use_first => {
                            _ = try innerParseValueRequest(field.type, allocator, source, options);

                            break;
                        },
                    }
                }
                @field(seen, field.name) = 1;
                @field(result, field.name) = try innerParseValueRequest(field.type, allocator, token.value_ptr.*, options);
                break;
            }
        } else {
            if (!options.ignore_unknown_fields)
                return error.UnknownField;
        }
    }

    inline for (info.@"struct".fields) |field| {
        switch (@field(seen, field.name)) {
            0 => if (field.default_value_ptr) |default_value| {
                @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default_value))).*;
            } else return error.MissingField,
            1 => {},
            else => {
                switch (options.duplicate_field_behavior) {
                    .@"error" => return error.DuplicateField,
                    else => {},
                }
            },
        }
    }

    return result;
}

/// Custom jsonStringify that is mostly used to enable
/// the ability to parse int values as hex and to parse address with checksum
/// and to treat array and slices of `u8` as hex encoded strings. This doesn't
/// apply if the slice is `const`.
///
/// Parsing hex values or dealing with strings like this is not part of the JSON RFC we need to rely on
/// the hability of zig to create a custom jsonStringify method for structs
pub fn jsonStringify(
    comptime T: type,
    self: T,
    writer_stream: anytype,
) @TypeOf(writer_stream.*).Error!void {
    const info = @typeInfo(T);

    try valueStart(writer_stream);

    try writer_stream.stream.writeByte('{');
    writer_stream.next_punctuation = .the_beginning;
    inline for (info.@"struct".fields) |field| {
        var emit_field = true;
        if (@typeInfo(field.type) == .optional) {
            if (@field(self, field.name) == null and !writer_stream.options.emit_null_optional_fields) {
                emit_field = false;
            }
        }

        if (emit_field) {
            try valueStart(writer_stream);
            try std.json.encodeJsonString(field.name, .{}, writer_stream.stream);
            writer_stream.next_punctuation = .colon;
            try innerStringify(@field(self, field.name), writer_stream);
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
/// Inner parser that enables the behaviour described above.
///
/// We don't use the `innerParse` from slice because the slice gets parsed
/// as a json dynamic `Value`.
pub fn innerParseValueRequest(
    comptime T: type,
    allocator: Allocator,
    source: Value,
    options: ParseOptions,
) ParseFromValueError!T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            switch (source) {
                .string => |val| return try std.fmt.parseInt(u1, val, 0) != 0,
                else => return std.json.innerParseFromValue(T, allocator, source, options),
            }
        },
        .int,
        .comptime_int,
        => {
            switch (source) {
                .number_string, .string => |str| {
                    if (std.mem.eql(u8, str, "0x"))
                        return 0;

                    return std.fmt.parseInt(T, str, 0);
                },
                .float => return std.json.innerParseFromValue(T, allocator, source, options),
                .integer => return std.json.innerParseFromValue(T, allocator, source, options),

                else => return error.UnexpectedToken,
            }
        },
        .optional => |opt_info| {
            switch (source) {
                .null => return null,
                else => return try innerParseValueRequest(opt_info.child, allocator, source, options),
            }
        },
        .@"enum" => |enum_info| {
            switch (source) {
                .number_string, .string => |slice| {
                    if (std.meta.stringToEnum(T, slice)) |result| return result;

                    const enum_number = std.fmt.parseInt(enum_info.tag_type, slice, 0) catch return error.InvalidEnumTag;
                    return std.meta.intToEnum(T, enum_number);
                },
                else => return std.json.innerParseFromValue(T, allocator, source, options),
            }
        },
        .array => |arr_info| {
            switch (source) {
                .array => |arr| {
                    var result: T = undefined;
                    for (arr.items, 0..) |item, i| {
                        result[i] = try innerParseValueRequest(arr_info.child, allocator, item, options);
                    }

                    return result;
                },
                .string => |str| {
                    if (arr_info.child != u8)
                        return error.UnexpectedToken;

                    var result: T = undefined;

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
                else => return std.json.innerParseFromValue(T, allocator, source, options),
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
                    const result: *ptr_info.child = try allocator.create(ptr_info.child);
                    result.* = try innerParseValueRequest(ptr_info.child, allocator, source, options);
                    return result;
                },
                .slice => {
                    switch (source) {
                        .array => |array| {
                            const arr = try allocator.alloc(ptr_info.child, array.items.len);
                            for (array.items, arr) |item, *res| {
                                res.* = try innerParseValueRequest(ptr_info.child, allocator, item, options);
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
                else => @compileError("Unable to parse pointer type " ++ @typeName(T)),
            }
        },
        else => return std.json.innerParseFromValue(T, allocator, source, options),
    }
}
/// Inner stringifier that enables the behaviour described above.
pub fn innerStringify(
    value: anytype,
    stream_writer: anytype,
) @TypeOf(stream_writer.*).Error!void {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .bool => {
            try valueStart(stream_writer);
            try stream_writer.stream.writeAll(if (value) "true" else "false");
            stream_writer.next_punctuation = .comma;
        },
        .int, .comptime_int => {
            try valueStart(stream_writer);
            try stream_writer.stream.writeByte('\"');
            try stream_writer.stream.print("0x{x}", .{value});
            try stream_writer.stream.writeByte('\"');
            stream_writer.next_punctuation = .comma;
        },
        .float, .comptime_float => {
            try valueStart(stream_writer);
            try stream_writer.stream.print("{d}", .{value});
            stream_writer.next_punctuation = .comma;
        },
        .null => {
            try valueStart(stream_writer);
            try stream_writer.stream.writeAll("null");
            stream_writer.next_punctuation = .comma;
        },
        .optional => {
            if (value) |val| {
                return try innerStringify(val, stream_writer);
            } else return try innerStringify(null, stream_writer);
        },
        .enum_literal => {
            try valueStart(stream_writer);
            try std.json.encodeJsonString(@tagName(value), .{}, stream_writer.stream);
            stream_writer.next_punctuation = .comma;
        },
        .@"enum" => |enum_info| {
            if (!enum_info.is_exhaustive) {
                inline for (enum_info.fields) |field| {
                    if (value == @field(@TypeOf(value), field.name)) {
                        break;
                    }
                } else return innerStringify(@intFromEnum(value), stream_writer);
            }

            try valueStart(stream_writer);
            try std.json.encodeJsonString(@tagName(value), .{}, stream_writer.stream);
            stream_writer.next_punctuation = .comma;
        },
        .error_set => {
            try valueStart(stream_writer);
            try std.json.encodeJsonString(@errorName(value), .{}, stream_writer.stream);
            stream_writer.next_punctuation = .comma;
        },
        .array => |arr_info| {
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
                return innerStringify(&value, stream_writer);
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => {
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return innerStringify(@as(Slice, value), stream_writer);
                    },
                    else => return innerStringify(value.*, stream_writer),
                },
                .many, .slice => {
                    if (ptr_info.size == .many and ptr_info.sentinel == null)
                        @compileError("Unable to stringify type '" ++ @typeName(@TypeOf(value)) ++ "' without sentinel");

                    const slice = if (ptr_info.size == .many) std.mem.span(value) else value;

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

                        stream_writer.indent_level += 1;
                        stream_writer.next_punctuation = .none;

                        for (slice) |span| {
                            try innerStringify(span, stream_writer);
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
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                try valueStart(stream_writer);
                try stream_writer.stream.writeByte('[');

                stream_writer.indent_level += 1;
                stream_writer.next_punctuation = .none;

                inline for (value) |val| {
                    try innerStringify(val, stream_writer);
                }

                switch (stream_writer.next_punctuation) {
                    .none, .comma => {},
                    else => unreachable,
                }

                try stream_writer.stream.writeByte(']');
                stream_writer.next_punctuation = .comma;

                return;
            } else {
                if (@hasDecl(@TypeOf(value), "jsonStringify"))
                    return value.jsonStringify(stream_writer)
                else
                    @compileError("Unable to parse structs without jsonStringify custom declaration. TypeName: " ++ @typeName(@TypeOf(value)));
            }
        },
        .@"union" => {
            if (@hasDecl(@TypeOf(value), "jsonStringify"))
                return value.jsonStringify(stream_writer)
            else
                @compileError("Unable to parse unions without jsonStringify custom declaration. Typename: " ++ @typeName(@TypeOf(value)));
        },
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
}

fn valueStart(stream_writer: anytype) @TypeOf(stream_writer.*).Error!void {
    switch (stream_writer.next_punctuation) {
        .the_beginning, .none => {},
        .comma => try stream_writer.stream.writeByte(','),
        .colon => try stream_writer.stream.writeByte(':'),
    }
}
