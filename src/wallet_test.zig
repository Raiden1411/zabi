//! The objective of this test is to not crash.
//! No checks are made. It's essentially a way to ensure
//! that the requests are sent and parsed without crashes
//! with the knowledge that we can send transactions or
//! interact with contracts.
//!
//! By default no debug message will be printed to the console.
//! If you which for this you will need to update the log level inside this
//! file.
//!
//! This expected to be ran against a Anvil instance.
const args_parser = @import("tests/args.zig");
const std = @import("std");
const utils = @import("utils/utils.zig");

const Anvil = @import("tests/Anvil.zig");
const Contract = @import("clients/contract.zig").Contract;
const WalletL1Client = @import("clients/optimism/clients/L1WalletClient.zig").WalletL1Client;
const Wallet = @import("clients/wallet.zig").Wallet;
const WalletClients = @import("clients/wallet.zig").WalletClients;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    var buffer: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    const uri = try std.Uri.parse("http://localhost:8545/");

    const clients = [_]WalletClients{ .http, .websocket };

    // Simple wallet tests.
    inline for (clients) |client| {
        var wallet: Wallet(client) = undefined;

        try wallet.init(buffer, .{ .allocator = gpa.allocator(), .uri = uri });
        defer wallet.deinit();

        try wallet.poolTransactionEnvelope(.{
            .type = .london,
            .value = 42069,
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        });
        {
            const tx_hash = try wallet.sendTransaction(.{ .type = .london });
            defer tx_hash.deinit();

            const receipt = try wallet.waitForTransactionReceipt(tx_hash.response, 0);
            defer receipt.deinit();
        }
        {
            const tx_hash = try wallet.sendTransaction(.{
                .type = .legacy,
                .value = 42069,
                .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
            });
            defer tx_hash.deinit();

            const receipt = try wallet.waitForTransactionReceipt(tx_hash.response, 0);
            defer receipt.deinit();
        }
        {
            const tx_hash = try wallet.sendTransaction(.{
                .type = .berlin,
                .value = 42069,
                .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
            });
            defer tx_hash.deinit();

            const receipt = try wallet.waitForTransactionReceipt(tx_hash.response, 0);
            defer receipt.deinit();
        }
    }

    const abi = &.{
        .{
            .abiFunction = .{
                .type = .function,
                .inputs = &.{
                    .{ .type = .{ .address = {} }, .name = "operator" },
                    .{ .type = .{ .bool = {} }, .name = "approved" },
                },
                .stateMutability = .nonpayable,
                .outputs = &.{},
                .name = "setApprovalForAll",
            },
        },
        .{
            .abiFunction = .{
                .type = .function,
                .inputs = &.{
                    .{ .type = .{ .uint = 256 }, .name = "tokenId" },
                },
                .stateMutability = .view,
                .outputs = &.{
                    .{ .type = .{ .address = {} }, .name = "" },
                },
                .name = "ownerOf",
            },
        },
        .{
            .abiConstructor = .{
                .type = .constructor,
                .inputs = &.{},
                .stateMutability = .nonpayable,
            },
        },
    };
    var anvil: Anvil = undefined;
    defer anvil.deinit();

    try anvil.initClient(.{ .fork_url = "", .alloc = gpa.allocator() });

    // Simple contract tests.
    inline for (clients) |client| {
        var contract: Contract(client) = undefined;
        defer contract.deinit();

        try contract.init(.{
            .abi = abi,
            .private_key = buffer,
            .wallet_opts = .{ .allocator = gpa.allocator(), .uri = uri },
        });

        {
            var hex_buffer: [1024]u8 = undefined;
            const bytes = try std.fmt.hexToBytes(&hex_buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
            const hash = try contract.deployContract(.{}, bytes, .{ .type = .london });
            defer hash.deinit();

            const receipt = try contract.wallet.waitForTransactionReceipt(hash.response, 0);
            defer receipt.deinit();
        }
        {
            const ReturnType = struct { [20]u8 };
            _ = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .london = .{
                .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
                .from = contract.wallet.getWalletAddress(),
            } });
        }
        {
            try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

            const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });
            defer result.deinit();

            try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        }
        {
            try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

            const result = try contract.writeContractFunction("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
                .type = .london,
                .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
            });
            defer result.deinit();

            const receipt = try contract.wallet.waitForTransactionReceipt(result.response, 0);
            defer receipt.deinit();

            try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        }
    }

    inline for (clients) |client| {
        var wallet_op: WalletL1Client(client) = undefined;
        defer wallet_op.deinit();

        try wallet_op.init(buffer, .{
            .allocator = gpa.allocator(),
            .uri = uri,
        }, null);

        const response = try wallet_op.depositTransaction(.{
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        });
        defer response.deinit();
    }
}
