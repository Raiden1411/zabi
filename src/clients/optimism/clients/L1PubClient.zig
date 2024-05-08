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
const Game = withdrawal_types.Game;
const GameResult = withdrawal_types.GameResult;
const Hash = types.Hash;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsIpc = clients.IpcClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const IpcClient = clients.IpcClient;
const Logs = log.Logs;
const L2Output = op_types.L2Output;
const Message = withdrawal_types.Message;
const OpMainNetContracts = contracts.OpMainNetContracts;
const ProvenWithdrawal = withdrawal_types.ProvenWithdrawal;
const PubClient = clients.PubClient;
const SemanticVersion = std.SemanticVersion;
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
            .ipc => IpcClient,
        };

        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
            .ipc => InitOptsIpc,
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
                    .ethereum, .sepolia => {},
                    else => return error.InvalidChain,
                }
            }

            try op_client.init(opts);

            self.* = .{
                .rpc_client = op_client,
                .allocator = opts.allocator,
                .contracts = op_contracts orelse .{},
            };
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *L1) void {
            self.rpc_client.deinit();
            self.allocator.destroy(self.rpc_client);
        }
        /// Retrieves a valid dispute game on an L2 that occurred after a provided L2 block number.
        /// Returns an error if no game was found.
        ///
        /// `limit` is the max amount of game to search
        ///
        /// `block_number` to filter only games that occurred after this block.
        ///
        /// `strategy` is weather to provide the latest game or one at random with the scope of the games that where found given the filters.
        pub fn getGame(self: *L1, limit: usize, block_number: u256, strategy: enum { random, latest, oldest }) !GameResult {
            const games = try self.getGames(limit, block_number);
            defer self.allocator.free(games);

            var rand = std.rand.DefaultPrng.init(block_number * limit);

            if (games.len == 0)
                return error.GameNotFound;

            switch (strategy) {
                .latest => return games[0],
                .oldest => return games[games.len - 1],
                .random => {
                    const random_int = rand.random().intRangeAtMost(usize, 0, games.len - 1);

                    return games[random_int];
                },
            }
        }
        /// Retrieves the dispute games for an L2
        ///
        /// `limit` is the max amount of game to search
        ///
        /// `block_number` to filter only games that occurred after this block.
        /// If null then it will return all games.
        pub fn getGames(self: *L1, limit: usize, block_number: ?u256) ![]const GameResult {
            const game_count_selector: []u8 = @constCast(&[_]u8{ 0x4d, 0x19, 0x75, 0xb4 });
            const game_type_selector: []u8 = @constCast(&[_]u8{ 0x3c, 0x9f, 0x39, 0x7c });

            const game_count = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.disputeGameFactory,
                .data = game_count_selector,
            } }, .{});
            defer game_count.deinit();

            const game_type = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = game_type_selector,
            } }, .{});
            defer game_type.deinit();

            const count = try utils.bytesToInt(u256, game_count.response);
            const gtype = try utils.bytesToInt(u32, game_type.response);

            const encoded = try abi_items.find_latest_games.encode(self.allocator, .{ gtype, @max(0, count - 1), @min(limit, count) });
            defer self.allocator.free(encoded);

            const games = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.disputeGameFactory,
                .data = encoded,
            } }, .{});
            defer games.deinit();

            const decoded = try decoder.decodeAbiParametersRuntime(self.allocator, struct { []const Game }, abi_items.find_latest_games.outputs, games.response, .{});
            defer self.allocator.free(decoded[0]);

            var list = std.ArrayList(GameResult).init(self.allocator);
            errdefer list.deinit();

            for (decoded[0]) |game| {
                const block_num = try utils.bytesToInt(u256, game.extraData);

                if (block_number) |number| {
                    if (number > block_num)
                        continue;
                }

                try list.ensureUnusedCapacity(1);
                list.appendAssumeCapacity(.{
                    .l2BlockNumber = block_num,
                    .index = game.index,
                    .metadata = game.metadata,
                    .timestamp = game.timestamp,
                    .rootClaim = game.rootClaim,
                });
            }

            return list.toOwnedSlice();
        }
        /// Returns if a withdrawal has finalized or not.
        pub fn getFinalizedWithdrawals(self: *L1, withdrawal_hash: Hash) !bool {
            const encoded = try abi_items.get_finalized_withdrawal.encode(self.allocator, .{withdrawal_hash});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return data.response[data.response.len - 1] != 0;
        }
        /// Gets the latest proposed L2 block number from the Oracle.
        pub fn getLatestProposedL2BlockNumber(self: *L1) !u64 {
            // Selector for `latestBlockNumber`
            const selector: []u8 = @constCast(&[_]u8{ 0x45, 0x99, 0xc7, 0x88 });

            const block = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});
            defer block.deinit();

            return utils.bytesToInt(u64, block.response);
        }

        pub fn getL2HashesForDepositTransaction(self: *L1, tx_hash: Hash) ![]const Hash {
            const deposit_data = try self.getTransactionDepositEvents(tx_hash);
            defer self.allocator.free(deposit_data);

            var list = try std.ArrayList(Hash).initCapacity(self.allocator, deposit_data.len);
            errdefer list.deinit();

            for (deposit_data) |data| {
                defer self.allocator.free(data.opaqueData);

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
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.get_l2_output_func.outputs, data.response, .{});

            const l2_output = decoded[0];

            return .{
                .outputIndex = index,
                .outputRoot = l2_output.outputRoot,
                .timestamp = l2_output.timestamp,
                .l2BlockNumber = l2_output.l2BlockNumber,
            };
        }
        /// Calls to the L2OutputOracle on L1 to get the output index.
        pub fn getL2OutputIndex(self: *L1, l2_block_number: u256) !u256 {
            const encoded = try abi_items.get_l2_index_func.encode(self.allocator, .{l2_block_number});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Retrieves the current version of the Portal contract.
        ///
        /// If the major is higher than 3 it means that fault proofs are enabled.
        pub fn getPortalVersion(self: *L1) !SemanticVersion {
            const selector_version: []u8 = @constCast(&[_]u8{ 0x54, 0xfd, 0x4d, 0x50 });
            const version = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = selector_version,
            } }, .{});
            defer version.deinit();

            const decode = try decoder.decodeAbiParameters(self.allocator, &.{
                .{ .type = .{ .string = {} }, .name = "" },
            }, version.response, .{});

            return SemanticVersion.parse(decode[0]);
        }
        /// Gets a proven withdrawl.
        pub fn getProvenWithdrawals(self: *L1, withdrawal_hash: Hash) !ProvenWithdrawal {
            const encoded = try abi_items.get_proven_withdrawal.encode(self.allocator, .{withdrawal_hash});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.portalAddress,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.get_proven_withdrawal.outputs, data.response, .{});

            const proven = decoded[0];

            if (proven.timestamp == 0)
                return error.InvalidWithdrawalHash;

            return .{
                .outputRoot = proven.outputRoot,
                .timestamp = proven.timestamp,
                .l2OutputIndex = proven.l2OutputIndex,
            };
        }
        /// Gets the amount of time to wait in ms until the next output is posted.
        pub fn getSecondsToNextL2Output(self: *L1, latest_l2_block: u64) !u128 {
            const latest = try self.getLatestProposedL2BlockNumber();

            if (latest_l2_block < latest)
                return error.InvalidBlockNumber;

            const selector: []u8 = @constCast(&[_]u8{ 0x52, 0x99, 0x33, 0xdf });

            const submission = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});
            defer submission.deinit();

            const interval = try utils.bytesToInt(i128, submission.response);

            const selector_time: []u8 = @constCast(&[_]u8{ 0x00, 0x21, 0x34, 0xcc });
            const block = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector_time,
            } }, .{});
            defer block.deinit();

            const time = try utils.bytesToInt(i128, block.response);

            const block_until: i128 = interval - (latest_l2_block - latest);

            return if (block_until < 0) @intCast(0) else @intCast(block_until * time);
        }
        /// Gets the amount of time to wait until a withdrawal is finalized.
        pub fn getSecondsToFinalize(self: *L1, withdrawal_hash: Hash) !u64 {
            const proven = try self.getProvenWithdrawals(withdrawal_hash);

            const selector: []u8 = @constCast(&[_]u8{ 0xf4, 0xda, 0xa2, 0x91 });
            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.l2OutputOracle,
                .data = selector,
            } }, .{});
            defer data.deinit();

            const time = try utils.bytesToInt(i64, data.response);
            const time_since: i64 = @divFloor(std.time.timestamp(), 1000) - @as(i64, @truncate(@as(i128, @intCast(proven.timestamp))));

            return if (time_since < 0) @intCast(0) else @intCast(time - time_since);
        }
        /// Gets the `TransactionDeposited` event logs from a transaction hash.
        ///
        /// To free the memory of this slice you will also need to loop through the
        /// returned slice and free the `opaqueData` field. Memory will be duped
        /// on that field because we destroy the Arena from the RPC request that owns
        /// the original piece of memory that contains the data.
        pub fn getTransactionDepositEvents(self: *L1, tx_hash: Hash) ![]const TransactionDeposited {
            const receipt = try self.rpc_client.getTransactionReceipt(tx_hash);
            defer receipt.deinit();

            const logs: Logs = switch (receipt.response) {
                inline else => |tx_receipt| tx_receipt.logs,
            };

            var list = std.ArrayList(TransactionDeposited).init(self.allocator);
            errdefer list.deinit();

            // Event selector for `TransactionDeposited`.
            const hash: Hash = comptime try utils.hashToBytes("0xb3813568d9991fc951961fcb4c784893574240a28925604d09fc577c55bb7c32");

            for (logs) |log_event| {
                const hash_topic: Hash = log_event.topics[0] orelse return error.ExpectedTopicData;

                if (std.mem.eql(u8, &hash, &hash_topic)) {
                    if (log_event.logIndex == null)
                        return error.UnexpectedNullIndex;

                    const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.transaction_deposited_event_data, log_event.data, .{});

                    const decoded_logs = try decoder_logs.decodeLogsComptime(abi_items.transaction_deposited_event_args, log_event.topics);

                    try list.append(.{
                        .from = decoded_logs[1],
                        .to = decoded_logs[2],
                        .version = decoded_logs[3],
                        // Needs to be duped because the arena owns this memory.
                        .opaqueData = try self.allocator.dupe(u8, decoded[0]),
                        .logIndex = log_event.logIndex.?,
                        .blockHash = log_event.blockHash.?,
                    });
                }
            }

            return try list.toOwnedSlice();
        }
        /// Gets the decoded withdrawl event logs from a given transaction receipt hash.
        pub fn getWithdrawMessages(self: *L1, tx_hash: Hash) !Message {
            const receipt_response = try self.rpc_client.getTransactionReceipt(tx_hash);
            defer receipt_response.deinit();

            const receipt = receipt_response.response;

            if (receipt != .l2_receipt)
                return error.InvalidTransactionHash;

            var list = std.ArrayList(Withdrawal).init(self.allocator);
            errdefer list.deinit();

            // The hash for the event selector `MessagePassed`
            const hash: Hash = comptime try utils.hashToBytes("0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054");

            for (receipt.l2_receipt.logs) |logs| {
                const hash_topic: Hash = logs.topics[0] orelse return error.ExpectedTopicData;

                if (std.mem.eql(u8, &hash, &hash_topic)) {
                    const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.message_passed_params, logs.data, .{});

                    const decoded_logs = try decoder_logs.decodeLogsComptime(abi_items.message_passed_indexed_params, logs.topics);

                    try list.append(.{
                        .nonce = decoded_logs[1],
                        .target = decoded_logs[2],
                        .sender = decoded_logs[3],
                        .value = decoded[0],
                        .gasLimit = decoded[1],
                        .data = decoded[2],
                        .withdrawalHash = decoded[3],
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

test "Foo" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: L1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{
        .uri = uri,
        .allocator = testing.allocator,
        .chain_id = .sepolia,
    }, .{ .portalAddress = utils.addressToBytes("0x16Fc5058F25648194471939df75CF27A2fdC48BC") catch unreachable });

    const version = try op.getPortalVersion();

    std.debug.print("Foo: {any}", .{version});
    // const games = try op.getGames(5, 69);
    // testing.allocator.free(games);
    //
    // try testing.expectEqual(games.len, 5);
}
