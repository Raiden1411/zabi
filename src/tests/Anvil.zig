const meta = @import("../meta/meta.zig");
const std = @import("std");
const types = @import("../meta/ethereum.zig");
const utils = @import("../utils/utils.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @This();
const Hash = types.Hash;
const Hex = types.Hex;
const RequestParser = meta.RequestParser;

pub const Reset = struct {
    forking: struct {
        jsonRpcUrl: []const u8,
        blockNumber: u64,
    },

    pub usingnamespace RequestParser(@This());
};

pub fn AnvilRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: AnvilMethods,
        params: T,
        id: usize = 1,

        pub usingnamespace RequestParser(@This());
    };
}

pub const AnvilMethods = enum { anvil_setBalance, anvil_setCode, anvil_setChainId, anvil_setNonce, anvil_setNextBlockBaseFeePerGas, anvil_setMinGasPrice, anvil_dropTransaction, anvil_mine, anvil_reset, anvil_impersonateAccount, anvil_stopImpersonatingAccount, anvil_setRpcUrl };

pub const StartUpOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    alloc: Allocator,
    /// Fork url for anvil to fork from
    fork_url: []const u8,
    /// Fork block number to use
    block_number_fork: u64 = 19062632,
    /// The localhost address.
    localhost: []const u8 = "http://127.0.0.1:8545/",
};

/// Allocator to use to create the ChildProcess and other allocations
alloc: std.mem.Allocator,
/// Fork block number to use
block_number_fork: u64,
/// The localhost address uri.
localhost: std.Uri,
/// Fork url for anvil to fork from
fork_url: []const u8,
/// The socket connection to anvil. Use `connectToAnvil` to populate this.
http_client: std.http.Client,
/// The ChildProcess result. This contains all related commands.
result: std.ChildProcess,
/// The theared that gets spawn on init for the ChildProcess so that we don't block the main thread.
thread: std.Thread,
/// Connection closed.
closed: bool = false,

pub fn initClient(self: *Anvil, opts: StartUpOptions) !void {
    self.* = .{
        .alloc = opts.alloc,
        .fork_url = opts.fork_url,
        .localhost = try std.Uri.parse(opts.localhost),
        .block_number_fork = opts.block_number_fork,
        .http_client = std.http.Client{ .allocator = opts.alloc },
        .thread = undefined,
        .result = undefined,
    };
}

/// Starts anvil process on a seperate thread;
pub fn initProcess(self: *Anvil, opts: StartUpOptions) !void {
    self.* = .{
        .alloc = opts.alloc,
        .fork_url = opts.fork_url,
        .localhost = try std.Uri.parse(opts.localhost),
        .block_number_fork = opts.block_number_fork,
        .thread = try std.Thread.spawn(.{}, start, .{self}),
        .http_client = std.http.Client{ .allocator = opts.alloc },
        .result = undefined,
    };

    self.thread.detach();
}

/// Cleans up the http client
pub fn deinit(self: *Anvil) void {
    if (@cmpxchgStrong(bool, &self.closed, false, true, .Monotonic, .Monotonic) == null) {
        self.http_client.deinit();
    }
}

/// Kills the anvil process and closes any connections.
/// Only use this if a process was created before
pub fn killProcessAndDeinit(self: *Anvil) void {
    if (@cmpxchgStrong(bool, &self.closed, false, true, .Monotonic, .Monotonic) == null) {
        _ = self.result.kill() catch |err| {
            std.io.getStdErr().writer().writeAll(@errorName(err)) catch {};
        };
        self.http_client.deinit();
    }
}

/// Sets the balance of a anvil account
pub fn setBalance(self: *Anvil, address: Address, balance: u256) !void {
    const request: AnvilRequest(struct { Address, u256 }) = .{ .params = .{ address, balance }, .method = .anvil_setBalance };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the contract code of a address.
pub fn setCode(self: *Anvil, address: Address, code: Hex) !void {
    const request: AnvilRequest(struct { Address, Hex }) = .{ .params = .{ address, code }, .method = .set_Code };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the rpc of the anvil connection
pub fn setRpcUrl(self: *Anvil, rpc_url: []const u8) !void {
    const request: AnvilRequest(struct { []const u8 }) = .{ .params = .{rpc_url}, .method = .anvil_setRpcUrl };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the coinbase address
pub fn setCoinbase(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .set_Coinbase };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Enable anvil verbose logging for anvil.
pub fn setLoggingEnable(self: *Anvil) !void {
    const request: AnvilRequest(struct {}) = .{ .params = .{}, .method = .set_LoggingEnabled };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the min gasprice from the anvil fork
pub fn setMinGasPrice(self: *Anvil, new_price: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setMinGasPrice };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

pub fn setNextBlockBaseFeePerGas(self: *Anvil, new_price: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_price}, .method = .anvil_setNextBlockBaseFeePerGas };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the networks chainId
pub fn setChainId(self: *Anvil, new_id: u64) !void {
    const request: AnvilRequest(struct { u64 }) = .{ .params = .{new_id}, .method = .anvil_setChainId };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Changes the nonce of a account
pub fn setNonce(self: *Anvil, address: []const u8, new_nonce: u64) !void {
    const request: AnvilRequest(struct { Address, u64 }) = .{ .params = .{ address, new_nonce }, .method = .anvil_setNonce };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Drops a pending transaction from the mempool
pub fn dropTransaction(self: *Anvil, tx_hash: Hash) !void {
    const request: AnvilRequest(struct { Hash }) = .{ .params = .{tx_hash}, .method = .anvil_dropTransaction };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Mine a pending transaction
pub fn mine(self: *Anvil, amount: u64, time_in_seconds: ?u64) !void {
    const request: AnvilRequest(struct { u64, ?u64 }) = .{ .params = .{ amount, time_in_seconds }, .method = .anvil_mine };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Reset the fork
pub fn reset(self: *Anvil, reset_config: ?Reset) !void {
    const request: AnvilRequest(struct { ?Reset }) = .{ .params = .{reset_config}, .method = .anvil_reset };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.
pub fn impersonateAccount(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Stops impersonating a EOA or contract.
pub fn stopImpersonatingAccount(self: *Anvil, address: Address) !void {
    const request: AnvilRequest(struct { Address }) = .{ .params = .{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    return self.sendRpcRequest(req_body);
}

/// Start the child process. Use this with init if you want to use this in a seperate theread.
pub fn start(self: *Anvil) !void {
    const port = self.localhost.port orelse return error.InvalidAddressPort;
    var result = std.ChildProcess.init(&.{ "anvil", "-f", self.fork_url, "--fork-block-number", self.block_number_fork, "--port", port }, self.alloc);
    result.stdin_behavior = .Pipe;
    result.stdout_behavior = .Pipe;
    result.stderr_behavior = .Pipe;

    try result.spawn();

    self.result = result;
}

/// Connects and disconnets on success. Usefull for the test runner so that we block the main thread until we are ready.
pub fn waitUntilReady(alloc: std.mem.Allocator, pooling_interval: u64) !void {
    var retry: u32 = 0;
    var stream: std.net.Stream = undefined;
    while (true) {
        if (retry > 20) break;
        stream = std.net.tcpConnectToHost(alloc, "127.0.0.1", 8545) catch {
            std.time.sleep(pooling_interval * std.time.ns_per_ms);
            retry += 1;
            continue;
        };

        break;
    }

    stream.close();
}

fn sendRpcRequest(self: *Anvil, req_body: []u8) !void {
    var body = std.ArrayList(u8).init(self.alloc);
    defer body.deinit();

    const req = try self.http_client.fetch(.{ .headers = .{ .content_type = .{ .override = "application/json" } }, .payload = req_body, .location = .{ .uri = self.localhost }, .response_storage = .{ .dynamic = &body } });

    if (req.status != .ok) return error.InvalidRequest;
}
