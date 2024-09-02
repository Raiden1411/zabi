const meta_json = @import("../meta/json.zig");
const meta_utils = @import("../meta/utils.zig");
const specification = @import("../evm/specification.zig");
const std = @import("std");
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @This();
const Child = std.process.Child;
const Client = std.http.Client;
const ConvertToEnum = meta_utils.ConvertToEnum;
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const SpecId = specification.SpecId;
const Value = std.json.Value;

/// Set of errors while fetching from a json rpc http endpoint.
pub const FetchErrors = Allocator.Error || Client.RequestError || Client.Request.WaitError ||
    Client.Request.FinishError || Client.Request.ReadError || std.Uri.ParseError || error{ StreamTooLong, InvalidRequest };

/// Values needed for the `anvil_reset` request.
pub const Forking = struct {
    jsonRpcUrl: []const u8,
    blockNumber: ?u64 = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta_json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta_json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta_json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Struct representation of a `anvil_reset` request.
pub const Reset = struct {
    forking: Forking,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta_json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta_json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta_json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Similar to Ethereum RPC Request but only for `AnvilMethods`.
pub fn AnvilRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: AnvilMethods,
        params: T,
        id: usize = 1,

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            return meta_json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            return meta_json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
            return meta_json.jsonStringify(@This(), self, writer_stream);
        }
    };
}

/// Set of methods implemented by this client for use with anvil.
pub const AnvilMethods = enum {
    anvil_setBalance,
    anvil_setCode,
    anvil_setChainId,
    anvil_setCoinbase,
    anvil_setNonce,
    anvil_setNextBlockBaseFeePerGas,
    anvil_setMinGasPrice,
    anvil_dropTransaction,
    anvil_mine,
    anvil_reset,
    anvil_impersonateAccount,
    anvil_stopImpersonatingAccount,
    anvil_setRpcUrl,
    anvil_setLoggingEnabled,
};

/// All startup options for starting an anvil proccess.
///
/// All `null` or `false` will not be emitted if you use `parseToArgumentsSlice`
pub const AnvilStartOptions = struct {
    /// Number of accounts to start anvil with
    accounts: ?u8 = null,
    /// Enable autoImpersonate on start up.
    @"auto-impersonate": bool = false,
    /// Block time in seconds for interval mining.
    @"block-time": ?u64 = null,
    /// Choose the EVM hardfork to use.
    hardfork: ?SpecId = null,
    /// The path to initialize the `genesis.json` file.
    init: ?[]const u8 = null,
    /// BIP39 mnemonic phrase used to generate accounts.
    mnemonic: ?[]const u8 = null,
    /// Disable auto and interval mining.
    @"no-mining": bool = false,
    /// The order were the transactions are ordered in the mempool.
    order: ?enum { fifo, fees } = null,
    /// The port number to listen on.
    port: ?u16 = null,
    /// Enables steps tracing for debug calls. Returns geth style traces.
    @"steps-tracing": bool = false,
    /// Starts the IPC endpoint at a given path.
    ipc: ?[]const u8 = null,
    /// Don't send messages to stdout on startup.
    silent: bool = false,
    /// Set the timestamp of the genesis block.
    timestamp: ?u64 = null,
    /// Disable deploying the default `CREATE2` factory when running anvil without forking.
    @"disable-default-create2-deployer": bool = false,
    /// Fetch state over a remote endpoint instead of starting from an empty state.
    @"fork-url": ?[]const u8 = null,
    /// Fetch state from a specific block number over a remote endpoint. This is dependent of passing `fork-url`.
    @"fork-block-number": ?u64 = null,
    /// Initial retry backoff on encountering errors.
    @"fork-retry-backoff": ?u64 = null,
    /// Number of retries per request for spurious networks.
    retries: bool = false,
    /// Timeout in ms for requests sent to the remote JSON-RPC server in forking mode.
    timeout: ?u64 = null,
    /// Sets the number of assumed available compute units per second for this provider.
    @"compute-units-per-second": ?u64 = null,
    /// Disables rate limiting for this node’s provider. Will always override --compute-units-per-second if present.
    @"no-rate-limit": bool = false,
    /// Disables RPC caching; all storage slots are read from the endpoint. This flag overrides the project’s configuration file
    @"no-storage-cache": bool = false,
    /// The base fee in a block
    @"base-fee": ?u64 = null,
    /// The chain ID
    @"chain-id": ?u64 = null,
    /// EIP-170: Contract code size limit in bytes. Useful to increase for tests.
    @"code-size-limit": ?u64 = null,
    /// The block gas limit
    @"gas-limit": ?u64 = null,
    /// The gas price
    @"gas-price": ?u64 = null,
    /// Set the CORS `allow_origin`
    @"allow-origin": ?[]const u8 = null,
    /// Disable CORS
    @"no-cors": bool = false,
    /// The IP address server will listen on.
    host: ?[]const u8 = null,
    /// Writes output of `anvil` as json to use specified file.
    @"config-out": ?[]const u8 = null,
    /// Dont keep full chain history.
    @"prune-history": bool = false,

    /// Converts `self` into a list of slices that will be used by the `anvil process.`
    /// If `self` is set with default value only the `anvil` command will be set in the list.
    pub fn parseToArgumentsSlice(self: AnvilStartOptions, allocator: Allocator) (Allocator.Error || error{NoSpaceLeft})![]const []const u8 {
        var list = try std.ArrayList([]const u8).initCapacity(allocator, 1);
        errdefer list.deinit();

        list.appendAssumeCapacity("anvil");

        inline for (std.meta.fields(@TypeOf(self))) |field| {
            const info = @typeInfo(field.type);

            switch (info) {
                .bool => {
                    if (@field(self, field.name)) {
                        const argument = "--" ++ field.name;
                        try list.append(argument);
                    }
                },
                .optional => {
                    if (@field(self, field.name)) |value| {
                        const value_info = @typeInfo(@TypeOf(value));

                        var buffer: [1024]u8 = undefined;
                        var buf_writer = std.io.fixedBufferStream(&buffer);

                        try list.ensureUnusedCapacity(2);

                        // Adds the argument name.
                        {
                            const argument = "--" ++ field.name;

                            list.appendAssumeCapacity(argument);
                        }

                        // Adds the arguments associated value.
                        {
                            switch (value_info) {
                                .int => try buf_writer.writer().print("{d}", .{value}),
                                .pointer => try buf_writer.writer().print("{s}", .{value}),
                                .@"enum" => try buf_writer.writer().print("{s}", .{@tagName(value)}),
                                else => @compileError("Unsupported type '" ++ @typeName(@TypeOf(value)) ++ "'"),
                            }

                            list.appendAssumeCapacity(buf_writer.getWritten());
                        }
                    }
                },
                else => @compileError("Unsupported type '" ++ @typeName(field.type) ++ "'"),
            }
        }

        return list.toOwnedSlice();
    }
};

/// Set of inital options to start the http client.
pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The port to use in anvil
    port: u16 = 6969,
};

/// Allocator to use to create the ChildProcess and other allocations
allocator: Allocator,
/// The localhost address uri.
uri: std.Uri,
/// The socket connection to anvil. Use `connectToAnvil` to populate this.
http_client: Client,

/// Inits the client but doesn't start a seperate process.
/// Use this if you already have an `anvil` instance running
pub fn initClient(self: *Anvil, options: InitOptions) void {
    const uri: std.Uri = .{
        .port = options.port,
        .host = .{ .percent_encoded = "localhost" },
        .scheme = "http",
    };

    self.* = .{
        .allocator = options.allocator,
        .uri = uri,
        .http_client = Client{ .allocator = options.allocator },
    };
}
/// Start the `anvil` as a child process. The arguments list will be created based on
/// `AnvilStartOptions`. This will need to allocate memory since it will create the list.
///
/// If `options` are set to their default value it will only start with `anvil` and no arguments.
pub fn initProcess(allocator: Allocator, options: AnvilStartOptions) (Allocator.Error || error{NoSpaceLeft} || Child.SpawnError)!Child {
    const args_slice = try options.parseToArgumentsSlice(allocator);
    defer allocator.free(args_slice);

    var result = std.process.Child.init(args_slice, allocator);
    result.stdin_behavior = .Ignore;
    result.stdout_behavior = .Ignore;
    result.stderr_behavior = .Ignore;

    try result.spawn();

    return result;
}
/// Cleans up the http client
pub fn deinit(self: *Anvil) void {
    self.http_client.deinit();
}
/// Sets the balance of a anvil account
pub fn setBalance(self: *Anvil, address: Address, balance: u256) FetchErrors!void {
    const request: AnvilRequest(struct { Address, u256 }) = .{ .params = .{ address, balance }, .method = .anvil_setBalance };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the contract code of a address.
pub fn setCode(self: *Anvil, address: Address, code: Hex) FetchErrors!void {
    const request: AnvilRequest(struct { Address, Hex }) = .{ .params = .{ address, code }, .method = .anvil_setCode };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the rpc of the anvil connection
pub fn setRpcUrl(self: *Anvil, rpc_url: []const u8) FetchErrors!void {
    const request: AnvilRequest(struct { []const u8 }) = .{ .params = .{rpc_url}, .method = .anvil_setRpcUrl };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the coinbase address
pub fn setCoinbase(self: *Anvil, address: Address) FetchErrors!void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_setCoinbase };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Enable anvil verbose logging for anvil.
pub fn setLoggingEnable(self: *Anvil) FetchErrors!void {
    const request: AnvilRequest(std.meta.Tuple(&[_]type{})) = .{ .params = .{}, .method = .anvil_setLoggingEnabled };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the min gasprice from the anvil fork
pub fn setMinGasPrice(self: *Anvil, new_price: u64) FetchErrors!void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setMinGasPrice };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the block base fee from the anvil fork
pub fn setNextBlockBaseFeePerGas(self: *Anvil, new_price: u64) FetchErrors!void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setNextBlockBaseFeePerGas };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the networks chainId
pub fn setChainId(self: *Anvil, new_id: u64) FetchErrors!void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_id}, .method = .anvil_setChainId };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the nonce of a account
pub fn setNonce(self: *Anvil, address: Address, new_nonce: u64) FetchErrors!void {
    const request: AnvilRequest(struct { Address, u64 }) = .{ .params = .{ address, new_nonce }, .method = .anvil_setNonce };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Drops a pending transaction from the mempool
pub fn dropTransaction(self: *Anvil, tx_hash: Hash) FetchErrors!void {
    const request: AnvilRequest(struct { Hash }) = .{ .params = .{tx_hash}, .method = .anvil_dropTransaction };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Mine a pending transaction
pub fn mine(self: *Anvil, amount: u64, time_in_seconds: ?u64) FetchErrors!void {
    const request: AnvilRequest(struct { u64, ?u64 }) = .{ .params = .{ amount, time_in_seconds }, .method = .anvil_mine };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Reset the fork
pub fn reset(self: *Anvil, reset_config: Reset) FetchErrors!void {
    const request: AnvilRequest(struct { Reset }) = .{ .params = .{reset_config}, .method = .anvil_reset };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.
pub fn impersonateAccount(self: *Anvil, address: Address) FetchErrors!void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Stops impersonating a EOA or contract.
pub fn stopImpersonatingAccount(self: *Anvil, address: Address) FetchErrors!void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Internal only. Discards the body from the response.
fn sendRpcRequest(self: *Anvil, req_body: []u8) FetchErrors!void {
    const req = try self.http_client.fetch(.{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .payload = req_body,
        .location = .{ .uri = self.uri },
    });

    if (req.status != .ok)
        return error.InvalidRequest;
}
