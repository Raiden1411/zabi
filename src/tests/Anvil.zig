const meta = @import("../meta/meta.zig");
const std = @import("std");
const utils = @import("../utils.zig");
const Allocator = std.mem.Allocator;

const Anvil = @This();

pub const Reset = struct {
    forking: struct {
        jsonRpcUrl: []const u8,
        blockNumber: u64,
    },
};

pub fn AnvilRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: AnvilMethods,
        params: T,
        id: usize = 1,
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
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
    retry_count: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
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
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// The socket connection to anvil. Use `connectToAnvil` to populate this.
http_client: std.http.Client,
/// The ChildProcess result. This contains all related commands.
result: std.ChildProcess,
/// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
retry_count: u8,
/// The theared that gets spawn on init for the ChildProcess so that we don't block the main thread.
thread: std.Thread,

pub fn initClient(self: *Anvil, opts: StartUpOptions) !void {
    self.* = .{
        .alloc = opts.alloc,
        .fork_url = opts.fork_url,
        .localhost = try std.Uri.parse(opts.localhost),
        .pooling_interval = opts.pooling_interval,
        .retry_count = opts.retry_count,
        .block_number_fork = opts.block_number_fork,
        .http_client = std.http.Client{ .allocator = opts.alloc },
        .thread = undefined,
        .result = undefined,
    };
}

pub fn initProcess(self: *Anvil, opts: StartUpOptions) !void {
    self.* = .{
        .alloc = opts.alloc,
        .fork_url = opts.fork_url,
        .localhost = try std.Uri.parse(opts.localhost),
        .pooling_interval = opts.pooling_interval,
        .retry_count = opts.retry_count,
        .block_number_fork = opts.block_number_fork,
        .thread = try std.Thread.spawn(.{}, start, .{self}),
        .http_client = std.http.Client{ .allocator = opts.alloc },
        .result = undefined,
    };
}

pub fn deinit(self: *Anvil) void {
    self.http_client.deinit();
}

/// Kills the anvil process and closes any connections.
pub fn deinitProcess(self: *Anvil) void {
    _ = self.result.kill() catch |err| {
        std.io.getStdErr().writer().writeAll(@errorName(err)) catch {};
    };
    self.http_client.deinit();
    self.thread.detach();
}

pub fn setBalance(self: *Anvil, address: []const u8, balance: u256) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    const hex_balance = try std.fmt.allocPrint(self.alloc, "0x{x}", .{balance});
    defer self.alloc.free(hex_balance);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{ address, hex_balance }, .method = .anvil_setBalance };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setCode(self: *Anvil, address: []const u8, code: []const u8) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{ address, code }, .method = .set_Code };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setRpcUrl(self: *Anvil, rpc_url: []const u8) !void {
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{rpc_url}, .method = .anvil_setRpcUrl };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setCoinbase(self: *Anvil, address: []const u8) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{address}, .method = .set_Coinbase };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setLoggingEnable(self: *Anvil) !void {
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest(&[_]type{}) = .{ .params = &.{}, .method = .set_LoggingEnabled };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setMinGasPrice(self: *Anvil, new_price: u64) !void {
    const hex_balance = try std.fmt.allocPrint(self.alloc, "0x{x}", .{new_price});
    defer self.alloc.free(hex_balance);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{hex_balance}, .method = .anvil_setMinGasPrice };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setNextBlockBaseFeePerGas(self: *Anvil, new_price: u64) !void {
    const hex_balance = try std.fmt.allocPrint(self.alloc, "0x{x}", .{new_price});
    defer self.alloc.free(hex_balance);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{hex_balance}, .method = .anvil_setNextBlockBaseFeePerGas };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setChainId(self: *Anvil, new_id: u64) !void {
    const hex_id = try std.fmt.allocPrint(self.alloc, "0x{x}", .{new_id});
    defer self.alloc.free(hex_id);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{hex_id}, .method = .anvil_setChainId };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn setNonce(self: *Anvil, address: []const u8, new_nonce: u64) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    const hex_id = try std.fmt.allocPrint(self.alloc, "0x{x}", .{new_nonce});
    defer self.alloc.free(hex_id);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{ address, hex_id }, .method = .anvil_setNonce };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn dropTransaction(self: *Anvil, tx_hash: []const u8) !void {
    if (!try utils.isHash(self.alloc, tx_hash)) return error.InvalidAddress;

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{tx_hash}, .method = .anvil_dropTransaction };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn mine(self: *Anvil, amount: u64, time_in_seconds: ?u64) !void {
    const hex_amount = try std.fmt.allocPrint(self.alloc, "0x{x}", .{amount});
    defer self.alloc.free(hex_amount);

    const hex_time: ?[]const u8 = if (time_in_seconds) |time| try std.fmt.allocPrint(self.alloc, "0x{x}", .{time}) else null;
    defer if (hex_time != null) self.alloc.free(hex_time);

    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest(std.meta.Tuple(&[_]type{ []const u8, ?[]const u8 })) = .{ .params = &.{ hex_amount, hex_time }, .method = .anvil_mine };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn reset(self: *Anvil, reset_config: ?Reset) !void {
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest(?Reset) = .{ .params = &.{reset_config}, .method = .anvil_reset };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn impersonateAccount(self: *Anvil, address: []const u8) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{address}, .method = .anvil_impersonateAccount };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

pub fn stopImpersonatingAccount(self: *Anvil, address: []const u8) !void {
    if (!try utils.isAddress(self.alloc, address)) return error.InvalidAddress;
    var headers = try std.http.Headers.initList(self.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    defer headers.deinit();

    const request: AnvilRequest([]const []const u8) = .{ .params = &.{address}, .method = .anvil_stopImpersonatingAccount };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    defer self.alloc.free(req_body);

    var req = try self.http_client.fetch(self.alloc, .{ .headers = headers, .payload = .{ .string = req_body }, .location = .{ .uri = self.localhost }, .method = .POST });
    defer req.deinit();

    if (req.status != .ok) return error.InvalidRequest;
}

/// Start the child process. Use this with init if you want to use this in a seperate theread.
pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", self.fork_url, "--fork-block-number", self.block_number_fork, "--port", self.localhost.port.? }, self.alloc);
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

test "setBalance" {
    var anvil: Anvil = undefined;
    defer anvil.deinit();
    try anvil.initClient(.{ .alloc = std.testing.allocator, .fork_url = "" });

    try anvil.setBalance("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", 69696969696969696969);
}
