const abi = @import("../../../abi/abi.zig");
const abi_items = @import("../abi.zig");
const abi_parameter = @import("../../../abi/abi_parameter.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
const decoder = @import("../../../decoding/decoder.zig");
const decoder_logs = @import("../../../decoding/logs_decode.zig");
const log = @import("../../../types/log.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_transactions = @import("../types/transaction.zig");
const op_utils = @import("../utils.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawl_types = @import("../types/withdrawl.zig");

const AbiParameter = abi_parameter.AbiParameter;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Clients = @import("../../wallet.zig").WalletClients;
const DepositData = op_transactions.DepositData;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsWs = clients.PubClient.InitOptions;
const Logs = log.Logs;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const Message = withdrawl_types.Message;
const OpMainNetContracts = contracts.OpMainNetContracts;
const PubClient = clients.PubClient;
const TransactionDeposited = op_transactions.TransactionDeposited;
const WebSocketClient = clients.WebSocket;
const Wei = types.Wei;
const Withdrawl = withdrawl_types.Withdrawl;
const WithdrawlEnvelope = withdrawl_types.WithdrawlEnvelope;

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
    };
}

test "Small" {
    const uri = try std.Uri.parse("http://localhost:8545/");

    var op: OptimismL1Client(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator });

    const messages = try op.getL2HashesForDepositTransaction(try utils.hashToBytes("0x33faeeee9c6d5e19edcdfc003f329c6652f05502ffbf3218d9093b92589a42c4"));
    // const receipt = try op.rpc_client.getTransactionReceipt(try utils.hashToBytes("0x388351387ada803799bec92fd8566d4f3d23e2b1208e62eea154ab4d924a974c"));

    std.debug.print("OP GAS: {any}\n\n", .{std.fmt.fmtSliceHexLower(&messages[0])});
}
