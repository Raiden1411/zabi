const abi = zabi_abi.abitypes;
const abi_parameter = zabi_abi.abi_parameter;
const human = @import("zabi-human").parsing;
const meta = @import("zabi-meta").abi;
const std = @import("std");
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;
const zabi_abi = @import("zabi-abi");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiEventParametersDataToPrimative = meta.AbiEventParametersDataToPrimative;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Set of errors while performing logs abi encoding.
pub const EncodeLogsErrors = Allocator.Error || error{
    SignedNumber,
    UnsignedNumber,
    InvalidParamType,
    InvalidAddressType,
    InvalidFixedBytesType,
    CannotEncodeSliceOfDynamicTypes,
    ExpectedComponents,
};

/// Encode event log topics were the abi event is comptime know.
///
/// `values` is expected to be a tuple of the values to encode.
/// Array and tuples are encoded as the hash representing their values.
///
/// Example:
///
/// const event = .{
///     .type = .event,
///     .inputs = &.{},
///     .name = "Transfer"
/// }
///
/// const encoded = encodeLogTopicsComptime(testing.allocator, event, .{});
///
/// Result: &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}
pub fn encodeLogTopicsComptime(allocator: Allocator, comptime event: AbiEvent, values: AbiEventParametersDataToPrimative(event.inputs)) ![]const ?Hash {
    var list = try std.ArrayList(?Hash).initCapacity(allocator, values.len + 1);
    errdefer list.deinit();

    const hash = try event.encode(allocator);

    try list.append(hash);

    if (values.len > 0) {
        inline for (values, 0..) |value, i| {
            const param = event.inputs[i];

            if (param.indexed) {
                const encoded = try encodeLog(allocator, param, value);
                try list.append(encoded);
            }
        }
    }

    return list.toOwnedSlice();
}
/// Encode event log topics
///
/// `values` is expected to be a tuple of the values to encode.
/// Array and tuples are encoded as the hash representing their values.
///
/// Example:
///
/// const event = .{
///     .type = .event,
///     .inputs = &.{},
///     .name = "Transfer"
/// }
///
/// const encoded = encodeLogTopics(testing.allocator, event, .{});
///
/// Result: &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}
pub fn encodeLogTopics(allocator: Allocator, event: AbiEvent, values: anytype) ![]const ?Hash {
    const info = @typeInfo(@TypeOf(values));

    if (info != .@"struct" or !info.@"struct".is_tuple)
        @compileError("Expected tuple type but found " ++ @typeName(@TypeOf(values)));

    var list = try std.ArrayList(?Hash).initCapacity(allocator, values.len + 1);
    errdefer list.deinit();

    const hash = try event.encode(allocator);

    try list.append(hash);

    if (values.len > 0) {
        std.debug.assert(event.inputs.len >= values.len);

        inline for (values, 0..) |value, i| {
            const param = event.inputs[i];

            if (param.indexed) {
                const encoded = try encodeLog(allocator, param, value);
                try list.append(encoded);
            }
        }
    }

    return try list.toOwnedSlice();
}

fn encodeLog(allocator: Allocator, param: AbiEventParameter, value: anytype) !?Hash {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .bool => {
            switch (param.type) {
                .bool => {
                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(u256, &buffer, @intFromBool(value), .big);

                    return buffer;
                },
                else => return error.InvalidParamType,
            }
        },
        .int => |int_info| {
            if (value > std.math.maxInt(u256))
                return error.Overflow;

            switch (param.type) {
                .uint => {
                    if (int_info.signedness != .unsigned)
                        return error.SignedNumber;

                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(u256, &buffer, value, .big);

                    return buffer;
                },
                .int => {
                    if (int_info.signedness != .signed)
                        return error.UnsignedNumber;

                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(i256, &buffer, value, .big);

                    return buffer;
                },
                else => return error.InvalidParamType,
            }
        },
        .comptime_int => {
            const IntType = std.math.IntFittingRange(value, value);

            return try encodeLog(allocator, param, @as(IntType, value));
        },
        .null => return null,
        .optional => {
            if (value) |val| return try encodeLog(allocator, param, val) else return null;
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes => {
                        var buffer: [32]u8 = undefined;
                        Keccak256.hash(&value, &buffer, .{});
                        return buffer;
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.InvalidAddressType;

                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buffer[12..], value[0..]);

                        return buffer;
                    },
                    .fixedBytes => |size| {
                        if (size != arr_info.len or arr_info.len > 32)
                            return error.InvalidFixedBytesType;

                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        @memcpy(buffer[0..arr_info.len], value[0..arr_info.len]);

                        return buffer;
                    },
                    else => return error.InvalidParamType,
                }
            }

            const new_param: AbiEventParameter = n_param: {
                var new_type = param.type;
                while (true) {
                    switch (new_type) {
                        .dynamicArray => |dyn_arr| {
                            new_type = dyn_arr.*;

                            switch (new_type) {
                                .dynamicArray, .fixedArray => continue,
                                else => break :n_param .{
                                    .type = new_type,
                                    .name = param.name,
                                    .indexed = param.indexed,
                                    .components = param.components,
                                },
                            }
                        },
                        .fixedArray => |fixed_arr| {
                            new_type = fixed_arr.child.*;

                            switch (new_type) {
                                .dynamicArray, .fixedArray => continue,
                                else => break :n_param .{
                                    .type = new_type,
                                    .name = param.name,
                                    .indexed = param.indexed,
                                    .components = param.components,
                                },
                            }
                        },
                        else => return error.InvalidParamType,
                    }
                }
            };

            var list = try std.ArrayList(u8).initCapacity(allocator, 32 * value.len);
            errdefer list.deinit();

            var writer = list.writer();

            const NestedType = FindNestedType(@TypeOf(value));

            var flatten = std.ArrayList(NestedType).init(testing.allocator);
            errdefer flatten.deinit();

            try flattenSliceOrArray(NestedType, value, &flatten);
            const slice = try flatten.toOwnedSlice();
            defer testing.allocator.free(slice);

            for (slice) |val| {
                const res = try encodeLog(allocator, new_param, val);
                if (res) |result| try writer.writeAll(&result);
            }

            const hashes_slice = try list.toOwnedSlice();
            defer allocator.free(hashes_slice);

            var buffer: [32]u8 = undefined;
            Keccak256.hash(slice, &buffer, .{});

            return buffer;
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeLog(allocator, param, value.*),
                .Slice => {
                    if (ptr_info.child == u8) {
                        switch (param.type) {
                            .string, .bytes => {
                                var buffer: [32]u8 = undefined;
                                Keccak256.hash(value, &buffer, .{});
                                return buffer;
                            },
                            else => return error.InvalidParamType,
                        }
                    }

                    const new_param: AbiEventParameter = n_param: {
                        var new_type = param.type;
                        while (true) {
                            switch (new_type) {
                                .dynamicArray => |dyn_arr| {
                                    new_type = dyn_arr.*;

                                    switch (new_type) {
                                        .dynamicArray, .fixedArray => continue,
                                        .string, .bytes => return error.CannotEncodeSliceOfDynamicTypes,
                                        else => break :n_param .{
                                            .type = new_type,
                                            .name = param.name,
                                            .indexed = param.indexed,
                                            .components = param.components,
                                        },
                                    }
                                },
                                .fixedArray => |fixed_arr| {
                                    new_type = fixed_arr.child.*;

                                    switch (new_type) {
                                        .dynamicArray, .fixedArray => continue,
                                        .string, .bytes => return error.CannotEncodeSliceOfDynamicTypes,
                                        else => break :n_param .{
                                            .type = new_type,
                                            .name = param.name,
                                            .indexed = param.indexed,
                                            .components = param.components,
                                        },
                                    }
                                },
                                else => return error.InvalidParamType,
                            }
                        }
                    };

                    var list = std.ArrayList(u8).init(allocator);
                    errdefer list.deinit();

                    var writer = list.writer();

                    const NestedType = FindNestedType(@TypeOf(value));
                    var flatten = std.ArrayList(NestedType).init(testing.allocator);
                    errdefer flatten.deinit();

                    try flattenSliceOrArray(NestedType, value, &flatten);

                    const slice = try flatten.toOwnedSlice();
                    defer testing.allocator.free(slice);

                    for (slice) |val| {
                        const res = try encodeLog(allocator, new_param, val);
                        if (res) |result| try writer.writeAll(&result);
                    }

                    const hashes_slice = try list.toOwnedSlice();
                    defer allocator.free(hashes_slice);

                    var buffer: [32]u8 = undefined;
                    Keccak256.hash(hashes_slice, &buffer, .{});

                    return buffer;
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(value)),
            }
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple)
                @compileError("Tuple types are not supported");

            if (param.type != .tuple)
                return error.InvalidParamType;

            if (param.components) |components| {
                var list = std.ArrayList(u8).init(allocator);
                errdefer list.deinit();

                var writer = list.writer();

                for (components) |component| {
                    inline for (struct_info.fields) |field| {
                        if (std.mem.eql(u8, field.name, component.name)) {
                            const new_param: AbiEventParameter = .{
                                .indexed = true,
                                .type = component.type,
                                .name = component.name,
                                .components = component.components,
                            };

                            const res = try encodeLog(allocator, new_param, @field(value, field.name));
                            if (res) |result| try writer.writeAll(&result);
                        }
                    }
                }

                const hashes_slice = try list.toOwnedSlice();
                defer allocator.free(hashes_slice);

                var buffer: [32]u8 = undefined;
                Keccak256.hash(hashes_slice, &buffer, .{});

                return buffer;
            } else return error.ExpectedComponents;
        },
        else => @compileError("Unsupported pointer type " ++ @typeName(value)),
    }
}

fn flattenSliceOrArray(comptime T: type, value: anytype, list: *std.ArrayList(T)) Allocator.Error!void {
    for (value) |val| {
        const info = @typeInfo(@TypeOf(value));

        switch (info) {
            .array => {
                if (@TypeOf(val) == T)
                    try list.append(val)
                else
                    try flattenSliceOrArray(T, val, list);
            },
            .pointer => {
                if (@TypeOf(val) == T)
                    try list.append(val)
                else
                    try flattenSliceOrArray(T, val, list);
            },
            else => if (@TypeOf(val) == T) try list.append(val),
        }
    }
}

fn FindNestedType(comptime T: type) type {
    const info = @typeInfo(T);

    switch (info) {
        .array => |arr_info| return FindNestedType(arr_info.child),
        .pointer => |ptr_info| return FindNestedType(ptr_info.child),
        else => return T,
    }
}
