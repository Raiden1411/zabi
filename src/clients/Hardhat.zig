const meta_json = zabi_meta.json;
const std = @import("std");
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;
const zabi_meta = @import("zabi-meta");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const FetchResult = std.http.Client.FetchResult;
const Hardhat = @This();
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;

/// Set of errors while fetching from a json rpc http endpoint.
pub const FetchErrors = Allocator.Error || Client.RequestError || Client.Request.WaitError ||
    Client.Request.FinishError || Client.Request.ReadError || std.Uri.ParseError || error{ StreamTooLong, InvalidRequest };

/// Values needed for the `hardhat_reset` request.
pub const Forking = struct {
    jsonRpcUrl: []const u8,
    blockNumber: ?u64 = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta_json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta_json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta_json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Struct representation of a `hardhat_reset` request.
pub const Reset = struct {
    forking: Forking,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta_json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta_json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta_json.jsonStringify(@This(), self, writer_stream);
    }
};

pub fn HardhatRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: HardhatMethods,
        params: T,
        id: usize = 1,

        pub fn jsonParse(
            allocator: Allocator,
            source: anytype,
            options: ParseOptions,
        ) ParseError(@TypeOf(source.*))!@This() {
            return meta_json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(
            allocator: Allocator,
            source: Value,
            options: ParseOptions,
        ) ParseFromValueError!@This() {
            return meta_json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(
            self: @This(),
            writer_stream: anytype,
        ) @TypeOf(writer_stream.*).Error!void {
            return meta_json.jsonStringify(@This(), self, writer_stream);
        }
    };
}

pub const HardhatMethods = enum {
    hardhat_setBalance,
    hardhat_setCode,
    hardhat_setChainId,
    hardhat_setCoinbase,
    hardhat_setNonce,
    hardhat_setNextBlockBaseFeePerGas,
    hardhat_setMinGasPrice,
    hardhat_dropTransaction,
    hardhat_mine,
    hardhat_reset,
    hardhat_impersonateAccount,
    hardhat_stopImpersonatingAccount,
    hardhat_setRpcUrl,
    hardhat_setLoggingEnabled,
};

pub const StartUpOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The localhost address.
    localhost: []const u8 = "http://127.0.0.1:8545/",
};

/// Allocator to use to create the ChildProcess and other allocations
allocator: std.mem.Allocator,
/// The localhost address uri.
localhost: std.Uri,
/// The socket connection to hardhat. Use `initClient` to populate this.
http_client: std.http.Client,

pub fn initClient(
    self: *Hardhat,
    opts: StartUpOptions,
) FetchErrors!void {
    self.* = .{
        .allocator = opts.allocator,
        .localhost = try std.Uri.parse(opts.localhost),
        .http_client = std.http.Client{ .allocator = opts.allocator },
    };
}
/// Cleans up the http client
pub fn deinit(self: *Hardhat) void {
    self.http_client.deinit();
}
/// Sets the balance of a hardhat account
pub fn setBalance(
    self: *Hardhat,
    address: Address,
    balance: u256,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address, u256 }) = .{
        .params = .{ address, balance },
        .method = .hardhat_setBalance,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the contract code of a address.
pub fn setCode(
    self: *Hardhat,
    address: Address,
    code: Hex,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address, Hex }) = .{
        .params = .{ address, code },
        .method = .hardhat_setCode,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the rpc of the hardhat connection
pub fn setRpcUrl(
    self: *Hardhat,
    rpc_url: []const u8,
) FetchErrors!void {
    const request: HardhatRequest(struct { []const u8 }) = .{
        .params = .{rpc_url},
        .method = .hardhat_setRpcUrl,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the coinbase address
pub fn setCoinbase(
    self: *Hardhat,
    address: Address,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address }) = .{
        .params = .{address},
        .method = .hardhat_setCoinbase,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Enable hardhat verbose logging for hardhat.
pub fn setLoggingEnable(self: *Hardhat) FetchErrors!void {
    const request: HardhatRequest(std.meta.Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .hardhat_setLoggingEnabled,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the min gasprice from the hardhat fork
pub fn setMinGasPrice(
    self: *Hardhat,
    new_price: u64,
) FetchErrors!void {
    const request: HardhatRequest(struct { u64 }) = .{
        .params = .{new_price},
        .method = .hardhat_setMinGasPrice,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the next blocks base fee.
pub fn setNextBlockBaseFeePerGas(
    self: *Hardhat,
    new_price: u64,
) FetchErrors!void {
    const request: HardhatRequest(struct { u64 }) = .{
        .params = .{new_price},
        .method = .hardhat_setNextBlockBaseFeePerGas,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the networks chainId
pub fn setChainId(
    self: *Hardhat,
    new_id: u64,
) FetchErrors!void {
    const request: HardhatRequest(struct { u64 }) = .{
        .params = .{new_id},
        .method = .hardhat_setChainId,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Changes the nonce of a account
pub fn setNonce(
    self: *Hardhat,
    address: Address,
    new_nonce: u64,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address, u64 }) = .{
        .params = .{ address, new_nonce },
        .method = .hardhat_setNonce,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Drops a pending transaction from the mempool
pub fn dropTransaction(
    self: *Hardhat,
    tx_hash: Hash,
) FetchErrors!void {
    const request: HardhatRequest(struct { Hash }) = .{
        .params = .{tx_hash},
        .method = .hardhat_dropTransaction,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Mine a pending transaction
pub fn mine(
    self: *Hardhat,
    amount: u64,
    time_in_seconds: ?u64,
) FetchErrors!void {
    const request: HardhatRequest(struct { u64, ?u64 }) = .{
        .params = .{ amount, time_in_seconds },
        .method = .hardhat_mine,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Reset the fork
pub fn reset(
    self: *Hardhat,
    reset_config: ?Reset,
) FetchErrors!void {
    const request: HardhatRequest(struct { ?Reset }) = .{
        .params = .{reset_config},
        .method = .hardhat_reset,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.
pub fn impersonateAccount(
    self: *Hardhat,
    address: Address,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address }) = .{
        .params = .{address},
        .method = .hardhat_impersonateAccount,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Stops impersonating a EOA or contract.
pub fn stopImpersonatingAccount(
    self: *Hardhat,
    address: Address,
) FetchErrors!void {
    const request: HardhatRequest(struct { Address }) = .{
        .params = .{address},
        .method = .hardhat_impersonateAccount,
    };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    return self.sendRpcRequest(req_body);
}
/// Internal fetch functions. Body is discarded.
pub fn sendRpcRequest(
    self: *Hardhat,
    req_body: []u8,
) FetchErrors!void {
    var body = std.ArrayList(u8).init(self.allocator);
    defer body.deinit();

    const req = try self.http_client.fetch(.{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .payload = req_body,
        .location = .{ .uri = self.localhost },
        .response_storage = .{ .dynamic = &body },
    });

    if (req.status != .ok) return error.InvalidRequest;
}
