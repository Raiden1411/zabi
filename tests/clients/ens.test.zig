const std = @import("std");
const test_clients = @import("../constants.zig");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const HttpProvider = @import("zabi").clients.Provider.HttpProvider;
const Anvil = @import("zabi").clients.Anvil;

test "Reset Anvil" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    const mainnet = try std.process.getEnvVarOwned(testing.allocator, "ANVIL_FORK_URL");
    defer testing.allocator.free(mainnet);

    var anvil: Anvil = undefined;
    defer anvil.deinit();

    anvil.initClient(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
    });

    try anvil.reset(.{
        .forking = .{
            .jsonRpcUrl = mainnet,
            .blockNumber = 19062632,
        },
    });
}

test "ENS Text" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();
    var ens = try HttpProvider.init(
        .{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    try testing.expectError(error.EvmFailedToExecute, ens.provider.getEnsText(testing.allocator, "zzabi.eth", "com.twitter", .{}));
}

test "ENS Name" {
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator);
        defer threaded_io.deinit();
        var ens = try HttpProvider.init(
            .{
                .allocator = testing.allocator,
                .io = threaded_io.io(),
                .network_config = test_clients.anvil_mainnet,
            },
        );
        defer ens.deinit();

        const value = try ens.provider.getEnsName(testing.allocator, "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", .{});
        defer value.deinit();

        try testing.expectEqualStrings(value.response, "vitalik.eth");
        try testing.expectError(error.EvmFailedToExecute, ens.provider.getEnsName(testing.allocator, "0xD9DA6Bf26964af9d7Eed9e03e53415D37aa96045", .{}));
    }
}

test "ENS Address" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();
    var ens = try HttpProvider.init(
        .{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    const value = try ens.provider.getEnsAddress(testing.allocator, "vitalik.eth", .{});
    defer value.deinit();

    try testing.expectEqualSlices(u8, &value.result, &try utils.addressToBytes("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"));
    try testing.expectError(error.EvmFailedToExecute, ens.provider.getEnsAddress(testing.allocator, "zzabi.eth", .{}));
}

test "ENS Resolver" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();
    var ens = try HttpProvider.init(
        .{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = test_clients.anvil_mainnet,
        },
    );
    defer ens.deinit();

    const value = try ens.provider.getEnsResolver(testing.allocator, "vitalik.eth", .{});

    try testing.expectEqualSlices(u8, &try utils.addressToBytes("0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41"), &value);
}
