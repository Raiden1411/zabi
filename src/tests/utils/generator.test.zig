const block = @import("../../types/block.zig");
const ethereum = @import("../../types/ethereum.zig");
const logs = @import("../../types/log.zig");
const proof = @import("../../types/proof.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../../types/transaction.zig");

const generateRandomData = @import("../../utils/generator.zig").generateRandomData;

test "Zabi types" {
    // Block types
    {
        const data = try generateRandomData(block.Block, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(block.BlobBlock, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(block.Withdrawal, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(block.LegacyBlock, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(block.BeaconBlock, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(block.BlockTransactions, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }

    // Transaction types
    {
        const data = try generateRandomData(transaction.Transaction, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(transaction.TransactionReceipt, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(transaction.TransactionEnvelopeSigned, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(transaction.TransactionEnvelope, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(transaction.FeeHistory, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(transaction.LondonEnvelopeSigned, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }

    // Logs
    {
        const data = try generateRandomData(logs.Logs, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(logs.Log, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }

    // Proof
    {
        const data = try generateRandomData(proof.ProofResult, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(proof.StorageProof, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }

    // Ethereum
    {
        const data = try generateRandomData(ethereum.PublicChains, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.ErrorResponse, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.EthereumRpcMethods, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.EthereumErrorCodes, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.EthereumRpcResponse(u32), testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.EthereumResponse(u64), testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
    {
        const data = try generateRandomData(ethereum.EthereumErrorResponse, testing.allocator, 0, .{ .slice_size = 32 });
        defer data.deinit();
    }
}
