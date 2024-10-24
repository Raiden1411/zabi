const abi_items = @import("../abi_optimism.zig");
const clients = @import("zabi-clients");
const encoder = @import("zabi-encoding").abi_encoding;
const serialize = @import("zabi-encoding").serialize;
const std = @import("std");
const testing = std.testing;
const transactions = zabi_types.transactions;
const op_types = @import("../types/types.zig");
const op_utils = @import("../utils.zig");
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_types = @import("zabi-types");
const withdrawal_types = @import("../types/withdrawl.zig");

const Clients = clients.wallet.WalletClients;
const EncodeErrors = encoder.EncodeErrors;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LondonEthCall = transactions.LondonEthCall;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const RPCResponse = types.RPCResponse;
const Signer = @import("zabi-crypto").Signer;
const SerializeErrors = serialize.SerializeErrors;
const WithdrawalRequest = withdrawal_types.WithdrawalRequest;

const L1Client = @import("L1PubClient.zig").L1Client;

/// Optimism  wallet client used for L2 interactions.
/// Currently only supports OP and not other chains of the superchain.
/// This implementation is not as robust as the `Wallet` implementation.
pub fn L1WalletClient(client_type: Clients) type {
    return struct {
        const L1Wallet = @This();
        /// The underlaying rpc client type (ws or http)
        const PubClient = L1Client(client_type);

        /// Set of possible errors when starting a withdrawal transaction.
        pub const WithdrawalErrors = EncodeErrors || PubClient.ClientType.BasicRequestErrors ||
            SerializeErrors || Signer.SigningErrors || error{ ExpectedOpStackContracts, UnableToFetchFeeInfoFromBlock, InvalidBlockNumber };

        /// The underlaying public op client. This contains the rpc_client
        op_client: *PubClient,
        /// The signer used to sign transactions
        signer: Signer,

        /// Starts the wallet client. Init options depend on the client type.
        /// This has all the expected L2 actions. If you are looking for L1 actions
        /// consider using `L1WalletClient`
        ///
        /// If the contracts are null it defaults to OP contracts.
        /// Caller must deinit after use.
        pub fn init(priv_key: ?Hash, opts: PubClient.InitOpts) (PubClient.InitErrors || error{IdentityElement})!*L1Wallet {
            const self = try opts.allocator.create(L1Wallet);
            errdefer opts.allocator.destroy(self);

            const op_signer = try Signer.init(priv_key);

            self.* = .{
                .op_client = try PubClient.init(opts),
                .signer = op_signer,
            };

            return self;
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *L1Wallet) void {
            const child_allocator = self.op_client.allocator;

            self.op_client.deinit();

            child_allocator.destroy(self);
        }
        /// Estimates the gas cost for calling `initiateWithdrawal`
        pub fn estimateInitiateWithdrawal(self: *L1Wallet, data: Hex) (PubClient.ClientType.BasicRequestErrors || error{ExpectedOpStackContracts})!RPCResponse(Gwei) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = contracts.l2ToL1MessagePasser,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `initiateWithdrawal`. This will send
        /// a transaction to the network.
        pub fn initiateWithdrawal(self: *L1Wallet, request: WithdrawalRequest) WithdrawalErrors!RPCResponse(Hash) {
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
        pub fn prepareInitiateWithdrawal(
            self: *L1Wallet,
            request: WithdrawalRequest,
        ) PubClient.ClientType.BasicRequestErrors!PreparedWithdrawal {
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
        pub fn sendTransaction(
            self: *L1Wallet,
            envelope: LondonTransactionEnvelope,
        ) (Signer.SigningErrors || PubClient.ClientType.BasicRequestErrors || SerializeErrors)!RPCResponse(Hash) {
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
