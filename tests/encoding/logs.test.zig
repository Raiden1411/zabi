const std = @import("std");
const abi = @import("zabi-abi").abitypes;
const human = @import("zabi-human").parsing;
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

// Types
const Hash = types.Hash;

const encodeLogTopics = @import("zabi-encoding").logs_encoding.encodeLogTopics;
const encodeLogTopicsComptime = @import("zabi-encoding").logs_encoding.encodeLogTopicsComptime;

test "Empty inputs" {
    const event = .{ .type = .event, .inputs = &.{}, .name = "Transfer" };

    const encoded = try encodeLogTopics(testing.allocator, event, .{});
    defer testing.allocator.free(encoded);

    const encoded_comptime = try encodeLogTopicsComptime(testing.allocator, event, .{});
    defer testing.allocator.free(encoded_comptime);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};

    try testing.expectEqualDeep(slice, encoded);
    try testing.expectEqualDeep(encoded_comptime, encoded);
}

test "Empty args" {
    const event = try human.parseHumanReadable(testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{});
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")};

    try testing.expectEqualDeep(slice, encoded);
}

test "With args" {
    const event = try human.parseHumanReadable(testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{ try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, try utils.hashToBytes("0x000000000000000000000000a5cc3c03994db5b0d9a5eedd10cabab0813678ac") };

    try testing.expectEqualDeep(slice, encoded);
}

test "Comptime Encoding" {
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .uint = 256 },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const encoded_comptime = try encodeLogTopicsComptime(testing.allocator, event, .{69});
        defer testing.allocator.free(encoded_comptime);

        const encoded = try encodeLogTopics(testing.allocator, event, .{69});
        defer testing.allocator.free(encoded);

        try testing.expectEqualDeep(encoded_comptime, encoded);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .int = 256 },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const encoded_comptime = try encodeLogTopicsComptime(testing.allocator, event, .{-69});
        defer testing.allocator.free(encoded_comptime);

        const encoded = try encodeLogTopics(testing.allocator, event, .{-69});
        defer testing.allocator.free(encoded);

        try testing.expectEqualDeep(encoded_comptime, encoded);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .string = {} },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const encoded_comptime = try encodeLogTopicsComptime(testing.allocator, event, .{"foo"});
        defer testing.allocator.free(encoded_comptime);

        const encoded = try encodeLogTopics(testing.allocator, event, .{"foo"});
        defer testing.allocator.free(encoded);

        try testing.expectEqualDeep(encoded_comptime, encoded);
    }
    {
        const event: abi.Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{
                    .type = .{ .dynamicArray = &.{ .uint = 256 } },
                    .name = "bar",
                    .indexed = true,
                },
            },
        };
        const value: []const u256 = &.{69};
        const encoded_comptime = try encodeLogTopicsComptime(testing.allocator, event, .{value});
        defer testing.allocator.free(encoded_comptime);

        const encoded = try encodeLogTopics(testing.allocator, event, .{value});
        defer testing.allocator.free(encoded);

        try testing.expectEqualDeep(encoded_comptime, encoded);
    }
}

test "With args string/bytes" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const str: []const u8 = "hello";
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{str});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const str: []const u8 = "hello";
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{str});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") };

        try testing.expectEqualDeep(slice, encoded);
    }
}

test "With remaing types" {
    const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)");
    defer event.deinit();

    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{ 69, -420, true, "01234" });
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{ try utils.hashToBytes("0x08056cee0ec7df6d2ab8d10ab36f1ac8be153e2a0001198ef7b4c17dde75cbc4"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000045"), try utils.hashToBytes("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe5c"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000001"), try utils.hashToBytes("0x3031323334000000000000000000000000000000000000000000000000000000") };
    try testing.expectEqualDeep(slice, encoded);
}

test "Array types" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{69};
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0xa80a8fcc11760162f08bb091d2c9389d07f2b73d0e996161dfac6f1043b5fc0b") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{ 69, 69 };
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0x1de70b39b0b9e807901612d596756f9f581455d5f89cb049b46f082f8a423dc6") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Bar(uint256[] indexed baz)");
        defer event.deinit();

        const arr: []const u256 = &.{};
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{arr});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ try utils.hashToBytes("0xf2f93df484f17a3a9dc5ad4281f6a49fe8ed98d0e9444200dc613445fe70c256"), try utils.hashToBytes("0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470") };

        try testing.expectEqualDeep(slice, encoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Bar(uint256[][][] indexed baz)");
        defer event.deinit();

        const arr: []const []const []const u256 = &.{&.{&.{69}}};
        const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{arr});
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
    const event = try human.parseHumanReadable(testing.allocator, slice);
    defer event.deinit();

    const bar: struct { foo: u256 } = .{ .foo = 69 };
    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{bar});
    defer testing.allocator.free(encoded);

    const hash_slice: []const ?Hash = &.{ try utils.hashToBytes("0xe74ea230b4c63fa6ee946baed76e1bc04d512f95a0f31338ee83c20b66631046"), try utils.hashToBytes("0xa80a8fcc11760162f08bb091d2c9389d07f2b73d0e996161dfac6f1043b5fc0b") };

    try testing.expectEqualDeep(hash_slice, encoded);
}

test "Errors" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        try testing.expectError(error.SignedNumber, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{-69}));
        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{false}));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bool indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{-69}));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidAddressType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{"0x00000000000000000000000000000000000"}));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidFixedBytesType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{"0x00000000000000000000000000000000000"}));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const str: []const u8 = "hey";
        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{str}));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        try testing.expectError(error.InvalidParamType, encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{"hey"}));
    }
}
