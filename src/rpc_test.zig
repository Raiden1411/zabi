//! The objective of this test is to not crash.
//! No checks are made. It's essentially a way to fuzz
//! our custom json parser and stringyfier. And to make sure
//! that the requests are sent and parsed without crashes.
//!
//! By default no debug message will be printed to the console.
//! If you which for this you will need to update the log level inside this
//! file.
//!
//! You can configure the amount of runs this will take by
//! passing in the '--runs=number' argument, but if nothing is provided
//! then it will default to 100 runs foreach rpc client.
const args_parser = @import("tests/args.zig");
const std = @import("std");
const utils = @import("utils/utils.zig");

const ENSClient = @import("clients/ens/ens.zig").ENSClient;
const L1Client = @import("clients/optimism/clients/L1PubClient.zig").L1Client;
const PubClient = @import("clients/Client.zig");
const WalletClients = @import("clients/wallet.zig").WalletClients;
const WebSocketClient = @import("clients/WebSocket.zig");
const IPCClient = @import("clients/IPC.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const CliArgs = struct {
    runs: ?usize = null,
    eth_specific: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const parsed = args_parser.parseArgs(CliArgs, gpa.allocator(), &args);

    const uri = try std.Uri.parse("http://localhost:8545/");

    var i: usize = 0;
    const runs = parsed.runs orelse 100;
    var rand = std.rand.DefaultPrng.init(runs);

    const clients = &[_]type{ PubClient, WebSocketClient, IPCClient };

    std.debug.print(
        \\ Script will run {d} times
    , .{runs * clients.len});

    inline for (clients) |Client| {
        var rpc_client: Client = undefined;
        defer rpc_client.deinit();

        if (Client == IPCClient) {
            try rpc_client.init(.{
                .path = "/tmp/anvil.ipc",
                .allocator = gpa.allocator(),
            });
        } else {
            try rpc_client.init(.{
                .uri = uri,
                .allocator = gpa.allocator(),
            });
        }

        const client: WalletClients = comptime blk: {
            break :blk switch (Client) {
                PubClient => .http,
                WebSocketClient => .websocket,
                IPCClient => .ipc,
                else => @compileError("Invalid type"),
            };
        };

        var op: L1Client(client) = undefined;
        defer op.deinit();

        if (Client == IPCClient) {
            try op.init(.{
                .path = "/tmp/anvil.ipc",
                .allocator = gpa.allocator(),
            }, null);
        } else {
            try op.init(.{
                .uri = uri,
                .allocator = gpa.allocator(),
            }, null);
        }

        var ens: ENSClient(client) = undefined;
        defer ens.deinit();

        if (Client == IPCClient) {
            try ens.init(
                .{ .path = "/tmp/anvil.ipc", .allocator = gpa.allocator() },
                .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
            );
        } else {
            try ens.init(
                .{ .uri = uri, .allocator = gpa.allocator() },
                .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
            );
        }

        const block_number = try rpc_client.getBlockNumber();
        defer block_number.deinit();

        while (i < runs) : (i += 1) {
            // Normal RPC requests.
            const num = rand.random().intRangeAtMost(u32, 0, @truncate(block_number.response));

            const block = try rpc_client.getBlockByNumber(.{ .block_number = num, .include_transaction_objects = num % 2 == 0 });
            defer block.deinit();

            const base_fee = switch (block.response) {
                inline else => |b| b.baseFeePerGas,
            };

            const hash = switch (block.response) {
                inline else => |b| b.hash,
            };

            switch (block.response) {
                inline else => |b| {
                    if (b.transactions) |txs| {
                        switch (txs) {
                            .hashes => |hashes| {
                                if (hashes.len > 0) {
                                    const buffer: [32]u8 = hashes[hashes.len - 1];

                                    const transaction = try rpc_client.getTransactionByHash(buffer);
                                    defer transaction.deinit();

                                    const receipt = try rpc_client.getTransactionReceipt(buffer);
                                    defer receipt.deinit();

                                    const from = switch (receipt.response) {
                                        inline else => |tx_receipt| tx_receipt.from,
                                    };

                                    const contract = switch (receipt.response) {
                                        inline else => |tx_receipt| tx_receipt.contractAddress,
                                    };

                                    if (contract) |addr| {
                                        const code = try rpc_client.getContractCode(.{ .address = addr, .block_number = num });
                                        defer code.deinit();
                                    }

                                    const nonce = try rpc_client.getAddressTransactionCount(.{ .block_number = num, .address = from });
                                    defer nonce.deinit();

                                    const balance = try rpc_client.getAddressBalance(.{ .address = from, .block_number = num });
                                    defer balance.deinit();
                                }
                            },
                            .objects => |txs_object| {
                                if (txs_object.len > 0) {
                                    const from = switch (txs_object[txs_object.len - 1]) {
                                        inline else => |tx| tx.from,
                                    };

                                    const nonce = try rpc_client.getAddressTransactionCount(.{ .block_number = num, .address = from });
                                    defer nonce.deinit();

                                    const balance = try rpc_client.getAddressBalance(.{ .address = from, .block_number = num });
                                    defer balance.deinit();
                                }
                            },
                        }
                    }
                },
            }

            const bloch_by_hash = try rpc_client.getBlockByHash(.{ .block_hash = hash.? });
            defer bloch_by_hash.deinit();

            const logs = try rpc_client.getLogs(.{ .fromBlock = num, .toBlock = num }, null);
            defer logs.deinit();

            const proof = try rpc_client.getProof(.{
                .address = try utils.addressToBytes("0x7F0d15C7FAae65896648C8273B6d7E43f58Fa842"),
                .storageKeys = &.{try utils.hashToBytes("0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")},
                .blockNumber = num,
            }, null);
            defer proof.deinit();

            const uncle = try rpc_client.getUncleCountByBlockNumber(.{ .block_number = num });
            defer uncle.deinit();

            const uncle_hash_count = try rpc_client.getUncleCountByBlockHash(hash.?);
            defer uncle_hash_count.deinit();

            if (uncle.response > 0) {
                const uncle_block = try rpc_client.getUncleByBlockNumberAndIndex(.{ .block_number = num }, 0);
                defer uncle_block.deinit();

                const uncle_block_hash = try rpc_client.getUncleByBlockHashAndIndex(hash.?, 0);
                defer uncle_block_hash.deinit();
            }

            const fee_history = try rpc_client.feeHistory(5, .{ .block_number = num }, &[_]f64{ 20, 30 });
            defer fee_history.deinit();

            const block_info = try rpc_client.getBlockTransactionCountByNumber(.{ .block_number = num });
            defer block_info.deinit();

            const storage = try rpc_client.getStorage(
                try utils.addressToBytes("0x295a70b2de5e3953354a6a8344e616ed314d7251"),
                try utils.hashToBytes("0x6661e9d6d8b923d5bbaab1b96e1dd51ff6ea2a93520fdc9eb75d059238b8c5e9"),
                .{ .block_number = num },
            );
            defer storage.deinit();

            const gas = try rpc_client.estimateGas(.{ .london = .{
                .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
                .value = 0,
            } }, .{ .block_number = num });
            defer gas.deinit();

            _ = try rpc_client.estimateFeesPerGas(.{ .london = .{
                .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
                .value = 0,
            } }, base_fee);

            _ = try rpc_client.estimateMaxFeePerGasManual(base_fee);

            const id_block = try rpc_client.newBlockFilter();
            defer id_block.deinit();

            const id_logs = try rpc_client.newLogFilter(.{ .fromBlock = num, .toBlock = num }, null);
            defer id_logs.deinit();

            const id = try rpc_client.newPendingTransactionFilter();
            defer id.deinit();

            const logs_tx = try rpc_client.getFilterOrLogChanges(id.response, .eth_getFilterChanges);
            defer logs_tx.deinit();

            const logs_log = try rpc_client.getFilterOrLogChanges(id_logs.response, .eth_getFilterLogs);
            defer logs_log.deinit();

            if (parsed.eth_specific) {
                // OPStack
                const messages = try op.getL2HashesForDepositTransaction(try utils.hashToBytes("0x33faeeee9c6d5e19edcdfc003f329c6652f05502ffbf3218d9093b92589a42c4"));
                defer gpa.allocator().free(messages);

                _ = try op.getL2Output(2725977);

                _ = try op.getSecondsToFinalize(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
                const block_l2 = try op.getLatestProposedL2BlockNumber();
                _ = try op.getSecondsToNextL2Output(block_l2);

                const deposit_events = try op.getTransactionDepositEvents(try utils.hashToBytes("0xe94031c3174788c3fee7216465c50bb2b72e7a1963f5af807b3768da10827f5c"));
                defer {
                    for (deposit_events) |event| gpa.allocator().free(event.opaqueData);
                    gpa.allocator().free(deposit_events);
                }

                _ = try op.getProvenWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));

                _ = try op.getFinalizedWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));

                // Ens
                _ = try ens.getEnsResolver("vitalik.eth", .{});
                {
                    const value = try ens.getEnsAddress("vitalik.eth", .{});
                    defer value.deinit();
                }
                {
                    const value = try ens.getEnsName("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", .{});
                    defer value.deinit();
                }
            }
        }

        i = 0;
    }
}
