const generator = @import("../../utils/generator.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../../types/root.zig");

test "Parse/Stringify Json" {
    {
        const gen = try generator.generateRandomData(types.block.Block, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.Block, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.block.BeaconBlock, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.BeaconBlock, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.block.BlobBlock, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.block.BlobBlock, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionEnvelope, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionEnvelope, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionEnvelopeSigned, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionEnvelopeSigned, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.TransactionReceipt, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.TransactionReceipt, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.Transaction, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.Transaction, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.log.Logs, testing.allocator, 0, .{ .slice_size = 20 });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.log.Logs, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumResponse(u32), testing.allocator, 0, .{
            .slice_size = 20,
            .use_default_values = true,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumResponse(u32), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumErrorResponse, testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumErrorResponse, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumSubscribeResponse(u64), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumSubscribeResponse(u64), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumRequest(struct { u64 }), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumRequest([1]u64), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated.params, parsed.value.params);
    }
    {
        const gen = try generator.generateRandomData(types.ethereum.EthereumRequest([2]u32), testing.allocator, 0, .{
            .slice_size = 20,
            .ascii = .{ .use_on_arrays_and_slices = true },
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumRequest([2]u32), testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.FeeHistory, testing.allocator, 0, .{
            .slice_size = 20,
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        const parsed = try std.json.parseFromSlice(types.transactions.FeeHistory, testing.allocator, as_slice, .{});
        defer parsed.deinit();

        try testing.expectEqualDeep(gen.generated, parsed.value);
    }
    {
        const gen = try generator.generateRandomData(types.transactions.FeeHistory, testing.allocator, 0, .{
            .slice_size = 20,
        });
        defer gen.deinit();

        const as_slice = try std.json.stringifyAlloc(testing.allocator, gen.generated, .{});
        defer testing.allocator.free(as_slice);

        try testing.expectError(error.UnknownField, std.json.parseFromSlice(types.transactions.LegacyEthCall, testing.allocator, as_slice, .{}));
    }
    {
        const slice =
            \\{"jsonrpc":"2.0","id":"0x1","result":{"oldestBlock":"0x138abdf","reward":[["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"],["0x0","0x0"]],"baseFeePerGas":["0xc1a5e9bd","0xb94f35a4","0xba5167aa","0xb955f8be","0xb5687db8","0xb8312e62","0xb54d83af","0xb4a85ac8","0xb6f845e6","0xb5783cb0","0xb981736c"],"gasUsedRatio":[0.3277559,0.5217706333333333,0.4789143,0.41523153333333335,0.5613852333333333,0.43725413333333335,0.48576623333333335,0.5511947666666667,0.46720463333333334,0.5889623333333334],"baseFeePerBlobGas":["0x1","0x1","0x1","0x1","0x1","0x1","0x1","0x1","0x1","0x1","0x1"],"blobGasUsedRatio":[0,1,1,0.5,0,1,0.16666666666666666,0,0.5,0.16666666666666666]}}
        ;

        const parsed = try std.json.parseFromSlice(types.ethereum.EthereumResponse(types.transactions.FeeHistory), testing.allocator, slice, .{});
        defer parsed.deinit();
    }
    {
        const slice =
            \\{"transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","from":"0xb2552eb7460f77f34ce3e33ecfc99d6669c38033","to":"0x9aed3a8896a85fe9a8cac52c9b402d092b629a30","cumulativeGasUsed":"0x506f4c","gasUsed":"0x20fec2","contractAddress":null,"logs":[{"address":"0xff970a61a04b1ca14834a43f5de4533ebddb5cc8","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","0x000000000000000000000000eff23b4be1091b53205e35f3afcd9c7182bf3062"],"data":"0x00000000000000000000000000000000000000000000000000000000004c4b40","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0x9","removed":false},{"address":"0xff970a61a04b1ca14834a43f5de4533ebddb5cc8","topics":["0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb3b4bf","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xa","removed":false},{"address":"0x82af49447d8a07e3bd95bd0d56f35241523fbab1","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x000000000000000000000000eff23b4be1091b53205e35f3afcd9c7182bf3062","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0x0000000000000000000000000000000000000000000000000009b2c08c45f8c6","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xb","removed":false},{"address":"0xeff23b4be1091b53205e35f3afcd9c7182bf3062","topics":["0x0e8e403c2d36126272b08c75823e988381d9dc47f2f0a9a080d95f891d95c469","0x000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8","0x00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30"],"data":"0x00000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000009b2c08c45f8c60000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c3803300000000000000000000000000000000000000000000000000000000004c4b4000000000000000000000000000000000000000000000000000000000000004e2","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xc","removed":false},{"address":"0x82af49447d8a07e3bd95bd0d56f35241523fbab1","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef","0x0000000000000000000000009aed3a8896a85fe9a8cac52c9b402d092b629a30","0x0000000000000000000000000000000000000000000000000000000000000000"],"data":"0x0000000000000000000000000000000000000000000000000009b2c08c45f8c6","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xd","removed":false},{"address":"0x9aed3a8896a85fe9a8cac52c9b402d092b629a30","topics":["0x27c98e911efdd224f4002f6cd831c3ad0d2759ee176f9ee8466d95826af22a1c","0x000000000000000000000000ff970a61a04b1ca14834a43f5de4533ebddb5cc8","0x000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","0x000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033"],"data":"0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000009b2c08c45f8c6000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033000000000000000000000000b2552eb7460f77f34ce3e33ecfc99d6669c38033","blockHash":"0x272adcde49f322e12b5a266a3a4624d7c7f25b0472adfeecf5e7c340f89e57d4","blockNumber":"0x526ce19","transactionHash":"0x3f58f319457602324e2d3d1bbb4200154c291c428ebde5e7db3653d46cbc5ed7","transactionIndex":"0x2","logIndex":"0xe","removed":false}],"status":"0x1","logsBloom":"0x08000000000000000000800000000000000000000000000000000000000000100000000000000000000000000000000100004000000000020010400000200000000000010001000000000008000000010100000000040000000000000000000000000001020000080000000400000800000000000000000000000010400000010000000000000000000000000000000000000000000000000000000000000000061000000000000000000100800000000000010000000010000000200000000000000002000048000000000000100000000000000000200000000000000020000010000000000000020820000002000000000000000200800000000000200000","type":"0x0","effectiveGasPrice":"0x5f5e100","deposit_nonce":null,"gasUsedForL1":"0x1d79d2","l1BlockNumber":"0x106028d"}
        ;

        const parsed = try std.json.parseFromSlice(types.transactions.ArbitrumReceipt, testing.allocator, slice, .{});
        defer parsed.deinit();
    }
    {
        const slice =
            \\{
            \\  "pending":{
            \\     "0x0216d5032f356960cd3749c31ab34eeff21b3395":{
            \\        "806":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x0216d5032f356960cd3749c31ab34eeff21b3395",
            \\           "gas":"0x5208",
            \\           "gasPrice":"0xba43b7400",
            \\           "hash":"0xaf953a2d01f55cfe080c0c94150a60105e8ac3d51153058a1f03dd239dd08586",
            \\           "input":"0x",
            \\           "nonce":"0x326",
            \\           "to":"0x7f69a91a3cf4be60020fb58b893b7cbb65376db8",
            \\           "transactionIndex":null,
            \\           "type": "0x00",
            \\           "value":"0x19a99f0cf456000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     },
            \\     "0x24d407e5a0b506e1cb2fae163100b5de01f5193c":{
            \\        "34":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x24d407e5a0b506e1cb2fae163100b5de01f5193c",
            \\           "gas":"0x44c72",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0xb5b8b853af32226755a65ba0602f7ed0e8be2211516153b75e9ed640a7d359fe",
            \\           "input":"0xb61d27f600000000000000000000000024d407e5a0b506e1cb2fae163100b5de01f5193c00000000000000000000000000000000000000000000000053444835ec580000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            \\           "nonce":"0x22",
            \\           "to":"0x7320785200f74861b69c49e4ab32399a71b34f1a",
            \\           "transactionIndex":null,
            \\           "type": "0x00",
            \\           "value":"0x0",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     }
            \\  },
            \\  "queued":{
            \\     "0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c":{
            \\        "3":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "type": "0x00",
            \\           "blockNumber":null,
            \\           "from":"0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0x57b30c59fc39a50e1cba90e3099286dfa5aaf60294a629240b5bbec6e2e66576",
            \\           "input":"0x",
            \\           "nonce":"0x3",
            \\           "to":"0x346fb27de7e7370008f5da379f74dd49f5f2f80f",
            \\           "transactionIndex":null,
            \\           "value":"0x1f161421c8e0000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     },
            \\     "0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a":{
            \\        "2":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a",
            \\           "type": "0x00",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0xba43b7400",
            \\           "hash":"0x3a3c0698552eec2455ed3190eac3996feccc806970a4a056106deaf6ceb1e5e3",
            \\           "input":"0x",
            \\           "nonce":"0x2",
            \\           "to":"0x24a461f25ee6a318bdef7f33de634a67bb67ac9d",
            \\           "transactionIndex":null,
            \\           "value":"0xebec21ee1da40000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        },
            \\        "6":{
            \\           "blockHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
            \\           "blockNumber":null,
            \\           "from":"0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a",
            \\           "gas":"0x15f90",
            \\           "gasPrice":"0x4a817c800",
            \\           "hash":"0xbbcd1e45eae3b859203a04be7d6e1d7b03b222ec1d66dfcc8011dd39794b147e",
            \\           "input":"0x",
            \\           "type": "0x00",
            \\           "nonce":"0x6",
            \\           "to":"0x6368f3f8c2b42435d6c136757382e4a59436a681",
            \\           "transactionIndex":null,
            \\           "value":"0xf9a951af55470000",
            \\           "v": "0x1",
            \\           "r": "0x23213",
            \\           "s": "0x32423452"
            \\        }
            \\     }
            \\  }
            \\}
            \\
        ;
        const parsed = try std.json.parseFromSlice(@import("../../types/txpool.zig").TxPoolContent, testing.allocator, slice, .{});
        defer parsed.deinit();

        const all = try std.json.stringifyAlloc(testing.allocator, parsed.value, .{});
        defer testing.allocator.free(all);
    }
    {
        const slice =
            \\{
            \\  "pending":{
            \\     "0x26588a9301b0428d95e6fc3a5024fce8bec12d51":{
            \\        "31813":"0x3375ee30428b2a71c428afa5e89e427905f95f7e: 0 wei + 500000 × 20000000000 wei"
            \\     },
            \\     "0x2a65aca4d5fc5b5c859090a6c34d164135398226":{
            \\        "563662":"0x958c1fa64b34db746925c6f8a3dd81128e40355e: 1051546810000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563663":"0x77517b1491a0299a44d668473411676f94e97e34: 1051190740000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563664":"0x3e2a7fe169c8f8eee251bb00d9fb6d304ce07d3a: 1050828950000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563665":"0xaf6c4695da477f8c663ea2d8b768ad82cb6a8522: 1050544770000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563666":"0x139b148094c50f4d20b01caf21b85edb711574db: 1048598530000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563667":"0x48b3bd66770b0d1eecefce090dafee36257538ae: 1048367260000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563668":"0x468569500925d53e06dd0993014ad166fd7dd381: 1048126690000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563669":"0x3dcb4c90477a4b8ff7190b79b524773cbe3be661: 1047965690000000000 wei + 90000 gas × 20000000000 wei",
            \\        "563670":"0x6dfef5bc94b031407ffe71ae8076ca0fbf190963: 1047859050000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0x9174e688d7de157c5c0583df424eaab2676ac162":{
            \\        "3":"0xbb9bc244d798123fde783fcc1c72d3bb8c189413: 30000000000000000000 wei + 85000 gas × 21000000000 wei"
            \\     },
            \\     "0xb18f9d01323e150096650ab989cfecd39d757aec":{
            \\        "777":"0xcd79c72690750f079ae6ab6ccd7e7aedc03c7720: 0 wei + 1000000 gas × 20000000000 wei"
            \\     },
            \\     "0xb2916c870cf66967b6510b76c07e9d13a5d23514":{
            \\        "2":"0x576f25199d60982a8f31a8dff4da8acb982e6aba: 26000000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0xbc0ca4f217e052753614d6b019948824d0d8688b":{
            \\        "0":"0x2910543af39aba0cd09dbb2d50200b3e800a63d2: 1000000000000000000 wei + 50000 gas × 1171602790622 wei"
            \\     },
            \\     "0xea674fdde714fd979de3edf0f56aa9716b898ec8":{
            \\        "70148":"0xe39c55ead9f997f7fa20ebe40fb4649943d7db66: 1000767667434026200 wei + 90000 gas × 20000000000 wei"
            \\     }
            \\  },
            \\  "queued":{
            \\     "0x0f6000de1578619320aba5e392706b131fb1de6f":{
            \\        "6":"0x8383534d0bcd0186d326c993031311c0ac0d9b2d: 9000000000000000000 wei + 21000 gas × 20000000000 wei"
            \\     },
            \\     "0x5b30608c678e1ac464a8994c3b33e5cdf3497112":{
            \\        "6":"0x9773547e27f8303c87089dc42d9288aa2b9d8f06: 50000000000000000000 wei + 90000 gas × 50000000000 wei"
            \\     },
            \\     "0x976a3fc5d6f7d259ebfb4cc2ae75115475e9867c":{
            \\        "3":"0x346fb27de7e7370008f5da379f74dd49f5f2f80f: 140000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     },
            \\     "0x9b11bf0459b0c4b2f87f8cebca4cfc26f294b63a":{
            \\        "2":"0x24a461f25ee6a318bdef7f33de634a67bb67ac9d: 17000000000000000000 wei + 90000 gas × 50000000000 wei",
            \\        "6":"0x6368f3f8c2b42435d6c136757382e4a59436a681: 17990000000000000000 wei + 90000 gas × 20000000000 wei",
            \\        "7":"0x6368f3f8c2b42435d6c136757382e4a59436a681: 17900000000000000000 wei + 90000 gas × 20000000000 wei"
            \\     }
            \\  }
            \\}
        ;

        const parsed = try std.json.parseFromSlice(@import("../../types/txpool.zig").TxPoolInspect, testing.allocator, slice, .{});
        defer parsed.deinit();

        const all = try std.json.stringifyAlloc(testing.allocator, parsed.value, .{});
        defer testing.allocator.free(all);
    }
}
