const meta_json = @import("../meta/json.zig");
const meta_utils = @import("../meta/utils.zig");
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
const Value = std.json.Value;

/// Values needed for the `anvil_reset` request.
pub const Forking = struct {
    jsonRpcUrl: []const u8,
    blockNumber: u64,

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
    anvil_setNonce,
    anvil_setNextBlockBaseFeePerGas,
    anvil_setMinGasPrice,
    anvil_dropTransaction,
    anvil_mine,
    anvil_reset,
    anvil_impersonateAccount,
    anvil_stopImpersonatingAccount,
    anvil_setRpcUrl,
};

pub const StartProcessOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// Fork url for anvil to fork from
    fork_url: []const u8,
    /// Fork block number to use
    block_number_fork: u64 = 19062632,
    /// The port to use in anvil
    port: u16 = 6969,
};

pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The port to use in anvil
    port: u16 = 6969,
};

/// Allocator to use to create the ChildProcess and other allocations
allocator: Allocator,
/// Fork block number to use
block_number_fork: u64,
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
        .block_number_fork = 0,
        .http_client = Client{ .allocator = options.allocator },
    };
}
/// Starts anvil process as a child process. Return the created child.
/// The caller is responsible for calling `kill` on the created process.
pub fn initProcess(self: *Anvil, opts: StartProcessOptions) !Child {
    const uri: std.Uri = .{
        .port = opts.port,
        .host = .{ .percent_encoded = "localhost" },
        .scheme = "http",
    };

    self.* = .{
        .allocator = opts.allocator,
        .uri = uri,
        .block_number_fork = opts.block_number_fork,
        .http_client = std.http.Client{ .allocator = opts.allocator },
    };

    return self.start(opts.fork_url);
}
/// Cleans up the http client
pub fn deinit(self: *Anvil) void {
    self.http_client.deinit();
}
/// Sets the balance of a anvil account
pub fn setBalance(self: *Anvil, address: Address, balance: u256) !void {
    const request: AnvilRequest(struct { Address, u256 }) = .{ .params = .{ address, balance }, .method = .anvil_setBalance };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the contract code of a address.
pub fn setCode(self: *Anvil, address: Address, code: Hex) !void {
    const request: AnvilRequest(struct { Address, Hex }) = .{ .params = .{ address, code }, .method = .set_Code };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the rpc of the anvil connection
pub fn setRpcUrl(self: *Anvil, rpc_url: []const u8) !void {
    const request: AnvilRequest(struct { []const u8 }) = .{ .params = .{rpc_url}, .method = .anvil_setRpcUrl };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the coinbase address
pub fn setCoinbase(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .set_Coinbase };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Enable anvil verbose logging for anvil.
pub fn setLoggingEnable(self: *Anvil) !void {
    const request: AnvilRequest(struct {}) = .{ .params = .{}, .method = .set_LoggingEnabled };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the min gasprice from the anvil fork
pub fn setMinGasPrice(self: *Anvil, new_price: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setMinGasPrice };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the block base fee from the anvil fork
pub fn setNextBlockBaseFeePerGas(self: *Anvil, new_price: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setNextBlockBaseFeePerGas };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the networks chainId
pub fn setChainId(self: *Anvil, new_id: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_id}, .method = .anvil_setChainId };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the nonce of a account
pub fn setNonce(self: *Anvil, address: Address, new_nonce: u64) !void {
    const request: AnvilRequest(struct { Address, u64 }) = .{ .params = .{ address, new_nonce }, .method = .anvil_setNonce };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Drops a pending transaction from the mempool
pub fn dropTransaction(self: *Anvil, tx_hash: Hash) !void {
    const request: AnvilRequest(struct { Hash }) = .{ .params = .{tx_hash}, .method = .anvil_dropTransaction };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Mine a pending transaction
pub fn mine(self: *Anvil, amount: u64, time_in_seconds: ?u64) !void {
    const request: AnvilRequest(struct { u64, ?u64 }) = .{ .params = .{ amount, time_in_seconds }, .method = .anvil_mine };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Reset the fork
pub fn reset(self: *Anvil, reset_config: ?Reset) !void {
    const request: AnvilRequest(struct { ?Reset }) = .{ .params = .{reset_config}, .method = .anvil_reset };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.
pub fn impersonateAccount(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Stops impersonating a EOA or contract.
pub fn stopImpersonatingAccount(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Start the child process. Use this with init if you want to use this in a seperate theread.
pub fn start(self: *Anvil, fork_url: []const u8) !Child {
    const port = try std.fmt.allocPrint(self.allocator, "{d}", .{self.localhost.port orelse return error.InvalidAddressPort});
    defer self.allocator.free(port);

    const block = try std.fmt.allocPrint(self.allocator, "{d}", .{self.block_number_fork});
    defer self.allocator.free(block);

    var result = std.process.Child.init(&.{ "anvil", "-f", fork_url, "--fork-block-number", block, "--port", port, "--ipc" }, self.allocator);
    result.stdin_behavior = .Ignore;
    result.stdout_behavior = .Ignore;
    result.stderr_behavior = .Ignore;

    try result.spawn();

    return result;
}

// Internal
fn sendRpcRequest(self: *Anvil, req_body: []u8) !void {
    var body = std.ArrayList(u8).init(self.allocator);
    defer body.deinit();

    const req = try self.http_client.fetch(.{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .payload = req_body,
        .location = .{ .uri = self.uri },
        .response_storage = .{ .dynamic = &body },
    });

    if (req.status != .ok)
        return error.InvalidRequest;
}
