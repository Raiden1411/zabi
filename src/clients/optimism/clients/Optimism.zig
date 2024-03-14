const abi = @import("../../../abi/abi.zig");
const abi_items = @import("../abi.zig");
const abi_parameter = @import("../../../abi/abi_parameter.zig");
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
const InitOptsWs = clients.WebSocket.InitOptions;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const Message = withdrawl_types.Message;
const OpMainNetContracts = contracts.OpMainNetContracts;
const PubClient = clients.PubClient;
const WebSocketClient = clients.WebSocket;
const Wei = types.Wei;
const Withdrawl = withdrawl_types.Withdrawl;
const WithdrawlEnvelope = withdrawl_types.WithdrawlEnvelope;

pub fn OptimismClient(comptime client_type: Clients) type {
    return struct {
        const Optimism = @This();

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

        pub fn init(self: *Optimism, opts: InitOpts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            try op_client.init(opts);

            self.* = .{
                .rpc_client = op_client,
                .allocator = op_client.allocator,
            };
        }

        pub fn deinit(self: *Optimism) void {
            const child_allocator = self.rpc_client.arena.child_allocator;

            self.rpc_client.deinit();
            child_allocator.destroy(self.rpc_client);

            self.* = undefined;
        }

        pub fn estimateL1Gas(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            const serialized = try serialize.serializeTransaction(self.client.allocator, .{ .london = london_envelope }, null);

            const encoded = try abi_items.get_l1_gas_func.encode(self.allocator, .{serialized});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = hex,
            } }, .{});

            return std.fmt.parseInt(u256, data, 0);
        }

        pub fn estimateL1GasFee(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);

            const encoded = try abi_items.get_l1_fee.encode(self.allocator, .{serialized});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{ .to = self.contracts.gasPriceOracle, .data = hex } }, .{});

            return std.fmt.parseInt(u256, data, 0);
        }

        pub fn estimateTotalFees(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            const l1_gas_fee = try self.estimateL1GasFee(london_envelope);
            const l2_gas = try self.rpc_client.estimateGas(.{ .london = .{
                .to = london_envelope.to,
                .data = london_envelope.data,
                .maxFeePerGas = london_envelope.maxFeePerGas,
                .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
                .value = london_envelope.value,
            } }, .{});
            const gas_price = try self.rpc_client.getGasPrice();

            return l1_gas_fee + l2_gas * gas_price;
        }

        pub fn estimateTotalGas(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            const l1_gas_fee = try self.estimateL1GasFee(london_envelope);
            const l2_gas = try self.rpc_client.estimateGas(.{ .london = .{
                .to = london_envelope.to,
                .data = london_envelope.data,
                .maxFeePerGas = london_envelope.maxFeePerGas,
                .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
                .value = london_envelope.value,
            } }, .{});

            return l1_gas_fee + l2_gas;
        }

        pub fn getBaseL1Fee(self: *Optimism) !Wei {
            // Selector for l1BaseFee();
            // We can get away with it since the abi has no input args.
            const selector: []const u8 = "0x519b4bd3";

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = selector,
            } }, .{});

            return std.fmt.parseInt(u256, data, 0);
        }

        pub fn getWithdrawMessages(self: *Optimism, tx_hash: Hash) !Message {
            const receipt = try self.rpc_client.getTransactionReceipt(tx_hash);

            if (receipt != .optimism)
                return error.InvalidTransactionHash;

            var list = std.ArrayList(Withdrawl).init(self.allocator);
            errdefer list.deinit();

            const hash: []const u8 = "0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054";

            const ReturnType = struct { []const u8, u256, Address, Address };
            for (receipt.optimism.logs) |log| {
                if (std.mem.eql(u8, hash, log.topics[0] orelse return error.ExpectedTopicData)) {
                    const decoded = try decoder.decodeAbiParameters(self.allocator, abi_items.message_passed_params, log.data, .{});
                    defer decoded.deinit();

                    const decoded_logs = try decoder_logs.decodeLogs(self.allocator, ReturnType, abi_items.message_passed_indexed_params, log.topics);
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
                .blockNumber = receipt.optimism.blockNumber.?,
                .messages = messages,
            };
        }

        pub fn prepareWithdrawlProofTransaction(self: *Optimism, withdrawl: Withdrawl, l2_output: L2Output) !WithdrawlEnvelope {
            const storage_slot = op_utils.getWithdrawlHashStorageSlot(withdrawl.withdrawalHash);
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
                .nonce = withdrawl.nonce,
                .sender = withdrawl.sender,
                .target = withdrawl.target,
                .value = withdrawl.value,
                .gasLimit = withdrawl.gasLimit,
                .data = withdrawl.data,
                .outputRootProof = .{
                    .version = [_]u8{0} ** 32,
                    .stateRoot = block_info.stateRoot,
                    .messagePasserStorageRoot = proof.storageHash,
                    .latestBlockHash = block_info.hash,
                },
                .withdrawlProof = proof.storageProof[0].proof,
                .l2OutputIndex = l2_output.outputIndex,
            };
        }
    };
}

// test "Small" {
//     const uri = try std.Uri.parse("https://sepolia.optimism.io");
//
//     var op: OptimismClient(.http) = undefined;
//     defer op.deinit();
//
//     try op.init(.{ .uri = uri, .allocator = testing.allocator, .chain_id = .op_sepolia });
//
//     const messages = try op.getWithdrawMessages(try utils.hashToBytes(""));
//     // const receipt = try op.rpc_client.getTransactionReceipt(try utils.hashToBytes("0x388351387ada803799bec92fd8566d4f3d23e2b1208e62eea154ab4d924a974c"));
//
//     std.debug.print("OP GAS: {any}\n\n", .{messages});
// }
