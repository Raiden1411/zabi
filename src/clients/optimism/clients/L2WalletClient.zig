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
const DepositEnvelope = zabi_types.transactions.DepositTransactionEnvelope;
const DepositData = zabi_types.transactions.DepositData;
const EncodeErrors = encoder.EncodeErrors;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsIpc = clients.IpcClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LondonEthCall = transactions.LondonEthCall;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const RPCResponse = types.RPCResponse;
const RootProof = withdrawal_types.WithdrawalRootProof;
const SerializeErrors = serialize.SerializeErrors;
const Signer = @import("zabi-crypto").Signer;
const Withdrawal = withdrawal_types.Withdrawal;
const WithdrawalEnvelope = withdrawal_types.WithdrawalEnvelope;
const WithdrawalNoHash = withdrawal_types.WithdrawalNoHash;

const L2Client = @import("L2PubClient.zig").L2Client;

/// Optimism wallet client used for L1 interactions.
/// Currently only supports OP and not other chains of the superchain.
/// This implementation is not as robust as the `Wallet` implementation.
pub fn L2WalletClient(client_type: Clients) type {
    return struct {
        const WalletL2 = @This();

        /// The underlaying rpc client type (ws or http)
        const PubClient = L2Client(client_type);

        /// The underlaying public op client. This contains the rpc_client
        op_client: *PubClient,
        /// The signer used to sign transactions
        signer: Signer,

        /// Set of possible errors when sending deposit transactions.
        pub const DepositErrors = EncodeErrors || SerializeErrors || Signer.SigningErrors || error{
            InvalidMintValue,
            ExpectedOpStackContracts,
            InvalidAddress,
            InvalidLength,
            InvalidCharacter,
            CreatingContractToKnowAddress,
            UnableToFetchFeeInfoFromBlock,
            InvalidBlockNumber,
        };

        /// Set of possible errors when sending prove transactions.
        pub const ProveErrors = EncodeErrors || SerializeErrors || Signer.SigningErrors || error{
            ExpectedOpStackContracts,
            UnableToFetchFeeInfoFromBlock,
            InvalidBlockNumber,
        };

        /// Set of possible errors when sending finalize transactions.
        pub const FinalizeErrors = EncodeErrors || SerializeErrors || Signer.SigningErrors || error{
            ExpectedOpStackContracts,
            UnableToFetchFeeInfoFromBlock,
            InvalidBlockNumber,
        };

        /// Starts the wallet client. Init options depend on the client type.
        /// This has all the expected L1 actions. If you are looking for L2 actions
        /// consider using `L2WalletClient`
        ///
        /// If the contracts are null it defaults to OP contracts.
        /// Caller must deinit after use.
        pub fn init(priv_key: ?Hash, opts: PubClient.ClientType.InitOptions) (PubClient.ClientType.InitErrors || error{IdentityElement})!*WalletL2 {
            const self = try opts.allocator.create(WalletL2);
            errdefer opts.allocator.destroy(self);

            const op_signer = try Signer.init(priv_key);

            self.* = .{
                .op_client = try PubClient.init(opts),
                .signer = op_signer,
            };

            return self;
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *WalletL2) void {
            const child_allocator = self.op_client.allocator;

            self.op_client.deinit();

            child_allocator.destroy(self);
        }
        /// Invokes the contract method to `depositTransaction`. This will send
        /// a transaction to the network.
        pub fn depositTransaction(self: *WalletL2, deposit_envelope: DepositEnvelope) DepositErrors!RPCResponse(Hash) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

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
                .to = contracts.portalAddress,
                .from = address,
                .gas = gas.response,
                .data = data,
                .value = deposit_data.value,
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
                .to = contracts.portalAddress,
                .value = deposit_data.value,
                .accessList = &.{},
                .nonce = nonce.response,
                .chainId = @intFromEnum(self.op_client.rpc_client.network_config.chain_id),
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Estimate the gas cost for the deposit transaction.
        /// Uses the portalAddress. The data is expected to be hex abi encoded data.
        pub fn estimateDepositTransaction(self: *WalletL2, data: Hex) (PubClient.ClientType.BasicRequestErrors || error{ExpectedOpStackContracts})!RPCResponse(Gwei) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `finalizeWithdrawal`
        pub fn estimateFinalizeWithdrawal(self: *WalletL2, data: Hex) (PubClient.ClientType.BasicRequestErrors || error{ExpectedOpStackContracts})!RPCResponse(Gwei) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `proveWithdrawal`
        pub fn estimateProveWithdrawal(self: *WalletL2, data: Hex) (PubClient.ClientType.BasicRequestErrors || error{ExpectedOpStackContracts})!RPCResponse(Gwei) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `finalizeWithdrawalTransaction`. This will send
        /// a transaction to the network.
        pub fn finalizeWithdrawal(self: *WalletL2, withdrawal: WithdrawalNoHash) FinalizeErrors!RPCResponse(Hash) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const address = self.signer.address_bytes;
            const data = try abi_items.finalize_withdrawal.encode(self.op_client.allocator, .{withdrawal});
            defer self.op_client.allocator.free(data);

            const gas = try self.estimateFinalizeWithdrawal(data);
            defer gas.deinit();

            const call: LondonEthCall = .{
                .to = contracts.portalAddress,
                .from = address,
                .gas = gas.response,
                .data = data,
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
                .to = contracts.portalAddress,
                .value = 0,
                .accessList = &.{},
                .nonce = nonce.response,
                .chainId = @intFromEnum(self.op_client.rpc_client.network_config.chain_id),
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Prepares a proof withdrawal transaction.
        pub fn prepareWithdrawalProofTransaction(
            self: *WalletL2,
            withdrawal: Withdrawal,
            l2_output: L2Output,
        ) (PubClient.ClientType.BasicRequestErrors || error{ InvalidBlockNumber, ExpectedOpStackContracts })!WithdrawalEnvelope {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const storage_slot = op_utils.getWithdrawalHashStorageSlot(withdrawal.withdrawalHash);
            const proof = try self.op_client.rpc_client.getProof(.{
                .address = contracts.l2ToL1MessagePasser,
                .storageKeys = &.{storage_slot},
                .blockNumber = @intCast(l2_output.l2BlockNumber),
            }, null);
            defer proof.deinit();

            const block = try self.op_client.rpc_client.getBlockByNumber(.{ .block_number = @intCast(l2_output.l2BlockNumber) });
            defer block.deinit();

            const block_info: struct { stateRoot: Hash, hash: Hash } = switch (block.response) {
                inline else => |block_info| .{ .stateRoot = block_info.stateRoot, .hash = block_info.hash.? },
            };

            var proofs = try std.ArrayList([]u8).initCapacity(self.op_client.allocator, proof.response.storageProof[0].proof.len);
            errdefer proofs.deinit();

            for (proof.response.storageProof[0].proof) |p| {
                proofs.appendAssumeCapacity(try self.op_client.allocator.dupe(u8, p));
            }

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
                    .messagePasserStorageRoot = proof.response.storageHash,
                    .latestBlockhash = block_info.hash,
                },
                .withdrawalProof = try proofs.toOwnedSlice(),
                .l2OutputIndex = l2_output.outputIndex,
            };
        }
        /// Invokes the contract method to `proveWithdrawalTransaction`. This will send
        /// a transaction to the network.
        pub fn proveWithdrawal(
            self: *WalletL2,
            withdrawal: WithdrawalNoHash,
            l2_output_index: u256,
            outputRootProof: RootProof,
            withdrawal_proof: []const Hex,
        ) ProveErrors!RPCResponse(Hash) {
            const contracts = self.op_client.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

            const address = self.signer.address_bytes;
            const data = try abi_items.prove_withdrawal.encode(self.op_client.allocator, .{
                withdrawal, l2_output_index, outputRootProof, withdrawal_proof,
            });
            defer self.op_client.allocator.free(data);

            const gas = try self.estimateProveWithdrawal(data);
            defer gas.deinit();

            const call: LondonEthCall = .{
                .to = contracts.portalAddress,
                .from = address,
                .gas = gas.response,
                .data = data,
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
                .to = contracts.portalAddress,
                .value = 0,
                .accessList = &.{},
                .nonce = nonce.response,
                .chainId = @intFromEnum(self.op_client.rpc_client.network_config.chain_id),
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Prepares the deposit transaction. Will error if its a creation transaction
        /// and a `to` address was given. It will also fail if the mint and value do not match.
        pub fn prepareDepositTransaction(
            self: *WalletL2,
            deposit_envelope: DepositEnvelope,
        ) (PubClient.ClientType.BasicRequestErrors || error{ CreatingContractToKnowAddress, InvalidMintValue })!DepositData {
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
        /// Sends a transaction envelope to the network. This serializes, hashes and signed before
        /// sending the transaction.
        pub fn sendTransaction(
            self: *WalletL2,
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
