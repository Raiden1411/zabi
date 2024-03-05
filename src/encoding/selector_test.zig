const abi = @import("../abi/abi.zig");
const human = @import("../human-readable/abi_parsing.zig");
const std = @import("std");
const testing = std.testing;

test "Constructor" {
    const sig = try human.parseHumanReadable(abi.Constructor, testing.allocator, "constructor(bool foo)");
    defer sig.deinit();

    const encoded = try sig.value.encode(testing.allocator, .{true});
    defer encoded.deinit();

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded.data)});
    defer testing.allocator.free(hex);
    try testing.expectEqualStrings("0000000000000000000000000000000000000000000000000000000000000001", hex);
}

test "Constructor multi params" {
    const sig = try human.parseHumanReadable(abi.Constructor, testing.allocator, "constructor(bool foo, string bar)");
    defer sig.deinit();

    const fizz: []const u8 = "fizzbuzz";
    const encoded = try sig.value.encode(testing.allocator, .{ true, fizz });
    defer encoded.deinit();

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded.data)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000", hex);
}

test "Error signature" {
    const sig = try human.parseHumanReadable(abi.Error, testing.allocator, "error Foo(bool foo, string bar)");
    defer sig.deinit();

    const fizz: []const u8 = "fizzbuzz";
    const encoded = try sig.value.encode(testing.allocator, .{ true, fizz });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000", hex);
}

test "Event signature" {
    const sig = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address indexed from, address indexed to, uint256 tokenId)");
    defer sig.deinit();

    const encoded = try sig.value.encode(testing.allocator);

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", hex);
}

test "Event signature non indexed" {
    const sig = try human.parseHumanReadable(abi.Event, testing.allocator, "event Transfer(address from, address to, uint256 tokenId)");
    defer sig.deinit();

    const encoded = try sig.value.encode(testing.allocator);

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", hex);
}

test "Function" {
    const sig = try human.parseHumanReadable(abi.Function, testing.allocator, "function Foo(bool foo, string bar)");
    defer sig.deinit();

    const fizz: []const u8 = "fizzbuzz";
    const encoded = try sig.value.encode(testing.allocator, .{ true, fizz });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000", hex);
}

test "Function outputs" {
    const sig = try human.parseHumanReadable(abi.Function, testing.allocator, "function Foo(bool foo, string bar) public view returns(int120 baz)");
    defer sig.deinit();

    const encoded = try sig.value.encodeOutputs(testing.allocator, .{1});
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("65c9c0c10000000000000000000000000000000000000000000000000000000000000001", hex);
}

test "AbiItem" {
    const sig = try human.parseHumanReadable(abi.AbiItem, testing.allocator, "function Foo(bool foo, string bar)");
    defer sig.deinit();

    const fizz: []const u8 = "fizzbuzz";
    const encoded = try sig.value.abiFunction.encode(testing.allocator, .{ true, fizz });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000", hex);
}
