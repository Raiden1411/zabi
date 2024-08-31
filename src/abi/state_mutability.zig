const std = @import("std");
const testing = std.testing;

/// Solidity abi stat mutability definition of functions and constructors.
pub const StateMutability = enum {
    nonpayable,
    payable,
    view,
    pure,
};

test "Json parse" {
    const slice =
        \\ [
        \\  "nonpayable",
        \\  "payable",
        \\  "view",
        \\  "pure"
        \\ ]
    ;

    const parsed = try std.json.parseFromSlice([]StateMutability, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expectEqual(StateMutability.nonpayable, parsed.value[0]);
    try testing.expectEqual(StateMutability.payable, parsed.value[1]);
    try testing.expectEqual(StateMutability.view, parsed.value[2]);
    try testing.expectEqual(StateMutability.pure, parsed.value[3]);
}
