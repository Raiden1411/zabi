const std = @import("std");
const abi = @import("zabi-abi").abitypes;
const human = @import("zabi-human").parsing;
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

// Types
const Hash = types.Hash;

const encodeLogTopicsComptime = @import("zabi-encoding").logs_encoding.encodeLogTopics;
const encodeLogTopics = @import("zabi-encoding").logs_encoding.encodeLogTopicsFromReflection;

test "Empty inputs" {
    const event: abi.Event = .{ .type = .event, .inputs = &.{}, .name = "Transfer" };

    const encoded_comptime = try encodeLogTopicsComptime(event, testing.allocator, .{});
    defer testing.allocator.free(encoded_comptime);

    const encoded = try encodeLogTopics(testing.allocator, event, .{});
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};

    try testing.expectEqualDeep(slice, encoded);
    try testing.expectEqualDeep(slice, encoded_comptime);
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

    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{
        null,
        @byteSwap(@as(u160, @bitCast(try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC")))),
    });
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
        const encoded = try encodeLogTopicsComptime(event, testing.allocator, .{69});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ event.encode() catch unreachable, [_]u8{0} ** 31 ++ [_]u8{0x45} };
        try testing.expectEqualDeep(slice, encoded);
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
        const encoded = try encodeLogTopicsComptime(event, testing.allocator, .{-69});
        defer testing.allocator.free(encoded);

        const slice: []const ?Hash = &.{ event.encode() catch unreachable, [_]u8{0xff} ** 31 ++ [_]u8{0xbb} };
        try testing.expectEqualDeep(slice, encoded);
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

        const encoded = try encodeLogTopicsComptime(event, testing.allocator, .{"foo"});
        defer testing.allocator.free(encoded);

        var buffer: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash("foo", &buffer, .{});

        const slice: []const ?Hash = &.{ event.encode() catch unreachable, buffer };
        try testing.expectEqualDeep(slice, encoded);
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

    const encoded = try encodeLogTopics(testing.allocator, event.value[0].abiEvent, .{ 69, -420, true, "01234".* });
    defer testing.allocator.free(encoded);

    const slice: []const ?Hash = &.{ try utils.hashToBytes("0x08056cee0ec7df6d2ab8d10ab36f1ac8be153e2a0001198ef7b4c17dde75cbc4"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000045"), try utils.hashToBytes("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe5c"), try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000001"), try utils.hashToBytes("0x3031323334000000000000000000000000000000000000000000000000000000") };
    try testing.expectEqualDeep(slice, encoded);
}
