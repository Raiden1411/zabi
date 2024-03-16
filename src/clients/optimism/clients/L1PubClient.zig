const abi_items = @import("../abi.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
const decoder = @import("../../../decoding/decoder.zig");
const decoder_logs = @import("../../../decoding/logs_decode.zig");
const log = @import("../../../types/log.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_transactions = @import("../types/transaction.zig");
const op_utils = @import("../utils.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawal_types = @import("../types/withdrawl.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Clients = @import("../../wallet.zig").WalletClients;
const Hash = types.Hash;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsWs = clients.PubClient.InitOptions;
const Logs = log.Logs;
const L2Output = op_types.L2Output;
const Message = withdrawal_types.Message;
const OpMainNetContracts = contracts.OpMainNetContracts;
const ProvenWithdrawal = withdrawal_types.ProvenWithdrawal;
const PubClient = clients.PubClient;
const TransactionDeposited = op_transactions.TransactionDeposited;
const WebSocketClient = clients.WebSocket;
const Withdrawal = withdrawal_types.Withdrawal;
const WithdrawlEnvelope = withdrawal_types.WithdrawalEnvelope;

/// Optimism client used for L1 interactions.
/// Currently only supports OP and not other chains of the superchain.
pub fn L1Client(comptime client_type: Clients) type {
    return struct {
        const L1 = @This();

        /// The underlaying rpc client type (ws or http)
        const ClientType = switch (client_type) {
            .http => PubClient,
            .websocket => WebSocketClient,
        };

        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
        };

        /// This is the same allocator as the rpc_client.
        /// Its a field mostly for convinience
        allocator: Allocator,
        /// The http or ws client that will be use to query the rpc server
        rpc_client: *ClientType,
        /// List of know contracts from OP
        contracts: OpMainNetContracts,

        /// Starts the RPC connection
        /// If the contracts are null it defaults to OP contracts.
        pub fn init(self: *L1, opts: InitOpts, op_contracts: ?OpMainNetContracts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            if (opts.chain_id) |id| {
                switch (id) {
                    .ethereum => {},
                    else => return error.InvalidChain,
                }
            }

            try op_client.init(opts);

            self.* = .{
                .rpc_client = op_client,
                .allocator = op_client.allocator,
                .contracts = op_contracts orelse .{},
            };
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *L1) void {
            const child_allocator = self.rpc_client.arena.child_allocator;

            self.rpc_client.deinit();
            child_allocator.destroy(self.rpc_client);

            self.* = undefined;
        }
        /// Returns if a withdrawal has finalized or not.
        pub fn getFinalizedWithdrawals(self: *L1, withdrawal_hash: Hash) !bool {
            const encoded = try abi_items.get_finalized_withdrawal.encode(self.allocator, .{withdrawal_hash});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = hex,
            } }, .{});

            return try std.fmt.parseInt(u1, data, 0) != 0;
        }
        /// Gets the latest proposed L2 block number from the Oracle.
        pub fn getLatestProposedL2BlockNumber(self: *L1) !u64 {
            // Selector for `latestBlockNumber`
            const selector: []const u8 = "0x4599c788";

            const block = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});

            return try std.fmt.parseInt(u64, block, 0);
        }

        pub fn getL2HashesForDepositTransaction(self: *L1, tx_hash: Hash) ![]const Hash {
            const deposit_data = try self.getTransactionDepositEvents(tx_hash);

            var list = try std.ArrayList(Hash).initCapacity(self.allocator, deposit_data.len);
            errdefer list.deinit();

            for (deposit_data) |data| {
                try list.append(try op_utils.getL2HashFromL1DepositInfo(self.allocator, .{
                    .to = data.to,
                    .from = data.from,
                    .opaque_data = data.opaqueData,
                    .l1_blockhash = data.blockHash,
                    .log_index = data.logIndex,
                    .domain = .user_deposit,
                }));
            }

            return try list.toOwnedSlice();
        }
        /// Calls to the L2OutputOracle contract on L1 to get the output for a given L2 block
        pub fn getL2Output(self: *L1, l2_block_number: u256) !L2Output {
            const index = try self.getL2OutputIndex(l2_block_number);

            const encoded = try abi_items.get_l2_output_func.encode(self.allocator, .{index});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = hex,
            } }, .{});

            const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.get_l2_output_func.outputs, data, .{});
            defer decoded.deinit();

            const l2_output = decoded.values[0];

            return .{ .outputIndex = index, .outputRoot = l2_output.outputRoot, .timestamp = l2_output.timestamp, .l2BlockNumber = l2_output.l2BlockNumber };
        }
        /// Calls to the L2OutputOracle on L1 to get the output index.
        pub fn getL2OutputIndex(self: *L1, l2_block_number: u256) !u256 {
            const encoded = try abi_items.get_l2_index_func.encode(self.allocator, .{l2_block_number});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = hex,
            } }, .{});
            return std.fmt.parseInt(u256, data, 0);
        }
        /// Gets a proven withdrawl.
        pub fn getProvenWithdrawals(self: *L1, withdrawal_hash: Hash) !ProvenWithdrawal {
            const encoded = try abi_items.get_proven_withdrawal.encode(self.allocator, .{withdrawal_hash});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = hex,
            } }, .{});

            const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.get_proven_withdrawal.outputs, data, .{});
            defer decoded.deinit();

            const proven = decoded.values[0];

            if (proven.timestamp == 0)
                return error.InvalidWithdrawalHash;

            return .{ .outputRoot = proven.outputRoot, .timestamp = proven.timestamp, .l2OutputIndex = proven.l2OutputIndex };
        }
        /// Gets the amount of time to wait in ms until the next output is posted.
        pub fn getSecondsToNextL2Output(self: *L1, latest_l2_block: u64) !u128 {
            const latest = try self.getLatestProposedL2BlockNumber();

            if (latest_l2_block < latest)
                return error.InvalidBlockNumber;

            const selector: []const u8 = "0x529933df";

            const submission = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});

            const interval = try std.fmt.parseInt(i128, submission, 0);

            const selector_time: []const u8 = "0x002134cc";
            const block = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector_time,
            } }, .{});

            const time = try std.fmt.parseInt(i128, block, 0);

            const block_until: i128 = interval - (latest_l2_block - latest);

            return if (block_until < 0) @intCast(0) else @intCast(block_until * time);
        }
        /// Gets the amount of time to wait until a withdrawal is finalized.
        pub fn getSecondsToFinalize(self: *L1, withdrawal_hash: Hash) !u64 {
            const proven = try self.getProvenWithdrawals(withdrawal_hash);

            const selector: []const u8 = "0xf4daa291";
            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});

            const time = try std.fmt.parseInt(i64, data, 0);
            const time_since: i64 = @divFloor(std.time.timestamp(), 1000) - @as(i64, @truncate(@as(i128, @intCast(proven.timestamp))));

            return if (time_since < 0) @intCast(0) else @intCast(time - time_since);
        }
        /// Gets the `TransactionDeposited` event logs from a transaction hash.
        pub fn getTransactionDepositEvents(self: *L1, tx_hash: Hash) ![]const TransactionDeposited {
            const receipt = try self.rpc_client.getTransactionReceipt(tx_hash);

            const logs: Logs = switch (receipt) {
                inline else => |tx_receipt| tx_receipt.logs,
            };

            var list = std.ArrayList(TransactionDeposited).init(self.allocator);
            errdefer list.deinit();

            // Event selector for `TransactionDeposited`.
            const hash: []const u8 = "0xb3813568d9991fc951961fcb4c784893574240a28925604d09fc577c55bb7c32";
            const ReturnType = struct { []const u8, Address, Address, u256 };
            for (logs) |log_event| {
                if (std.mem.eql(u8, hash, log_event.topics[0] orelse return error.ExpectedTopicData)) {
                    if (log_event.logIndex == null)
                        return error.UnexpectedNullIndex;

                    const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.transaction_deposited_event_data, log_event.data, .{});
                    defer decoded.deinit();

                    const decoded_logs = try decoder_logs.decodeLogs(self.allocator, ReturnType, abi_items.transaction_deposited_event_args, log_event.topics);
                    defer decoded_logs.deinit();

                    try list.append(.{
                        .from = decoded_logs.result[1],
                        .to = decoded_logs.result[2],
                        .version = decoded_logs.result[3],
                        .opaqueData = try self.allocator.dupe(u8, decoded.values[0]),
                        .logIndex = log_event.logIndex.?,
                        .blockHash = log_event.blockHash.?,
                    });
                }
            }

            return try list.toOwnedSlice();
        }
        /// Gets the decoded withdrawl event logs from a given transaction receipt hash.
        pub fn getWithdrawMessages(self: *L1, tx_hash: Hash) !Message {
            const receipt = try self.rpc_client.getTransactionReceipt(tx_hash);

            if (receipt != .l2_receipt)
                return error.InvalidTransactionHash;

            var list = std.ArrayList(Withdrawal).init(self.allocator);
            errdefer list.deinit();

            // The hash for the event selector `MessagePassed`
            const hash: []const u8 = "0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054";

            const ReturnType = struct { []const u8, u256, Address, Address };
            for (receipt.l2_receipt.logs) |logs| {
                if (std.mem.eql(u8, hash, logs.topics[0] orelse return error.ExpectedTopicData)) {
                    const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.message_passed_params, logs.data, .{});
                    defer decoded.deinit();

                    const decoded_logs = try decoder_logs.decodeLogs(self.allocator, ReturnType, abi_items.message_passed_indexed_params, logs.topics);
                    defer decoded_logs.deinit();

                    try list.append(.{
                        .nonce = decoded_logs.result[1],
                        .target = decoded_logs.result[2],
                        .sender = decoded_logs.result[3],
                        .value = decoded.values[0],
                        .gasLimit = decoded.values[1],
                        .data = decoded.values[2],
                        .withdrawalHash = decoded.values[3],
                    });
                }
            }

            const messages = try list.toOwnedSlice();

            return .{
                .blockNumber = receipt.l2_receipt.blockNumber.?,
                .messages = messages,
            };
        }
        /// Waits until the next L2 output is posted.
        /// This will keep pooling until it can get the L2Output or it exceeds the max retries.
        pub fn waitForNextL2Output(self: *L1, latest_l2_block: u64) !L2Output {
            const time = try self.getSecondsToNextL2Output(latest_l2_block);
            std.time.sleep(time * 1000);

            var retries: usize = 0;
            const l2_output = while (true) : (retries += 1) {
                if (retries > self.rpc_client.retries)
                    return error.ExceedRetriesAmount;

                const output = self.getL2Output(latest_l2_block) catch |err| switch (err) {
                    error.EvmFailedToExecute => {
                        std.time.sleep(self.rpc_client.pooling_interval);
                        continue;
                    },
                    else => return err,
                };

                break output;
            };

            return l2_output;
        }
        /// Waits until the withdrawal has finalized.
        pub fn waitToFinalize(self: *L1, withdrawal_hash: Hash) !void {
            const time = try self.getSecondsToFinalize(withdrawal_hash);
            std.time.sleep(time * 1000);
        }
    };
}

test "GetL2HashFromL1DepositInfo" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const messages = try op.getL2HashesForDepositTransaction(try utils.hashToBytes("0x33faeeee9c6d5e19edcdfc003f329c6652f05502ffbf3218d9093b92589a42c4"));

    try testing.expectEqualSlices(u8, &try utils.hashToBytes("0xed88afbd3f126180bd5488c2212cd033c51a6f9b1765249bdb738dcac1d0cb41"), &messages[0]);
}

test "GetL2Output" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const l2_output = try op.getL2Output(2725977);

    try testing.expectEqual(l2_output.timestamp, 1686075935);
    try testing.expectEqual(l2_output.outputIndex, 0);
    try testing.expectEqual(l2_output.l2BlockNumber, 105236863);
}

test "getSecondsToFinalize" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const seconds = try op.getSecondsToFinalize(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
    try testing.expectEqual(seconds, 0);
}

test "GetSecondsToNextL2Output" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const block = try op.getLatestProposedL2BlockNumber();
    const seconds = try op.getSecondsToNextL2Output(block);
    try testing.expectEqual(seconds, 3600);
}

test "GetTransactionDepositEvents" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const deposit_events = try op.getTransactionDepositEvents(try utils.hashToBytes("0xe94031c3174788c3fee7216465c50bb2b72e7a1963f5af807b3768da10827f5c"));

    try testing.expect(deposit_events.len != 0);
    try testing.expectEqual(deposit_events[0].to, try utils.addressToBytes("0xbc3ed6B537f2980e66f396Fe14210A56ba3f72C4"));
}

test "GetProvenWithdrawals" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const proven = try op.getProvenWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));

    try testing.expectEqual(proven.l2OutputIndex, 1490);
}

test "GetFinalizedWithdrawals" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

    const finalized = try op.getFinalizedWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
    try testing.expect(finalized);
}

test "Errors" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);
    try testing.expectError(error.InvalidBlockNumber, op.getSecondsToNextL2Output(1));
    try testing.expectError(error.InvalidWithdrawalHash, op.getSecondsToFinalize(try utils.hashToBytes("0xe94031c3174788c3fee7216465c50bb2b72e7a1963f5af807b3768da10827f5c")));
}
