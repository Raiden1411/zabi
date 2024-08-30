const std = @import("std");
const test_clients = @import("../constants.zig");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const ENSClient = @import("../../clients/ens/ens.zig").ENSClient;

test "ENS Text" {
    var ens = try ENSClient(.http).init(
        .{
            .allocator = testing.allocator,
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    try testing.expectError(error.EvmFailedToExecute, ens.getEnsText("zzabi.eth", "com.twitter", .{}));
}

test "ENS Name" {
    {
        var ens = try ENSClient(.http).init(
            .{
                .allocator = testing.allocator,
                .network_config = test_clients.anvil_mainnet,
            },
        );
        defer ens.deinit();

        const value = try ens.getEnsName("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", .{});
        defer value.deinit();

        try testing.expectEqualStrings(value.response, "vitalik.eth");
        try testing.expectError(error.EvmFailedToExecute, ens.getEnsName("0xD9DA6Bf26964af9d7Eed9e03e53415D37aa96045", .{}));
    }
}

test "ENS Address" {
    var ens = try ENSClient(.http).init(
        .{
            .allocator = testing.allocator,
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    const value = try ens.getEnsAddress("vitalik.eth", .{});
    defer value.deinit();

    try testing.expectEqualSlices(u8, &value.result, &try utils.addressToBytes("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"));
    try testing.expectError(error.EvmFailedToExecute, ens.getEnsAddress("zzabi.eth", .{}));
}

test "ENS Resolver" {
    var ens = try ENSClient(.http).init(
        .{
            .allocator = testing.allocator,
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    const value = try ens.getEnsResolver("vitalik.eth", .{});

    try testing.expectEqualSlices(u8, &try utils.addressToBytes("0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41"), &value);
}
