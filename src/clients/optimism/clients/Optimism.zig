const abi = @import("../../../abi/abi.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
const decoder = @import("../../../decoding/decoder.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_transactions = @import("../types/transaction.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");

const Allocator = std.mem.Allocator;
const Clients = @import("../../wallet.zig").WalletClients;
const DepositData = op_transactions.DepositData;
const Function = abi.Function;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsWs = clients.PubClient.InitOptions;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const OpMainNetContracts = contracts.OpMainNetContracts;
const PubClient = clients.PubClient;
const WebSocketClient = clients.WebSocket;
const Wei = types.Wei;

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

        pub fn estimateL1GasFee(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            // Abi representation of the gas price oracle `getL1Fee` function
            const func: Function = .{
                .type = .function,
                .name = "getL1Fee",
                .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
                .stateMutability = .view,
                // Not the real outputs represented in the ABI but here we don't really care for it.
                // The ABI returns a uint256 but we can just `parseInt` it
                .outputs = &.{},
            };

            const serialized = try serialize.serializeTransaction(self.allocator, .{ .london = london_envelope }, null);

            const encoded = try func.encode(self.allocator, .{serialized});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{ .to = self.contracts.gasPriceOracle, .data = hex } }, .{});

            return std.fmt.parseInt(u256, data, 0);
        }

        pub fn estimateL1Gas(self: *Optimism, london_envelope: LondonTransactionEnvelope) !Wei {
            // Abi representation of the gas price oracle `getL1GasUsed` function
            const func: Function = .{
                .type = .function,
                .name = "getL1GasUsed",
                .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
                .stateMutability = .view,
                // Not the real outputs represented in the ABI but here we don't really care for it.
                // The ABI returns a uint256 but we can just `parseInt` it
                .outputs = &.{},
            };

            const serialized = try serialize.serializeTransaction(self.client.allocator, .{ .london = london_envelope }, null);

            const encoded = try func.encode(self.allocator, .{serialized});
            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.allocator.free(hex);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.contracts.gasPriceOracle,
                .data = hex,
            } }, .{});

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
    };
}

test "Small" {
    const uri = try std.Uri.parse("");

    var op: OptimismClient(.http) = undefined;
    defer op.deinit();

    try op.init(.{ .uri = uri, .allocator = testing.allocator, .chain_id = .op_mainnet });

    const receipt = try op.rpc_client.getTransactionReceipt(try utils.hashToBytes("0x388351387ada803799bec92fd8566d4f3d23e2b1208e62eea154ab4d924a974c"));

    std.debug.print("OP GAS: {any}\n\n", .{receipt});
}
