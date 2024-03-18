const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/abi.zig");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

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

    if (info != .Struct or !info.Struct.is_tuple)
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
        .Bool => {
            switch (param.type) {
                .bool => {
                    var buffer: [32]u8 = undefined;
                    std.mem.writeInt(u256, &buffer, @intFromBool(value), .big);

                    return buffer;
                },
                else => return error.InvalidParamType,
            }
        },
        .Int => |int_info| {
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
        .ComptimeInt => {
            const IntType = std.math.IntFittingRange(value, value);

            return try encodeLog(allocator, param, @as(IntType, value));
        },
        .Null => return null,
        .Optional => {
            if (value) |val| return try encodeLog(allocator, param, val) else return null;
        },
        .Array => |arr_info| {
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

            const NestedType = findNestedType(@TypeOf(value));

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
        .Pointer => |ptr_info| {
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

                    const NestedType = findNestedType(@TypeOf(value));
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
        .Struct => |struct_info| {
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

fn flattenSliceOrArray(comptime T: type, value: anytype, list: *std.ArrayList(T)) !void {
    for (value) |val| {
        const info = @typeInfo(@TypeOf(value));

        switch (info) {
            .Array => {
                if (@TypeOf(val) == T)
                    try list.append(val)
                else
                    try flattenSliceOrArray(T, val, list);
            },
            .Pointer => {
                if (@TypeOf(val) == T)
                    try list.append(val)
                else
                    try flattenSliceOrArray(T, val, list);
            },
            else => if (@TypeOf(val) == T) try list.append(val),
        }
    }
}

fn findNestedType(comptime T: type) type {
    const info = @typeInfo(T);

    switch (info) {
        .Array => |arr_info| return findNestedType(arr_info.child),
        .Pointer => |ptr_info| return findNestedType(ptr_info.child),
        else => return T,
    }
}

test "Empty inputs" {
    const event = .{ .type = .event, .inputs = &.{}, .name = "Transfer" };

    const encoded = try encodeLogTopics(testing.allocator, event, .{});
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};

    try testing.expectEqualDeep(slice, encoded);
}

test "Empty args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value, .{});
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")};

    try testing.expectEqualDeep(slice, encoded);
}

test "With args" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{ try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, try utils.hashToBytes("0x000000000000000000000000a5cc3c03994db5b0d9a5eedd10cabab0813678ac") };

    try testing.expectEqualDeep(slice, encoded);
}

test "With args string/bytes" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogTopics(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogTopics(testing.allocator, event.value, .{"hello"});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const str: []const u8 = "hello";
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{str});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const str: []const u8 = "hello";
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{str});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
}

test "With remaing types" {
    const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value, .{ 69, -420, true, "01234" });
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{ try utils.hashToBytes("0x08056cee0ec7df6d2ab8d10ab36f1ac8be153e2a0001198ef7b4c17dde75cbc4"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000045"), try utils.hashToBytes("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe5c"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000001"), try utils.hashToBytes("0x3031323334000000000000000000000000000000000000000000000000000000") };
    try testing.expectEqualDeep(slice, encoded);
}

test "Array types" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{69};
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0xa80a8fcc11760162f08bb091d2c9389d07f2b73d0e996161dfac6f1043b5fc0b") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{ 69, 69 };
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0x1de70b39b0b9e807901612d596756f9f581455d5f89cb049b46f082f8a423dc6") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{};
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Bar(uint256[][][] indexed baz)");
        defer event.deinit();

        const arr: []const []const []const u256 = &.{&.{&.{69}}};
        const encoded = try encodeLogTopics(testing.allocator, event.value, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0x9ef9519e463db05a446c0dfbe83eff19a03f2087827426a7e38b69df591bef7f"), try utils.hashToBytes("0xa80a8fcc11760162f08bb091d2c9389d07f2b73d0e996161dfac6f1043b5fc0b") };

        try testing.expectEqualDeep(slice, encoded);
    }
}

test "Structs" {
    const slice =
        \\struct Foo{uint256 foo;}
        \\event Bar(Foo indexed foo)
    ;
    const event = try human.parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer event.deinit();

    const bar: struct { foo: u256 } = .{ .foo = 69 };
    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{bar});
    defer testing.allocator.free(encoded);

    const hash_slice: []const ?Hash = &.{ try utils.hashToBytes("0xe74ea230b4c63fa6ee946baed76e1bc04d512f95a0f31338ee83c20b66631046"), try utils.hashToBytes("0xa80a8fcc11760162f08bb091d2c9389d07f2b73d0e996161dfac6f1043b5fc0b") };

    try testing.expectEqualDeep(hash_slice, encoded);
}

test "Errors" {
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        try testing.expectError(error.SignedNumber, encodeLogTopics(testing.allocator, event.value, .{-69}));
        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value, .{false}));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bool indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value, .{-69}));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidAddressType, encodeLogTopics(testing.allocator, event.value, .{"0x00000000000000000000000000000000000"}));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidFixedBytesType, encodeLogTopics(testing.allocator, event.value, .{"0x00000000000000000000000000000000000"}));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const str: []const u8 = "hey";
        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value, .{str}));
    }
    {
        const event = try human.parseHumanReadable(abi.Event, testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value, .{"hey"}));
    }
}
