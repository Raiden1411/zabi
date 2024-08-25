const abi_items = @import("../abi_optimism.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
const decoder = @import("../../../decoding/decoder.zig");
const decoder_logs = @import("../../../decoding/logs_decode.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_transactions = @import("../types/transaction.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawal_types = @import("../types/withdrawl.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Clients = @import("../../wallet.zig").WalletClients;
const Gwei = types.Gwei;
const Hash = types.Hash;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsIpc = clients.IpcClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const IpcClient = clients.IpcClient;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const Message = withdrawal_types.Message;
const OpMainNetContracts = contracts.OpMainNetContracts;
const ProvenWithdrawal = withdrawal_types.ProvenWithdrawal;
const PubClient = clients.PubClient;
const WebSocketClient = clients.WebSocket;
const Wei = types.Wei;
const Withdrawal = withdrawal_types.Withdrawal;

/// Optimism client used for L2 interactions.
/// Currently only supports OP and not other chains of the superchain.
pub fn L2Client(comptime client_type: Clients) type {
    return struct {
        const L2 = @This();

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
        pub fn init(opts: InitOpts, op_contracts: ?OpMainNetContracts) !*L2 {
            const self = try opts.allocator.create(L2);
            errdefer opts.allocator.destroy(self);

            if (opts.chain_id) |id| {
                switch (id) {
                    .op_mainnet, .op_sepolia, .base, .zora => {},
                    else => return error.InvalidChain,
                }
            } else return error.ExpectedChainId;

            self.* = .{
                .rpc_client = try ClientType.init(opts),
                .allocator = opts.allocator,
                .contracts = op_contracts orelse .{},
            };

            return self;
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *L2) void {
            const child_allocator = self.allocator;

            self.rpc_client.deinit();
            child_allocator.destroy(self);
        }
        /// Returns the L1 gas used to execute L2 transactions
        pub fn estimateL1Gas(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei {
            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);
            defer self.allocator.free(serialized);

            const encoded = try abi_items.get_l1_gas_func.encode(self.allocator, .{serialized});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Returns the L1 fee used to execute L2 transactions
        pub fn estimateL1GasFee(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei {
            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);
            defer self.allocator.free(serialized);

            const encoded = try abi_items.get_l1_fee.encode(self.allocator, .{serialized});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Estimates the L1 + L2 fees to execute a transaction on L2
        pub fn estimateTotalFees(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei {
            const l1_gas_fee = try self.estimateL1GasFee(london_envelope);
            const l2_gas = try self.rpc_client.estimateGas(.{ .london = .{
                .to = london_envelope.to,
                .data = london_envelope.data,
                .maxFeePerGas = london_envelope.maxFeePerGas,
                .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
                .value = london_envelope.value,
            } }, .{});
            defer l2_gas.deinit();

            const gas_price = try self.rpc_client.getGasPrice();
            defer gas_price.deinit();

            return l1_gas_fee + l2_gas.response * gas_price.response;
        }
        /// Estimates the L1 + L2 gas to execute a transaction on L2
        pub fn estimateTotalGas(self: *L2, london_envelope: LondonTransactionEnvelope) !Wei {
            const l1_gas_fee = try self.estimateL1GasFee(london_envelope);
            const l2_gas = try self.rpc_client.estimateGas(.{ .london = .{
                .to = london_envelope.to,
                .data = london_envelope.data,
                .maxFeePerGas = london_envelope.maxFeePerGas,
                .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
                .value = london_envelope.value,
            } }, .{});
            defer l2_gas.deinit();

            return l1_gas_fee + l2_gas.response;
        }
        /// Returns the base fee on L1
        pub fn getBaseL1Fee(self: *L2) !Wei {
            // Selector for "l1BaseFee()"
            const selector: []u8 = @constCast(&[_]u8{ 0x51, 0x9b, 0x4b, 0xd3 });

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = selector,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Gets the decoded withdrawl event logs from a given transaction receipt hash.
        pub fn getWithdrawMessages(self: *L2, tx_hash: Hash) !Message {
            const receipt_message = try self.rpc_client.getTransactionReceipt(tx_hash);
            defer receipt_message.deinit();

            const receipt = receipt_message.response;

            switch (receipt_message.response) {
                .op_receipt => {},
                inline else => |tx_receipt| {
                    const to = tx_receipt.to orelse return error.InvalidTransactionHash;

                    const casted_to: u160 = @bitCast(to);
                    const casted_l2: u160 = @bitCast(self.contracts.l2ToL1MessagePasser);

                    if (casted_to != casted_l2)
                        return error.InvalidTransactionHash;
                },
            }

            var list = std.ArrayList(Withdrawal).init(self.allocator);
            errdefer list.deinit();

            // The hash for the event selector `MessagePassed`
            const hash: Hash = comptime try utils.hashToBytes("0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054");

            const logs = switch (receipt) {
                inline else => |tx_receipt| tx_receipt.logs,
            };

            for (logs) |log| {
                const topic_hash: Hash = log.topics[0] orelse return error.ExpectedTopicData;
                if (std.mem.eql(u8, &hash, &topic_hash)) {
                    const decoded = try decoder.decodeAbiParameterLeaky(struct { u256, u256, []u8, Hash }, self.allocator, log.data, .{});

                    const decoded_logs = try decoder_logs.decodeLogs(struct { Hash, u256, Address, Address }, log.topics, .{});

                    try list.ensureUnusedCapacity(1);
                    list.appendAssumeCapacity(.{
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

            const block = switch (receipt) {
                inline else => |tx_receipt| tx_receipt.blockNumber,
            };

            return .{
                .blockNumber = block.?,
                .messages = messages,
            };
        }
    };
}
