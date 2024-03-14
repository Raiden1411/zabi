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
const OpMainNetContracts = contracts.OpMainNetContracts;
const ProvenWithdrawl = withdrawal_types.ProvenWithdrawl;
const PubClient = clients.PubClient;
const TransactionDeposited = op_transactions.TransactionDeposited;
const WebSocketClient = clients.WebSocket;
const Withdrawl = withdrawal_types.Withdrawl;
const WithdrawlEnvelope = withdrawal_types.WithdrawlEnvelope;

pub fn OptimismL1Client(comptime client_type: Clients) type {
    return struct {
        const OptimismL1 = @This();

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

        allocator: Allocator,

        rpc_client: *ClientType,

        contracts: OpMainNetContracts = .{},

        pub fn init(self: *OptimismL1, opts: InitOpts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            try op_client.init(opts);

            self.* = .{
                .rpc_client = op_client,
                .allocator = op_client.allocator,
            };
        }

        pub fn deinit(self: *OptimismL1) void {
            const child_allocator = self.rpc_client.arena.child_allocator;

            self.rpc_client.deinit();
            child_allocator.destroy(self.rpc_client);

            self.* = undefined;
        }

        pub fn getFinalizedWithdrawals(self: *OptimismL1, withdrawal_hash: Hash) !bool {
            const encoded = try abi_items.get_finalized_withdrawal.encode(self.allocator, .{withdrawal_hash});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = hex,
            } }, .{});

            return try std.fmt.parseInt(u1, data, 0) != 0;
        }

        pub fn getLatestProposedL2BlockNumber(self: *OptimismL1) !u64 {
            const selector: []const u8 = "0x4599c788";

            const block = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});

            return try std.fmt.parseInt(u64, block, 0);
        }

        pub fn getL2HashesForDepositTransaction(self: *OptimismL1, tx_hash: Hash) ![]const Hash {
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

        pub fn getL2Output(self: *OptimismL1, l2_block_number: u256) !L2Output {
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

        pub fn getL2OutputIndex(self: *OptimismL1, l2_block_number: u256) !u256 {
            const encoded = try abi_items.get_l2_index_func.encode(self.allocator, .{l2_block_number});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = hex,
            } }, .{});
            return std.fmt.parseInt(u256, data, 0);
        }

        pub fn getProvenWithdrawals(self: *OptimismL1, withdrawal_hash: Hash) !ProvenWithdrawl {
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

        pub fn getSecondsToNextL2Output(self: *OptimismL1, latest_l2_block: u64) !u128 {
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

        pub fn getSecondsToFinalize(self: *OptimismL1, withdrawal_hash: Hash) !u64 {
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

        pub fn getTransactionDepositEvents(self: *OptimismL1, tx_hash: Hash) ![]const TransactionDeposited {
            const receipt = try self.rpc_client.getTransactionReceipt(tx_hash);

            const logs: Logs = switch (receipt) {
                inline else => |tx_receipt| tx_receipt.logs,
            };

            var list = std.ArrayList(TransactionDeposited).init(self.allocator);
            errdefer list.deinit();

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

        pub fn prepareWithdrawalProofTransaction(self: *OptimismL1, withdrawal: Withdrawl, l2_output: L2Output) !WithdrawlEnvelope {
            const storage_slot = op_utils.getWithdrawlHashStorageSlot(withdrawal.withdrawalHash);
            const proof = try self.rpc_client.getProof(.{
                .address = self.contracts.l2ToL1MessagePasser,
                .storageKeys = &.{storage_slot},
                .blockNumber = l2_output.l2BlockNumber,
            }, null);

            const block = try self.rpc_client.getBlockByNumber(.{ .block_number = l2_output.l2BlockNumber });
            const block_info: struct { stateRoot: Hash, hash: Hash } = switch (block) {
                inline else => |block_info| .{ .stateRoot = block_info.stateRoot, .hash = block_info.hash.? },
            };

            return .{
                .nonce = withdrawal.nonce,
                .sender = withdrawal.sender,
                .target = withdrawal.target,
                .value = withdrawal.value,
                .gasLimit = withdrawal.gasLimit,
                .data = withdrawal.data,
                .outputRootProof = .{
                    .version = [_]u8{0} ** 32,
                    .stateRoot = block_info.stateRoot,
                    .messagePasserStorageRoot = proof.storageHash,
                    .latestBlockHash = block_info.hash,
                },
                .withdrawalProof = proof.storageProof[0].proof,
                .l2OutputIndex = l2_output.outputIndex,
            };
        }

        pub fn waitForNextL2Output(self: *OptimismL1, latest_l2_block: u64) !L2Output {
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

        pub fn waitToFinalize(self: *OptimismL1, withdrawal_hash: Hash) !void {
            const time = try self.getSecondsToFinalize(withdrawal_hash);
            std.time.sleep(time * 1000);
        }
    };
}

test "Small" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: OptimismL1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator });

    // const messages = try op.getL2HashesForDepositTransaction(try utils.hashToBytes("0x33faeeee9c6d5e19edcdfc003f329c6652f05502ffbf3218d9093b92589a42c4"));
    // const receipt = try op.rpc_client.getTransactionReceipt(try utils.hashToBytes("0x388351387ada803799bec92fd8566d4f3d23e2b1208e62eea154ab4d924a974c"));

    const block = try op.getFinalizedWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
    std.debug.print("OP GAS: {any}\n\n", .{block});
}
