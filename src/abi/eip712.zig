const std = @import("std");
const abi_parameter = @import("abi_parameter.zig");
const param = @import("param_type.zig");
const testing = std.testing;
const AbiParameter = abi_parameter.AbiParameter;
const Allocator = std.mem.Allocator;
const ParamType = param.ParamType;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

pub const TypedDataDomain = struct { chainId: ?u64 = null, name: ?[]const u8 = null, verifyingContract: ?[]const u8 = null, version: ?[]const u8 = null, salt: ?[]const u8 = null };

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

pub fn encodeStruct(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, data: anytype, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(types));
    const data_info = @typeInfo(@TypeOf(data));

    if (info != .Struct or info.Struct.is_tuple)
        @compileError("Expected struct type but found: " ++ @typeName(@TypeOf(types)));

    if (data_info != .Struct or info.Struct.is_tuple)
        @compileError("Expected struct type but found: " ++ @typeName(@TypeOf(data)));

    const type_hash = try hashType(allocator, types, primary_type);
    try writer.writeAll(&type_hash);

    const fields = @field(types, primary_type);

    inline for (fields) |message_prop| {
        inline for (data_info.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, message_prop.name)) {
                try encodeStructField(allocator, types, message_prop.type, @field(data, message_prop.name), writer);
            }
        }
    }
}

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
        .Bool => {
            const param_type = try ParamType.typeToUnion(primary_type, allocator);
            errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

            switch (param_type) {
                .bool => try writer.writeInt(u256, @intFromBool(value), .big),
                else => return error.UnexpectTypeFound,
            }
        },
        .Int, .ComptimeInt => {
            const param_type = try ParamType.typeToUnion(primary_type, allocator);
            errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

            switch (param_type) {
                .int, .uint => try writer.writeInt(u256, value, .big),
                else => return error.UnexpectTypeFound,
            }
        },
        .Optional => {
            if (value) |v| {
                try encodeStructField(allocator, types, primary_type, v, writer);
            }
        },
        .Array => |arr_info| {
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
        .Pointer => |ptr_info| {
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
        .Struct => |struct_info| {
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

pub fn encodeType(allocator: Allocator, comptime types_fields: anytype, comptime primary_type: []const u8, writer: anytype) !void {
    const info = @typeInfo(@TypeOf(types_fields));

    var result = std.StringArrayHashMap(void).init(allocator);
    defer result.deinit();

    try findTypeDependencies(types_fields, primary_type, &result);

    try writer.writeAll(primary_type);
    try writer.writeByte('(');
    if (!result.swapRemove(primary_type))
        return error.InvalidPrimType;

    inline for (info.Struct.fields) |field| {
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
        inline for (info.Struct.fields) |field| {
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

pub fn findTypeDependencies(comptime types_fields: anytype, comptime primary_type: []const u8, result: *std.StringArrayHashMap(void)) Allocator.Error!void {
    if (result.getKey(primary_type) != null)
        return;

    const info = @typeInfo(@TypeOf(types_fields));

    inline for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, primary_type)) {
            try result.put(primary_type, {});
            const messages = @field(types_fields, field.name);

            inline for (messages) |message| {
                try findTypeDependencies(types_fields, message.type, result);
            }
        }
    } else return;
}

test "With Message" {
    const fields = .{ .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const hash = try hashStruct(testing.allocator, fields, "Mail", .{ .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" }, .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" }, .contents = "Hello, Bob!" });

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e", hex);
}

test "With Domain" {
    const domain: TypedDataDomain = .{ .name = "Ether Mail", .version = "1", .chainId = 1, .verifyingContract = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC" };
    const types = .{ .EIP712Domain = &.{ .{ .type = "string", .name = "name" }, .{ .name = "version", .type = "string" }, .{ .name = "chainId", .type = "uint256" }, .{ .name = "verifyingContract", .type = "address" } }, .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const hash = try hashStruct(testing.allocator, types, "EIP712Domain", domain);

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xf2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f", hex);
}

test "EIP712 Minimal" {
    const hash = try hashTypedData(testing.allocator, .{ .EIP712Domain = .{} }, "EIP712Domain", .{}, .{});
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x8d4a3f4082945b7879e2b55f181c31a77c8c0a464b70669458abbaaf99de4c38", hex);
}

test "EIP712 Example" {
    const domain: TypedDataDomain = .{ .name = "Ether Mail", .version = "1", .chainId = 1, .verifyingContract = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC" };
    const types = .{ .EIP712Domain = &.{ .{ .type = "string", .name = "name" }, .{ .name = "version", .type = "string" }, .{ .name = "chainId", .type = "uint256" }, .{ .name = "verifyingContract", .type = "address" } }, .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const hash = try hashTypedData(testing.allocator, types, "Mail", domain, .{ .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" }, .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" }, .contents = "Hello, Bob!" });

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2", hex);
}

test "EIP712 Complex" {
    const domain: TypedDataDomain = .{ .name = "Ether Mail 🥵", .version = "1.1.1", .chainId = 1, .verifyingContract = "0x0000000000000000000000000000000000000000" };
    const types = .{ .EIP712Domain = &.{ .{ .type = "string", .name = "name" }, .{ .type = "string", .name = "version" }, .{ .type = "uint256", .name = "chainId" }, .{ .type = "address", .name = "verifyingContract" } }, .Name = &.{ .{ .type = "string", .name = "first" }, .{ .name = "last", .type = "string" } }, .Person = &.{ .{ .name = "name", .type = "Name" }, .{ .name = "wallet", .type = "address" }, .{ .type = "string[3]", .name = "favoriteColors" }, .{ .name = "foo", .type = "uint256" }, .{ .name = "age", .type = "uint8" }, .{ .name = "isCool", .type = "bool" } }, .Mail = &.{ .{ .name = "timestamp", .type = "uint256" }, .{ .type = "Person", .name = "from" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" }, .{ .name = "hash", .type = "bytes" } } };

    const message = .{ .timestamp = 1234567890, .contents = "Hello, Bob! 🖤", .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", .from = .{ .name = .{ .first = "Cow", .last = "Burns" }, .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", .foo = 123123123123123123, .age = 69, .favoriteColors = &.{ "red", "green", "blue" }, .isCool = false }, .to = .{ .name = .{ .first = "Bob", .last = "Builder" }, .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB", .foo = 123123123123123123, .age = 70, .favoriteColors = &.{ "orange", "yellow", "green" }, .isCool = true } };

    const hash = try hashTypedData(testing.allocator, types, "Mail", domain, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x9a74cb859ad30835ffb2da406423233c212cf6dd78e6c2c98b0c9289568954ae", hex);
}

test "EIP712 Complex empty domain data" {
    const types = .{ .EIP712Domain = &.{}, .Name = &.{ .{ .type = "string", .name = "first" }, .{ .name = "last", .type = "string" } }, .Person = &.{ .{ .name = "name", .type = "Name" }, .{ .name = "wallet", .type = "address" }, .{ .type = "string[3]", .name = "favoriteColors" }, .{ .name = "foo", .type = "uint256" }, .{ .name = "age", .type = "uint8" }, .{ .name = "isCool", .type = "bool" } }, .Mail = &.{ .{ .name = "timestamp", .type = "uint256" }, .{ .type = "Person", .name = "from" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" }, .{ .name = "hash", .type = "bytes" } } };

    const message = .{ .timestamp = 1234567890, .contents = "Hello, Bob! 🖤", .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", .from = .{ .name = .{ .first = "Cow", .last = "Burns" }, .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", .foo = 123123123123123123, .age = 69, .favoriteColors = &.{ "red", "green", "blue" }, .isCool = false }, .to = .{ .name = .{ .first = "Bob", .last = "Builder" }, .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB", .foo = 123123123123123123, .age = 70, .favoriteColors = &.{ "orange", "yellow", "green" }, .isCool = true } };

    const hash = try hashTypedData(testing.allocator, types, "Mail", .{}, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x14ed1dbbfecbe5de3919f7ea47daafdf3a29dfbb60dd88d85509f79773d503a5", hex);
}

test "EIP712 Complex null domain data" {
    const types = .{ .EIP712Domain = &.{}, .Name = &.{ .{ .type = "string", .name = "first" }, .{ .name = "last", .type = "string" } }, .Person = &.{ .{ .name = "name", .type = "Name" }, .{ .name = "wallet", .type = "address" }, .{ .type = "string[3]", .name = "favoriteColors" }, .{ .name = "foo", .type = "uint256" }, .{ .name = "age", .type = "uint8" }, .{ .name = "isCool", .type = "bool" } }, .Mail = &.{ .{ .name = "timestamp", .type = "uint256" }, .{ .type = "Person", .name = "from" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" }, .{ .name = "hash", .type = "bytes" } } };

    const message = .{ .timestamp = 1234567890, .contents = "Hello, Bob! 🖤", .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", .from = .{ .name = .{ .first = "Cow", .last = "Burns" }, .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", .foo = 123123123123123123, .age = 69, .favoriteColors = &.{ "red", "green", "blue" }, .isCool = false }, .to = .{ .name = .{ .first = "Bob", .last = "Builder" }, .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB", .foo = 123123123123123123, .age = 70, .favoriteColors = &.{ "orange", "yellow", "green" }, .isCool = true } };

    const hash = try hashTypedData(testing.allocator, types, "Mail", null, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xad520b9936265259bb247eb16258d7b59c02dca1b278c7590f19d5ee03d362e8", hex);
}

test "EIP712 Complex empty domain name" {
    const types = .{ .EIP712Domain = &.{.{ .type = "string", .name = "name" }}, .Name = &.{ .{ .type = "string", .name = "first" }, .{ .name = "last", .type = "string" } }, .Person = &.{ .{ .name = "name", .type = "Name" }, .{ .name = "wallet", .type = "address" }, .{ .type = "string[3]", .name = "favoriteColors" }, .{ .name = "foo", .type = "uint256" }, .{ .name = "age", .type = "uint8" }, .{ .name = "isCool", .type = "bool" } }, .Mail = &.{ .{ .name = "timestamp", .type = "uint256" }, .{ .type = "Person", .name = "from" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" }, .{ .name = "hash", .type = "bytes" } } };

    const message = .{ .timestamp = 1234567890, .contents = "Hello, Bob! 🖤", .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", .from = .{ .name = .{ .first = "Cow", .last = "Burns" }, .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826", .foo = 123123123123123123, .age = 69, .favoriteColors = &.{ "red", "green", "blue" }, .isCool = false }, .to = .{ .name = .{ .first = "Bob", .last = "Builder" }, .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB", .foo = 123123123123123123, .age = 70, .favoriteColors = &.{ "orange", "yellow", "green" }, .isCool = true } };

    const hash = try hashTypedData(testing.allocator, types, "Mail", .{ .name = "" }, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xc3f4f9ebd774352940f60aebbc83fcee20d0b17eb42bd1b20c91a748001ecb53", hex);
}
