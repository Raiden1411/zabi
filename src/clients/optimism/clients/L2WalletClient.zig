const abi_items = @import("../abi.zig");
const clients = @import("../../root.zig");
const contracts = @import("../contracts.zig");
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
const OpMainNetContracts = contracts.OpMainNetContracts;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const RootProof = withdrawal_types.WithdrawalRootProof;
const Signer = signer.Signer;
const Withdrawal = withdrawal_types.Withdrawal;
const WithdrawalEnvelope = withdrawal_types.WithdrawalEnvelope;
const WithdrawalNoHash = withdrawal_types.WithdrawalNoHash;
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
        };

        /// The underlaying public op client. This contains the rpc_client
        op_client: *ClientType,
        /// The signer used to sign transactions
        signer: Signer,
        /// The wallet nonce that will be used to send transactions
        wallet_nonce: u64 = 0,

        /// Starts the wallet client. Init options depend on the client type.
        /// This has all the expected L2 actions. If you are looking for L1 actions
        /// consider using `L1WalletClient`
        ///
        /// If the contracts are null it defaults to OP contracts.
        /// Caller must deinit after use.
        pub fn init(self: *L2Wallet, priv_key: []const u8, opts: InitOpts, op_contracts: ?OpMainNetContracts) !void {
            const op_client = try opts.allocator.create(ClientType);
            errdefer opts.allocator.destroy(op_client);

            try op_client.init(opts, op_contracts);
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
        pub fn deinit(self: *L2Wallet) void {
            const child_allocator = self.op_client.rpc_client.arena.child_allocator;

            self.op_client.deinit();
            self.signer.deinit();

            child_allocator.destroy(self.op_client);

            self.* = undefined;
        }
        /// Estimates the gas cost for calling `finalizeWithdrawal`
        pub fn estimateFinalizeWithdrawal(self: *L2Wallet, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `initiateWithdrawal`
        pub fn estimateInitiateWithdrawal(self: *L2Wallet, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.l2ToL1MessagePasser,
                .data = data,
            } }, .{});
        }
        /// Estimates the gas cost for calling `proveWithdrawal`
        pub fn estimateProveWithdrawal(self: *L2Wallet, data: Hex) !Gwei {
            return self.op_client.rpc_client.estimateGas(.{ .london = .{
                .to = self.op_client.contracts.portalAddress,
                .data = data,
            } }, .{});
        }
        /// Invokes the contract method to `initiateWithdrawal`. This will send
        /// a transaction to the network.
        pub fn initiateWithdrawal(self: *L2Wallet, request: WithdrawalRequest) !Hash {
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
        pub fn prepareInitiateWithdrawal(self: *L2Wallet, request: WithdrawalRequest) !PreparedWithdrawal {
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
        pub fn finalizeWithdrawal(self: *L2Wallet, withdrawal: WithdrawalNoHash) !Hash {
            const address = try self.signer.getAddressFromPublicKey();
            const data = try abi_items.finalize_withdrawal.encode(self.op_client.allocator, .{withdrawal});

            const hex_data = try std.fmt.allocPrint(self.op_client.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(data)});
            defer self.op_client.allocator.free(hex_data);

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
        pub fn proveWithdrawal(self: *L2Wallet, withdrawal: WithdrawalNoHash, l2_output_index: u256, outputRootProof: RootProof, withdrawal_proof: []const Hex) !Hash {
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
        pub fn prepareWithdrawalProofTransaction(self: *L2Wallet, withdrawal: Withdrawal, l2_output: L2Output) !WithdrawalEnvelope {
            const storage_slot = op_utils.getWithdrawalHashStorageSlot(withdrawal.withdrawalHash);
            const proof = try self.op_client.rpc_client.getProof(.{
                .address = self.op_client.contracts.l2ToL1MessagePasser,
                .storageKeys = &.{storage_slot},
                .blockNumber = @intCast(l2_output.l2BlockNumber),
            }, null);

            const block = try self.op_client.rpc_client.getBlockByNumber(.{ .block_number = @intCast(l2_output.l2BlockNumber) });
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
                    .latestBlockhash = block_info.hash,
                },
                .withdrawalProof = proof.storageProof[0].proof,
                .l2OutputIndex = l2_output.outputIndex,
            };
        }
        /// Sends a transaction envelope to the network. This serializes, hashes and signed before
        /// sending the transaction.
        pub fn sendTransaction(self: *L2Wallet, envelope: LondonTransactionEnvelope) !Hash {
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

test "InitiateWithdrawal" {
    var wallet_op: L2WalletClient(.http) = undefined;
    defer wallet_op.deinit();

    const uri = try std.Uri.parse("http://localhost:8544/");
    try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
        .allocator = testing.allocator,
        .uri = uri,
        .chain_id = .op_mainnet,
    }, null);

    _ = try wallet_op.initiateWithdrawal(.{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    });
}

test "PrepareWithdrawalProofTransaction" {
    std.time.sleep(std.time.ns_per_ms * 500);
    var wallet_op: L2WalletClient(.http) = undefined;
    defer wallet_op.deinit();

    const uri = try std.Uri.parse("http://localhost:8544/");
    try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
        .allocator = testing.allocator,
        .uri = uri,
        .chain_id = .op_mainnet,
    }, null);

    const args: WithdrawalEnvelope = .{
        .l2OutputIndex = 4529,
        .outputRootProof = .{
            .version = try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000000"),
            .stateRoot = try utils.hashToBytes("0xc068943dc4eb3e6aa23f342d5b87dddc16ec66ca5e94373f7c0a65f28d8ec0e3"),
            .messagePasserStorageRoot = try utils.hashToBytes("0x5203022804e44a6b8e2ff945b383a6c83c0dae38a412291afed3fdc8b7d3ceb9"),
            .latestBlockhash = try utils.hashToBytes("0x54e494ad9b3cd1425e5bc1e5e6b623fb13fcc2c2d672cb1b6014e50c9d881b31"),
        },
        .withdrawalProof = &.{
            "0xf90211a07dd255038ced20e27bd9c823d53dff05dab9b56f47efec4d1373c6af4fef5989a0a72a37936fd968f361c541a4d5374d3862f0c3e6125b095158982b8eca440da0a0bb0cf61ec3b7954fa2f09263e712f1b9ed681dcab015932294512ad8b288b90da0d91dbd89baf8206e4952fa0f183cb76fee20ad8ab6d0c200053c4ed3e64d1b32a0ab94dcdd454eb74ece1d1fc6bee90a2cc9468a9be3500d774328cced5dd136dca0b1264c351be909f6c5a5e77ead04ba06fb2d63eba010106407459f26de11810aa0a7ad5e83e3e1b8d2e85dc249a99fbcff1673cf55c9915c879ac139ac0bf26dd5a06e3f37c44aa84556026bb48e6246eecfc33171ebcfe58947b031bafe17ae5a00a073b391a00e484b6729f77c11aa424511c8618c34a23dddbfc0fe0265dc4eb4cfa01b50892e8e4ecbfd5bc0cf53604f6f23cd706dc79719972d62be28e627ae287ca05658e252128bfb8ff743644e9610400bebc0264a5a1511469e9d35088c601437a0801f808739c855673327108f22e24fb63c4be593bb1c1bc4e3cd6ea104679e76a098a631fd53cccaaafc3b2e217a85cc4243fec1de269dab5135dede898a56993da0b72713ea8fc5cf977ed19945cd080171f40ea428fe438b99ffa70e086f2e38a1a0be5a3eadca25a2ed6a9b09f8d4203ad9bf76627a241756240cb241a5d7bfd422a0453403dd41482ab5064f94fa2d2e96182fb8b3b9f85473d300689c63f46f244180",
            "0xf90211a0a0ab3e1601d6549af5c32a5c38fef42f0866f24fc16ce70f5d6119733b32ce1ba0f92fcd0021c63ab9136e6df54db3ab735dc267ca8e5725c1c127c107c0d3fc83a0efeb2ad3839ca38f72fbb877c158ade23d7d62b49971abbbe874ae4d44298cdba0d5435ee90a9a1f4c369a0228fcef2d70f8e45d11bdb7bd7b823eb2e265824ac1a033a919415c4532290ca370f71492f352c9c729e4012955d461d525cb8b0faa3ca05cc9620184e8a396cacd0c4f76d25fd4ef80831b3717bfe1d89a0753c544a46fa059baaf0e765b6ff0c9488f7afa06071b9eda81a13b2db2762287c26623f8b27ca04735c39e8cd3d267e6e91f867c2b7120c86ff0c98c4cccd67dfa634f0870f6eda02a80ec76fee519323b8b553e071480d28ca693f95a21b82a48c70adc8155dcbba07809ffaff9ca0875ef1f6e1f84584e2fc79fc2054a47c150aea03f02dabf5cfaa00775eb64cd0add1462a1d0d762424f60fd5faed324f51d48d709ed564cc6d494a011c3b1c19b83e86d587900cfe3a3e2d8534a5c705bad96e68ef3ca0126cbe6a0a0459db754e27d481108d0bfe242f492f06e317437700d860d8a171b961acb3be1a058c7be7e1965ecae30b844bf8676adc851d6af299c6bccaf0856bec60776b01fa05a5ddb72a2a98858c0b4120d728947537bdcc9ab061c4b8da0f684576822bebca07e38f091de1b9e0fcf00f9fdfdec18eb34bfd3996c88329c4cd2d916dbf29cdc80",
            "0xf90211a091e1c27400a43c5a5c197c19c9f9762fa99615f751f093ec268dcde5a0e46363a07c4dff1acc35fa31805556cda36b9618263faecf49a5b287b97fe39a13408c8da03c37d2c5a2f388350546e74c4593236849543f6476aa70f034d88ecc43e1d190a0abaf9651fa71053aa953bdc895c75969f82ed3569d9f001a7f7be66a92b1e6c9a04dfc96da68c1d49908f89f5a9bed4f65c514d1e2193ff1126f9700952e4daceda0ceb6d263009c644f0a348d951e12185bafe238e985432fb5a0deb94fa9a3b2b3a0eb493209507df91c53c45366178061b03226000cf2a8c4ef88fc4e809ae82cd0a064006be53d6f88a198080f749ffb1d6743843c63d3e6f6e395f103c572c73796a0466c8bea652668720b53de631bc1d16935bfaa85c730f6f7d19fcbe4704ab047a0c2792da5608db91851be4114546902cb4cbebea053665b1329c1e73f24e72d48a05fdd0ade55a0571d508274576bcd7a2ced913e77534ff267b3e60368b2ee95c5a0b574398c5e6640048b26a7ca2298105f027dd3561652a1f1fa9ba1c01ed0057fa0d1a98317c3dee409a6178771fc67378e3a14197f4f9f9e5aed1c6b05584d3f48a0e9abf8d9df852a45a5310777b46fbdfa0876e83063a94bc91096c4d5bb8385dba0f831723d52c0b60b61bb830c9a33c9f9b2d83830c3ed570e5da44ae6ee80a953a0333636ac068b435c011fd4e7d30dc52a8bbaf8e9d861a95eee4d3e512ff839c580",
            "0xf901b1a0e480ad00d97a48b6ecdbf027135399615123578f3de7e572259000b946f4c87080a09d2298b1328a8afd6b47f0bd57a1332011ab02614a86ef6b544baf61e425ba9ea05713276bc96f85c79bb9f4e4ef517d5bafe56db6775fd27f757981fe94846aa4a02f787118beba540f07c1fd3b488628ee0fa47694aa5eb1d86405ff25b3d6f66b80a09a628c00eebfe343a8f4a7072aa6ee968eea22a6dde4ac3a29d65bdaae854758a01ffd70ab795cbc879376990fad07f95ec2bf6dc9a51ae3603bfd5f321dc7474aa0cf82883dc01744467fa15bec5689b559b70aa63c6d341548676605e927a102cba0fdb90a7114f2137e15ac8915bf54727cd5d0dead26962eefe4ab2499ec6b5c65a00909bea4f700704cda454c330e2a88f73ebd6a7d7e8fef4204397e154953de99a0bbab7f75e0804aaee0f2761a49579f08820eb074f5ff9320ff5f48383975079880a0b3663141987995925fed9ef86f8fc02a44a42136645714891831ccdf1e08c68ea00a23286f92dbcd146255c6c2cc880990cbd694894653701169c07f6098d9573da0d8a58420dc5d85d4150c2bc6fcae28eb3a843d92aaba1274161e12554c389b8d80",
            "0xe19f20418ffb24ba711dfecd671b4054aa2e87efe3d10484b88078ceef79373c6001",
        },
        .data = "0xd764ad0b0001000000000000000000000000000000000000000000000000000000002d49000000000000000000000000420000000000000000000000000000000000001000000000000000000000000099c9fc46f92e8a1c0dec1b1747d010903e884be1000000000000000000000000000000000000000000000000002e2f6e5e148000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000a41635f5fd000000000000000000000000bcce5f55dfda11600e48e91598ad0f8645466142000000000000000000000000bcce5f55dfda11600e48e91598ad0f8645466142000000000000000000000000000000000000000000000000002e2f6e5e1480000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        .gasLimit = 287624,
        .nonce = 1766847064778384329583297500742918515827483896875618958121606201292631369,
        .sender = try utils.addressToBytes("0x4200000000000000000000000000000000000007"),
        .target = try utils.addressToBytes("0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1"),
        .value = 13000000000000000,
    };

    const prepared = try wallet_op.prepareWithdrawalProofTransaction(.{
        .data = args.data,
        .gasLimit = args.gasLimit,
        .nonce = args.nonce,
        .sender = args.sender,
        .target = args.target,
        .value = args.value,
        .withdrawalHash = try utils.hashToBytes("0x178f1e0216fb50bef160eb8af7d1d98000026a84371cef4a13d8d79996cc8589"),
    }, .{
        .outputRoot = try utils.hashToBytes("0xdc3b54fd33b5d8a60f275ca83c74b625e3942be5b70b2f7f0b9cadd869eb7b1a"),
        .outputIndex = args.l2OutputIndex,
        .l2BlockNumber = 113388533,
        .timestamp = 1702377887,
    });

    try testing.expectEqualDeep(args, prepared);
}

test "ProveWithdrawal" {
    std.time.sleep(std.time.ns_per_ms * 500);
    var wallet_op: L2WalletClient(.http) = undefined;
    defer wallet_op.deinit();

    const uri = try std.Uri.parse("http://localhost:8544/");
    try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
        .allocator = testing.allocator,
        .uri = uri,
        .chain_id = .op_mainnet,
    }, null);

    const args = .{
        .l2_output_index = 4529,
        .outputRootProof = .{
            .version = try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000000"),
            .stateRoot = try utils.hashToBytes("0x92822c772346d9c8ad1c28885a736de9189a4523e0c79639831a4eed651d837f"),
            .messagePasserStorageRoot = try utils.hashToBytes("0x04091eb8ad4eb056aff2749c1d17b1ed1a0cdcd44f9d7a539ffd56e4b2b4e1f8"),
            .latestBlockhash = try utils.hashToBytes("0x67319b70138527b1087a535099cf8a4db4692ca7cee16b7a3ebd950408ed610a"),
        },
        .withdrawalProof = &.{
            "0xf90211a07dd255038ced20e27bd9c823d53dff05dab9b56f47efec4d1373c6af4fef5989a0a72a37936fd968f361c541a4d5374d3862f0c3e6125b095158982b8eca440da0a0bb0cf61ec3b7954fa2f09263e712f1b9ed681dcab015932294512ad8b288b90da0d91dbd89baf8206e4952fa0f183cb76fee20ad8ab6d0c200053c4ed3e64d1b32a0ab94dcdd454eb74ece1d1fc6bee90a2cc9468a9be3500d774328cced5dd136dca0fa51148073d2fd37bea62e78e31d2f29f95bacdd72ee987ecbbce8fa98433681a0a7ad5e83e3e1b8d2e85dc249a99fbcff1673cf55c9915c879ac139ac0bf26dd5a0c5766a7cdac0498fd865d735ab9085a3a4163e2338c422e33c4a6b4d1ad0e9afa073b391a00e484b6729f77c11aa424511c8618c34a23dddbfc0fe0265dc4eb4cfa01b50892e8e4ecbfd5bc0cf53604f6f23cd706dc79719972d62be28e627ae287ca05658e252128bfb8ff743644e9610400bebc0264a5a1511469e9d35088c601437a06b5301e3158ca1288125e03b486e99d23baaa5706858ed39488854e197de81bba098a631fd53cccaaafc3b2e217a85cc4243fec1de269dab5135dede898a56993da0b72713ea8fc5cf977ed19945cd080171f40ea428fe438b99ffa70e086f2e38a1a0be5a3eadca25a2ed6a9b09f8d4203ad9bf76627a241756240cb241a5d7bfd422a0453403dd41482ab5064f94fa2d2e96182fb8b3b9f85473d300689c63f46f244180",
            "0xf90211a0a0ab3e1601d6549af5c32a5c38fef42f0866f24fc16ce70f5d6119733b32ce1ba0f92fcd0021c63ab9136e6df54db3ab735dc267ca8e5725c1c127c107c0d3fc83a0efeb2ad3839ca38f72fbb877c158ade23d7d62b49971abbbe874ae4d44298cdba0d5435ee90a9a1f4c369a0228fcef2d70f8e45d11bdb7bd7b823eb2e265824ac1a033a919415c4532290ca370f71492f352c9c729e4012955d461d525cb8b0faa3ca05cc9620184e8a396cacd0c4f76d25fd4ef80831b3717bfe1d89a0753c544a46fa059baaf0e765b6ff0c9488f7afa06071b9eda81a13b2db2762287c26623f8b27ca04735c39e8cd3d267e6e91f867c2b7120c86ff0c98c4cccd67dfa634f0870f6eda02a80ec76fee519323b8b553e071480d28ca693f95a21b82a48c70adc8155dcbba07809ffaff9ca0875ef1f6e1f84584e2fc79fc2054a47c150aea03f02dabf5cfaa00775eb64cd0add1462a1d0d762424f60fd5faed324f51d48d709ed564cc6d494a011c3b1c19b83e86d587900cfe3a3e2d8534a5c705bad96e68ef3ca0126cbe6a0a0459db754e27d481108d0bfe242f492f06e317437700d860d8a171b961acb3be1a058c7be7e1965ecae30b844bf8676adc851d6af299c6bccaf0856bec60776b01fa05a5ddb72a2a98858c0b4120d728947537bdcc9ab061c4b8da0f684576822bebca07e38f091de1b9e0fcf00f9fdfdec18eb34bfd3996c88329c4cd2d916dbf29cdc80",
            "0xf90211a091e1c27400a43c5a5c197c19c9f9762fa99615f751f093ec268dcde5a0e46363a07c4dff1acc35fa31805556cda36b9618263faecf49a5b287b97fe39a13408c8da03c37d2c5a2f388350546e74c4593236849543f6476aa70f034d88ecc43e1d190a0abaf9651fa71053aa953bdc895c75969f82ed3569d9f001a7f7be66a92b1e6c9a04dfc96da68c1d49908f89f5a9bed4f65c514d1e2193ff1126f9700952e4daceda0ceb6d263009c644f0a348d951e12185bafe238e985432fb5a0deb94fa9a3b2b3a0eb493209507df91c53c45366178061b03226000cf2a8c4ef88fc4e809ae82cd0a064006be53d6f88a198080f749ffb1d6743843c63d3e6f6e395f103c572c73796a0466c8bea652668720b53de631bc1d16935bfaa85c730f6f7d19fcbe4704ab047a0c2792da5608db91851be4114546902cb4cbebea053665b1329c1e73f24e72d48a05fdd0ade55a0571d508274576bcd7a2ced913e77534ff267b3e60368b2ee95c5a0b574398c5e6640048b26a7ca2298105f027dd3561652a1f1fa9ba1c01ed0057fa0d1a98317c3dee409a6178771fc67378e3a14197f4f9f9e5aed1c6b05584d3f48a0e9abf8d9df852a45a5310777b46fbdfa0876e83063a94bc91096c4d5bb8385dba0f831723d52c0b60b61bb830c9a33c9f9b2d83830c3ed570e5da44ae6ee80a953a0333636ac068b435c011fd4e7d30dc52a8bbaf8e9d861a95eee4d3e512ff839c580",
            "0xf901b1a0e480ad00d97a48b6ecdbf027135399615123578f3de7e572259000b946f4c87080a09d2298b1328a8afd6b47f0bd57a1332011ab02614a86ef6b544baf61e425ba9ea05713276bc96f85c79bb9f4e4ef517d5bafe56db6775fd27f757981fe94846aa4a02f787118beba540f07c1fd3b488628ee0fa47694aa5eb1d86405ff25b3d6f66b80a09a628c00eebfe343a8f4a7072aa6ee968eea22a6dde4ac3a29d65bdaae854758a01ffd70ab795cbc879376990fad07f95ec2bf6dc9a51ae3603bfd5f321dc7474aa0cf82883dc01744467fa15bec5689b559b70aa63c6d341548676605e927a102cba0fdb90a7114f2137e15ac8915bf54727cd5d0dead26962eefe4ab2499ec6b5c65a00909bea4f700704cda454c330e2a88f73ebd6a7d7e8fef4204397e154953de99a0bbab7f75e0804aaee0f2761a49579f08820eb074f5ff9320ff5f48383975079880a0b3663141987995925fed9ef86f8fc02a44a42136645714891831ccdf1e08c68ea00a23286f92dbcd146255c6c2cc880990cbd694894653701169c07f6098d9573da0d8a58420dc5d85d4150c2bc6fcae28eb3a843d92aaba1274161e12554c389b8d80",
            "0xe19f20418ffb24ba711dfecd671b4054aa2e87efe3d10484b88078ceef79373c6001",
        },
        .withdrawal = .{
            .data = "0xd764ad0b0001000000000000000000000000000000000000000000000000000000002d49000000000000000000000000420000000000000000000000000000000000001000000000000000000000000099c9fc46f92e8a1c0dec1b1747d010903e884be1000000000000000000000000000000000000000000000000002e2f6e5e148000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000a41635f5fd000000000000000000000000bcce5f55dfda11600e48e91598ad0f8645466142000000000000000000000000bcce5f55dfda11600e48e91598ad0f8645466142000000000000000000000000000000000000000000000000002e2f6e5e1480000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            .gasLimit = 287624,
            .nonce = 1766847064778384329583297500742918515827483896875618958121606201292631369,
            .sender = try utils.addressToBytes("0x4200000000000000000000000000000000000007"),
            .target = try utils.addressToBytes("0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1"),
            .value = 13000000000000000,
        },
    };

    _ = try wallet_op.proveWithdrawal(args.withdrawal, args.l2_output_index, args.outputRootProof, args.withdrawalProof);
}

test "FinalizeWithdrawal" {
    std.time.sleep(std.time.ns_per_ms * 500);
    var wallet_op: L2WalletClient(.http) = undefined;
    defer wallet_op.deinit();

    const uri = try std.Uri.parse("http://localhost:8544/");
    try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
        .allocator = testing.allocator,
        .uri = uri,
        .chain_id = .op_mainnet,
    }, null);

    _ = try wallet_op.finalizeWithdrawal(.{
        .data = "0x01",
        .sender = try utils.addressToBytes("0x02f086dBC384d69b3041BC738F0a8af5e49dA181"),
        .target = try utils.addressToBytes("0x02f086dBC384d69b3041BC738F0a8af5e49dA181"),
        .value = 335000000000000000000,
        .gasLimit = 100000,
        .nonce = 1766847064778384329583297500742918515827483896875618958121606201292641795,
    });
}
