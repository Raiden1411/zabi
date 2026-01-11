const std = @import("std");
const testing = std.testing;
const types = @import("zabi").types.ethereum;
const withdrawl = @import("zabi").clients.withdrawal_types;
const utils = @import("zabi").utils.utils;

const Hash = types.Hash;
const HttpProvider = @import("zabi").clients.Provider.HttpProvider;
const Wallet = @import("zabi").clients.Wallet;
const WithdrawalEnvelope = withdrawl.WithdrawalEnvelope;

test "InitiateWithdrawal" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(buffer[0..], "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var http_provider = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = std.testing.io,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{},
        },
    });
    defer http_provider.deinit();

    var wallet_op = try Wallet.init(buffer, testing.allocator, &http_provider.provider, false);
    defer wallet_op.deinit();

    const inital = try wallet_op.initiateWithdrawal(.{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    });
    defer inital.deinit();
}
