const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// The block explorers api query options.
pub const QueryOptions = struct {
    /// The page number if pagination is enabled.
    page: ?usize = null,
    /// The number of items displayed per page.
    offset: ?usize = null,
    /// The prefered sorting sequence.
    /// Asc for ascending and desc for descending.
    sort: ?enum { asc, desc } = null,
};

/// Writes the given value to the `std.io.Writer` stream.
///
/// See `QueryWriter` for a more detailed documentation.
pub fn searchUrlParams(value: anytype, options: QueryOptions, out_stream: anytype) @TypeOf(out_stream).Error!void {
    const info = @typeInfo(@TypeOf(value));

    std.debug.assert(info == .Struct); // Must be a non tuple struct type
    std.debug.assert(!info.Struct.is_tuple); // Must be a non tuple struct type

    var writer = writeStream(out_stream);

    try writer.beginQuery();
    inline for (info.Struct.fields) |field| {
        try writer.writeParameter(field.name);
        try writer.writeValue(@field(value, field.name));
    }

    try writer.writeQueryOptions(options);
}
/// Writes the given value to an `ArrayList` stream.
/// This will allocated memory instead of writting to `std.io.Writer`.
/// You will need to free the allocated memory.
///
/// See `QueryWriter` for a more detailed documentation.
pub fn searchUrlParamsAlloc(allocator: Allocator, value: anytype, options: QueryOptions) Allocator.Error![]u8 {
    var list = ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try searchUrlParams(value, options, list.writer());
    return list.toOwnedSlice();
}
/// See `QueryWriter` for a more detailed documentation.
pub fn writeStream(out_stream: anytype) QueryWriter(@TypeOf(out_stream)) {
    return QueryWriter(@TypeOf(out_stream)).init(out_stream);
}

/// Essentially a wrapper for a `Writer` interface
/// specified for query parameters.
/// The final expected sequence is something like: **"?foo=1&bar=2"**
///
/// Supported types:
///   * Zig `bool` -> "true" or "false"
///   * Zig `?T` -> "null" for null values or it renders `T` if it's supported.
///   * Zig `u32`, `i64`, etc -> the string representation of the number.
///   * Zig `floats` -> the string representation of the float.
///   * Zig `[N]u8` -> it assumes as a hex encoded string. For arrays of size 20,40,42 it will assume as a ethereum address.
///   * Zig `enum` -> the tagname of the enum.
///   * Zig `*T` -> the rending of T if it's supported.
///   * Zig `[]const u8` -> it writes it as a normal string.
///   * Zig `[]u8` -> it writes it as a hex encoded string.
///   * Zig `[]const T` -> the rendering of T if it's supported. Values are comma seperated in case
///   of multiple values. It will not place the brackets on the query parameters.
///
/// All other types are currently not supported.
pub fn QueryWriter(comptime OutStream: type) type {
    return struct {
        const Self = @This();

        pub const Stream = OutStream;
        pub const Error = Stream.Error;

        next_punctuation: enum {
            assign,
            comma,
            none,
            start_parameter,
            start_query,
        } = .start_query,
        stream: OutStream,

        /// Start the writer initial state.
        pub fn init(stream: OutStream) Self {
            return .{
                .stream = stream,
            };
        }
        /// Start the begging of the query string.
        pub fn beginQuery(self: *Self) Error!void {
            try self.stream.writeByte('?');
            self.next_punctuation = .none;
        }
        /// Start either the parameter or value of the query string.
        pub fn valueOrParameterStart(self: *Self) Error!void {
            switch (self.next_punctuation) {
                .none, .start_query => {},
                .comma => try self.stream.writeByte(','),
                .start_parameter => try self.stream.writeByte('&'),
                .assign => try self.stream.writeByte('='),
            }
        }
        /// Marks the current value as done.
        pub fn valueDone(self: *Self) void {
            self.next_punctuation = .start_parameter;
        }
        /// Marks the current parameter as done.
        pub fn parameterDone(self: *Self) void {
            self.next_punctuation = .assign;
        }
        /// Writes the query options into the `Stream`.
        /// It will only write non null values otherwise it will do nothing.
        pub fn writeQueryOptions(self: *Self, options: QueryOptions) Error!void {
            inline for (std.meta.fields(@TypeOf(options))) |field| {
                if (@field(options, field.name)) |value| {
                    try self.writeParameter(field.name);
                    try self.writeValue(value);
                }
            }
        }
        /// Writes a parameter of the query string.
        pub fn writeParameter(self: *Self, name: []const u8) Error!void {
            try self.valueOrParameterStart();
            try self.stream.writeAll(name);
            self.parameterDone();
        }
        /// Writes the value of the parameter of the query string.
        /// Not all types are accepted.
        pub fn writeValue(self: *Self, value: anytype) Error!void {
            const info = @typeInfo(@TypeOf(value));

            switch (info) {
                .Bool => {
                    try self.valueOrParameterStart();
                    if (value) try self.stream.writeAll("true") else try self.stream.writeAll("false");
                    self.valueDone();
                    return;
                },
                .Int => {
                    try self.valueOrParameterStart();
                    try self.stream.print("{}", .{value});
                    self.valueDone();
                    return;
                },
                .ComptimeInt => return self.writeValue(@as(std.math.IntFittingRange(value, value), value)),
                .Float, .ComptimeFloat => {
                    try self.valueOrParameterStart();
                    try self.stream.print("{}", .{value});
                    self.valueDone();
                    return;
                },
                .Optional => {
                    if (value) |val| {
                        return self.writeValue(val);
                    }

                    return self.writeValue(null);
                },
                .Null => {
                    try self.valueOrParameterStart();
                    try self.stream.writeAll("null");
                    self.valueDone();
                },
                .Enum, .EnumLiteral => {
                    try self.valueOrParameterStart();
                    try self.stream.writeAll(@tagName(value));
                    self.valueDone();
                },
                .Array => |arr_info| {
                    if (arr_info.child != u8)
                        @compileError("Unable to parse non `u8` array types");

                    try self.valueOrParameterStart();
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
                            try self.stream.writeAll(buffer[0..]);
                        },
                        else => {
                            const hexed = std.fmt.bytesToHex(value, .lower);
                            try self.stream.writeAll(hexed[0..]);
                        },
                    }
                    self.valueDone();
                },
                .Pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => switch (@typeInfo(ptr_info.child)) {
                            .Array => {
                                const Slice = []const std.meta.Elem(ptr_info.child);
                                return try self.writeValue(@as(Slice, value));
                            },
                            else => return self.writeValue(value.*),
                        },
                        .Many, .Slice => {
                            if (ptr_info.size == .Many and ptr_info.sentinel == null)
                                @compileError("Unable to stringify type '" ++ @typeName(@TypeOf(value)) ++ "' without sentinel");

                            const slice = if (ptr_info.size == .Many) std.mem.span(value) else value;

                            if (ptr_info.child == u8) {
                                try self.valueOrParameterStart();
                                if (ptr_info.is_const) {
                                    try self.stream.writeAll(slice);
                                } else {
                                    try self.stream.writeAll("0x");

                                    var buf: [2]u8 = undefined;

                                    const charset = "0123456789abcdef";
                                    for (value) |c| {
                                        buf[0] = charset[c >> 4];
                                        buf[1] = charset[c & 15];
                                        try self.stream.writeAll(&buf);
                                    }
                                }
                                return self.valueDone();
                            }

                            try self.valueOrParameterStart();

                            self.next_punctuation = .none;
                            for (value) |val| {
                                try self.writeValue(val);
                                self.next_punctuation = .comma;
                            }
                            return self.valueDone();
                        },
                        else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
                    }
                },
                else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
            }
        }
    };
}
