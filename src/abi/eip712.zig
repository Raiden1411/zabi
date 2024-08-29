const std = @import("std");
const abi_parameter = @import("abi_parameter.zig");
const param = @import("param_type.zig");
const testing = std.testing;

// Types
const AbiParameter = abi_parameter.AbiParameter;
const Allocator = std.mem.Allocator;
const ParamType = param.ParamType;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

pub const TypedDataDomain = struct {
    chainId: ?u64 = null,
    name: ?[]const u8 = null,
    verifyingContract: ?[]const u8 = null,
    version: ?[]const u8 = null,
    salt: ?[]const u8 = null,
};

pub const MessageProperty = struct {
    name: []const u8,
    type: []const u8,
};

/// Performs hashing of EIP712 according to the expecification
/// https://eips.ethereum.org/EIPS/eip-712
///
/// `types` parameter is expected to be a struct where the struct
/// keys are used to grab the solidity type information so that the
/// encoding and hashing can happen based on it. See the specification
/// for more details.
///
/// `primary_type` is the expected main type that you want to hash this message.
/// Compilation will fail if the provided string doesn't exist on the `types` parameter
///
/// `domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
/// domain types.
///
/// `message` is expected to be a struct where the solidity types are transalated to the native
/// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
/// In the future work will be done where the compiler will offer more clearer types
/// base on a meta programming type function.
pub fn hashTypedData(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, domain: ?TypedDataDomain, message: anytype) ![Keccak256.digest_length]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var writer = list.writer();
    try writer.writeAll("\x19\x01");

    if (domain) |dom| {
        if (!@hasField(@TypeOf(types), "EIP712Domain"))
            @compileError("Expected EIP712Domain field on types parameter");

        const hash = try hashStruct(allocator, types, "EIP712Domain", dom);
        try writer.writeAll(&hash);
    }

    if (!std.mem.eql(u8, primary_type, "EIP712Domain")) {
        const hash = try hashStruct(allocator, types, primary_type, message);
        try writer.writeAll(&hash);
    }

    const slice = try list.toOwnedSlice();
    defer allocator.free(slice);

    var buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(slice, &buffer, .{});

    return buffer;
}
/// Performs hashing of EIP712 structs according to the expecification
/// https://eips.ethereum.org/EIPS/eip-712
///
/// `types` parameter is expected to be a struct where the struct
/// keys are used to grab the solidity type information so that the
/// encoding and hashing can happen based on it. See the specification
/// for more details.
///
/// `primary_type` is the expected main type that you want to hash this message.
/// Compilation will fail if the provided string doesn't exist on the `types` parameter
///
/// `data` is expected to be a struct where the solidity types are transalated to the native
/// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
/// In the future work will be done where the compiler will offer more clearer types
/// base on a meta programming type function.
pub fn hashStruct(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, data: anytype) ![Keccak256.digest_length]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try encodeStruct(allocator, types, primary_type, data, list.writer());

    const slice = try list.toOwnedSlice();
    defer allocator.free(slice);

    var buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(slice, &buffer, .{});

    return buffer;
}
/// Performs encoding of EIP712 structs according to the expecification
/// https://eips.ethereum.org/EIPS/eip-712
///
/// `types` parameter is expected to be a struct where the struct
/// keys are used to grab the solidity type information so that the
/// encoding and hashing can happen based on it. See the specification
/// for more details.
///
/// `primary_type` is the expected main type that you want to hash this message.
/// Compilation will fail if the provided string doesn't exist on the `types` parameter
///
/// `data` is expected to be a struct where the solidity types are transalated to the native
/// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
/// In the future work will be done where the compiler will offer more clearer types
/// base on a meta programming type function.
///
/// Slices, arrays, strings and bytes will all be encoded as "bytes32" instead of their
/// usual encoded values.
pub fn encodeStruct(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, data: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(types));
    const data_info = @typeInfo(@TypeOf(data));

    if (info != .@"struct" or info.@"struct".is_tuple)
        @compileError("Expected struct type but found: " ++ @typeName(@TypeOf(types)));

    if (data_info != .@"struct" or info.@"struct".is_tuple)
        @compileError("Expected struct type but found: " ++ @typeName(@TypeOf(data)));

    const type_hash = try hashType(allocator, types, primary_type);
    try writer.writeAll(&type_hash);

    const fields = @field(types, primary_type);

    inline for (fields) |message_prop| {
        inline for (data_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, message_prop.name)) {
                try encodeStructField(allocator, types, message_prop.type, @field(data, message_prop.name), writer);
            }
        }
    }
}
/// Encodes a singular struct field.
pub fn encodeStructField(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, value: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(value));
    if (@hasField(@TypeOf(types), primary_type)) {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try encodeStruct(allocator, types, primary_type, value, list.writer());

        const slice = try list.toOwnedSlice();
        defer allocator.free(slice);

        var buffer: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(slice, &buffer, .{});

        try writer.writeAll(&buffer);
        return;
    }

    switch (info) {
        .bool => {
            const param_type = try ParamType.typeToUnion(primary_type, allocator);
            errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

            switch (param_type) {
                .bool => try writer.writeInt(u256, @intFromBool(value), .big),
                else => return error.UnexpectTypeFound,
            }
        },
        .int, .comptime_int => {
            const param_type = try ParamType.typeToUnion(primary_type, allocator);
            errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

            switch (param_type) {
                .int, .uint => try writer.writeInt(u256, value, .big),
                else => return error.UnexpectTypeFound,
            }
        },
        .optional => {
            if (value) |v| {
                try encodeStructField(allocator, types, primary_type, v, writer);
            }
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                const param_type = try ParamType.typeToUnion(primary_type, allocator);
                errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

                switch (param_type) {
                    .string, .bytes => {
                        const slice = slice: {
                            if (value.len == 0) break :slice value[0..];

                            if (std.mem.startsWith(u8, value[0..], "0x")) {
                                break :slice value[2..];
                            }

                            break :slice value[0..];
                        };
                        const buf = try allocator.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);
                        defer allocator.free(buf);

                        const bytes = if (std.fmt.hexToBytes(buf, slice)) |result| result else |_| slice;
                        var buffer: [Keccak256.digest_length]u8 = undefined;
                        Keccak256.hash(bytes, &buffer, .{});
                        try writer.writeAll(&buffer);
                    },
                    .address => {
                        const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        _ = try std.fmt.hexToBytes(buffer[12..], hex);

                        try writer.writeAll(&buffer);
                    },
                    .fixedBytes => |size| {
                        const hex: []const u8 = if (std.mem.startsWith(u8, &value, "0x")) value[2..] else &value;
                        var buffer: [32]u8 = [_]u8{0} ** 32;
                        _ = try std.fmt.hexToBytes(buffer[0..size], hex);

                        try writer.writeAll(&buffer);
                    },
                    else => return error.UnexpectTypeFound,
                }
                return;
            }

            const param_type = try ParamType.typeToUnion(primary_type, allocator);
            defer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

            switch (param_type) {
                .dynamicArray, .fixedArray => {
                    var list = std.ArrayList(u8).init(allocator);
                    errdefer list.deinit();

                    const index = comptime std.mem.lastIndexOf(u8, primary_type, "[");
                    const arr_type = primary_type[0 .. index orelse return error.InvalidType];
                    for (value) |v| {
                        try encodeStructField(allocator, types, arr_type, v, list.writer());
                    }

                    const slice = try list.toOwnedSlice();
                    defer allocator.free(slice);

                    var buffer: [Keccak256.digest_length]u8 = undefined;
                    Keccak256.hash(slice, &buffer, .{});
                    try writer.writeAll(&buffer);
                },
                else => return error.UnexpectTypeFound,
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeStructField(allocator, types, primary_type, value.*, writer),
                .Slice => {
                    if (ptr_info.child == u8) {
                        const param_type = try ParamType.typeToUnion(primary_type, allocator);
                        errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

                        switch (param_type) {
                            .string, .bytes => {
                                const slice = slice: {
                                    if (value.len == 0) break :slice value[0..];

                                    if (std.mem.startsWith(u8, value[0..], "0x")) {
                                        break :slice value[2..];
                                    }

                                    break :slice value[0..];
                                };
                                const buf = try allocator.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);
                                defer allocator.free(buf);

                                const bytes = if (std.fmt.hexToBytes(buf, slice)) |result| result else |_| slice;
                                var buffer: [Keccak256.digest_length]u8 = undefined;
                                Keccak256.hash(bytes, &buffer, .{});
                                try writer.writeAll(&buffer);
                            },
                            .address => {
                                const hex = if (std.mem.startsWith(u8, value, "0x")) value[2..] else value;
                                var buffer: [32]u8 = [_]u8{0} ** 32;
                                _ = try std.fmt.hexToBytes(buffer[12..], hex);

                                try writer.writeAll(&buffer);
                            },
                            .fixedBytes => |size| {
                                const hex = if (std.mem.startsWith(u8, value, "0x")) value[2..] else value;
                                var buffer: [32]u8 = [_]u8{0} ** 32;
                                _ = try std.fmt.hexToBytes(buffer[0..size], hex);

                                try writer.writeAll(&buffer);
                            },
                            else => return error.UnexpectTypeFound,
                        }
                        return;
                    }

                    const param_type = try ParamType.typeToUnion(primary_type, allocator);
                    defer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

                    switch (param_type) {
                        .dynamicArray, .fixedArray => {
                            var list = std.ArrayList(u8).init(allocator);
                            errdefer list.deinit();

                            const index = comptime std.mem.lastIndexOf(u8, primary_type, "[");
                            const arr_type = primary_type[0 .. index orelse return error.InvalidType];
                            for (value) |v| {
                                try encodeStructField(allocator, types, arr_type, v, list.writer());
                            }

                            const slice = try list.toOwnedSlice();
                            defer allocator.free(slice);

                            var buffer: [Keccak256.digest_length]u8 = undefined;
                            Keccak256.hash(slice, &buffer, .{});
                            try writer.writeAll(&buffer);
                        },
                        else => return error.UnexpectTypeFound,
                    }
                },
                else => @compileError("Pointer type not supported " ++ @typeName(@TypeOf(value))),
            }
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                const param_type = try ParamType.typeToUnion(primary_type, allocator);
                defer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

                switch (param_type) {
                    .dynamicArray, .fixedArray => {
                        var list = std.ArrayList(u8).init(allocator);
                        errdefer list.deinit();

                        const index = comptime std.mem.lastIndexOf(u8, primary_type, "[");
                        const arr_type = primary_type[0 .. index orelse return error.InvalidType];
                        inline for (value) |v| {
                            try encodeStructField(allocator, types, arr_type, v, list.writer());
                        }

                        const slice = try list.toOwnedSlice();
                        defer allocator.free(slice);

                        var buffer: [Keccak256.digest_length]u8 = undefined;
                        Keccak256.hash(slice, &buffer, .{});

                        try writer.writeAll(&buffer);
                    },
                    else => return error.UnexpectTypeFound,
                }
            } else @compileError("Unsupported struct type " ++ @typeName(@TypeOf(value)));
        },
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
}
/// Hash the main types and it's nested children
pub fn hashType(allocator: Allocator, comptime types_fields: anytype, comptime primary_type: []const u8) ![Keccak256.digest_length]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try encodeType(allocator, types_fields, primary_type, list.writer());

    const slice = try list.toOwnedSlice();
    defer allocator.free(slice);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(slice, &hash, .{});

    return hash;
}
/// Encodes the main type from a struct into a "human-readable" format.
///
/// *Ex: struct { Mail: []const struct {type: "address", name: "foo"}} into "Mail(address foo)"*
pub fn encodeType(allocator: Allocator, comptime types_fields: anytype, comptime primary_type: []const u8, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(types_fields));

    var result = std.StringArrayHashMap(void).init(allocator);
    defer result.deinit();

    try findTypeDependencies(types_fields, primary_type, &result);

    try writer.writeAll(primary_type);
    try writer.writeByte('(');
    if (!result.swapRemove(primary_type))
        return error.InvalidPrimType;

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, primary_type)) {
            const values = @field(types_fields, field.name);
            inline for (values, 0..) |value, i| {
                try writer.writeAll(value.type);
                try writer.writeAll(" ");
                try writer.writeAll(value.name);

                if (values.len > 1 and i < values.len - 1)
                    try writer.writeByte(',');
            }
        }
    }

    try writer.writeByte(')');

    const keys = result.keys();

    // In place sort of the result keys
    std.sort.pdq([]const u8, keys, {}, struct {
        fn lessThan(_: void, left: []const u8, right: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(left, right);
        }
    }.lessThan);

    for (keys) |key| {
        inline for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, key)) {
                const values = @field(types_fields, field.name);
                try writer.writeAll(field.name);
                try writer.writeByte('(');
                inline for (values, 0..) |value, i| {
                    try writer.writeAll(value.type);
                    try writer.writeAll(" ");
                    try writer.writeAll(value.name);

                    if (values.len > 1 and i < values.len - 1)
                        try writer.writeByte(',');
                }
                try writer.writeByte(')');
            }
        }
    }
}
/// Finds the main type child type and recursivly checks their children as well.
pub fn findTypeDependencies(comptime types_fields: anytype, comptime primary_type: []const u8, result: *std.StringArrayHashMap(void)) Allocator.Error!void {
    if (result.getKey(primary_type) != null)
        return;

    const info = @typeInfo(@TypeOf(types_fields));

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, primary_type)) {
            try result.put(primary_type, {});
            const messages = @field(types_fields, field.name);

            inline for (messages) |message| {
                try findTypeDependencies(types_fields, message.type, result);
            }
        }
    } else return;
}
