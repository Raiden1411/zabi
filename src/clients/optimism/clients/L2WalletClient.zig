const abi_items = @import("../abi_optimism.zig");
const clients = @import("../../root.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_utils = @import("../utils.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawal_types = @import("../types/withdrawl.zig");

const Clients = clients.wallet.WalletClients;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsIpc = clients.IpcClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LondonEthCall = transactions.LondonEthCall;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const RPCResponse = types.RPCResponse;
const Signer = @import("../../../crypto/Signer.zig");
const WithdrawalRequest = withdrawal_types.WithdrawalRequest;

const L2Client = @import("L2PubClient.zig").L2Client;

/// Optimism  wallet client used for L2 interactions.
/// Currently only supports OP and not other chains of the superchain.
/// This implementation is not as robust as the `Wallet` implementation.
pub fn L2WalletClient(client_type: Clients) type {
    return struct {
        const L2Wallet = @This();
        /// The underlaying rpc client type (ws or http)
        const ClientType = L2Client(client_type);
        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
            .ipc => InitOptsIpc,
        };

        /// The underlaying public op client. This contains the rpc_client
        op_client: *ClientType,
        /// The signer used to sign transactions
        signer: Signer,

        /// Starts the wallet client. Init options depend on the client type.
        /// This has all the expected L2 actions. If you are looking for L1 actions
        /// consider using `L1WalletClient`
        ///
        /// If the contracts are null it defaults to OP contracts.
        /// Caller must deinit after use.
        pub fn init(priv_key: ?Hash, opts: InitOpts) !*L2Wallet {
            const self = try opts.allocator.create(L2Wallet);
            errdefer opts.allocator.destroy(self);

            const op_signer = try Signer.init(priv_key);

            self.* = .{
                .op_client = try ClientType.init(opts),
                .signer = op_signer,
            };
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *L2Wallet) void {
            const child_allocator = self.op_client.allocator;

            self.op_client.deinit();

            child_allocator.destroy(self);
        }
        /// Estimates the gas cost for calling `initiateWithdrawal`
        pub fn estimateInitiateWithdrawal(self: *L2Wallet, data: Hex) !RPCResponse(Gwei) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = contracts.l2ToL1MessagePasser,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `initiateWithdrawal`. This will send
        /// a transaction to the network.
        pub fn initiateWithdrawal(self: *L2Wallet, request: WithdrawalRequest) !RPCResponse(Hash) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const address = self.signer.address_bytes;

            const prepared = try self.prepareInitiateWithdrawal(request);
            const data = try abi_items.initiate_withdrawal.encode(self.op_client.allocator, .{
                prepared.to,
                prepared.gas,
                prepared.data,
            });
            defer self.op_client.allocator.free(data);

            const gas = try self.estimateInitiateWithdrawal(data);
            defer gas.deinit();

            const call: LondonEthCall = .{
                .to = contracts.l2ToL1MessagePasser,
                .from = address,
                .gas = gas.response,
                .data = data,
                .value = prepared.value,
            };
            const fees = try self.op_client.rpc_client.estimateFeesPerGas(.{ .london = call }, null);
            const nonce = try self.op_client.rpc_client.getAddressTransactionCount(.{
                .address = self.signer.address_bytes,
                .tag = .pending,
            });
            defer nonce.deinit();

            const tx: LondonTransactionEnvelope = .{
                .gas = gas.response,
                .data = data,
                .to = contracts.l2ToL1MessagePasser,
                .value = prepared.value,
                .accessList = &.{},
                .nonce = nonce.response,
                .chainId = @intFromEnum(self.op_client.rpc_client.network_config.chain_id),
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Prepares the interaction with the contract method to `initiateWithdrawal`.
        pub fn prepareInitiateWithdrawal(self: *L2Wallet, request: WithdrawalRequest) !PreparedWithdrawal {
            const gas = gas: {
                if (request.gas) |gas| break :gas gas;

                const gas = try self.op_client.rpc_client.estimateGas(.{ .london = .{
                    .to = request.to,
                    .data = request.data,
                    .value = request.value,
                } }, .{});
                defer gas.deinit();

                break :gas gas.response;
            };

            const data = request.data orelse @constCast("");
            const value = request.value orelse 0;

            return .{
                .gas = gas,
                .value = value,
                .data = data,
                .to = request.to,
            };
        }
        /// Sends a transaction envelope to the network. This serializes, hashes and signed before
        /// sending the transaction.
        pub fn sendTransaction(self: *L2Wallet, envelope: LondonTransactionEnvelope) !RPCResponse(Hash) {
            const serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, null);
            defer self.op_client.allocator.free(serialized);

            var hash: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash, .{});

            const signed = try self.signer.sign(hash);

            const signed_serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, signed);
            defer self.op_client.allocator.free(signed_serialized);

            const tx_hash = try self.op_client.rpc_client.sendRawTransaction(signed_serialized);

            return tx_hash;
        }
    };
}
