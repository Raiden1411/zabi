const std = @import("std");
const testing = std.testing;
const types = @import("zabi").types.ethereum;
const withdrawl = @import("zabi").superchain.withdrawal_types;
const utils = @import("zabi").utils.utils;

const Hash = types.Hash;
const L1WalletClient = @import("zabi").superchain.l1_wallet_client.L1WalletClient;
const WithdrawalEnvelope = withdrawl.WithdrawalEnvelope;

test "InitiateWithdrawal" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(buffer[0..], "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var wallet_op = try L1WalletClient(.http).init(buffer, .{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{},
        },
    });
    defer wallet_op.deinit();

    const inital = try wallet_op.initiateWithdrawal(.{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    });
    defer inital.deinit();
}

test "Ref All Decls" {
    std.testing.refAllDecls(L1WalletClient(.http));
    std.testing.refAllDecls(L1WalletClient(.ipc));
    std.testing.refAllDecls(L1WalletClient(.websocket));
}
