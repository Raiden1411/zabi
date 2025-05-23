const abi = @import("zabi").abi.abitypes;
const multicall = @import("zabi").clients.multicall;
const std = @import("std");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const Function = abi.Function;
const MulticallTargets = multicall.MulticallTargets;
const WebSocketHandler = @import("zabi").clients.WebSocket;

test "BlockByNumber" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByNumber(.{ .block_number = 10 });
        defer block_number.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByNumber(.{});
        defer block_number.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByNumber(.{ .include_transaction_objects = true });
        defer block_number.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByNumber(.{ .block_number = 1000000, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockByHash" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByHash(.{
            .block_hash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response == .beacon);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockByHash(.{
            .block_hash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
            .include_transaction_objects = true,
        });
        defer block_number.deinit();

        try testing.expect(block_number.response == .beacon);
        try testing.expect(block_number.response.beacon.transactions != null);
        try testing.expect(block_number.response.beacon.transactions.? == .objects);
    }
}

test "BlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const block_number = try client.getBlockTransactionCountByHash(try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
    defer block_number.deinit();

    try testing.expect(block_number.response != 0);
}

test "BlockTransactionCountByNumber" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockTransactionCountByNumber(.{ .block_number = 100101 });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getBlockTransactionCountByNumber(.{});
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
}

test "AddressBalance" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getAddressBalance(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
            .block_number = 100101,
        });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getAddressBalance(.{
            .address = try utils.addressToBytes("0xdAC17F958D2ee523a2206206994597C13D831ec7"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
}

test "AddressNonce" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getAddressTransactionCount(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const block_number = try client.getAddressTransactionCount(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
            .block_number = 100012,
        });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
}

test "BlockNumber" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const block_number = try client.getBlockNumber();
    defer block_number.deinit();

    try testing.expect(block_number.response != 0);
}

test "GetChainId" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const chain = try client.getChainId();
    defer chain.deinit();

    try testing.expectEqual(chain.response, 1);
}

test "GetStorage" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{});
        defer storage.deinit();

        try testing.expectEqual(@as(u256, @bitCast(storage.response)), 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{ .block_number = 101010 });
        defer storage.deinit();

        try testing.expectEqual(@as(u256, @bitCast(storage.response)), 0);
    }
}

test "GetAccounts" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const accounts = try client.getAccounts();
    defer accounts.deinit();

    try testing.expectEqual(accounts.response.len, 10);
    try testing.expectEqualSlices(u8, &accounts.response[0], &try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"));
}

test "GetContractCode" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const code = try client.getContractCode(.{
            .address = try utils.addressToBytes("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
        });
        defer code.deinit();

        try testing.expect(code.response.len != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const code = try client.getContractCode(.{
            .address = try utils.addressToBytes("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            .block_number = 101010,
        });
        defer code.deinit();

        try testing.expectEqual(code.response.len, 0);
    }
}

test "GetTransactionByHash" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const tx = try client.getTransactionByHash(try utils.hashToBytes("0x360bf48bf75f0020d05cc97526b246d67c266dcf91897c01cf7acfe94fe2154e"));
    defer tx.deinit();

    try testing.expect(tx.response == .london);
    try testing.expectEqual(tx.response.london.blockHash, try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
}

test "GetReceipt" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const receipt = try client.getTransactionReceipt(try utils.hashToBytes("0x360bf48bf75f0020d05cc97526b246d67c266dcf91897c01cf7acfe94fe2154e"));
    defer receipt.deinit();

    try testing.expect(receipt.response == .legacy);
    try testing.expectEqual(receipt.response.legacy.blockHash, try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
}

test "GetFilter" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterChanges);
        defer filter.deinit();

        try testing.expectEqual(filter.response.len, 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterLogs);
        defer filter.deinit();

        try testing.expectEqual(filter.response.len, 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.InvalidRpcMethod, client.getFilterOrLogChanges(0, .eth_chainId));
    }
}

test "GetGasPrice" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const gas = try client.getGasPrice();
    defer gas.deinit();

    try testing.expect(gas.response != 0);
}

test "GetUncleCountByBlockHash" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const uncle = try client.getUncleCountByBlockHash(try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
    defer uncle.deinit();

    try testing.expectEqual(uncle.response, 0);
}

test "GetUncleCountByBlockNumber" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const uncle = try client.getUncleCountByBlockNumber(.{});
        defer uncle.deinit();

        try testing.expectEqual(uncle.response, 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const uncle = try client.getUncleCountByBlockNumber(.{ .block_number = 101010 });
        defer uncle.deinit();

        try testing.expectEqual(uncle.response, 0);
    }
}

test "GetUncleByBlockNumberAndIndex" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.InvalidBlockNumberOrIndex, client.getUncleByBlockNumberAndIndex(.{}, 0));
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const uncle = try client.getUncleByBlockNumberAndIndex(.{ .block_number = 15537381 }, 0);
        defer uncle.deinit();

        try testing.expect(uncle.response == .legacy);
    }
}

test "GetUncleByBlockHashAndIndex" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const tx = try client.getUncleByBlockHashAndIndex(try utils.hashToBytes("0x4e216c95f527e9ba0f1161a1c4609b893302c704f05a520da8141ca91878f63e"), 0);
    defer tx.deinit();

    try testing.expect(tx.response == .legacy);
}

test "GetTransactionByBlockNumberAndIndex" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.TransactionNotFound, client.getTransactionByBlockNumberAndIndex(.{}, 0));
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const tx = try client.getTransactionByBlockNumberAndIndex(.{ .block_number = 15537381 }, 0);
        defer tx.deinit();

        try testing.expect(tx.response == .london);
    }
}

test "EstimateGas" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.TransactionRejected, client.estimateGas(.{ .london = .{ .gas = 10 } }, .{}));
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.InvalidInput, client.estimateGas(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 }));
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const fee = try client.estimateGas(.{ .legacy = .{ .value = 10 } }, .{});
        defer fee.deinit();

        try testing.expect(fee.response != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.InvalidInput, client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 }));
    }
}

test "CreateAccessList" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const access = try client.createAccessList(.{ .london = .{ .value = 10 } }, .{});
        defer access.deinit();

        try testing.expect(access.response.gasUsed != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try testing.expectError(error.InvalidInput, client.createAccessList(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 }));
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const access = try client.createAccessList(.{ .legacy = .{ .value = 10 } }, .{});
        defer access.deinit();

        try testing.expect(access.response.gasUsed != 0);
    }
}

test "GetNetworkPeerCount" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    try testing.expectError(error.InvalidParams, client.getNetworkPeerCount());
}

test "GetNetworkVersionId" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const id = try client.getNetworkVersionId();
    defer id.deinit();

    try testing.expectEqual(id.response, 1);
}

test "GetNetworkListenStatus" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const id = try client.getNetworkListenStatus();
    defer id.deinit();

    try testing.expectEqual(id.response, true);
}

test "GetSha3Hash" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    try testing.expectError(error.InvalidParams, client.getSha3Hash("foobar"));
}

test "GetClientVersion" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const version = try client.getClientVersion();
    defer version.deinit();

    try testing.expect(version.response.len != 0);
}

test "BlobBaseFee" {
    if (true) return error.SkipZigTest;
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const base_fee = try client.blobBaseFee();
    defer base_fee.deinit();

    try testing.expectEqual(base_fee.response, 0);
}

test "EstimateBlobMaxFeePerGas" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const base_fee = try client.estimateBlobMaxFeePerGas();

    try testing.expect(base_fee != 0);
}

test "EstimateMaxFeePerGas" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const fees = try client.estimateMaxFeePerGas();
    defer fees.deinit();

    try testing.expect(fees.response != 0);
}

test "EstimateFeePerGas" {
    if (true) return error.SkipZigTest;
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const fee = try client.estimateFeesPerGas(.{ .london = .{} }, null);

        try testing.expect(fee.london.max_fee_gas != 0);
        try testing.expect(fee.london.max_priority_fee != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const fee = try client.estimateFeesPerGas(.{ .legacy = .{} }, null);

        try testing.expect(fee.legacy.gas_price != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const fee = try client.estimateFeesPerGas(.{ .london = .{} }, 1000);

        try testing.expect(fee.london.max_fee_gas != 0);
        try testing.expect(fee.london.max_priority_fee != 0);
    }
}

test "GetProof" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{}, .blockNumber = 101010 }, null);
        defer proofs.deinit();

        try testing.expect(proofs.response.balance != 0);
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{} }, .latest);
        defer proofs.deinit();

        try testing.expect(proofs.response.balance != 0);
    }
}

test "GetLogs" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const logs = try client.getLogs(.{ .toBlock = 101010, .fromBlock = 101010 }, null);
        defer logs.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const logs = try client.getLogs(.{}, .latest);
        defer logs.deinit();
    }
}

test "NewLogFilter" {
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const logs = try client.newLogFilter(.{}, .latest);
        defer logs.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const logs = try client.newLogFilter(.{ .fromBlock = 101010, .toBlock = 101010 }, null);
        defer logs.deinit();
    }
}

test "NewBlockFilter" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const block_id = try client.newBlockFilter();
    defer block_id.deinit();
}

test "NewPendingTransactionFilter" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const tx_id = try client.newPendingTransactionFilter();
    defer tx_id.deinit();
}

test "UninstallFilter" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const status = try client.uninstallFilter(1);
    defer status.deinit();
}

test "GetProtocolVersion" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    try testing.expectError(error.InvalidParams, client.getProtocolVersion());
}

test "SyncStatus" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const status = client.getSyncStatus();
    defer if (status) |s| s.deinit();
}

test "FeeHistory" {
    if (true) return error.SkipZigTest;

    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, null);
        defer status.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        const uri = try std.Uri.parse("http://127.0.0.1:6969/");

        var client = try WebSocketHandler.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
}

test "Multicall" {
    const uri = try std.Uri.parse("http://127.0.0.1:6969/");

    var client = try WebSocketHandler.init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
        },
    });
    defer client.deinit();

    const supply: Function = .{
        .type = .function,
        .name = "totalSupply",
        .stateMutability = .view,
        .inputs = &.{},
        .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
    };

    const balance: Function = .{
        .type = .function,
        .name = "balanceOf",
        .stateMutability = .view,
        .inputs = &.{.{ .type = .{ .address = {} }, .name = "balanceOf" }},
        .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
    };

    const a: []const MulticallTargets = &.{
        MulticallTargets{ .function = supply, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
        MulticallTargets{ .function = balance, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
    };

    const res = try client.multicall3(a, .{ {}, .{try utils.addressToBytes("0xFded38DF0180039867E54EBdec2012D534862cE3")} }, true);
    defer res.deinit();

    try testing.expect(res.result.len != 0);
    try testing.expectEqual(res.result[0].success, true);
}

test "Ref All Decls" {
    std.testing.refAllDecls(WebSocketHandler);
}
