const abi_items = @import("../abi.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_transactions = @import("../types/transaction.zig");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawal_types = @import("../types/withdrawl.zig");

const Clients = clients.wallet.WalletClients;
const DepositEnvelope = op_transactions.DepositTransactionEnvelope;
const DepositData = op_transactions.DepositData;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LondonEthCall = transactions.LondonEthCall;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const OpMainNetContracts = contracts.OpMainNetContracts;
const RPCResponse = types.RPCResponse;
const Signer = @import("../../../crypto/signer.zig");

const L1Client = @import("L1PubClient.zig").L1Client;

/// Optimism wallet client used for L1 interactions.
/// Currently only supports OP and not other chains of the superchain.
/// This implementation is not as robust as the `Wallet` implementation.
pub fn WalletL1Client(client_type: Clients) type {
    return struct {
        const WalletL1 = @This();

        /// The underlaying rpc client type (ws or http)
        const ClientType = L1Client(client_type);
        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
        };
        /// The underlaying public op client. This contains the rpc_client
        op_client: *ClientType,
        /// The signer used to sign transactions
        signer: Signer,
        /// The wallet nonce that will be used to send transactions
        wallet_nonce: u64 = 0,

        /// Starts the wallet client. Init options depend on the client type.
        /// This has all the expected L1 actions. If you are looking for L2 actions
        /// consider using `L2WalletClient`
        ///
        /// If the contracts are null it defaults to OP contracts.
        /// Caller must deinit after use.
        pub fn init(self: *WalletL1, priv_key: ?Hash, opts: InitOpts, op_contracts: ?OpMainNetContracts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            try op_client.init(opts, op_contracts);
            errdefer op_client.deinit();

            const op_signer = try Signer.init(priv_key);

            self.* = .{
                .op_client = op_client,
                .signer = op_signer,
            };

            const nonce = try self.op_client.rpc_client.getAddressTransactionCount(.{
                .address = op_signer.address_bytes,
            });
            defer nonce.deinit();

            self.wallet_nonce = nonce.response;
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *WalletL1) void {
            const child_allocator = self.op_client.allocator;

            self.op_client.deinit();

            child_allocator.destroy(self.op_client);

            self.* = undefined;
        }
        /// Prepares the deposit transaction. Will error if its a creation transaction
        /// and a `to` address was given. It will also fail if the mint and value do not match.
        pub fn prepareDepositTransaction(self: *WalletL1, deposit_envelope: DepositEnvelope) !DepositData {
            const mint = deposit_envelope.mint orelse 0;
            const value = deposit_envelope.value orelse 0;
            const data = deposit_envelope.data orelse @constCast("");

            if (deposit_envelope.creation and deposit_envelope.to != null)
                return error.CreatingContractToKnowAddress;

            if (mint != value)
                return error.InvalidMintValue;

            const gas = gas: {
                if (deposit_envelope.gas) |gas| break :gas gas;

                const gas = try self.op_client.rpc_client.estimateGas(.{ .london = .{
                    .value = value,
                    .to = deposit_envelope.to,
                    .from = self.signer.address_bytes,
                } }, .{});
                defer gas.deinit();

                break :gas gas.response;
            };

            return .{
                .value = value,
                .gas = gas,
                .creation = deposit_envelope.creation,
                .data = data,
                .mint = mint,
            };
        }
        /// Estimate the gas cost for the deposit transaction.
        /// Uses the portalAddress. The data is expected to be hex abi encoded data.
        pub fn estimateDepositTransaction(self: *WalletL1, data: Hex) !RPCResponse(Gwei) {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `depositTransaction`. This will send
        /// a transaction to the network.
        pub fn depositTransaction(self: *WalletL1, deposit_envelope: DepositEnvelope) !RPCResponse(Hash) {
            const address = self.signer.address_bytes;
            const deposit_data = try self.prepareDepositTransaction(deposit_envelope);

            const data = try abi_items.deposit_transaction.encode(self.op_client.allocator, .{
                if (deposit_data.creation)
                    comptime try utils.addressToBytes("0x0000000000000000000000000000000000000000")
                else
                    deposit_envelope.to orelse return error.ExpectedToAddress,
                deposit_data.mint,
                deposit_data.gas,
                deposit_data.creation,
                deposit_data.data.?,
            });
            defer self.op_client.allocator.free(data);

            const gas = try self.estimateDepositTransaction(data);
            defer gas.deinit();

            const call: LondonEthCall = .{
                .to = self.op_client.contracts.portalAddress,
                .from = address,
                .gas = gas.response,
                .data = data,
                .value = deposit_data.value,
            };

            const fees = try self.op_client.rpc_client.estimateFeesPerGas(.{ .london = call }, null);

            const tx: LondonTransactionEnvelope = .{
                .gas = gas.response,
                .data = data,
                .to = self.op_client.contracts.portalAddress,
                .value = deposit_data.value,
                .accessList = &.{},
                .nonce = self.wallet_nonce,
                .chainId = self.op_client.rpc_client.chain_id,
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Sends a transaction envelope to the network. This serializes, hashes and signed before
        /// sending the transaction.
        pub fn sendTransaction(self: *WalletL1, envelope: LondonTransactionEnvelope) !RPCResponse(Hash) {
            const serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, null);
            defer self.op_client.allocator.free(serialized);

            var hash: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash, .{});

            const signed = try self.signer.sign(hash);

            const signed_serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, signed);
            defer self.op_client.allocator.free(signed_serialized);

            const tx_hash = try self.op_client.rpc_client.sendRawTransaction(signed_serialized);
            self.wallet_nonce += 1;

            return tx_hash;
        }
    };
}
