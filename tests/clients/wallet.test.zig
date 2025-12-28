const eip712 = @import("zabi").abi.eip712;
const std = @import("std");
const testing = std.testing;
const transactions = @import("zabi").types.transactions;
const types = @import("zabi").types.ethereum;
const utils = @import("zabi").utils.utils;
const clients = @import("zabi").clients;

const Hash = types.Hash;
const HttpProvider = clients.Provider.HttpProvider;
const IpcProvider = clients.Provider.IpcProvider;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Signature = @import("zabi").crypto.signature.Signature;
const Signer = @import("zabi").crypto.Signer;
const TransactionEnvelope = transactions.TransactionEnvelope;
const UnpreparedTransactionEnvelope = transactions.UnpreparedTransactionEnvelope;
const Wallet = clients.Wallet;
const WebsocketProvider = clients.Provider.WebsocketProvider;

test "HashAuthorization" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const message = try wallet.hashAuthorityEip7702(try utils.addressToBytes("0x90F79bf6EB2c4f870365E785982E1f101E93b906"), 69);

    const hex = try std.fmt.allocPrint(testing.allocator, "{x}", .{&message});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings(hex, "5daf8ca195709ae5c4f081a74786f87dbce7ab39130624532d52a47ad2627181");
}

test "Recover Auth Address" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const message = try wallet.signAuthorizationEip7702(try utils.addressToBytes("0x90F79bf6EB2c4f870365E785982E1f101E93b906"), 0);

    try testing.expect(@as(u160, @bitCast(try wallet.recoverAuthorizationAddress(message))) == @as(u160, @bitCast(wallet.getWalletAddress())));
    try testing.expect(@as(u160, @bitCast(try wallet.recoverAuthorizationAddress(message))) != @as(u160, @bitCast(try utils.addressToBytes("0x90F79bf6EB2c4f870365E785982E1f101E93b906"))));
}

test "Verify Auth" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const message = try wallet.signAuthorizationEip7702(try utils.addressToBytes("0x90F79bf6EB2c4f870365E785982E1f101E93b906"), 0);

    try testing.expect(try wallet.verifyAuthorization(null, message));
}

test "Address match" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    try testing.expectEqualStrings(&wallet.getWalletAddress(), &try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"));
}

test "verifyMessage" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0", &hash_buffer, .{});
    const sign = try wallet.signer.sign(hash_buffer);

    try testing.expect(wallet.signer.verifyMessage(hash_buffer, sign));
    try testing.expect(wallet.verifyMessage(sign, "02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0"));
}

test "signMessage" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const sig = try wallet.signEthereumMessage("hello world");
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("a461f509887bd19e312c0c58467ce8ff8e300d3c1a90b608a760c5b80318eaf15fe57c96f9175d6cd4daad4663763baa7e78836e067d0163e9a2ccf2ff753f5b00", hex);
}

test "signTypedData" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const sig = try wallet.signTypedData(.{ .EIP712Domain = &.{} }, "EIP712Domain", .{}, .{});
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da87197eb020923476a6d0149ca90bc1c894251cc30b38e0dd2cdd48567e12386d3ed40a509397410a4fd2d66e1300a39ac42f828f8a5a2cb948b35c22cf29e801", hex);
}

test "verifyTypedData" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    const domain: eip712.TypedDataDomain = .{
        .name = "Ether Mail",
        .version = "1",
        .chainId = 1,
        .verifyingContract = "0x0000000000000000000000000000000000000000",
    };
    const e_types = .{
        .EIP712Domain = &.{
            .{ .type = "string", .name = "name" },
            .{ .name = "version", .type = "string" },
            .{ .name = "chainId", .type = "uint256" },
            .{ .name = "verifyingContract", .type = "address" },
        },
        .Person = &.{
            .{ .name = "name", .type = "string" },
            .{ .name = "wallet", .type = "address" },
        },
        .Mail = &.{
            .{ .name = "from", .type = "Person" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
        },
    };

    const sig = try Signature.fromHex("0x32f3d5975ba38d6c2fba9b95d5cbed1febaa68003d3d588d51f2de522ad54117760cfc249470a75232552e43991f53953a3d74edf6944553c6bef2469bb9e5921b");
    const validate = try wallet.verifyTypedData(sig, e_types, "Mail", domain, .{
        .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" },
        .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" },
        .contents = "Hello, Bob!",
    });

    try testing.expect(validate);
}

test "sendTransaction" {
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        const uri = try std.Uri.parse("http://localhost:6969/");
        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const tx: UnpreparedTransactionEnvelope = .{
            .type = .london,
            .value = try utils.parseEth(1),
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        };

        const tx_hash = try wallet.sendTransaction(tx);
        defer tx_hash.deinit();

        const receipt = try wallet.rpc_client.waitForTransactionReceipt(tx_hash.response, 0);
        defer receipt.deinit();
    }
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        const uri = try std.Uri.parse("http://localhost:6969/");
        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const tx: UnpreparedTransactionEnvelope = .{
            .type = .london,
            .value = try utils.parseEth(1),
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        };

        const tx_hash = try wallet.sendTransaction(tx);
        defer tx_hash.deinit();

        const receipt = try wallet.rpc_client.waitForTransactionReceipt(tx_hash.response, 0);
        defer receipt.deinit();
    }
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        const uri = try std.Uri.parse("http://localhost:6969/");
        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try client.readLoopSeperateThread();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const tx: UnpreparedTransactionEnvelope = .{
            .type = .london,
            .value = try utils.parseEth(1),
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        };

        const tx_hash = try wallet.sendTransaction(tx);
        defer tx_hash.deinit();

        const receipt = try wallet.rpc_client.waitForTransactionReceipt(tx_hash.response, 0);
        defer receipt.deinit();
    }
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try IpcProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .path = "/tmp/anvil.ipc" },
            },
        });
        defer client.deinit();

        try client.readLoopSeperateThread();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const tx: UnpreparedTransactionEnvelope = .{
            .type = .london,
            .value = try utils.parseEth(1),
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        };

        const tx_hash = try wallet.sendTransaction(tx);
        defer tx_hash.deinit();

        const receipt = try wallet.rpc_client.waitForTransactionReceipt(tx_hash.response, 0);
        defer receipt.deinit();
    }
}

test "Get First element With Nonce Manager" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, true);
    defer wallet.deinit();

    {
        const first = wallet.envelopes_pool.getFirstElementFromPool(wallet.allocator);
        const last = wallet.envelopes_pool.getLastElementFromPool(wallet.allocator);
        try testing.expect(first == null);
        try testing.expect(last == null);
    }

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        _ = try wallet.nonce_manager.?.updateNonce(wallet.rpc_client);
        const nonce = try wallet.nonce_manager.?.getNonce(wallet.rpc_client);

        try wallet.poolTransactionEnvelope(.{ .type = .london, .nonce = nonce });
    }

    {
        const first = wallet.envelopes_pool.getFirstElementFromPool(wallet.allocator);
        const last = wallet.envelopes_pool.getLastElementFromPool(wallet.allocator);
        try testing.expect(first != null);
        try testing.expect(last != null);

        try testing.expect(last.?.london.nonce != 0);
    }
}

test "Pool transactions" {
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        const uri = try std.Uri.parse("http://localhost:6969/");
        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        try wallet.poolTransactionEnvelope(.{ .type = .london, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .berlin, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .legacy, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .cancun, .nonce = 0 });

        const env = wallet.findTransactionEnvelopeFromPool(.{ .type = .london, .nonce = 0 });
        try testing.expect(env != null);
    }
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        const uri = try std.Uri.parse("http://localhost:6969/");
        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try client.readLoopSeperateThread();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        try wallet.poolTransactionEnvelope(.{ .type = .london, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .berlin, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .legacy, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .cancun, .nonce = 0 });

        const env = wallet.findTransactionEnvelopeFromPool(.{ .type = .london, .nonce = 0 });
        try testing.expect(env != null);
    }
    {
        var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
        defer threaded_io.deinit();

        var buffer: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var client = try IpcProvider.init(.{
            .allocator = testing.allocator,
            .io = threaded_io.io(),
            .network_config = .{
                .endpoint = .{ .path = "/tmp/anvil.ipc" },
            },
        });
        defer client.deinit();

        try client.readLoopSeperateThread();

        var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        try wallet.poolTransactionEnvelope(.{ .type = .london, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .berlin, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .legacy, .nonce = 0 });
        try wallet.poolTransactionEnvelope(.{ .type = .cancun, .nonce = 0 });

        const env = wallet.findTransactionEnvelopeFromPool(.{ .type = .london, .nonce = 0 });
        try testing.expect(env != null);
    }
}

test "Get First element" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    {
        const first = wallet.envelopes_pool.getFirstElementFromPool(wallet.allocator);
        const last = wallet.envelopes_pool.getLastElementFromPool(wallet.allocator);
        try testing.expect(first == null);
        try testing.expect(last == null);
    }

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        try wallet.poolTransactionEnvelope(.{ .type = .london });
    }

    {
        const first = wallet.envelopes_pool.getFirstElementFromPool(wallet.allocator);
        const last = wallet.envelopes_pool.getLastElementFromPool(wallet.allocator);
        try testing.expect(first != null);
        try testing.expect(last != null);
    }
}

test "assertTransaction" {
    var tx: TransactionEnvelope = undefined;
    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    {
        tx = .{ .london = .{
            .nonce = 0,
            .gas = 21001,
            .maxPriorityFeePerGas = 2,
            .maxFeePerGas = 2,
            .chainId = 1,
            .accessList = &.{},
            .value = 0,
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
            .data = null,
        } };
        try wallet.assertTransaction(tx);

        tx.london.chainId = 2;
        try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

        tx.london.chainId = 1;

        tx.london.maxPriorityFeePerGas = 69;
        tx.london.to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        try testing.expectError(error.TransactionTipToHigh, wallet.assertTransaction(tx));
    }
    {
        tx = .{ .cancun = .{
            .nonce = 0,
            .gas = 21001,
            .maxPriorityFeePerGas = 2,
            .maxFeePerGas = 2,
            .chainId = 1,
            .accessList = &.{},
            .value = 0,
            .maxFeePerBlobGas = 2,
            .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
            .data = null,
        } };
        try wallet.assertTransaction(tx);

        tx.cancun.chainId = 2;
        try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

        tx.cancun.chainId = 1;

        tx.cancun.maxPriorityFeePerGas = 69;
        tx.cancun.to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        try testing.expectError(error.TransactionTipToHigh, wallet.assertTransaction(tx));
    }
}

test "assertTransactionLegacy" {
    var tx: TransactionEnvelope = undefined;

    var threaded_io: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded_io.deinit();

    const uri = try std.Uri.parse("http://localhost:6969/");
    var buffer: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    var client = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    var wallet = try Wallet.init(buffer, testing.allocator, &client.provider, false);
    defer wallet.deinit();

    tx = .{ .berlin = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .accessList = &.{},
        .value = 0,
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.berlin.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.berlin.chainId = 1;

    tx = .{ .legacy = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .value = 0,
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.legacy.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.legacy.chainId = 1;
}

test "Ref All Decls" {
    if (true) return error.SkipZigTest;
    _ = testing.refAllDecls(Wallet);
}
