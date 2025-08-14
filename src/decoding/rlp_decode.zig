const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

// Types
const Allocator = std.mem.Allocator;

/// Set of errors while performing RLP decoding.
pub const RlpDecodeErrors = error{ UnexpectedValue, InvalidEnumTag, LengthMissmatch, Overflow } || Allocator.Error;

/// RLP decoding wrapper function. Encoded string must follow the RLP specification.
///
/// Supported types:
///   * `bool`
///   * `int`
///   * `enum`, `enum_literal`
///   * `null`
///   * `?T`
///   * `[N]T` array types.
///   * `[]const T` slices.
///   * `structs`. Both tuple and non tuples.
///
/// All other types are currently not supported.
pub fn decodeRlp(comptime T: type, allocator: Allocator, encoded: []const u8) RlpDecodeErrors!T {
    var decoder = RlpDecoder.init(encoded);

    return decoder.decode(T, allocator);
}

/// RLP Decoder structure. Decodes based on the RLP specification.
pub const RlpDecoder = struct {
    /// The RLP encoded slice.
    encoded: []const u8,
    /// The position into the encoded slice.
    position: usize,

    /// Sets the decoder initial state.
    pub fn init(encoded: []const u8) RlpDecoder {
        std.debug.assert(encoded.len > 0); // Invalid encoded slice len.

        return .{
            .encoded = encoded,
            .position = 0,
        };
    }
    /// Advances the decoder position by `new` size.
    pub fn advancePosition(self: *RlpDecoder, new: usize) void {
        self.position += new;
    }
    /// Decodes a rlp encoded slice into a provided type.
    /// The encoded slice must follow the RLP specification.
    ///
    /// Supported types:
    ///   * `bool`
    ///   * `int`
    ///   * `enum`, `enum_literal`
    ///   * `null`
    ///   * `?T`
    ///   * `[N]T` array types.
    ///   * `[]const T` slices.
    ///   * `structs`. Both tuple and non tuples.
    ///
    /// All other types are currently not supported.
    pub fn decode(self: *RlpDecoder, comptime T: type, allocator: Allocator) RlpDecodeErrors!T {
        const info = @typeInfo(T);

        switch (info) {
            .bool => {
                const byte = self.encoded[self.position];
                self.advancePosition(1);

                switch (byte) {
                    0x80 => return false,
                    0x01 => return true,
                    else => return error.UnexpectedValue,
                }
            },
            .int => |int_info| {
                if (int_info.signedness == .signed)
                    @compileError("Signed integers are not supported for RLP decoding");

                std.debug.assert(self.position < self.encoded.len);

                const bit = self.encoded[self.position];
                self.advancePosition(1);

                if (bit < 0x80)
                    return if (int_info.bits < 8) @truncate(bit) else @intCast(bit);

                const int_size = bit - 0x80;

                std.debug.assert(self.position + int_size <= self.encoded.len);

                const number = self.encoded[self.position .. self.position + int_size];
                self.advancePosition(number.len);

                return utils.bytesToInt(T, number);
            },
            .null => {
                std.debug.assert(self.position < self.encoded.len);

                return if (self.encoded[self.position] != 0x80) error.UnexpectedValue else null;
            },
            .optional => |opt_info| {
                std.debug.assert(self.position < self.encoded.len);

                if (self.encoded[self.position] == 0x80) {
                    self.advancePosition(1);
                    return null;
                }

                const decoded = try self.decode(opt_info.child, allocator);

                return @as(T, decoded);
            },
            .@"enum", .enum_literal => {
                const tag_name = try self.decodeString();

                return std.meta.stringToEnum(T, tag_name) orelse error.InvalidEnumTag;
            },
            .array => |arr_info| {
                std.debug.assert(self.position < self.encoded.len);

                if (arr_info.child == u8) {
                    const slice = try self.decodeString();

                    if (slice.len != arr_info.len)
                        return error.LengthMissmatch;

                    return slice[0..arr_info.len].*;
                }

                var result: T = undefined;
                const size = self.encoded[self.position];
                self.advancePosition(1);

                if (size <= 0xf7) {
                    for (0..arr_info.len) |i| {
                        result[i] = try self.decode(arr_info.child, allocator);
                    }

                    return result;
                }

                const len = size - 0xf7;
                self.advancePosition(len);

                for (0..arr_info.len) |i| {
                    result[i] = try self.decode(arr_info.child, allocator);
                }

                return result;
            },
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .one => {
                        const result = try allocator.create(ptr_info.child);
                        errdefer allocator.destroy(result);

                        result.* = try self.decode(ptr_info.child, allocator);

                        return result;
                    },
                    .slice => {
                        std.debug.assert(self.position < self.encoded.len);

                        if (ptr_info.child == u8) {
                            const slice = try self.decodeString();

                            if (ptr_info.is_const)
                                return slice;

                            return @constCast(slice);
                        }

                        const size = self.encoded[self.position];
                        self.advancePosition(1);

                        if (size <= 0xf7) {
                            const slice_len = size - 0xc0;

                            var result = std.array_list.Managed(ptr_info.child).init(allocator);
                            errdefer result.deinit();

                            const expected_position = self.position + slice_len;

                            while (true) {
                                if (self.position >= expected_position)
                                    break;

                                const decoded = try self.decode(ptr_info.child, allocator);
                                try result.append(decoded);
                            }

                            std.debug.assert(self.position == expected_position);

                            return result.toOwnedSlice();
                        }

                        const slice_len = size - 0xf7;

                        var result = std.array_list.Managed(ptr_info.child).init(allocator);
                        errdefer result.deinit();

                        std.debug.assert(self.position + slice_len <= self.encoded.len);
                        const len = self.encoded[self.position .. self.position + slice_len];
                        const number = try utils.bytesToInt(usize, len);

                        self.advancePosition(slice_len);
                        const expected_position = self.position + number;

                        while (true) {
                            if (self.position >= expected_position)
                                break;

                            const decoded = try self.decode(ptr_info.child, allocator);
                            try result.append(decoded);
                        }

                        std.debug.assert(self.position == expected_position);

                        return result.toOwnedSlice();
                    },
                    else => @compileError("Unable to decode to pointer type '" ++ @typeName(T) ++ "'"),
                }
            },
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    const size = self.encoded[self.position];
                    self.advancePosition(1);

                    if (size <= 0xf7) {
                        var result: T = undefined;

                        inline for (struct_info.fields) |field| {
                            @field(result, field.name) = try self.decode(field.type, allocator);
                        }

                        return result;
                    }

                    const len = size - 0xf7;
                    self.advancePosition(len);

                    var result: T = undefined;

                    inline for (struct_info.fields, 0..) |field, i| {
                        result[i] = try self.decode(field.type, allocator);
                    }

                    return result;
                }

                var result: T = undefined;

                inline for (struct_info.fields) |field| {
                    @field(result, field.name) = try self.decode(field.type, allocator);
                }

                return result;
            },
            else => @compileError("Unable to decode to type '" ++ @typeName(T) ++ "'"),
        }
    }
    /// Decodes directly to a `[]const u8` slice from the expected RLP specification.
    fn decodeString(self: *RlpDecoder) RlpDecodeErrors![]const u8 {
        std.debug.assert(self.position < self.encoded.len);

        const size = self.encoded[self.position];

        if (size <= 0xb7) {
            const len = size - 0x80;

            std.debug.assert(self.position + len <= self.encoded.len);
            self.advancePosition(1);

            const slice = self.encoded[self.position .. self.position + len];
            self.advancePosition(slice.len);

            return slice;
        }

        const len = size - 0xb7;

        std.debug.assert(self.position + len < self.encoded.len);
        self.advancePosition(1);

        const slice_len = self.encoded[self.position .. self.position + len];
        self.advancePosition(slice_len.len);

        const number = try utils.bytesToInt(usize, slice_len);
        std.debug.assert(self.position + number <= self.encoded.len);

        const slice = self.encoded[self.position .. self.position + number];
        self.advancePosition(number);

        return slice;
    }
};
