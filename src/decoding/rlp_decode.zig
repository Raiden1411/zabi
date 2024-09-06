const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const Allocator = std.mem.Allocator;
const encodeRlp = @import("../encoding/rlp.zig").encodeRlp;

/// Set of errors while performing RLP decoding.
pub const RlpDecodeErrors = error{ UnexpectedValue, InvalidEnumTag, LengthMissmatch } || Allocator.Error || std.fmt.ParseIntError;

/// RLP decoding. Encoded string must follow the RLP specs.
pub fn decodeRlp(allocator: Allocator, comptime T: type, encoded: []const u8) RlpDecodeErrors!T {
    const decoded = try decodeItem(allocator, T, encoded, 0);

    return decoded.data;
}

fn DecodedResult(comptime T: type) type {
    return struct { consumed: usize, data: T };
}

fn decodeItem(allocator: Allocator, comptime T: type, encoded: []const u8, position: usize) RlpDecodeErrors!DecodedResult(T) {
    const info = @typeInfo(T);

    std.debug.assert(encoded.len > 0); // Cannot decode 0 length;

    if (position > encoded.len - 1)
        return error.Overflow;

    switch (info) {
        .bool => {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,
            switch (encoded[position]) {
                0x80 => return .{ .consumed = 1, .data = false },
                0x01 => return .{ .consumed = 1, .data = true },
                else => return error.UnexpectedValue,
            }
        },
        .int => {
            if (info.int.signedness == .signed)
                @compileError("Signed integers are not supported for RLP decoding");

            std.debug.assert(position < encoded.len); // Overflow on encoded string,

            if (encoded[position] < 0x80) return .{ .consumed = 1, .data = @intCast(encoded[position]) };
            const len = encoded[position] - 0x80;
            const hex_number = encoded[position + 1 .. position + len + 1];

            const hexed = std.fmt.fmtSliceHexLower(hex_number);

            const slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
            defer allocator.free(slice);

            return .{ .consumed = len + 1, .data = if (slice.len != 0) try std.fmt.parseInt(T, slice, 16) else @intCast(0) };
        },
        .float => {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,

            if (encoded[position] < 0x80) return .{ .consumed = 1, .data = @as(T, @floatFromInt(encoded[position])) };
            const len = encoded[position] - 0x80;
            const hex_number = encoded[position + 1 .. position + len + 1];

            const hexed = std.fmt.fmtSliceHexLower(hex_number);

            const slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
            defer allocator.free(slice);

            const bits = info.float.bits;
            const AsInt = @Type(.{ .int = .{ .signedness = .unsigned, .bits = bits } });
            const parsed = try std.fmt.parseInt(AsInt, slice, 16);
            return .{ .consumed = len + 1, .data = if (slice.len != 0) @as(T, @floatFromInt(parsed)) else @floatCast(0) };
        },
        .null => {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,
            return if (encoded[position] != 0x80) error.UnexpectedValue else .{ .consumed = 1, .data = null };
        },
        .optional => |opt_info| {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,
            //
            if (encoded[position] == 0x80) return .{ .consumed = 1, .data = null };

            const opt = try decodeItem(allocator, opt_info.child, encoded, position);
            return .{ .consumed = opt.consumed, .data = opt.data };
        },
        .@"enum", .enum_literal => {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,

            const size = encoded[position];

            if (size <= 0xb7) {
                const str_len = size - 0x80;
                std.debug.assert(position + str_len < encoded.len); // Overflow on encoded string,

                const slice = encoded[position + 1 .. position + str_len + 1];
                const e = std.meta.stringToEnum(T, slice) orelse return error.InvalidEnumTag;

                return .{ .consumed = str_len + 1, .data = e };
            }
            const len_size = size - 0xb7;
            std.debug.assert(position + len_size < encoded.len); // Overflow on encoded string,

            const len = encoded[position + 1 .. position + len_size + 1];

            const hexed = std.fmt.fmtSliceHexLower(len);

            const len_slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
            defer allocator.free(len_slice);

            const parsed = try std.fmt.parseInt(usize, len_slice, 16);
            std.debug.assert(position + len_size + parsed < encoded.len); // Overflow on encoded string,

            const e = std.meta.stringToEnum(T, encoded[position + len_size + 1 .. position + parsed + 1 + len_size]) orelse return error.InvalidEnumTag;

            return .{ .consumed = 2 + len_size + parsed, .data = e };
        },
        .array => |arr_info| {
            std.debug.assert(position < encoded.len); // Overflow on encoded string,

            if (arr_info.child == u8) {
                const size = encoded[position];
                if (size <= 0xb7) {
                    const str_len = size - 0x80;
                    std.debug.assert(position + str_len < encoded.len); // Overflow on encoded string,

                    const slice = encoded[position + 1 .. position + str_len + 1];

                    if (slice.len != arr_info.len)
                        return error.LengthMissmatch;

                    var result: T = undefined;
                    @memcpy(result[0..], slice[0..arr_info.len]);

                    return .{ .consumed = str_len + 1, .data = result };
                }
                const len_size = size - 0xb7;
                const len = encoded[position + 1 .. position + len_size + 1];
                std.debug.assert(position + len_size < encoded.len); // Overflow on encoded string,

                const hexed = std.fmt.fmtSliceHexLower(len);
                const len_slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
                defer allocator.free(len_slice);

                const parsed = try std.fmt.parseInt(usize, len_slice, 16);

                std.debug.assert(position + len_size + parsed < encoded.len); // Overflow on encoded string,
                const slice = encoded[position + 1 + len_size .. position + parsed + 1 + len_size];

                if (slice.len != arr_info.len)
                    return error.LengthMissmatch;

                var result: T = undefined;
                @memcpy(result[0..], slice[0..arr_info.len]);

                return .{ .consumed = 2 + len_size + parsed, .data = result };
            }

            const arr_size = encoded[position];

            if (arr_size <= 0xf7) {
                var result: T = undefined;

                var cur_pos = position + 1;
                for (0..arr_info.len) |i| {
                    const decoded = try decodeItem(allocator, arr_info.child, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = arr_info.len + 1, .data = result };
            }

            const arr_len = arr_size - 0xf7;
            var result: T = undefined;

            var cur_pos = position + arr_len + 1;
            for (0..arr_info.len) |i| {
                const decoded = try decodeItem(allocator, arr_info.child, encoded[cur_pos..], 0);
                result[i] = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = arr_info.len + 1, .data = result };
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const res: *ptr_info.child = try allocator.create(ptr_info.child);
                    const decoded = try decodeItem(allocator, ptr_info.child, encoded, position);
                    res.* = decoded.data;

                    return .{ .consumed = decoded.consumed, .data = res };
                },
                .Slice => {
                    std.debug.assert(position < encoded.len); // Overflow on encoded string,

                    if (ptr_info.child == u8) {
                        const size = encoded[position];

                        if (size <= 0xb7) {
                            const str_len = size - 0x80;
                            const slice = encoded[position + 1 .. position + str_len + 1];

                            if (ptr_info.is_const) return .{ .consumed = str_len + 1, .data = slice };
                            return .{ .consumed = str_len + 1, .data = @constCast(slice) };
                        }

                        const len_size = size - 0xb7;
                        const len = encoded[position + 1 .. position + len_size + 1];
                        std.debug.assert(position + len_size < encoded.len); // Overflow on encoded string,

                        const hexed = std.fmt.fmtSliceHexLower(len);
                        const len_slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
                        defer allocator.free(len_slice);

                        const parsed = try std.fmt.parseInt(usize, len_slice, 16);
                        std.debug.assert(position + len_size + parsed < encoded.len); // Overflow on encoded string,

                        if (ptr_info.is_const)
                            return .{ .consumed = 2 + len_size + parsed, .data = encoded[position + 1 + len_size .. position + parsed + 1 + len_size] };

                        return .{ .consumed = 2 + len_size + parsed, .data = @constCast(encoded[position + 1 + len_size .. position + parsed + 1 + len_size]) };
                    }
                    const arr_size = encoded[position];

                    if (arr_size <= 0xf7) {
                        const arr_len = arr_size - 0xC0;
                        var result = std.ArrayList(ptr_info.child).init(allocator);
                        errdefer result.deinit();

                        var read: usize = 0;
                        while (true) {
                            if (read >= arr_len)
                                break;

                            const decoded = try decodeItem(allocator, ptr_info.child, encoded[read + position + 1 ..], 0);
                            try result.append(decoded.data);
                            read += decoded.consumed;
                        }

                        std.debug.assert(read == arr_len);

                        return .{ .consumed = arr_len + 1, .data = try result.toOwnedSlice() };
                    }

                    const arr_len = arr_size - 0xf7;
                    const len = encoded[position + 1 .. position + arr_len + 1];
                    std.debug.assert(position + arr_len < encoded.len); // Overflow on encoded string,

                    const hexed = std.fmt.fmtSliceHexLower(len);

                    const len_slice = try std.fmt.allocPrint(allocator, "{s}", .{hexed});
                    defer allocator.free(len_slice);

                    const parsed_len = try std.fmt.parseInt(usize, len_slice, 16);
                    var result = std.ArrayList(ptr_info.child).init(allocator);
                    errdefer result.deinit();

                    var cur_pos = position + arr_len + 1;
                    for (0..parsed_len) |_| {
                        if (cur_pos >= encoded.len) break;
                        const decoded = try decodeItem(allocator, ptr_info.child, encoded[cur_pos..], 0);
                        try result.append(decoded.data);
                        cur_pos += decoded.consumed;
                    }

                    return .{ .consumed = cur_pos, .data = try result.toOwnedSlice() };
                },
                else => @compileError("Unable to parse pointer type " ++ @typeName(T)),
            }
        },
        .vector => |vec_info| {
            const arr_size = encoded[position];

            if (arr_size <= 0xf7) {
                var result: T = undefined;

                var cur_pos = position + 1;
                for (0..vec_info.len) |i| {
                    const decoded = try decodeItem(allocator, vec_info.child, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = vec_info.len + 1, .data = result };
            }

            const arr_len = arr_size - 0xf7;
            var result: T = undefined;

            var cur_pos = position + arr_len + 1;
            for (0..vec_info.len) |i| {
                const decoded = try decodeItem(allocator, vec_info.child, encoded[cur_pos..], 0);
                result[i] = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = vec_info.len + 1, .data = result };
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                const arr_size = encoded[position];
                if (arr_size <= 0xf7) {
                    var result: T = undefined;

                    var cur_pos = position + 1;
                    inline for (struct_info.fields, 0..) |field, i| {
                        const decoded = try decodeItem(allocator, field.type, encoded, cur_pos);
                        result[i] = decoded.data;
                        cur_pos += decoded.consumed;
                    }

                    return .{ .consumed = cur_pos, .data = result };
                }

                const arr_len = arr_size - 0xf7;
                var result: T = undefined;

                var cur_pos = position + arr_len + 1;
                inline for (struct_info.fields, 0..) |field, i| {
                    const decoded = try decodeItem(allocator, field.type, encoded, cur_pos);
                    result[i] = decoded.data;
                    cur_pos += decoded.consumed;
                }

                return .{ .consumed = cur_pos, .data = result };
            }

            var result: T = undefined;

            var cur_pos = position;
            inline for (struct_info.fields) |field| {
                const decoded = try decodeItem(allocator, field.type, encoded, cur_pos);
                @field(result, field.name) = decoded.data;
                cur_pos += decoded.consumed;
            }

            return .{ .consumed = cur_pos, .data = result };
        },
        else => @compileError("Unable to parse type " ++ @typeName(T)),
    }
}
