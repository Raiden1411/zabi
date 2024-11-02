const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

// Types
const Allocator = std.mem.Allocator;
const ByteAlignedInt = std.math.ByteAlignedInt;
const ArrayListWriter = std.ArrayList(u8).Writer;

/// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
/// This also supports generating a `Writer` interface.
///
/// Supported types:
///   * `bool`
///   * `int`
///   * `enum`, `enum_literal`
///   * `error_set`,
///   * `null`
///   * `?T`
///   * `[N]T` array types.
///   * `[]const T` slices.
///   * `*T` pointer types.
///   * `structs`. Both tuple and non tuples.
///
/// All other types are currently not supported.
///
/// Depending on your use case you case use this in to ways.
///
/// Use `encodeNoList` if the type that you need to encode isn't a tuple, slice or array (doesn't apply for u8 slices and arrays.)
/// and use `encodeList` if you need to encode the above mentioned.
///
/// Only `encodeList` will allocate memory when using this interface.
pub fn RlpEncoder(comptime OutWriter: type) type {
    return struct {
        /// The underlaying stream that we will write to.
        stream: OutWriter,

        const Self = @This();

        /// Set of errors that can be produced when encoding values.
        pub const Error = OutWriter.Error || error{ Overflow, NegativeNumber };
        /// The writer interface that can rlp encode.
        pub const Writer = std.io.Writer(*Self, Error, encodeString);

        /// Value that are used to identifity the size depending on the type
        pub const RlpSizeTag = enum(u8) {
            number = 0x80,
            string = 0xb7,
            list = 0xf7,
        };

        /// Sets the initial state.
        pub fn init(stream: OutWriter) Self {
            return .{
                .stream = stream,
            };
        }
        /// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
        /// For non `u8` slices and arrays use `encodeList`. Same applies for tuples and structs.
        pub fn encodeNoList(self: *Self, payload: anytype) Error!void {
            const info = @typeInfo(@TypeOf(payload));

            switch (info) {
                .bool => {
                    return switch (payload) {
                        true => self.stream.writeByte(0x01),
                        false => self.stream.writeByte(0x80),
                    };
                },
                .int => |int_info| {
                    if (int_info.signedness == .signed)
                        @compileError("Signed integers are not supported for RLP encoding.");

                    if (payload == 0)
                        return self.stream.writeByte(0x80);

                    if (payload < 0x80)
                        return self.stream.writeByte(@intCast(payload));

                    return self.writeSize(ByteAlignedInt(@TypeOf(payload)), payload, .number);
                },
                .comptime_int => {
                    if (payload < 0) return error.NegativeNumber;

                    const IntType = std.math.IntFittingRange(payload, payload);
                    return self.encodeNoList(@as(IntType, @intCast(payload)));
                },
                .null => return self.stream.writeByte(0x80),
                .optional => return if (payload) |item| self.encodeNoList(item) else self.stream.writeByte(0x80),
                .@"enum", .enum_literal => return self.encodeString(@tagName(payload)),
                .error_set => return self.encodeString(@errorName(payload)),
                .array => |arr_info| {
                    if (arr_info.child != u8)
                        @compileError("This method only supports u8 arrays. Please use `encodeList` instead.");

                    return self.encodeString(&payload);
                },
                .pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => return self.encodeNoList(payload.*),
                        .Slice => {
                            if (ptr_info.child != u8)
                                @compileError("This method only supports u8 slices. Please use `encodeList` instead.");

                            return self.encodeString(payload);
                        },
                        else => @compileError("Unable to encode pointer type '" ++ @typeName(@TypeOf(payload)) ++ "'"),
                    }
                },
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple)
                        @compileError("This method doesn't support tuples. Please use `encodeList` instead.");

                    inline for (struct_info.fields) |field| {
                        try self.encodeNoList(@field(payload, field.name));
                    }
                },
                else => @compileError("Unable to encode type '" ++ @typeName(@TypeOf(payload)) ++ "'"),
            }
        }
        /// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
        /// Only use this if you payload contains a slice, array or tuple/struct.
        ///
        /// This will allocate memory because it creates a `ArrayList` writer for the recursive calls.
        pub fn encodeList(self: *Self, allocator: Allocator, payload: anytype) Error!void {
            const info = @typeInfo(@TypeOf(payload));

            switch (info) {
                .optional => return if (payload) |item| self.encodeList(allocator, item) else self.stream.writeByte(0x80),
                .array => |arr_info| {
                    if (arr_info.child == u8)
                        return self.encodeString(&payload);

                    if (payload.len == 0)
                        return self.stream.writeByte(0xc0);

                    var arr = std.ArrayList(u8).init(allocator);
                    errdefer arr.deinit();

                    var recursive: RlpEncoder(ArrayListWriter) = .init(arr.writer());

                    for (payload) |item| {
                        try recursive.encodeList(allocator, item);
                    }

                    const slice = try arr.toOwnedSlice();
                    defer allocator.free(slice);

                    if (slice.len > std.math.maxInt(u64))
                        return error.Overflow;

                    if (slice.len < 56) {
                        try self.stream.writeByte(@intCast(0xc0 + slice.len));
                        return self.stream.writeAll(slice);
                    }

                    try self.writeSize(usize, slice.len, .list);
                    return self.stream.writeAll(slice);
                },
                .pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => return self.encodeList(allocator, payload.*),
                        .Slice => {
                            if (ptr_info.child == u8)
                                return self.encodeString(payload);

                            if (payload.len == 0)
                                return self.stream.writeByte(0xc0);

                            var arr = std.ArrayList(u8).init(allocator);
                            errdefer arr.deinit();

                            var recursive: RlpEncoder(ArrayListWriter) = .init(arr.writer());

                            for (payload) |item| {
                                try recursive.encodeList(allocator, item);
                            }

                            const slice = try arr.toOwnedSlice();
                            defer allocator.free(slice);

                            if (slice.len > std.math.maxInt(u64))
                                return error.Overflow;

                            if (slice.len < 56) {
                                try self.stream.writeByte(@intCast(0xc0 + slice.len));
                                return self.stream.writeAll(slice);
                            }

                            try self.writeSize(usize, slice.len, .list);
                            return self.stream.writeAll(slice);
                        },
                        else => return self.encodeNoList(payload),
                    }
                },
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        if (payload.len == 0)
                            return self.stream.writeByte(0xc0);

                        var arr = std.ArrayList(u8).init(allocator);
                        errdefer arr.deinit();

                        var recursive: RlpEncoder(ArrayListWriter) = .init(arr.writer());

                        inline for (payload) |item| {
                            try recursive.encodeList(allocator, item);
                        }

                        const slice = try arr.toOwnedSlice();
                        defer allocator.free(slice);

                        if (slice.len > std.math.maxInt(u64))
                            return error.Overflow;

                        if (slice.len < 56) {
                            try self.stream.writeByte(@intCast(0xc0 + slice.len));
                            return self.stream.writeAll(slice);
                        }

                        try self.writeSize(usize, slice.len, .list);
                        return self.stream.writeAll(slice);
                    }

                    inline for (struct_info.fields) |field| {
                        try self.encodeList(allocator, @field(payload, field.name));
                    }
                },
                else => return self.encodeNoList(payload),
            }
        }
        /// Performs RLP encoding on a "string" type.
        ///
        /// For more information please check the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
        pub fn encodeString(self: *Self, slice: []const u8) Error!void {
            if (slice.len == 0)
                return self.stream.writeByte(0x80);

            if (slice.len < 56) {
                try self.stream.writeByte(@intCast(0x80 + slice.len));

                return self.stream.writeAll(slice);
            }

            if (slice.len > std.math.maxInt(u64))
                return error.Overflow;

            try self.writeSize(usize, slice.len, .string);

            return self.stream.writeAll(slice);
        }
        /// Finds the bit size of the passed number and writes it to the stream.
        ///
        /// Example:
        /// ```zig
        /// const slice = "dog";
        ///
        /// try rlp_encoder.writeSize(usize, slice.len, .number);
        /// // Encodes as 0x80 + slice.len
        ///
        /// try rlp_encoder.writeSize(usize, slice.len, .string);
        /// // Encodes as 0xb7 + slice.len
        ///
        /// try rlp_encoder.writeSize(usize, slice.len, .list);
        /// // Encodes as 0xf7 + slice.len
        /// ```
        pub fn writeSize(self: *Self, comptime T: type, number: T, tag: RlpSizeTag) Error!void {
            if (@typeInfo(T) != .int)
                @compileError("This method only support integers");

            const base = std.math.log2(number);
            const upper = (std.math.shl(T, 1, base)) - 1;
            const magnitude_bits = if (upper >= number) base else base + 1;

            const size = std.math.divCeil(T, magnitude_bits, 8) catch return error.Overflow;

            try self.stream.writeByte(@intFromEnum(tag) + @as(u8, @truncate(size)));

            const buffer_size = @divExact(@typeInfo(T).int.bits, 8);
            var buffer: [buffer_size]u8 = undefined;

            std.mem.writeInt(T, &buffer, number, .big);

            return self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
        }
        /// RLP encoding writer interface.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

/// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
///
/// Supported types:
///   * `bool`
///   * `int`
///   * `enum`, `enum_literal`
///   * `error_set`,
///   * `null`
///   * `?T`
///   * `[N]T` array types.
///   * `[]const T` slices.
///   * `*T` pointer types.
///   * `structs`. Both tuple and non tuples.
///
/// All other types are currently not supported.
///
/// **Example**
/// ```zig
/// const encoded = try encodeRlp(allocator, 69420);
/// defer allocator.free(encoded);
/// ```
pub fn encodeRlp(allocator: Allocator, payload: anytype) RlpEncoder(ArrayListWriter).Error![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var encoder: RlpEncoder(ArrayListWriter) = .init(list.writer());
    try encoder.encodeList(allocator, payload);

    return list.toOwnedSlice();
}
/// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
///
/// Supported types:
///   * `bool`
///   * `int`
///   * `enum`, `enum_literal`
///   * `error_set`,
///   * `null`
///   * `?T`
///   * `[N]T` array types.
///   * `[]const T` slices.
///   * `*T` pointer types.
///   * `structs`. Both tuple and non tuples.
///
/// All other types are currently not supported.
///
/// **Example**
/// ```zig
/// var list = std.ArrayList(u8).init(allocator);
/// errdefer list.deinit();
///
/// try encodeRlpFromArrayListWriter(allocator, 69420, list);
/// const encoded = try list.toOwnedSlice();
/// ```
pub fn encodeRlpFromArrayListWriter(allocator: Allocator, payload: anytype, list: ArrayListWriter) RlpEncoder(ArrayListWriter).Error!void {
    var encoder: RlpEncoder(ArrayListWriter) = .init(list);
    try encoder.encodeList(allocator, payload);
}
