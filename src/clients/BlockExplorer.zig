const abi = @import("../abi/abi.zig");
const explorer = @import("../types/explorer.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const url = @import("url.zig");
const utils = @import("../utils/utils.zig");

const Abi = abi.Abi;
const Address = types.Address;
const AddressBalanceRequest = explorer.AddressBalanceRequest;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const BlockCountDown = explorer.BlockCountdown;
const BlockRewards = explorer.BlockRewards;
const BlocktimeRequest = explorer.BlocktimeRequest;
const ContractCreationResult = explorer.ContractCreationResult;
const EndPoints = explorer.EndPoints;
const Erc1155TokenEventRequest = explorer.Erc1155TokenEventRequest;
const EtherPriceResponse = explorer.EtherPriceResponse;
const ExplorerLog = explorer.ExplorerLog;
const ExplorerResponse = explorer.ExplorerResponse;
const ExplorerRequestResponse = explorer.ExplorerRequestResponse;
const ExplorerTransaction = explorer.ExplorerTransaction;
const GetSourceResult = explorer.GetSourceResult;
const Hash = types.Hash;
const HttpClient = std.http.Client;
const InternalExplorerTransaction = explorer.InternalExplorerTransaction;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LogRequest = explorer.LogRequest;
const MultiAddressBalance = explorer.MultiAddressBalance;
const MultiAddressBalanceRequest = explorer.MultiAddressBalanceRequest;
const QueryOptions = url.QueryOptions;
const QueryWriter = url.QueryWriter;
const RangeRequest = explorer.RangeRequest;
const ReceiptStatus = explorer.ReceiptStatus;
const TransactionStatus = explorer.TransactionStatus;
const TransactionListRequest = explorer.TransactionListRequest;
const TokenBalanceRequest = explorer.TokenBalanceRequest;
const TokenEventRequest = explorer.TokenEventRequest;
const TokenExplorerTransaction = explorer.TokenExplorerTransaction;
const Uri = std.Uri;

const Explorer = @This();

const explorer_log = std.log.scoped(.explorer);

/// The block explorer modules.
pub const Modules = enum {
    account,
    contract,
    transaction,
    block,
    logs,
    stats,

    // PRO module only
    token,
};

/// The block explorer actions.
pub const Actions = enum {
    // Account actions
    balance,
    balancemulti,
    txlist,
    txlistinternal,
    tokentx,
    tokennfttx,
    token1155tx,
    tokenbalance,

    // Only available in PRO plans. We will not support these methods.
    balancehistory,
    tokenbalancehistory,
    addresstokenbalance,
    addresstokennftbalance,
    addresstokennftinventory,

    // Contract actions
    getabi,
    getsourcecode,
    getcontractcreation,

    // Transaction actions
    getstatus,
    gettxreceiptstatus,

    // Block actions
    getblockreward,
    getblockcountdown,
    getblocknobytime,

    // Log actions
    getLogs,

    // Stats actions
    tokensupply,
    ethprice,
    ethsupply,

    // Only available in PRO plans. We will not support these methods.
    dailyblockrewards,
    dailyavgblocktime,
    tokensupplyhistory,

    // Token actions. PRO only.
    tokenholderlist,
    tokeninfo,
};

/// The client init options
pub const InitOpts = struct {
    allocator: Allocator,
    /// The Explorer api key.
    apikey: []const u8,
    /// Set of supported endpoints.
    endpoint: EndPoints = .{ .optimism = null },
    /// The max size that the fetch call can use
    max_append_size: usize = std.math.maxInt(u16),
    /// The number of retries for the client to make on 429 errors.
    retries: usize = 5,
};

/// Used by the `Explorer` client to build the uri query parameters.
pub const QueryParameters = struct {
    /// The module of the endpoint to target.
    module: Modules,
    /// The action endpoint to target.
    action: Actions,
    /// Set of pagination options.
    options: QueryOptions,
    /// Endpoint api key.
    apikey: []const u8,

    /// Build the query based on the provided `value` and it's inner state.
    /// Uses the `QueryWriter` to build the searchUrlParams.
    pub fn buildQuery(self: @This(), value: anytype, writer: anytype) !void {
        const info = @typeInfo(@TypeOf(value));

        comptime {
            std.debug.assert(info == .Struct); // Must be a non tuple struct type
            std.debug.assert(!info.Struct.is_tuple); // Must be a non tuple struct type
        }

        var stream = QueryWriter(@TypeOf(writer)).init(writer);

        try stream.beginQuery();

        try stream.writeParameter("module");
        try stream.writeValue(self.module);

        try stream.writeParameter("action");
        try stream.writeValue(self.action);

        inline for (info.Struct.fields) |field| {
            try stream.writeParameter(field.name);
            try stream.writeValue(@field(value, field.name));
        }

        try stream.writeQueryOptions(self.options);

        try stream.writeParameter("apikey");
        try stream.writeValue(self.apikey);
    }
    /// Build the query parameters without any provided values.
    /// Uses the `QueryWriter` to build the searchUrlParams.
    pub fn buildDefaultQuery(self: @This(), writer: anytype) !void {
        var stream = QueryWriter(@TypeOf(writer)).init(writer);

        try stream.beginQuery();

        try stream.writeParameter("module");
        try stream.writeValue(self.module);

        try stream.writeParameter("action");
        try stream.writeValue(self.action);

        try stream.writeQueryOptions(self.options);

        try stream.writeParameter("apikey");
        try stream.writeValue(self.apikey);
    }
};

/// The Explorer api key.
apikey: []const u8,
/// The allocator of this client.
allocator: Allocator,
/// The underlaying http client.
client: HttpClient,
/// Set of supported endpoints.
endpoint: EndPoints,
/// The max size that the fetch call can use
max_append_size: usize,
/// The number of retries for the client to make on 429 errors.
retries: usize,

/// Creates the initial client state.
/// This client only supports the free api endpoints via the api. We will not support PRO methods.
/// But `zabi` has all the tools you will need to create the methods to target those endpoints.
pub fn init(opts: InitOpts) Explorer {
    return .{
        .allocator = opts.allocator,
        .apikey = opts.apikey,
        .client = HttpClient{ .allocator = opts.allocator },
        .endpoint = opts.endpoint,
        .max_append_size = opts.max_append_size,
        .retries = opts.retries,
    };
}
/// Deinits the http/s server.
pub fn deinit(self: *Explorer) void {
    self.client.deinit();
}
/// Queries the api endpoint to find the `address` contract ABI.
pub fn getAbi(self: *Explorer, address: Address) !ExplorerResponse(Abi) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .contract,
        .action = .getabi,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .address = address }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    // The api sends the ABI as a string... So we grab it and reparse it as `Abi`
    const parsed = try self.sendRequest([]const u8, uri);
    defer parsed.deinit();

    const as_abi = try std.json.parseFromSlice(Abi, self.allocator, parsed.response, .{ .allocate = .alloc_always });

    return ExplorerResponse(Abi).fromJson(as_abi.arena, as_abi.value);
}
/// Queries the api endpoint to find the `address` balance at the specified `tag`
pub fn getAddressBalance(self: *Explorer, request: AddressBalanceRequest) !ExplorerResponse(u256) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .balance,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(u256, uri);
}
/// Queries the api endpoint to find the block reward at the specified `block_number`
pub fn getBlockCountDown(self: *Explorer, block_number: u64) !ExplorerResponse(BlockCountDown) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .block,
        .action = .getblockcountdown,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .blockno = block_number }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(BlockCountDown, uri);
}
/// Queries the api endpoint to find the block reward at the specified `block_number`
pub fn getBlockNumberByTimestamp(self: *Explorer, request: BlocktimeRequest) !ExplorerResponse(u64) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .block,
        .action = .getblocknobytime,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(u64, uri);
}
/// Queries the api endpoint to find the block reward at the specified `block_number`
pub fn getBlockReward(self: *Explorer, block_number: u64) !ExplorerResponse(BlockRewards) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .block,
        .action = .getblockreward,
        .options = .{},
        .apikey = self.apikey,
    };
    try query.buildQuery(.{ .blockno = block_number }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(BlockRewards, uri);
}
/// Queries the api endpoint to find the creation tx address from the target contract addresses.
pub fn getContractCreation(self: *Explorer, addresses: []const Address) !ExplorerResponse([]const ContractCreationResult) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .contract,
        .action = .getcontractcreation,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .contractaddresses = addresses }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const ContractCreationResult, uri);
}
/// Queries the api endpoint to find the `address` erc20 token balance.
pub fn getErc20TokenBalance(self: *Explorer, request: TokenBalanceRequest) !ExplorerResponse(u256) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .tokenbalance,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(u256, uri);
}
/// Queries the api endpoint to find the `address` erc20 token supply.
pub fn getErc20TokenSupply(self: *Explorer, address: Address) !ExplorerResponse(u256) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .stats,
        .action = .tokensupply,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .contractaddress = address }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(u256, uri);
}
/// Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`
pub fn getErc20TokenTransferEvents(self: *Explorer, request: TokenEventRequest, options: QueryOptions) !ExplorerResponse([]const TokenExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .tokentx,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const TokenExplorerTransaction, uri);
}
/// Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`
pub fn getErc721TokenTransferEvents(self: *Explorer, request: TokenEventRequest, options: QueryOptions) !ExplorerResponse([]const TokenExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .tokennfttx,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const TokenExplorerTransaction, uri);
}
/// Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`
pub fn getErc1155TokenTransferEvents(self: *Explorer, request: Erc1155TokenEventRequest, options: QueryOptions) !ExplorerResponse([]const TokenExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .token1155tx,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const TokenExplorerTransaction, uri);
}
/// Queries the api endpoint to find the `address` erc20 token balance.
pub fn getEtherPrice(self: *Explorer) !ExplorerResponse(EtherPriceResponse) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .stats,
        .action = .ethprice,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildDefaultQuery(buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(EtherPriceResponse, uri);
}
/// Queries the api endpoint to find the `address` internal transaction list based on a block range.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`.
pub fn getInternalTransactionList(self: *Explorer, request: TransactionListRequest, options: QueryOptions) !ExplorerResponse([]const InternalExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .txlistinternal,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const InternalExplorerTransaction, uri);
}
/// Queries the api endpoint to find the internal transactions from a transaction hash.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`.
pub fn getInternalTransactionListByHash(self: *Explorer, tx_hash: Hash) !ExplorerResponse([]const InternalExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .txlistinternal,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .txhash = tx_hash }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const InternalExplorerTransaction, uri);
}
/// Queries the api endpoint to find the `address` balances at the specified `tag`
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`
pub fn getInternalTransactionListByRange(self: *Explorer, request: RangeRequest, options: QueryOptions) !ExplorerResponse([]const InternalExplorerTransaction) {
    std.debug.assert(request.startblock <= request.endblock); // Invalid range provided.

    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .txlistinternal,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const InternalExplorerTransaction, uri);
}
/// Queries the api endpoint to find the logs at the target `address` based on the provided block range.
pub fn getLogs(self: *Explorer, request: LogRequest, options: QueryOptions) !ExplorerResponse([]const ExplorerLog) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .logs,
        .action = .getLogs,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const ExplorerLog, uri);
}
/// Queries the api endpoint to find the `address` balances at the specified `tag`
pub fn getMultiAddressBalance(self: *Explorer, request: MultiAddressBalanceRequest) !ExplorerResponse([]const MultiAddressBalance) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .balancemulti,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const MultiAddressBalance, uri);
}
/// Queries the api endpoint to find the `address` contract source information if it's present.
/// The api might send the result with empty field in case the source information is not present.
/// This will cause the json parse to fail.
pub fn getSourceCode(self: *Explorer, address: Address) !ExplorerResponse([]const GetSourceResult) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .contract,
        .action = .getsourcecode,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .address = address }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const GetSourceResult, uri);
}
/// Queries the api endpoint to find the `address` erc20 token balance.
pub fn getTotalEtherSupply(self: *Explorer) !ExplorerResponse(u256) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .stats,
        .action = .ethsupply,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildDefaultQuery(buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(u256, uri);
}
/// Queries the api endpoint to find the `address` transaction list based on a block range.
///
/// This can fail because the response can be higher than `max_append_size`.
/// If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
/// or increasing the `max_append_size`
pub fn getTransactionList(self: *Explorer, request: TransactionListRequest, options: QueryOptions) !ExplorerResponse([]const ExplorerTransaction) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .account,
        .action = .txlist,
        .options = options,
        .apikey = self.apikey,
    };

    try query.buildQuery(request, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest([]const ExplorerTransaction, uri);
}
/// Queries the api endpoint to find the transaction receipt status based on the provided `hash`
pub fn getTransactionReceiptStatus(self: *Explorer, hash: Hash) !ExplorerResponse(ReceiptStatus) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .transaction,
        .action = .gettxreceiptstatus,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .txhash = hash }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(ReceiptStatus, uri);
}
/// Queries the api endpoint to find the transaction status based on the provided `hash`
pub fn getTransactionStatus(self: *Explorer, hash: Hash) !ExplorerResponse(TransactionStatus) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try buf_writter.writer().writeAll(self.endpoint.getEndpoint());

    const query: QueryParameters = .{
        .module = .transaction,
        .action = .getstatus,
        .options = .{},
        .apikey = self.apikey,
    };

    try query.buildQuery(.{ .txhash = hash }, buf_writter.writer());

    const uri = try Uri.parse(buf_writter.getWritten());

    return self.sendRequest(TransactionStatus, uri);
}
/// Writes request to endpoint and parses the response according to the provided type.
/// Handles 429 errors but not the rest.
///
/// Builds the uri from the endpoint's api url plus the query parameters from the provided `value`
/// and possible set `QueryOptions`. The current max buffer size is 4096.
///
/// `value` must be a non tuple struct type.
pub fn sendRequest(self: *Explorer, comptime T: type, uri: Uri) !ExplorerResponse(T) {
    var body = ArrayList(u8).init(self.allocator);
    defer body.deinit();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.internalRequest(uri, &body);

        switch (req.status) {
            .ok => {
                const res_body = try body.toOwnedSlice();
                defer self.allocator.free(res_body);

                explorer_log.err("Got response from server: {s}", .{res_body});

                return self.parseExplorerResponse(T, res_body);
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                explorer_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                // Clears any message that was written
                body.clearAndFree();

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => {
                explorer_log.debug("Unexpected server response. Server returned: {s} status", .{req.status.phrase() orelse @tagName(req.status)});
                return error.UnexpectedServerResponse;
            },
        }
    }
}
/// The internal fetch `GET` request.
fn internalRequest(self: *Explorer, uri: Uri, list: *ArrayList(u8)) !HttpClient.FetchResult {
    const result = try self.client.fetch(.{
        .method = .GET,
        .response_storage = .{ .dynamic = list },
        .location = .{ .uri = uri },
        .max_append_size = self.max_append_size,
    });

    return result;
}
/// Parses the response from the server as `ExplorerRequestResponse(T)`
fn parseExplorerResponse(self: *Explorer, comptime T: type, request: []const u8) !ExplorerResponse(T) {
    const parsed = std.json.parseFromSlice(
        ExplorerRequestResponse(T),
        self.allocator,
        request,
        .{ .allocate = .alloc_always },
    ) catch return error.UnexpectedErrorFound;

    switch (parsed.value) {
        .success => |response| return ExplorerResponse(T).fromJson(parsed.arena, response.result),
        .@"error" => |response| {
            errdefer parsed.deinit();

            explorer_log.debug("Explorer error message: {s}", .{response.message});
            explorer_log.debug("Explorer error response: {s}", .{response.result});

            return error.InvalidRequest;
        },
    }
}

test "QueryParameters" {
    const value: QueryParameters = .{ .module = .account, .action = .balance, .options = .{ .page = 1 }, .apikey = "FOO" };

    {
        var request_buffer: [4 * 1024]u8 = undefined;
        var buf_writter = std.io.fixedBufferStream(&request_buffer);

        try value.buildQuery(.{ .bar = 69 }, buf_writter.writer());

        try testing.expectEqualStrings("?module=account&action=balance&bar=69&page=1&apikey=FOO", buf_writter.getWritten());
    }
    {
        var request_buffer: [4 * 1024]u8 = undefined;
        var buf_writter = std.io.fixedBufferStream(&request_buffer);

        try value.buildDefaultQuery(buf_writter.writer());

        try testing.expectEqualStrings("?module=account&action=balance&page=1&apikey=FOO", buf_writter.getWritten());
    }
}
