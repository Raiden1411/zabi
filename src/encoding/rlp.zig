const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const Allocator = std.mem.Allocator;

pub const RlpEncodeErrors = error{ NegativeNumber, Overflow } || Allocator.Error;

/// RLP Encoding. Items is expected to be a tuple of values.
/// Compilation will fail if you pass in any other type.
/// Caller owns the memory so it must be freed.
pub fn encodeRlp(alloc: Allocator, items: anytype) ![]u8 {
    const info = @typeInfo(@TypeOf(items));

    if (info != .@"struct") @compileError("Expected tuple type instead found " ++ @typeName(@TypeOf(items)));
    if (!info.@"struct".is_tuple) @compileError("Expected tuple type instead found " ++ @typeName(@TypeOf(items)));

    var list = std.ArrayList(u8).init(alloc);
    var writer = list.writer();

    inline for (items) |payload| {
        try encodeItem(alloc, payload, &writer);
    }

    return list.toOwnedSlice();
}
/// Reflects on the items and encodes based on it's type.
fn encodeItem(alloc: Allocator, payload: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(payload));

    switch (info) {
        .bool => if (payload) try writer.writeByte(0x01) else try writer.writeByte(0x80),
        .int => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                var buffer: [32]u8 = undefined;
                const size_slice = utils.formatInt(@intCast(payload), &buffer);
                try writer.writeByte(0x80 + size_slice);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .comptime_int => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intCast(payload)) else {
                const IntType = std.math.IntFittingRange(payload, payload);
                return try encodeItem(alloc, @as(IntType, @intCast(payload)), writer);
            }
        },
        .float => |float_info| {
            if (payload < 0)
                return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
                const bits = float_info.bits;
                const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = bits } });
                const as_int = @as(IntType, @bitCast(payload));
                var buffer: [32]u8 = undefined;
                const size_slice = utils.formatInt(as_int, &buffer);
                try writer.writeByte(0x80 + size_slice);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .comptime_float => {
            if (payload < 0) return error.NegativeNumber;

            if (payload == 0) try writer.writeByte(0x80) else if (payload < 0x80) try writer.writeByte(@intFromFloat(payload)) else {
                if (payload > std.math.maxInt(u256))
                    @compileError("Cannot fit " ++ payload ++ " as u256");

                const size = comptime utils.computeSize(@intFromFloat(payload));
                try writer.writeByte(0x80 + size);
                var buffer: [32]u8 = undefined;
                const size_slice = utils.formatInt(@intFromFloat(payload), &buffer);
                try writer.writeAll(buffer[32 - size_slice ..]);
            }
        },
        .null => try writer.writeByte(0x80),
        .optional => {
            if (payload) |item| try encodeItem(alloc, item, writer) else try writer.writeByte(0x80);
        },
        .@"enum", .enum_literal => try encodeItem(alloc, @tagName(payload), writer),
        .error_set => try encodeItem(alloc, @errorName(payload), writer),
        .array => |arr_info| {
            if (arr_info.child == u8) {
                if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
                    try writer.writeByte(@intCast(0x80 + payload.len));
                    try writer.writeAll(&payload);
                } else {
                    if (payload.len > std.math.maxInt(u64))
                        return error.Overflow;

                    var buffer: [32]u8 = undefined;
                    const size = utils.formatInt(payload.len, &buffer);
                    try writer.writeByte(0xb7 + size);
                    try writer.writeAll(buffer[32 - size ..]);
                    try writer.writeAll(&payload);
                }
            } else {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    var arr = std.ArrayList(u8).init(alloc);
                    errdefer arr.deinit();
                    const arr_writer = arr.writer();

                    for (payload) |item| {
                        try encodeItem(alloc, item, &arr_writer);
                    }

                    const bytes = try arr.toOwnedSlice();
                    defer alloc.free(bytes);

                    if (bytes.len > std.math.maxInt(u64))
                        return error.Overflow;

                    if (bytes.len < 56) {
                        try writer.writeByte(@intCast(0xc0 + bytes.len));
                        try writer.writeAll(bytes);
                    } else {
                        var buffer: [32]u8 = undefined;
                        const size = utils.formatInt(bytes.len, &buffer);
                        try writer.writeByte(0xf7 + size);
                        try writer.writeAll(buffer[32 - size ..]);
                        try writer.writeAll(bytes);
                    }
                }
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    try encodeItem(alloc, payload.*, writer);
                },
                .Slice, .Many => {
                    if (ptr_info.child == u8) {
                        if (payload.len == 0) try writer.writeByte(0x80) else if (payload.len < 56) {
                            try writer.writeByte(@intCast(0x80 + payload.len));
                            try writer.writeAll(payload);
                        } else {
                            if (payload.len > std.math.maxInt(u64))
                                return error.Overflow;

                            var buffer: [32]u8 = undefined;
                            const size = utils.formatInt(payload.len, &buffer);
                            try writer.writeByte(0xb7 + size);
                            try writer.writeAll(buffer[32 - size ..]);
                            try writer.writeAll(payload);
                        }
                    } else {
                        if (payload.len == 0) try writer.writeByte(0xc0) else {
                            var slice = std.ArrayList(u8).init(alloc);
                            errdefer slice.deinit();
                            const slice_writer = slice.writer();

                            for (payload) |item| {
                                try encodeItem(alloc, item, &slice_writer);
                            }

                            const bytes = try slice.toOwnedSlice();
                            defer alloc.free(bytes);

                            if (bytes.len > std.math.maxInt(u64))
                                return error.Overflow;

                            if (bytes.len < 56) {
                                try writer.writeByte(@intCast(0xc0 + bytes.len));
                                try writer.writeAll(bytes);
                            } else {
                                var buffer: [32]u8 = undefined;
                                const size = utils.formatInt(bytes.len, &buffer);
                                try writer.writeByte(0xf7 + size);
                                try writer.writeAll(buffer[32 - size ..]);
                                try writer.writeAll(bytes);
                            }
                        }
                    }
                },
                else => @compileError("Unable to parse pointer type " ++ @typeName(@TypeOf(payload))),
            }
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                if (payload.len == 0) try writer.writeByte(0xc0) else {
                    var tuple = std.ArrayList(u8).init(alloc);
                    errdefer tuple.deinit();
                    const tuple_writer = tuple.writer();

                    inline for (payload) |item| {
                        try encodeItem(alloc, item, &tuple_writer);
                    }

                    const bytes = try tuple.toOwnedSlice();
                    defer alloc.free(bytes);

                    if (bytes.len > std.math.maxInt(u64))
                        return error.Overflow;

                    if (bytes.len < 56) {
                        try writer.writeByte(@intCast(0xc0 + bytes.len));
                        try writer.writeAll(bytes);
                    } else {
                        var buffer: [32]u8 = undefined;
                        const size = utils.formatInt(bytes.len, &buffer);
                        try writer.writeByte(0xf7 + size);
                        try writer.writeAll(buffer[32 - size ..]);
                        try writer.writeAll(bytes);
                    }
                }
            } else {
                inline for (struct_info.fields) |field| {
                    try encodeItem(alloc, @field(payload, field.name), writer);
                }
            }
        },
        .@"union" => |union_info| {
            if (union_info.tag_type) |TagType| {
                inline for (union_info.fields) |u_field| {
                    if (payload == @field(TagType, u_field.name)) {
                        if (u_field.type == void) {
                            try encodeItem(alloc, u_field.name, writer);
                        } else try encodeItem(alloc, @field(payload, u_field.name), writer);
                    }
                }
            } else try encodeItem(alloc, @tagName(payload), writer);
        },
        .vector => |vec_info| {
            if (vec_info.len == 0) try writer.writeByte(0xc0) else {
                var slice = std.ArrayList(u8).init(alloc);
                errdefer slice.deinit();
                const slice_writer = slice.writer();

                for (0..vec_info.len) |i| {
                    try encodeItem(alloc, payload[i], &slice_writer);
                }

                const bytes = try slice.toOwnedSlice();
                defer alloc.free(bytes);

                if (bytes.len > std.math.maxInt(u64))
                    return error.Overflow;

                if (bytes.len < 56) {
                    try writer.writeByte(@intCast(0xc0 + bytes.len));
                    try writer.writeAll(bytes);
                } else {
                    var buffer: [32]u8 = undefined;
                    const size = utils.formatInt(bytes.len, &buffer);
                    try writer.writeByte(0xf7 + size);
                    try writer.writeAll(buffer[32 - size ..]);
                    try writer.writeAll(bytes);
                }
            }
        },

        else => @compileError("Unable to parse type " ++ @typeName(@TypeOf(payload))),
    }
}
