const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

// Types
const Allocator = std.mem.Allocator;
const ByteAlignedInt = std.math.ByteAlignedInt;
const ArrayListWriter = std.ArrayList(u8).Writer;

/// Set of errors while performing rlp encoding.
pub const RlpEncodeErrors = error{ NegativeNumber, Overflow } || Allocator.Error;

// pub fn encodeRlp(allocator: Allocator, payload: anytype) RlpEncodeErrors![]u8 {
//     _ = allocator;
//     _ = payload;
// }

pub fn RlpEncoder(comptime OutWriter: type) type {
    return struct {
        stream: OutWriter,

        const Self = @This();
        pub const Error = OutWriter.Error || error{ Overflow, NegativeNumber };

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

                    const base = std.math.log2(payload);
                    const upper = (std.math.shl(@TypeOf(payload), 1, base)) - 1;
                    const magnitude_bits = if (upper >= payload) base else base + 1;

                    const size = std.math.divCeil(@TypeOf(payload), magnitude_bits, 8) catch return error.Overflow;

                    try self.stream.writeByte(0x80 + @as(u8, @truncate(size)));

                    const buffer_size = @divExact(@typeInfo(ByteAlignedInt(@TypeOf(payload))).int.bits, 8);
                    var buffer: [buffer_size]u8 = undefined;

                    std.mem.writeInt(ByteAlignedInt(@TypeOf(payload)), &buffer, @intCast(payload), .big);

                    return self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
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
                else => @compileError("Unable to encode type '" ++ @typeName(@TypeOf(payload)) ++ "'"),
            }
        }

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

                    var recursive: RlpEncoder(ArrayListWriter) = .{
                        .stream = arr.writer(),
                    };

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

                    const base = std.math.log2(slice.len);
                    const upper = (std.math.shl(usize, 1, base)) - 1;
                    const magnitude_bits = if (upper >= slice.len) base else base + 1;

                    const size = std.math.divCeil(usize, magnitude_bits, 8) catch return error.Overflow;

                    try self.stream.writeByte(0xf7 + @as(u8, @truncate(size)));

                    const buffer_size = @divExact(@typeInfo(usize).int.bits, 8);
                    var buffer: [buffer_size]u8 = undefined;

                    std.mem.writeInt(usize, &buffer, slice.len, .big);

                    try self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
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

                            var recursive: RlpEncoder(ArrayListWriter) = .{
                                .stream = arr.writer(),
                            };

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

                            const base = std.math.log2(slice.len);
                            const upper = (std.math.shl(usize, 1, base)) - 1;
                            const magnitude_bits = if (upper >= slice.len) base else base + 1;

                            const size = std.math.divCeil(usize, magnitude_bits, 8) catch return error.Overflow;

                            try self.stream.writeByte(0xf7 + @as(u8, @truncate(size)));

                            const buffer_size = @divExact(@typeInfo(usize).int.bits, 8);
                            var buffer: [buffer_size]u8 = undefined;

                            std.mem.writeInt(usize, &buffer, slice.len, .big);

                            try self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
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

                        var recursive: RlpEncoder(ArrayListWriter) = .{
                            .stream = arr.writer(),
                        };

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

                        const base = std.math.log2(slice.len);
                        const upper = (std.math.shl(usize, 1, base)) - 1;
                        const magnitude_bits = if (upper >= slice.len) base else base + 1;

                        const size = std.math.divCeil(usize, magnitude_bits, 8) catch return error.Overflow;

                        try self.stream.writeByte(0xf7 + @as(u8, @truncate(size)));

                        const buffer_size = @divExact(@typeInfo(usize).int.bits, 8);
                        var buffer: [buffer_size]u8 = undefined;

                        std.mem.writeInt(usize, &buffer, slice.len, .big);

                        try self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
                        return self.stream.writeAll(slice);
                    }

                    inline for (struct_info.fields) |field| {
                        try self.encodeList(allocator, @field(payload, field.name));
                    }
                },
                else => return self.encodeNoList(payload),
            }
        }

        pub fn encodeString(self: *Self, slice: []const u8) Error!void {
            if (slice.len == 0)
                return self.stream.writeByte(0x80);

            if (slice.len < 56) {
                try self.stream.writeByte(@intCast(0x80 + slice.len));

                return self.stream.writeAll(slice);
            }

            if (slice.len > std.math.maxInt(u64))
                return error.Overflow;

            const base = std.math.log2(slice.len);
            const upper = (std.math.shl(usize, 1, base)) - 1;
            const magnitude_bits = if (upper >= slice.len) base else base + 1;

            const size = std.math.divCeil(usize, magnitude_bits, 8) catch return error.Overflow;

            try self.stream.writeByte(0xb7 + @as(u8, @truncate(size)));

            const buffer_size = @divExact(@typeInfo(usize).int.bits, 8);
            var buffer: [buffer_size]u8 = undefined;

            std.mem.writeInt(usize, &buffer, slice.len, .big);

            try self.stream.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);

            return self.stream.writeAll(slice);
        }
    };
}

/// RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
///
/// Reflects on the items and encodes based on it's type.\
/// Supports almost all of zig's type.
///
/// Doesn't support `opaque`, `fn`, `anyframe`, `error_union`, `void`, `null` types.
///
/// **Example**
/// ```zig
/// const encoded = try encodeRlp(allocator, 69420);
/// defer allocator.free(encoded);
/// ```
pub fn encodeRlp(allocator: Allocator, payload: anytype) RlpEncodeErrors![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var encoder: RlpEncoder(ArrayListWriter) = .{
        .stream = list.writer(),
    };

    try encoder.encodeList(allocator, payload);

    // switch (info) {
    //     .bool => if (payload) try writer.writeByte(0x01) else try writer.writeByte(0x80),
    //     .int => |int_info| {
    //         if (int_info.signedness == .signed)
    //             @compileError("Signed integers are not supported for RLP decoding.");
    //
    //         if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
    //             const buffer_size = @divExact(@typeInfo(ByteAlignedInt(@TypeOf(payload))).int.bits, 8);
    //
    //             const base = std.math.log2(payload);
    //             const upper = (std.math.shl(@TypeOf(payload), 1, base)) - 1;
    //             const magnitude_bits = if (upper >= payload) base else base + 1;
    //
    //             const size = std.math.divCeil(@TypeOf(payload), magnitude_bits, 8) catch return error.Overflow;
    //
    //             try writer.writeByte(0x80 + @as(u8, @truncate(size)));
    //
    //             var buffer: [buffer_size]u8 = undefined;
    //             std.mem.writeInt(ByteAlignedInt(@TypeOf(payload)), &buffer, @intCast(payload), .big);
    //
    //             try writer.writeAll(buffer[buffer.len - @as(u8, @truncate(size)) ..]);
    //         }
    //     },
    //     .comptime_int => {
    //         if (payload < 0) return error.NegativeNumber;
    //
    //         if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
    //             const IntType = std.math.IntFittingRange(payload, payload);
    //             return encodeRlp(allocator, @as(IntType, @intCast(payload)));
    //         }
    //     },
    //     .float => |float_info| {
    //         if (payload < 0)
    //             return error.NegativeNumber;
    //
    //         if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
    //             const bits = float_info.bits;
    //             const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = bits } });
    //             const as_int = @as(IntType, @bitCast(payload));
    //             var buffer: [32]u8 = undefined;
    //             const size_slice = utils.formatInt(as_int, &buffer);
    //             try writer.writeByte(0x80 + size_slice);
    //             try writer.writeAll(buffer[32 - size_slice ..]);
    //         }
    //     },
    //     .comptime_float => {
    //         if (payload < 0) return error.NegativeNumber;
    //
    //         if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
    //             if (payload > std.math.maxInt(u256))
    //                 @compileError("Cannot fit " ++ payload ++ " as u256");
    //
    //             const size = comptime utils.computeSize(@intFromFloat(payload));
    //             try writer.writeByte(0x80 + size);
    //             var buffer: [32]u8 = undefined;
    //             const size_slice = utils.formatInt(@intFromFloat(payload), &buffer);
    //             try writer.writeAll(buffer[32 - size_slice ..]);
    //         }
    //     },
    //     .null => try writer.writeByte(0x80),
    //     .optional => {
    //         if (payload) |item| return encodeRlp(allocator, item) else try writer.writeByte(0x80);
    //     },
    //     .@"enum", .enum_literal => return encodeRlp(allocator, @tagName(payload)),
    //     .error_set => return encodeRlp(allocator, @errorName(payload)),
    //     .array => |arr_info| {
    //         if (arr_info.child == u8) {
    //             if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
    //                 try writer.writeByte(@intCast(0x80 + payload.len));
    //                 try writer.writeAll(&payload);
    //             } else {
    //                 if (payload.len > std.math.maxInt(u64))
    //                     return error.Overflow;
    //
    //                 var buffer: [32]u8 = undefined;
    //                 const size = utils.formatInt(payload.len, &buffer);
    //                 try writer.writeByte(0xb7 + size);
    //                 try writer.writeAll(buffer[32 - size ..]);
    //                 try writer.writeAll(&payload);
    //             }
    //         } else {
    //             if (payload.len == 0) try writer.writeByte(0xc0) else {
    //                 var arr = std.ArrayList(u8).init(allocator);
    //                 errdefer arr.deinit();
    //
    //                 const arr_writer = arr.writer();
    //
    //                 for (payload) |item| {
    //                     const slice = try encodeRlp(allocator, item);
    //                     defer allocator.free(slice);
    //
    //                     try arr_writer.writeAll(slice);
    //                 }
    //
    //                 const bytes = try arr.toOwnedSlice();
    //                 defer allocator.free(bytes);
    //
    //                 if (bytes.len > std.math.maxInt(u64))
    //                     return error.Overflow;
    //
    //                 if (bytes.len < 56) {
    //                     try writer.writeByte(@intCast(0xc0 + bytes.len));
    //                     try writer.writeAll(bytes);
    //                 } else {
    //                     var buffer: [32]u8 = undefined;
    //                     const size = utils.formatInt(bytes.len, &buffer);
    //                     try writer.writeByte(0xf7 + size);
    //                     try writer.writeAll(buffer[32 - size ..]);
    //                     try writer.writeAll(bytes);
    //                 }
    //             }
    //         }
    //     },
    //     .pointer => |ptr_info| {
    //         switch (ptr_info.size) {
    //             .One => return encodeRlp(allocator, payload.*),
    //             .Slice, .Many => {
    //                 if (ptr_info.child == u8) {
    //                     if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
    //                         try writer.writeByte(@intCast(0x80 + payload.len));
    //                         try writer.writeAll(payload);
    //                     } else {
    //                         if (payload.len > std.math.maxInt(u64))
    //                             return error.Overflow;
    //
    //                         var buffer: [32]u8 = undefined;
    //                         const size = utils.formatInt(payload.len, &buffer);
    //                         try writer.writeByte(0xb7 + size);
    //                         try writer.writeAll(buffer[32 - size ..]);
    //                         try writer.writeAll(payload);
    //                     }
    //                 } else {
    //                     if (payload.len == 0) try writer.writeByte(0xc0) else {
    //                         var slice = std.ArrayList(u8).init(allocator);
    //                         errdefer slice.deinit();
    //                         const slice_writer = slice.writer();
    //
    //                         for (payload) |item| {
    //                             const encoded = try encodeRlp(allocator, item);
    //                             defer allocator.free(encoded);
    //
    //                             try slice_writer.writeAll(encoded);
    //                         }
    //
    //                         const bytes = try slice.toOwnedSlice();
    //                         defer allocator.free(bytes);
    //
    //                         if (bytes.len > std.math.maxInt(u64))
    //                             return error.Overflow;
    //
    //                         if (bytes.len < 56) {
    //                             try writer.writeByte(@intCast(0xc0 + bytes.len));
    //                             try writer.writeAll(bytes);
    //                         } else {
    //                             var buffer: [32]u8 = undefined;
    //                             const size = utils.formatInt(bytes.len, &buffer);
    //                             try writer.writeByte(0xf7 + size);
    //                             try writer.writeAll(buffer[32 - size ..]);
    //                             try writer.writeAll(bytes);
    //                         }
    //                     }
    //                 }
    //             },
    //             else => @compileError("Unable to parse pointer type " ++ @typeName(@TypeOf(payload))),
    //         }
    //     },
    //     .@"struct" => |struct_info| {
    //         if (struct_info.is_tuple) {
    //             if (payload.len == 0) try writer.writeByte(0xc0) else {
    //                 var tuple = std.ArrayList(u8).init(allocator);
    //                 errdefer tuple.deinit();
    //                 const tuple_writer = tuple.writer();
    //
    //                 inline for (payload) |item| {
    //                     const slice = try encodeRlp(allocator, item);
    //                     defer allocator.free(slice);
    //
    //                     try tuple_writer.writeAll(slice);
    //                 }
    //
    //                 const bytes = try tuple.toOwnedSlice();
    //                 defer allocator.free(bytes);
    //
    //                 if (bytes.len > std.math.maxInt(u64))
    //                     return error.Overflow;
    //
    //                 if (bytes.len < 56) {
    //                     try writer.writeByte(@intCast(0xc0 + bytes.len));
    //                     try writer.writeAll(bytes);
    //                 } else {
    //                     var buffer: [32]u8 = undefined;
    //                     const size = utils.formatInt(bytes.len, &buffer);
    //                     try writer.writeByte(0xf7 + size);
    //                     try writer.writeAll(buffer[32 - size ..]);
    //                     try writer.writeAll(bytes);
    //                 }
    //             }
    //         } else {
    //             inline for (struct_info.fields) |field| {
    //                 const slice = try encodeRlp(allocator, @field(payload, field.name));
    //                 defer allocator.free(slice);
    //
    //                 try writer.writeAll(slice);
    //             }
    //         }
    //     },
    //     .@"union" => |union_info| {
    //         if (union_info.tag_type) |TagType| {
    //             inline for (union_info.fields) |u_field| {
    //                 if (payload == @field(TagType, u_field.name)) {
    //                     if (u_field.type == void) {
    //                         const slice = try encodeRlp(allocator, u_field.name);
    //                         defer allocator.free(slice);
    //
    //                         try writer.writeAll(slice);
    //                     } else {
    //                         const slice = try encodeRlp(allocator, @field(payload, u_field.name));
    //                         defer allocator.free(slice);
    //
    //                         try writer.writeAll(slice);
    //                     }
    //                 }
    //             }
    //         } else {
    //             const slice = try encodeRlp(allocator, @tagName(payload));
    //             defer allocator.free(slice);
    //
    //             try writer.writeAll(slice);
    //         }
    //     },
    //     .vector => |vec_info| {
    //         if (vec_info.len == 0) try writer.writeByte(0xc0) else {
    //             var slice = std.ArrayList(u8).init(allocator);
    //             errdefer slice.deinit();
    //             const slice_writer = slice.writer();
    //
    //             for (0..vec_info.len) |i| {
    //                 const encoded = try encodeRlp(allocator, payload[i]);
    //                 defer allocator.free(encoded);
    //
    //                 try slice_writer.writeAll(encoded);
    //             }
    //
    //             const bytes = try slice.toOwnedSlice();
    //             defer allocator.free(bytes);
    //
    //             if (bytes.len > std.math.maxInt(u64))
    //                 return error.Overflow;
    //
    //             if (bytes.len < 56) {
    //                 try writer.writeByte(@intCast(0xc0 + bytes.len));
    //                 try writer.writeAll(bytes);
    //             } else {
    //                 var buffer: [32]u8 = undefined;
    //                 const size = utils.formatInt(bytes.len, &buffer);
    //                 try writer.writeByte(0xf7 + size);
    //                 try writer.writeAll(buffer[32 - size ..]);
    //                 try writer.writeAll(bytes);
    //             }
    //         }
    //     },
    //
    //     else => @compileError("Unable to parse type " ++ @typeName(@TypeOf(payload))),
    // }

    return list.toOwnedSlice();
}
