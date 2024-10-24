const abi_items = @import("../abi_optimism.zig");
const clients = @import("zabi-clients");
const encoder = @import("zabi-encoding").abi_encoding;
const decoder = zabi_decoding.abi_decoder;
const decoder_logs = zabi_decoding.logs_decoder;
const std = @import("std");
const serialize = @import("zabi-encoding").serialize;
const testing = std.testing;
const transactions = zabi_types.transactions;
const op_types = @import("../types/types.zig");
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_decoding = @import("zabi-decoding");
const zabi_types = @import("zabi-types");
const withdrawal_types = @import("../types/withdrawl.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Clients = clients.wallet.WalletClients;
const EncodeErrors = encoder.EncodeErrors;
const DecodeErrors = decoder.DecoderErrors;
const Gwei = types.Gwei;
const Hash = types.Hash;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsIpc = clients.IpcClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const IpcClient = clients.IpcClient;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const LogsDecodeErrors = decoder_logs.LogsDecoderErrors;
const L2Output = op_types.L2Output;
const Message = withdrawal_types.Message;
const ProvenWithdrawal = withdrawal_types.ProvenWithdrawal;
const PubClient = clients.PubClient;
const SerializeErrors = serialize.SerializeErrors;
const WebSocketClient = clients.WebSocket;
const Wei = types.Wei;
const Withdrawal = withdrawal_types.Withdrawal;

/// Optimism client used for L2 interactions.
/// Currently only supports OP and not other chains of the superchain.
pub fn L2Client(comptime client_type: Clients) type {
    return struct {
        const L2 = @This();

        /// The underlaying rpc client type (ws or http)
        pub const ClientType = switch (client_type) {
            .http => PubClient,
            .websocket => WebSocketClient,
            .ipc => IpcClient,
        };

        /// Set of possible errors when checking withdrawal messages.
        const WithdrawalMessageErrors = error{
            TransactionReceiptNotFound,
            ExpectedOpStackContracts,
            ExpectedTopicData,
            InvalidTransactionHash,
            InvalidHash,
            InvalidLength,
            InvalidCharacter,
        } || ClientType.BasicRequestErrors || DecodeErrors || LogsDecodeErrors;

        /// Set of possible errors when performing op_stack client actions.
        pub const L2Errors = EncodeErrors || ClientType.BasicRequestErrors || SerializeErrors || error{ ExpectedOpStackContracts, Overflow };

        /// This is the same allocator as the rpc_client.
        /// Its a field mostly for convinience
        allocator: Allocator,
        /// The http or ws client that will be use to query the rpc server
        rpc_client: *ClientType,

        /// Starts the RPC connection
        /// If the contracts are null it defaults to OP contracts.
        pub fn init(opts: ClientType.InitOptions) (ClientType.InitErrors || error{InvalidChain})!*L2 {
            const self = try opts.allocator.create(L2);
            errdefer opts.allocator.destroy(self);

            switch (opts.network_config.chain_id) {
                .op_mainnet, .op_sepolia, .base, .zora => {},
                else => return error.InvalidChain,
            }

            self.* = .{
                .rpc_client = try ClientType.init(opts),
                .allocator = opts.allocator,
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
        pub fn estimateL1Gas(self: *L2, london_envelope: LondonTransactionEnvelope) L2Errors!Wei {
            const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);
            defer self.allocator.free(serialized);

            const encoded = try abi_items.get_l1_gas_func.encode(self.allocator, .{serialized});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = contracts.gasPriceOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Returns the L1 fee used to execute L2 transactions
        pub fn estimateL1GasFee(self: *L2, london_envelope: LondonTransactionEnvelope) L2Errors!Wei {
            const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);
            defer self.allocator.free(serialized);

            const encoded = try abi_items.get_l1_fee.encode(self.allocator, .{serialized});
            defer self.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = contracts.gasPriceOracle,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Estimates the L1 + L2 fees to execute a transaction on L2
        pub fn estimateTotalFees(self: *L2, london_envelope: LondonTransactionEnvelope) L2Errors!Wei {
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
        pub fn estimateTotalGas(self: *L2, london_envelope: LondonTransactionEnvelope) L2Errors!Wei {
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
            const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            // Selector for "l1BaseFee()"
            const selector: []u8 = @constCast(&[_]u8{ 0x51, 0x9b, 0x4b, 0xd3 });

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = contracts.gasPriceOracle,
                .data = selector,
            } }, .{});
            defer data.deinit();

            return utils.bytesToInt(u256, data.response);
        }
        /// Gets the decoded withdrawl event logs from a given transaction receipt hash.
        pub fn getWithdrawMessages(self: *L2, tx_hash: Hash) WithdrawalMessageErrors!Message {
            const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const receipt_message = try self.rpc_client.getTransactionReceipt(tx_hash);
            defer receipt_message.deinit();

            const receipt = receipt_message.response;

            switch (receipt_message.response) {
                .op_receipt => {},
                inline else => |tx_receipt| {
                    const to = tx_receipt.to orelse return error.InvalidTransactionHash;

                    const casted_to: u160 = @bitCast(to);
                    const casted_l2: u160 = @bitCast(contracts.l2ToL1MessagePasser);

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
