const std = @import("std");
const abi_parameter = @import("abi_parameter.zig");
const param = @import("param_type.zig");
const AbiParameter = abi_parameter.AbiParameter;
const Allocator = std.mem.Allocator;
const ParamType = param.ParamType;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

pub const TypedDataDomain = struct { chainId: ?u64 = null, name: ?[]const u8 = null, verifyingContract: ?[]const u8 = null, version: ?[]const u8 = null, salt: ?[]const u8 = null };

pub const MessageProperty = struct {
    name: []const u8,
    type: []const u8,
};

pub fn hashTypedData(allocator: Allocator, comptime types: anytype, comptime primary_type: []const u8, domain: ?TypedDataDomain, message: anytype) ![Keccak256.digest_length]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    var writer = list.writer();
    try writer.writeAll("\x19\x01");

    if (domain) |dom| {
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
    }

    switch (info) {
        .Bool => try writer.writeInt(u256, @intFromBool(value), .big),
        .Int, .ComptimeInt => try writer.writeInt(u256, value, .big),
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
                        var buffer: [Keccak256.digest_length]u8 = undefined;
                        Keccak256.hash(&value, &buffer, .{});
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

            var list = std.ArrayList(u8).init(allocator);
            errdefer list.deinit();

            const index = std.mem.lastIndexOfLinear(u8, primary_type, "[");
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
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeStructField(allocator, types, primary_type, value.*, writer),
                .Slice => {
                    if (ptr_info.child == u8) {
                        const param_type = try ParamType.typeToUnion(primary_type, allocator);
                        errdefer if (param_type == .dynamicArray or param_type == .fixedArray) param_type.freeArrayParamType(allocator);

                        switch (param_type) {
                            .string, .bytes => {
                                var buffer: [Keccak256.digest_length]u8 = undefined;
                                Keccak256.hash(value, &buffer, .{});
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

                    var list = std.ArrayList(u8).init(allocator);
                    errdefer list.deinit();

                    const index = std.mem.lastIndexOf(u8, primary_type, "[");
                    const arr_type = primary_type[0..index];
                    for (value) |v| {
                        try encodeStructField(allocator, types, arr_type, v, list.writer());
                    }

                    const slice = try list.toOwnedSlice();
                    defer allocator.free(slice);

                    var buffer: [Keccak256.digest_length]u8 = undefined;
                    Keccak256.hash(slice, &buffer, .{});
                    try writer.writeAll(&buffer);
                },
                else => @compileError("Pointer type not supported " ++ @typeName(@TypeOf(value))),
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple) {
                var list = std.ArrayList(u8).init(allocator);
                errdefer list.deinit();

                const index = std.mem.lastIndexOf(u8, primary_type, "[");
                const arr_type = primary_type[0..index];
                for (value) |v| {
                    try encodeStructField(allocator, types, arr_type, v, list.writer());
                }
                const slice = try list.toOwnedSlice();
                var buffer: [Keccak256.digest_length]u8 = undefined;
                Keccak256.hash(slice, &buffer, .{});
                try writer.writeAll(&buffer);
            }
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

test "Message" {
    const fields = .{ .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const hash = try hashType(std.testing.allocator, fields, "Mail");
    std.debug.print("Hash: 0x{s}\n\n\n", .{std.fmt.fmtSliceHexLower(&hash)});

    const a = try hashStruct(std.testing.allocator, fields, "Mail", .{ .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" }, .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" }, .contents = "Hello, Bob!" });

    std.debug.print("Hash: 0x{s}\n\n\n", .{std.fmt.fmtSliceHexLower(&a)});
}

test "Domain" {
    const domain: TypedDataDomain = .{ .name = "Ether Mail", .version = "1", .chainId = 1, .verifyingContract = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC" };
    const types = .{ .EIP712Domain = &.{ .{ .type = "string", .name = "name" }, .{ .name = "version", .type = "string" }, .{ .name = "chainId", .type = "uint256" }, .{ .name = "verifyingContract", .type = "address" } }, .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const hash = try hashTypedData(std.testing.allocator, types, "Mail", domain, .{ .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" }, .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" }, .contents = "Hello, Bob!" });
    std.debug.print("Hash: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&hash)});
}
