const abi_items = @import("../abi.zig");
const clients = @import("../../root.zig");
const serialize = @import("../../../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transactions = @import("../../../types/transaction.zig");
const op_types = @import("../types/types.zig");
const op_utils = @import("../utils.zig");
const signer = @import("secp256k1");
const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../utils/utils.zig");
const withdrawal_types = @import("../types/withdrawl.zig");

const Clients = clients.wallet.WalletClients;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const InitOptsHttp = clients.PubClient.InitOptions;
const InitOptsWs = clients.WebSocket.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LondonEthCall = transactions.LondonEthCall;
const LondonTransactionEnvelope = transactions.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const RootProof = withdrawal_types.WithdrawalRootProof;
const Signer = signer.Signer;
const Withdrawal = withdrawal_types.Withdrawal;
const WithdrawalEnvelope = withdrawal_types.WithdrawalEnvelope;
const WithdrawalNoHash = withdrawal_types.WithdrawalNoHash;
const WithdrawalRequest = withdrawal_types.WithdrawalRequest;

const OptimismClient = @import("Optimism.zig").OptimismClient;

/// Optimism  wallet client used for L2 interactions.
/// Currently only supports OP and not other chains of the superchain.
/// This implementation is not as robust as the `Wallet` implementation.
pub fn WalletOptimismClient(client_type: Clients) type {
    return struct {
        const WalletOptimism = @This();
        /// The underlaying rpc client type (ws or http)
        const ClientType = OptimismClient(client_type);
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
        /// This has all the expected L2 actions. If you are looking for L1 actions
        /// consider using `WalletOptimismL1Client`
        /// Caller must deinit after use.
        pub fn init(self: *WalletOptimism, priv_key: []const u8, opts: InitOpts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            try op_client.init(opts);
            errdefer op_client.deinit();

            const op_signer = try Signer.init(priv_key);

            self.* = .{
                .op_client = op_client,
                .signer = op_signer,
            };

            self.wallet_nonce = try self.op_client.rpc_client.getAddressTransactionCount(.{
                .address = try op_signer.getAddressFromPublicKey(),
            });
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *WalletOptimism) void {
            const child_allocator = self.op_client.rpc_client.arena.child_allocator;

            self.op_client.deinit();
            self.signer.deinit();

            child_allocator.destroy(self.op_client);

            self.* = undefined;
        }
        /// Estimates the gas cost for calling `finalizeWithdrawal`
        pub fn estimateFinalizeWithdrawal(self: *WalletOptimism, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `initiateWithdrawal`
        pub fn estimateInitiateWithdrawal(self: *WalletOptimism, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.l2ToL1MessagePasser,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `proveWithdrawal`
        pub fn estimateProveWithdrawal(self: *WalletOptimism, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `initiateWithdrawal`. This will send
        /// a transaction to the network.
        pub fn initiateWithdrawal(self: *WalletOptimism, request: WithdrawalRequest) !Hash {
            const address = try self.signer.getAddressFromPublicKey();

            const prepared = try self.prepareInitiateWithdrawal(request);
            const data = try abi_items.initiate_withdrawal.encode(self.op_client.allocator, .{
                prepared.to,
                prepared.gas,
                prepared.data,
            });

            const hex_data = try std.fmt.allocPrint(self.op_client.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(data)});
            defer self.op_client.allocator.free(hex_data);

            const gas = try self.estimateInitiateWithdrawal(hex_data);

            const call: LondonEthCall = .{
                .to = self.op_client.contracts.l2ToL1MessagePasser,
                .from = address,
                .gas = gas,
                .data = data,
                .value = prepared.value,
            };
            const fees = try self.op_client.rpc_client.estimateFeesPerGas(.{ .london = call }, null);

            const tx: LondonTransactionEnvelope = .{
                .gas = gas,
                .data = hex_data,
                .to = self.op_client.contracts.l2ToL1MessagePasser,
                .value = prepared.value,
                .accessList = &.{},
                .nonce = self.wallet_nonce,
                .chainId = self.op_client.rpc_client.chain_id,
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Prepares the interaction with the contract method to `initiateWithdrawal`.
        pub fn prepareInitiateWithdrawal(self: *WalletOptimism, request: WithdrawalRequest) !PreparedWithdrawal {
            const gas = request.gas orelse try self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = request.to,
                .data = request.data,
                .value = request.value,
            } }, .{});
            const data = request.data orelse "";
            const value = request.value orelse 0;

            return .{
                .gas = gas,
                .value = value,
                .data = data,
                .to = request.to,
            };
        }
        /// Invokes the contract method to `finalizeWithdrawalTransaction`. This will send
        /// a transaction to the network.
        pub fn finalizeWithdrawal(self: *WalletOptimism, withdrawal: WithdrawalNoHash) !Hash {
            const address = try self.signer.getAddressFromPublicKey();
            const data = try abi_items.finalize_withdrawal.encode(self.op_client.allocator, .{withdrawal});

            const hex_data = try std.fmt.allocPrint(self.op_client.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(data)});
            defer self.op_client.allocator.free(hex_data);

            std.debug.print("Hex: {s}\n", .{hex_data});
            const gas = try self.estimateFinalizeWithdrawal(hex_data);

            const call: LondonEthCall = .{
                .to = self.op_client.contracts.portalAddress,
                .from = address,
                .gas = gas,
                .data = hex_data,
            };

            const fees = try self.op_client.rpc_client.estimateFeesPerGas(.{ .london = call }, null);

            const tx: LondonTransactionEnvelope = .{
                .gas = gas,
                .data = hex_data,
                .to = self.op_client.contracts.portalAddress,
                .value = 0,
                .accessList = &.{},
                .nonce = self.wallet_nonce,
                .chainId = self.op_client.rpc_client.chain_id,
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Invokes the contract method to `proveWithdrawalTransaction`. This will send
        /// a transaction to the network.
        pub fn proveWithdrawal(self: *WalletOptimism, withdrawal: WithdrawalNoHash, l2_output_index: u256, outputRootProof: RootProof, withdrawal_proof: []const Hex) !Hash {
            const address = try self.signer.getAddressFromPublicKey();
            const data = try abi_items.prove_withdrawal.encode(self.op_client.allocator, .{
                withdrawal, l2_output_index, outputRootProof, withdrawal_proof,
            });

            const hex_data = try std.fmt.allocPrint(self.op_client.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(data)});
            defer self.op_client.allocator.free(hex_data);

            const gas = try self.estimateProveWithdrawal(hex_data);

            const call: LondonEthCall = .{
                .to = self.op_client.contracts.portalAddress,
                .from = address,
                .gas = gas,
                .data = hex_data,
            };

            const fees = try self.op_client.rpc_client.estimateFeesPerGas(.{ .london = call }, null);

            const tx: LondonTransactionEnvelope = .{
                .gas = gas,
                .data = hex_data,
                .to = self.op_client.contracts.portalAddress,
                .value = 0,
                .accessList = &.{},
                .nonce = self.wallet_nonce,
                .chainId = self.op_client.rpc_client.chain_id,
                .maxFeePerGas = fees.london.max_fee_gas,
                .maxPriorityFeePerGas = fees.london.max_priority_fee,
            };

            return self.sendTransaction(tx);
        }
        /// Prepares a proof withdrawal transaction.
        pub fn prepareWithdrawalProofTransaction(self: *WalletOptimism, withdrawal: Withdrawal, l2_output: L2Output) !WithdrawalEnvelope {
            const storage_slot = op_utils.getWithdrawlHashStorageSlot(withdrawal.withdrawalHash);
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
                .nonce = withdrawal.nonce,
                .sender = withdrawal.sender,
                .target = withdrawal.target,
                .value = withdrawal.value,
                .gasLimit = withdrawal.gasLimit,
                .data = withdrawal.data,
                .outputRootProof = .{
                    .version = [_]u8{0} ** 32,
                    .stateRoot = block_info.stateRoot,
                    .messagePasserStorageRoot = proof.storageHash,
                    .latestBlockHash = block_info.hash,
                },
                .withdrawalProof = proof.storageProof[0].proof,
                .l2OutputIndex = l2_output.outputIndex,
            };
        }
        /// Sends a transaction envelope to the network. This serializes, hashes and signed before
        /// sending the transaction.
        pub fn sendTransaction(self: *WalletOptimism, envelope: LondonTransactionEnvelope) !Hash {
            const serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, null);
            defer self.op_client.allocator.free(serialized);

            var hash: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash, .{});

            const signed = try self.signer.sign(hash);

            const signed_serialized = try serialize.serializeTransaction(self.op_client.allocator, .{ .london = envelope }, signed);
            defer self.op_client.allocator.free(signed_serialized);

            const hexed = try std.fmt.allocPrint(self.op_client.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(signed_serialized)});
            defer self.op_client.allocator.free(hexed);

            const tx_hash = try self.op_client.rpc_client.sendRawTransaction(hexed);
            self.wallet_nonce += 1;

            return tx_hash;
        }
    };
}

test "Small" {
    var wallet_op: WalletOptimismClient(.http) = undefined;
    defer wallet_op.deinit();

    const uri = try std.Uri.parse("http://localhost:8545/");
    try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
        .allocator = testing.allocator,
        .uri = uri,
        .chain_id = .op_mainnet,
    });

    const hash = try wallet_op.initiateWithdrawal(.{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    });

    std.debug.print("HASH: {s}\n", .{std.fmt.fmtSliceHexLower(&hash)});
}
