const abi = @import("../../abi/abi.zig");
const human = @import("../../human-readable/abi_parsing.zig");
const logs_decode = @import("../../decoding/logs_decode.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const AbiEvent = abi.Event;
const Hash = [32]u8;
const LogDecoderOptions = logs_decode.LogDecoderOptions;

// Functions
const decodeLogs = logs_decode.decodeLogs;
const encodeLogs = @import("../../encoding/logs.zig").encodeLogTopics;

test "Decode empty inputs" {
    const slice: []const ?Hash = &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")};
    const decoded = try decodeLogs(struct { Hash }, slice, .{});

    try testing.expectEqualDeep(.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}, decoded);
}

test "Decode empty args" {
    const event = try human.parseHumanReadable(testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{});
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(struct { Hash }, encoded, .{});

    try testing.expectEqualDeep(.{try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")}, decoded);
}

test "Decode with args" {
    const event = try human.parseHumanReadable(testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{ null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(struct { Hash, ?Hash, [20]u8 }, encoded, .{});

    try testing.expectEqualDeep(.{ try utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"), null, try utils.addressToBytes("0xa5cc3c03994DB5b0d9A5eEdD10CabaB0813678AC") }, decoded);
}

test "Decoded with args string/bytes" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(string indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, ?Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0x9f0b7f1630bdb7d474466e2dfef0fb9dff65f7a50eec83935b68f77d0808f08a"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes indexed message)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, Hash }), encoded, .{});

        try testing.expectEqualDeep(.{ try utils.hashToBytes("0xefc9afd358f1472682cf8cc82e1d3ae36be2538ed858a4a604119399d6f22b48"), try utils.hashToBytes("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8") }, decoded);
    }
}

test "Decode Arrays" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(address indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97")});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, [20]u8 }, encoded, .{});

        try testing.expectEqualDeep(.{ encoded[0], try utils.addressToBytes("0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97") }, decoded);
    }

    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, [5]u8 }, encoded, .{ .bytes_endian = .little });

        try testing.expectEqualDeep(.{ encoded[0], "hello".* }, decoded);
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(bytes5 indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{"hello"});
        defer testing.allocator.free(encoded);

        const decoded = try decodeLogs(struct { Hash, *const [5]u8 }, encoded, .{ .allocator = testing.allocator, .bytes_endian = .little });
        defer testing.allocator.destroy(decoded[1]);

        try testing.expectEqualDeep(.{ encoded[0], "hello" }, decoded);
    }
}

test "Decode with remaing types" {
    const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a, int indexed b, bool indexed c)");
    defer event.deinit();

    const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{ 69, -420, true });
    defer testing.allocator.free(encoded);

    const decoded = try decodeLogs(std.meta.Tuple(&[_]type{ Hash, u256, i256, bool }), encoded, .{});

    try testing.expectEqualDeep(.{
        try utils.hashToBytes("0x99cb3d24e259f33004405cf6e508105e2fd2885003235a6a7fcb843bd09728b1"),
        @as(u256, @intCast(69)),
        @as(i256, @intCast(-420)),
        true,
    }, decoded);
}

test "Errors" {
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{69});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.ExpectedAllocator, decodeLogs(struct { Hash, *const [5]u8 }, encoded, .{ .bytes_endian = .little }));
    }
    {
        const event = try human.parseHumanReadable(testing.allocator, "event Foo(uint indexed a)");
        defer event.deinit();

        const encoded = try encodeLogs(testing.allocator, event.value[0].abiEvent, .{null});
        defer testing.allocator.free(encoded);

        try testing.expectError(error.UnexpectedTupleFieldType, decodeLogs(struct { Hash, [5]u8 }, encoded, .{ .bytes_endian = .little }));
    }
}
