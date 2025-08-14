const abi_ens = @import("ens/abi_ens.zig");
const abi_op = @import("optimism/abi_optimism.zig");
const block = zabi_types.block;
const decoder = @import("zabi-decoding").abi_decoder;
const decoder_logs = @import("zabi-decoding").logs_decoder;
const ens_utils = @import("ens/ens_utils.zig");
const http = std.http;
const log = zabi_types.log;
const network = @import("network.zig");
const meta = zabi_meta.utils;
const meta_abi = zabi_meta.abi;
const op_types = @import("optimism/types/types.zig");
const op_utils = @import("optimism/utils.zig");
const proof = zabi_types.proof;
const serialize = @import("zabi-encoding").serialize;
const std = @import("std");
const sync = zabi_types.sync;
const testing = std.testing;
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const txpool = zabi_types.txpool;
const withdrawal_types = @import("optimism/types/withdrawl.zig");
const zabi_abi = @import("zabi-abi");
const zabi_meta = @import("zabi-meta");
const zabi_types = @import("zabi-types");
const zabi_utils = @import("zabi-utils");

// Types
const Function = zabi_abi.abitypes.Function;
const Chains = types.PublicChains;
const AbiDecoded = decoder.AbiDecoded;
const AbiParametersToPrimative = meta_abi.AbiParametersToPrimative;
const AccessListResult = transaction.AccessListResult;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const BalanceBlockTag = block.BalanceBlockTag;
const BalanceRequest = block.BalanceRequest;
const Block = block.Block;
const BlockHashRequest = block.BlockHashRequest;
const BlockNumberRequest = block.BlockNumberRequest;
const BlockRequest = block.BlockRequest;
const BlockTag = block.BlockTag;
const Channel = zabi_utils.channel.Channel;
const EthCall = transaction.EthCall;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorCodes = types.EthereumErrorCodes;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EthereumSubscribeResponse = types.EthereumSubscribeResponse;
const EthereumZigErrors = types.EthereumZigErrors;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
const FeeHistory = transaction.FeeHistory;
const FetchResult = http.Client.FetchResult;
const Game = withdrawal_types.Game;
const GameResult = withdrawal_types.GameResult;
const Hash = types.Hash;
const Hex = types.Hex;
const HttpClient = std.http.Client;
const HttpConnection = http.Client.Connection;
const IpcReader = @import("blocking/IpcReader.zig");
const JsonParsed = std.json.Parsed;
const LondonTransactionEnvelope = zabi_types.transactions.LondonTransactionEnvelope;
const LogRequest = log.LogRequest;
const Log = log.Log;
const Logs = log.Logs;
const LogTagRequest = log.LogTagRequest;
const L2Output = op_types.L2Output;
const ProviderOutput = op_types.L2Output;
const Message = withdrawal_types.Message;
const NetworkConfig = network.NetworkConfig;
const NextGameTimings = withdrawal_types.NextGameTimings;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const ProvenWithdrawal = withdrawal_types.ProvenWithdrawal;
const Provider = @This();
const RPCResponse = types.RPCResponse;
const SemanticVersion = std.SemanticVersion;
const Stack = zabi_utils.stack.Stack;
const Subscriptions = types.Subscriptions;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionDeposited = zabi_types.transactions.TransactionDeposited;
const TransactionReceipt = transaction.TransactionReceipt;
const Tuple = std.meta.Tuple;
const TxPoolContent = txpool.TxPoolContent;
const TxPoolInspect = txpool.TxPoolInspect;
const TxPoolStatus = txpool.TxPoolStatus;
const Value = std.json.Value;
const WatchLogsRequest = log.WatchLogsRequest;
const Withdrawal = withdrawal_types.Withdrawal;
const WsClient = @import("blocking/WebSocketClient.zig");

/// Scoped logging for the JSON RPC client.
const provider_log = std.log.scoped(.provider);

pub const Call = struct {
    /// The target address.
    target: Address,
    /// The calldata from the function that you want to run.
    callData: Hex,
};

pub const Call3 = struct {
    /// The target address.
    target: Address,
    /// Tells the contract weather to allow the call to fail or not.
    allowFailure: bool,
    /// The calldata used to call the function you want to run.
    callData: Hex,
};

pub const Call3Value = struct {
    /// The target address.
    target: Address,
    /// Tells the contract weather to allow the call to fail or not.
    allowFailure: bool,
    /// The value sent in the call.
    value: u256,
    /// The calldata from the function that you want to run.
    callData: Hex,
};

/// The result struct when calling the multicall contract.
pub const Result = struct {
    /// Weather the call was successfull or not.
    success: bool,
    /// The return data from the function call.
    returnData: Hex,
};

/// Arguments for the multicall3 function call
pub const MulticallTargets = struct {
    function: Function,
    target_address: Address,
};

/// Type function that gets the expected arguments from the provided abi's.
pub fn MulticallArguments(comptime targets: []const MulticallTargets) type {
    if (targets.len == 0) return void;
    var fields: [targets.len]std.builtin.Type.StructField = undefined;

    for (targets, 0..) |target, i| {
        const Arguments = AbiParametersToPrimative(target.function.inputs);

        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = Arguments,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(Arguments) > 0) @alignOf(Arguments) else 0,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Multicall3 aggregate3 abi representation.
pub const aggregate3_abi: Function = .{
    .name = "aggregate3",
    .type = .function,
    .stateMutability = .payable,
    .inputs = &.{
        .{
            .type = .{ .dynamicArray = &.{ .tuple = {} } },
            .name = "calls",
            .components = &.{
                .{ .type = .{ .address = {} }, .name = "target" },
                .{ .type = .{ .bool = {} }, .name = "allowFailure" },
                .{ .type = .{ .bytes = {} }, .name = "callData" },
            },
        },
    },
    .outputs = &.{
        .{
            .type = .{ .dynamicArray = &.{ .tuple = {} } },
            .name = "returnData",
            .components = &.{
                .{ .type = .{ .bool = {} }, .name = "success" },
                .{ .type = .{ .bytes = {} }, .name = "returnData" },
            },
        },
    },
};

vtable: *const VTable,
/// The network config that the provider will connect to.
network_config: NetworkConfig,

const VTable = struct {
    sendRpcRequest: *const fn (self: *Provider, request: []u8) anyerror!JsonParsed(Value),
};

/// Grabs the current base blob fee. Make sure that your endpoint supports `eth_blobBaseFee`
///
/// RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)
pub fn blobBaseFee(self: *Provider) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blobBaseFee);
}

/// Create an accessList of addresses and storageKeys for a transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *Provider, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}

/// Estimate the gas used for blobs.
///
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation.
pub fn estimateBlobMaxFeePerGas(self: *Provider) !u64 {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else gas_price.response - base.response;
}

/// Estimate `maxPriorityFeePerGas` and `maxFeePerGas` for london enabled chains and `gasPrice` if not.\
/// This method will make multiple http requests in order to calculate this.
///
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
///
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(
    self: *Provider,
    call_object: EthCall,
    base_fee_per_gas: ?u64,
) !EstimateFeeReturn {
    const current_fee: ?u64 = block: {
        if (base_fee_per_gas) |fee|
            break :block fee;

        const rpc_block = try self.getBlockByNumber(.{});
        rpc_block.deinit();

        break :block switch (rpc_block.response) {
            inline else => |block_info| block_info.baseFeePerGas,
        };
    };

    switch (call_object) {
        .london => |tx| {
            const base_fee = current_fee orelse return error.UnableToFetchFeeInfoFromBlock;
            const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(base_fee);

            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(base_fee)) * self.network_config.base_fee_multiplier);
            const max_fee = if (tx.maxFeePerGas) |max| max else @as(u64, @intFromFloat(mutiplier)) + max_priority;

            return .{
                .london = .{
                    .max_fee_gas = max_fee,
                    .max_priority_fee = max_priority,
                },
            };
        },
        .legacy => |tx| {
            const gas_price = gas: {
                if (tx.gasPrice) |price| break :gas price;
                const gas_price = try self.getGasPrice();
                defer gas_price.deinit();

                break :gas gas_price.response;
            };
            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(gas_price)) * self.network_config.base_fee_multiplier);
            const price: u64 = @intFromFloat(mutiplier);
            return .{
                .legacy = .{ .gas_price = price },
            };
        },
    }
}

/// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
///
/// The transaction will not be added to the blockchain.
///
/// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
/// for a variety of reasons including EVM mechanics and node performance.
///
/// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
pub fn estimateGas(self: *Provider, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(u64) {
    return self.sendEthCallRequest(u64, call_object, opts, .eth_estimateGas);
}

/// Returns the L1 gas used to execute Provider transactions
pub fn estimateL1Gas(
    self: *Provider,
    allocator: Allocator,
    london_envelope: LondonTransactionEnvelope,
) !u256 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const serialized = try serialize.serializeTransaction(allocator, .{ .london = london_envelope }, null);
    defer allocator.free(serialized);

    const encoded = try abi_op.get_l1_gas_func.encode(allocator, .{serialized});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.gasPriceOracle,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    return zabi_utils.utils.bytesToInt(u256, data.response);
}

/// Returns the L1 fee used to execute Provider transactions
pub fn estimateL1GasFee(
    self: *Provider,
    allocator: Allocator,
    london_envelope: LondonTransactionEnvelope,
) !u256 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const serialized = try serialize.serializeTransaction(allocator, .{ .london = london_envelope }, null);
    defer allocator.free(serialized);

    const encoded = try abi_op.get_l1_fee.encode(allocator, .{serialized});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.gasPriceOracle,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    return zabi_utils.utils.bytesToInt(u256, data.response);
}

/// Estimates `maxPriorityFeePerGas` manually.
///
/// Gets the information based on the latest block if `base_fee_per_gas` is set to null.
///
/// If the node you are currently using supports `eth_maxPriorityFeePerGas` consider using [estimateMaxFeePerGas](/api/clients/Client#estimateMaxFeePerGas).
pub fn estimateMaxFeePerGasManual(
    self: *Provider,
    base_fee_per_gas: ?u64,
) !u64 {
    const current_fee: ?u64 = block: {
        if (base_fee_per_gas) |fee|
            break :block fee;

        const rpc_block = try self.getBlockByNumber(.{});
        rpc_block.deinit();

        break :block switch (rpc_block.response) {
            inline else => |block_info| block_info.baseFeePerGas,
        };
    };
    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    const base_fee = current_fee orelse return error.UnableToFetchFeeInfoFromBlock;

    return if (base_fee > gas_price.response) 0 else gas_price.response - base_fee;
}

/// Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.
pub fn estimateMaxFeePerGas(self: *Provider) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_maxPriorityFeePerGas);
}

/// Estimates the L1 + Provider fees to execute a transaction on L2
pub fn estimateTotalFees(
    self: *Provider,
    london_envelope: LondonTransactionEnvelope,
) !u256 {
    const l1_gas_fee = try self.estimateL1GasFee(london_envelope);
    const l2_gas = try self.estimateGas(.{ .london = .{
        .to = london_envelope.to,
        .data = london_envelope.data,
        .maxFeePerGas = london_envelope.maxFeePerGas,
        .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
        .value = london_envelope.value,
    } }, .{});
    defer l2_gas.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return l1_gas_fee + l2_gas.response * gas_price.response;
}

/// Estimates the L1 + L2 gas to execute a transaction on L2
pub fn estimateTotalGas(
    self: *Provider,
    allocator: Allocator,
    london_envelope: LondonTransactionEnvelope,
) !u256 {
    const l1_gas_fee = try self.estimateL1GasFee(allocator, london_envelope);
    const l2_gas = try self.estimateGas(.{ .london = .{
        .to = london_envelope.to,
        .data = london_envelope.data,
        .maxFeePerGas = london_envelope.maxFeePerGas,
        .maxPriorityFeePerGas = london_envelope.maxPriorityFeePerGas,
        .value = london_envelope.value,
    } }, .{});
    defer l2_gas.deinit();

    return l1_gas_fee + l2_gas.response;
}

/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(
    self: *Provider,
    blockCount: u64,
    newest_block: BlockNumberRequest,
    reward_percentil: ?[]const f64,
) !RPCResponse(FeeHistory) {
    const tag: BalanceBlockTag = newest_block.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (newest_block.block_number) |number| {
        const request: EthereumRequest(struct { u64, u64, ?[]const f64 }) = .{
            .params = .{ blockCount, number, reward_percentil },
            .method = .eth_feeHistory,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { u64, BalanceBlockTag, ?[]const f64 }) = .{
            .params = .{ blockCount, tag, reward_percentil },
            .method = .eth_feeHistory,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(FeeHistory, response);
}

/// Returns a list of addresses owned by client.
///
/// RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)
pub fn getAccounts(self: *Provider) !RPCResponse([]const Address) {
    return self.sendBasicRequest([]const Address, .eth_accounts);
}

/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(
    self: *Provider,
    opts: BalanceRequest,
) !RPCResponse(u256) {
    return self.sendAddressRequest(u256, opts, .eth_getBalance);
}

/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(
    self: *Provider,
    opts: BalanceRequest,
) !RPCResponse(u64) {
    return self.sendAddressRequest(u64, opts, .eth_getTransactionCount);
}

/// Returns the base fee on L1
pub fn getBaseL1Fee(self: *Provider) !u256 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    // Selector for "l1BaseFee()"
    const selector: []u8 = @constCast(&[_]u8{ 0x51, 0x9b, 0x4b, 0xd3 });

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.gasPriceOracle,
        .data = selector,
    } }, .{});
    defer data.deinit();

    return zabi_utils.utils.bytesToInt(u256, data.response);
}

/// Returns information about a block by hash.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(
    self: *Provider,
    opts: BlockHashRequest,
) !RPCResponse(Block) {
    return self.getBlockByHashType(Block, opts);
}

/// Returns information about a block by hash.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHashType(
    self: *Provider,
    comptime T: type,
    opts: BlockHashRequest,
) !RPCResponse(T) {
    const include = opts.include_transaction_objects orelse false;

    const request: EthereumRequest(struct { Hash, bool }) = .{
        .params = .{ opts.block_hash, include },
        .method = .eth_getBlockByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const request_block = try self.parseRPCEvent(?T, response);

    const block_info = request_block.response orelse return error.InvalidBlockHash;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}

/// Returns information about a block by number.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumber(
    self: *Provider,
    opts: BlockRequest,
) !RPCResponse(Block) {
    return self.getBlockByNumberType(Block, opts);
}

/// Returns information about a block by number.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumberType(
    self: *Provider,
    comptime T: type,
    opts: BlockRequest,
) !RPCResponse(T) {
    const tag: BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, bool }) = .{
            .params = .{ number, include },
            .method = .eth_getBlockByNumber,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { BlockTag, bool }) = .{
            .params = .{ tag, include },
            .method = .eth_getBlockByNumber,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const request_block = try self.parseRPCEvent(?T, response);

    const block_info = request_block.response orelse return error.InvalidBlockNumber;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}

/// Returns the number of most recent block.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockNumber(self: *Provider) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blockNumber);
}

/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(
    self: *Provider,
    block_hash: Hash,
) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}

/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(
    self: *Provider,
    opts: BlockNumberRequest,
) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}

/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *Provider) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_chainId);
}

/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *Provider) !RPCResponse([]const u8) {
    return self.sendBasicRequest([]const u8, .web3_clientVersion);
}

/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(
    self: *Provider,
    opts: BalanceRequest,
) !RPCResponse(Hex) {
    return self.sendAddressRequest(Hex, opts, .eth_getCode);
}

/// Gets the ENS address associated with the ENS name.
///
/// Caller owns the memory if the request is successfull.
/// Calls the resolver address and decodes with address resolver.
///
/// The names are not normalized so make sure that the names are normalized before hand.
pub fn getEnsAddress(
    rpc_client: *Provider,
    allocator: Allocator,
    name: []const u8,
    opts: BlockNumberRequest,
) !AbiDecoded(Address) {
    const contracts = rpc_client.network_config.ens_contracts orelse return error.ExpectedEnsContracts;

    const hash = try ens_utils.hashName(name);

    const encoded = try abi_ens.addr_resolver.encode(allocator, .{hash});
    defer allocator.free(encoded);

    var buffer: [1024]u8 = undefined;
    const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

    const resolver_encoded = try abi_ens.resolver.encode(allocator, .{ buffer[0..bytes_read], encoded });
    defer allocator.free(resolver_encoded);

    const value = try rpc_client.sendEthCall(.{ .london = .{
        .to = contracts.ensUniversalResolver,
        .data = resolver_encoded,
    } }, opts);
    defer value.deinit();

    if (value.response.len == 0)
        return error.EvmFailedToExecute;

    const decoded = try decoder.decodeAbiParameter(
        struct { []u8, Address },
        allocator,
        value.response,
        .{ .allow_junk_data = true, .allocate_when = .alloc_always },
    );
    defer decoded.deinit();

    if (decoded.result[0].len == 0)
        return error.FailedToDecodeResponse;

    const decoded_result = try decoder.decodeAbiParameter(
        Address,
        allocator,
        decoded.result[0],
        .{ .allow_junk_data = true, .allocate_when = .alloc_always },
    );

    if (decoded_result.result.len == 0)
        return error.FailedToDecodeResponse;

    return decoded_result;
}

/// Gets the ENS name associated with the address.
///
/// Caller owns the memory if the request is successfull.
/// Calls the reverse resolver and decodes with the same.
///
/// This will fail if its not a valid checksumed address.
pub fn getEnsName(
    rpc_client: *Provider,
    allocator: Allocator,
    address: []const u8,
    opts: BlockNumberRequest,
) !RPCResponse([]const u8) {
    const contracts = rpc_client.network_config.ens_contracts orelse return error.ExpectedEnsContracts;

    if (!zabi_utils.utils.isAddress(address))
        return error.InvalidAddress;

    var address_reverse: [53]u8 = undefined;
    var buf: [40]u8 = undefined;
    _ = std.ascii.lowerString(&buf, address[2..]);

    @memcpy(address_reverse[0..40], buf[0..40]);
    @memcpy(address_reverse[40..], ".addr.reverse");

    var buffer: [100]u8 = undefined;
    const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], address_reverse[0..]);

    const encoded = try abi_ens.reverse_resolver.encode(allocator, .{buffer[0..bytes_read]});
    defer allocator.free(encoded);

    const value = try rpc_client.sendEthCall(.{ .london = .{
        .to = contracts.ensUniversalResolver,
        .data = encoded,
    } }, opts);
    defer value.deinit();

    const address_bytes = try zabi_utils.utils.addressToBytes(address);

    if (value.response.len == 0)
        return error.EvmFailedToExecute;

    const decoded = try decoder.decodeAbiParameter(
        struct { []u8, Address, Address, Address },
        allocator,
        value.response,
        .{ .allocate_when = .alloc_always },
    );
    errdefer decoded.deinit();

    if (!(@as(u160, @bitCast(address_bytes)) == @as(u160, @bitCast(address_bytes))))
        return error.InvalidAddress;

    return RPCResponse([]const u8).fromJson(decoded.arena, decoded.result[0]);
}

/// Gets the ENS resolver associated with the name.
///
/// Caller owns the memory if the request is successfull.
/// Calls the find resolver and decodes with the same one.
///
/// The names are not normalized so make sure that the names are normalized before hand.
pub fn getEnsResolver(
    rpc_client: *Provider,
    allocator: Allocator,
    name: []const u8,
    opts: BlockNumberRequest,
) !Address {
    const contracts = rpc_client.network_config.ens_contracts orelse return error.ExpectedEnsContracts;

    var buffer: [1024]u8 = undefined;
    const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

    const encoded = try abi_ens.find_resolver.encode(allocator, .{buffer[0..bytes_read]});
    defer allocator.free(encoded);

    const value = try rpc_client.sendEthCall(.{ .london = .{
        .to = contracts.ensUniversalResolver,
        .data = encoded,
    } }, opts);
    defer value.deinit();

    const decoded = try decoder.decodeAbiParameterLeaky(
        struct { Address, [32]u8 },
        allocator,
        value.response,
        .{ .allow_junk_data = true },
    );

    return decoded[0];
}

/// Gets a text record for a specific ENS name.
///
/// Caller owns the memory if the request is successfull.
/// Calls the resolver and decodes with the text resolver.
///
/// The names are not normalized so make sure that the names are normalized before hand.
pub fn getEnsText(
    rpc_client: *Provider,
    allocator: Allocator,
    name: []const u8,
    key: []const u8,
    opts: BlockNumberRequest,
) !AbiDecoded([]const u8) {
    const contracts = rpc_client.network_config.ens_contracts orelse return error.ExpectedEnsContracts;

    var buffer: [1024]u8 = undefined;
    const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

    const hash = try ens_utils.hashName(name);
    const text_encoded = try abi_ens.text_resolver.encode(allocator, .{ hash, key });
    defer allocator.free(text_encoded);

    const encoded = try abi_ens.resolver.encode(allocator, .{ buffer[0..bytes_read], text_encoded });
    defer allocator.free(encoded);

    const value = try rpc_client.sendEthCall(.{ .london = .{
        .to = contracts.ensUniversalResolver,
        .data = encoded,
    } }, opts);
    errdefer value.deinit();

    if (value.response.len == 0)
        return error.EvmFailedToExecute;

    const decoded = try decoder.decodeAbiParameter(struct { []u8, Address }, allocator, value.response, .{});
    defer decoded.deinit();

    const decoded_text = try decoder.decodeAbiParameter(
        []const u8,
        allocator,
        decoded.result[0],
        .{ .allocate_when = .alloc_always },
    );
    errdefer decoded_text.deinit();

    if (decoded_text.result.len == 0)
        return error.FailedToDecodeResponse;

    return decoded_text;
}

/// Returns if a withdrawal has finalized or not.
pub fn getFinalizedWithdrawals(
    self: *Provider,
    allocator: Allocator,
    withdrawal_hash: Hash,
) !bool {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const encoded = try abi_op.get_finalized_withdrawal.encode(allocator, .{withdrawal_hash});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.portalAddress,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    return data.response[data.response.len - 1] != 0;
}

/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// returns an array of all logs matching filter with given id depending on the selected method
///
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges \
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(
    self: *Provider,
    filter_id: u128,
    method: EthereumRpcMethods,
) !RPCResponse(Logs) {
    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    switch (method) {
        .eth_getFilterLogs, .eth_getFilterChanges => {},
        else => return error.InvalidRpcMethod,
    }

    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{filter_id},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_filter = try self.parseRPCEvent(?Logs, response);

    const filter = possible_filter.response orelse return error.InvalidFilterId;

    return .{
        .arena = possible_filter.arena,
        .response = filter,
    };
}

/// Retrieves a valid dispute game on an Provider that occurred after a provided L2 block number.
/// Returns an error if no game was found.
///
/// `limit` is the max amount of game to search
///
/// `block_number` to filter only games that occurred after this block.
///
/// `strategy` is weather to provide the latest game or one at random with the scope of the games that where found given the filters.
pub fn getGame(
    self: *Provider,
    allocator: Allocator,
    limit: usize,
    block_number: u256,
    strategy: enum { random, latest, oldest },
) !GameResult {
    const games = try self.getGames(allocator, limit, block_number);
    defer allocator.free(games);

    var rand = std.Random.DefaultPrng.init(@intCast(block_number * limit));

    if (games.len == 0)
        return error.GameNotFound;

    switch (strategy) {
        .latest => return games[0],
        .oldest => return games[games.len - 1],
        .random => {
            const random_int = rand.random().intRangeAtMost(usize, 0, games.len - 1);

            return games[random_int];
        },
    }
}

/// Retrieves the dispute games for an Provider
///
/// `limit` is the max amount of game to search
///
/// `block_number` to filter only games that occurred after this block.
/// If null then it will return all games.
pub fn getGames(
    self: *Provider,
    allocator: Allocator,
    limit: usize,
    block_number: ?u256,
) ![]const GameResult {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const version = try self.getPortalVersion(allocator);

    if (version.major < 3)
        return error.FaultProofsNotEnabled;

    // Selector for "gameCount()"
    const game_count_selector: []u8 = @constCast(&[_]u8{ 0x4d, 0x19, 0x75, 0xb4 });
    // Selector for "respectedGameType()"
    const game_type_selector: []u8 = @constCast(&[_]u8{ 0x3c, 0x9f, 0x39, 0x7c });

    const game_count = try self.sendEthCall(.{ .london = .{
        .to = contracts.disputeGameFactory,
        .data = game_count_selector,
    } }, .{});
    defer game_count.deinit();

    const game_type = try self.sendEthCall(.{ .london = .{
        .to = contracts.portalAddress,
        .data = game_type_selector,
    } }, .{});
    defer game_type.deinit();

    const count = try zabi_utils.utils.bytesToInt(u256, game_count.response);
    const gtype = try zabi_utils.utils.bytesToInt(u32, game_type.response);

    const encoded = try abi_op.find_latest_games.encode(allocator, .{ gtype, if (count != 0) @max(0, count - 1) else 0, @min(limit, count) });
    defer allocator.free(encoded);

    const games = try self.sendEthCall(.{ .london = .{
        .to = contracts.disputeGameFactory,
        .data = encoded,
    } }, .{});
    defer games.deinit();

    const decoded = try decoder.decodeAbiParameter([]const Game, allocator, games.response, .{});
    defer decoded.deinit();

    var list = std.array_list.Managed(GameResult).init(allocator);
    errdefer list.deinit();

    for (decoded.result) |game| {
        const block_num = try zabi_utils.utils.bytesToInt(u256, game.extraData);

        if (block_number) |number| {
            if (number > block_num)
                continue;
        }

        try list.ensureUnusedCapacity(1);
        list.appendAssumeCapacity(.{
            .l2BlockNumber = block_num,
            .index = game.index,
            .metadata = game.metadata,
            .timestamp = game.timestamp,
            .rootClaim = game.rootClaim,
        });
    }

    return list.toOwnedSlice();
}

/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *Provider) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_gasPrice);
}

/// Gets the latest proposed Provider block number from the Oracle.
pub fn getLatestProposedL2BlockNumber(self: *Provider) !u64 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    // Selector for `latestBlockNumber`
    const selector: []u8 = @constCast(&[_]u8{ 0x45, 0x99, 0xc7, 0x88 });

    const block_info = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = selector,
    } }, .{});
    defer block_info.deinit();

    return zabi_utils.utils.bytesToInt(u64, block_info.response);
}

/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(
    self: *Provider,
    opts: LogRequest,
    tag: ?BalanceBlockTag,
) !RPCResponse(Logs) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { LogTagRequest }) = .{
            .params = .{.{
                .fromBlock = request_tag,
                .toBlock = request_tag,
                .address = opts.address,
                .blockHash = opts.blockHash,
                .topics = opts.topics,
            }},
            .method = .eth_getLogs,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_getLogs,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_logs = try self.parseRPCEvent(?Logs, response);

    const logs = possible_logs.response orelse return error.InvalidLogRequestParams;

    return .{
        .arena = possible_logs.arena,
        .response = logs,
    };
}

/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *Provider) !RPCResponse(bool) {
    return self.sendBasicRequest(bool, .net_listening);
}

/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *Provider) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_peerCount);
}

/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *Provider) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_version);
}

/// Retrieves the current version of the Portal contract.
///
/// If the major is at least 3 it means that fault proofs are enabled.
pub fn getPortalVersion(
    self: *Provider,
    allocator: Allocator,
) !SemanticVersion {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const selector_version: []u8 = @constCast(&[_]u8{ 0x54, 0xfd, 0x4d, 0x50 });
    const version = try self.sendEthCall(.{ .london = .{
        .to = contracts.portalAddress,
        .data = selector_version,
    } }, .{});
    defer version.deinit();

    const decode = try decoder.decodeAbiParameterLeaky([]const u8, allocator, version.response, .{});

    return SemanticVersion.parse(decode);
}

/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(
    self: *Provider,
    opts: ProofRequest,
    tag: ?ProofBlockTag,
) !RPCResponse(ProofResult) {
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { Address, []const Hash, block.ProofBlockTag }) = .{
            .params = .{ opts.address, opts.storageKeys, request_tag },
            .method = .eth_getProof,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const number = opts.blockNumber orelse return error.ExpectBlockNumberOrTag;

        const request: EthereumRequest(struct { Address, []const Hash, u64 }) = .{
            .params = .{ opts.address, opts.storageKeys, number },
            .method = .eth_getProof,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(ProofResult, response);
}

/// Returns the current Ethereum protocol version.
///
/// RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)
pub fn getProtocolVersion(self: *Provider) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_protocolVersion);
}

/// Gets the l2 transaction hashes for the deposit transaction event.
///
/// `hash` is expected to be the transaction hash from the deposit transaction.
pub fn getL2HashesForDepositTransaction(
    self: *Provider,
    allocator: Allocator,
    tx_hash: Hash,
) ![]const Hash {
    const deposit_data = try self.getTransactionDepositEvents(allocator, tx_hash);
    defer allocator.free(deposit_data);

    var list = try std.array_list.Managed(Hash).initCapacity(allocator, deposit_data.len);
    errdefer list.deinit();

    for (deposit_data) |data| {
        defer allocator.free(data.opaqueData);

        try list.append(try op_utils.getL2HashFromL1DepositInfo(allocator, .{
            .to = data.to,
            .from = data.from,
            .opaque_data = data.opaqueData,
            .l1_blockhash = data.blockHash,
            .log_index = data.logIndex,
            .domain = .user_deposit,
        }));
    }

    return list.toOwnedSlice();
}

/// Calls to the ProviderOutputOracle contract on Provider to get the output for a given L2 block
pub fn getL2Output(
    self: *Provider,
    allocator: Allocator,
    l2_block_number: u256,
) !L2Output {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const version = try self.getPortalVersion(allocator);

    if (version.major >= 3) {
        const game = try self.getGame(allocator, 1, l2_block_number, .latest);

        return .{
            .outputIndex = game.index,
            .outputRoot = game.rootClaim,
            .timestamp = game.timestamp,
            .l2BlockNumber = @intCast(game.l2BlockNumber),
        };
    }

    const index = try self.getL2OutputIndex(allocator, l2_block_number);

    const encoded = try abi_op.get_l2_output_func.encode(allocator, .{index});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    const decoded = try decoder.decodeAbiParameter(struct { outputRoot: Hash, timestamp: u128, l2BlockNumber: u128 }, allocator, data.response, .{});
    defer decoded.deinit();

    const l2_output = decoded.result;

    return .{
        .outputIndex = index,
        .outputRoot = l2_output.outputRoot,
        .timestamp = l2_output.timestamp,
        .l2BlockNumber = l2_output.l2BlockNumber,
    };
}

/// Calls to the ProviderOutputOracle on Provider to get the output index.
pub fn getL2OutputIndex(
    self: *Provider,
    allocator: Allocator,
    l2_block_number: u256,
) !u256 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const encoded = try abi_op.get_l2_index_func.encode(allocator, .{l2_block_number});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    return zabi_utils.utils.bytesToInt(u256, data.response);
}

/// Gets a proven withdrawal.
///
/// Will call the portal contract to get the information. If the timestamp is 0
/// this will error with invalid withdrawal hash.
pub fn getProvenWithdrawals(
    self: *Provider,
    allocator: Allocator,
    withdrawal_hash: Hash,
) !ProvenWithdrawal {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;

    const encoded = try abi_op.get_proven_withdrawal.encode(allocator, .{withdrawal_hash});
    defer allocator.free(encoded);

    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.portalAddress,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    const proven = try decoder.decodeAbiParameterLeaky(ProvenWithdrawal, allocator, data.response, .{});

    if (proven.timestamp == 0)
        return error.InvalidWithdrawalHash;

    return proven;
}

/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(
    self: *Provider,
    tx_hash: Hash,
) !RPCResponse(Hex) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{tx_hash},
        .method = .eth_getRawTransactionByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(Hex, response);
}

/// Gets the amount of time to wait in ms until the next output is posted.
///
/// Calls the l2OutputOracle to get this information.
pub fn getSecondsToNextL2Output(self: *Provider, latest_l2_block: u64) !u128 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;
    const latest = try self.getLatestProposedL2BlockNumber();

    if (latest_l2_block < latest)
        return error.InvalidBlockNumber;

    // Selector for "SUBMISSION_INTERVAL()"
    const selector: []u8 = @constCast(&[_]u8{ 0x52, 0x99, 0x33, 0xdf });

    const submission = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = selector,
    } }, .{});
    defer submission.deinit();

    const interval = try zabi_utils.utils.bytesToInt(i128, submission.response);

    // Selector for "Provider_BLOCK_TIME()"
    const selector_time: []u8 = @constCast(&[_]u8{ 0x00, 0x21, 0x34, 0xcc });
    const block_info = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = selector_time,
    } }, .{});
    defer block_info.deinit();

    const time = try zabi_utils.utils.bytesToInt(i128, block_info.response);

    const block_until: i128 = interval - (latest_l2_block - latest);

    return if (block_until < 0) @intCast(0) else @intCast(block_until * time);
}

/// Gets the amount of time to wait until a withdrawal is finalized.
///
/// Calls the l2OutputOracle to get this information.
pub fn getSecondsToFinalize(
    self: *Provider,
    allocator: Allocator,
    withdrawal_hash: Hash,
) !u64 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;
    const proven = try self.getProvenWithdrawals(allocator, withdrawal_hash);

    // Selector for "FINALIZATION_PERIOD_SECONDS()"
    const selector: []u8 = @constCast(&[_]u8{ 0xf4, 0xda, 0xa2, 0x91 });
    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.l2OutputOracle,
        .data = selector,
    } }, .{});
    defer data.deinit();

    const time = try zabi_utils.utils.bytesToInt(i64, data.response);
    const time_since: i64 = @divFloor(std.time.timestamp(), 1000) - @as(i64, @truncate(@as(i128, @intCast(proven.timestamp))));

    return if (time_since < 0) @intCast(0) else @intCast(time - time_since);
}

/// Gets the amount of time to wait until a dispute game has finalized
///
/// Uses the portal to find this information. Will error if the time is 0.
pub fn getSecondsToFinalizeGame(
    self: *Provider,
    allocator: Allocator,
    withdrawal_hash: Hash,
) !u64 {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectOpStackContracts;
    const proven = try self.getProvenWithdrawals(allocator, withdrawal_hash);

    // Selector for "proofMaturityDelaySeconds()"
    const selector: []u8 = @constCast(&[_]u8{ 0xbf, 0x65, 0x3a, 0x5c });
    const data = try self.sendEthCall(.{ .london = .{
        .to = contracts.portalAddress,
        .data = selector,
    } }, .{});
    defer data.deinit();

    const time = try zabi_utils.utils.bytesToInt(i64, data.response);

    if (time == 0)
        return error.WithdrawalNotProved;

    const time_since: i64 = @divFloor(std.time.timestamp(), 1000) - @as(i64, @truncate(@as(i128, @intCast(proven.timestamp))));

    return if (time_since < 0) @intCast(0) else @intCast(time - time_since);
}

/// Gets the timings until the next dispute game is submitted based on the provided `l2BlockNumber`
pub fn getSecondsUntilNextGame(
    self: *Provider,
    allocator: Allocator,
    interval_buffer: f64,
    l2BlockNumber: u64,
) !NextGameTimings {
    const games = try self.getGames(allocator, 10, null);
    defer allocator.free(games);

    var elapsed_time: i64 = 0;
    var block_interval: i64 = 0;

    for (games, 1..) |game, i| {
        if (i == games.len)
            break;

        const time = try std.math.sub(i128, @intCast(games[i].timestamp), @intCast(game.timestamp));
        const block_number = try std.math.sub(i128, @intCast(games[i].l2BlockNumber), @intCast(game.l2BlockNumber));

        elapsed_time = @intCast(elapsed_time - (time - block_number));
        block_interval = @intCast(block_interval - block_number);
    }

    elapsed_time = try std.math.divCeil(isize, elapsed_time, @intCast(games.len - 1));
    block_interval = try std.math.divCeil(isize, block_interval, @intCast(games.len - 1));

    const latest_game = games[0];
    const latest_timestamp: i64 = @intCast(latest_game.timestamp * 1000);

    const interval: i64 = @intFromFloat(@ceil(@as(f64, @floatFromInt(elapsed_time)) * interval_buffer) + 1);
    const now = std.time.timestamp() * 1000;

    const seconds: i64 = blk: {
        if (now < latest_timestamp)
            break :blk 0;

        if (latest_game.l2BlockNumber > l2BlockNumber)
            break :blk 0;

        const elapsed_blocks: i64 = @intCast(l2BlockNumber - latest_game.l2BlockNumber);
        const elapsed = try std.math.divCeil(i64, now - latest_timestamp, 1000);

        const seconds_until: i64 = interval - @mod(elapsed, interval);

        break :blk if (elapsed_blocks < block_interval) seconds_until else try std.math.divFloor(i64, elapsed_blocks, block_interval) * interval;
    };

    const timestamp: ?i64 = if (seconds > 0) now + seconds * 1000 else null;

    return .{
        .interval = elapsed_time,
        .seconds = seconds,
        .timestamp = timestamp,
    };
}

/// Returns the Keccak256 hash of the given message.
/// Must be a hex encoded message.
///
/// RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)
pub fn getSha3Hash(
    self: *Provider,
    message: []const u8,
) !RPCResponse(Hash) {
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{message},
        .method = .web3_sha3,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [4096]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(Hash, response);
}

/// Returns the value from a storage position at a given address.
///
/// RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)
pub fn getStorage(
    self: *Provider,
    address: Address,
    storage_key: Hash,
    opts: BlockNumberRequest,
) !RPCResponse(Hash) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, Hash, u64 }) = .{
            .params = .{ address, storage_key, number },
            .method = .eth_getStorageAt,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { Address, Hash, BalanceBlockTag }) = .{
            .params = .{ address, storage_key, tag },
            .method = .eth_getStorageAt,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(Hash, response);
}

/// Returns null if the node has finished syncing. Otherwise it will return
/// the sync progress.
///
/// RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)
pub fn getSyncStatus(self: *Provider) ?RPCResponse(SyncProgress) {
    return self.sendBasicRequest(SyncProgress, .eth_syncing) catch null;
}

/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(
    self: *Provider,
    block_hash: Hash,
    index: usize,
) !RPCResponse(Transaction) {
    return self.getTransactionByBlockHashAndIndexType(Transaction, block_hash, index);
}

/// Returns information about a transaction by block hash and transaction index position.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndexType(
    self: *Provider,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getTransactionByBlockHashAndIndex,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_tx = try self.parseRPCEvent(?T, response);

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}

pub fn getTransactionByBlockNumberAndIndex(
    self: *Provider,
    opts: BlockNumberRequest,
    index: usize,
) !RPCResponse(Transaction) {
    return self.getTransactionByBlockNumberAndIndexType(Transaction, opts, index);
}

/// Returns information about a transaction by block number and transaction index position.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndexType(
    self: *Provider,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_tx = try self.parseRPCEvent(?T, response);

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}

/// Returns the information about a transaction requested by transaction hash.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHash(
    self: *Provider,
    transaction_hash: Hash,
) !RPCResponse(Transaction) {
    return self.getTransactionByHashType(Transaction, transaction_hash);
}

/// Returns the information about a transaction requested by transaction hash.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHashType(
    self: *Provider,
    comptime T: type,
    transaction_hash: Hash,
) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_tx = try self.parseRPCEvent(?T, response);

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}

/// Gets the `TransactionDeposited` event logs from a transaction hash.
///
/// To free the memory of this slice you will also need to loop through the
/// returned slice and free the `opaqueData` field. Memory will be duped
/// on that field because we destroy the Arena from the RPC request that owns
/// the original piece of memory that contains the data.
pub fn getTransactionDepositEvents(self: *Provider, allocator: Allocator, tx_hash: Hash) ![]const TransactionDeposited {
    const receipt = try self.getTransactionReceipt(tx_hash);
    defer receipt.deinit();

    const logs: Logs = switch (receipt.response) {
        inline else => |tx_receipt| tx_receipt.logs,
    };

    var list = std.array_list.Managed(TransactionDeposited).init(allocator);
    errdefer list.deinit();

    // Event selector for `TransactionDeposited`.
    const hash: u256 = comptime @bitCast(zabi_utils.utils.hashToBytes("0xb3813568d9991fc951961fcb4c784893574240a28925604d09fc577c55bb7c32") catch unreachable);

    for (logs) |log_event| {
        const hash_topic: u256 = @bitCast(log_event.topics[0] orelse return error.ExpectedTopicData);

        if (hash != hash_topic)
            continue;

        if (log_event.logIndex == null)
            return error.UnexpectedNullIndex;

        const decoded = try decoder.decodeAbiParameter([]u8, allocator, log_event.data, .{});
        defer decoded.deinit();

        const decoded_logs = try decoder_logs.decodeLogs(struct { Hash, Address, Address, u256 }, log_event.topics, .{});

        try list.append(.{
            .from = decoded_logs[1],
            .to = decoded_logs[2],
            .version = decoded_logs[3],
            // Needs to be duped because the arena owns this memory.
            .opaqueData = try allocator.dupe(u8, decoded.result),
            .logIndex = log_event.logIndex.?,
            .blockHash = log_event.blockHash.?,
        });
    }

    return list.toOwnedSlice();
}

/// Returns the receipt of a transaction by transaction hash.
///
/// Consider using this method if the provided `TransactionReceipt` types fail to json parse the request and
/// you know extractly the shape of the data that the receipt is expected to be like.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(
    self: *Provider,
    transaction_hash: Hash,
) !RPCResponse(TransactionReceipt) {
    return self.getTransactionReceiptType(TransactionReceipt, transaction_hash);
}

/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceiptType(
    self: *Provider,
    comptime T: type,
    transaction_hash: Hash,
) !RPCResponse(TransactionReceipt) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionReceipt,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const possible_receipt = try self.parseRPCEvent(?T, response);

    const receipt = possible_receipt.response orelse return error.TransactionReceiptNotFound;

    return .{
        .arena = possible_receipt.arena,
        .response = receipt,
    };
}

/// The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// The result is an object with two fields pending and queued.\
/// Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.\
/// These batches themselves are maps associating nonces with actual transactions.
///
/// RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContent(self: *Provider) !RPCResponse(TxPoolContent) {
    return self.sendBasicRequest(TxPoolContent, .txpool_content);
}

/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(
    self: *Provider,
    from: Address,
) !RPCResponse([]const PoolTransactionByNonce) {
    const request: EthereumRequest(struct { Address }) = .{
        .params = .{from},
        .method = .txpool_contentFrom,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent([]const PoolTransactionByNonce, response);
}

/// The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.\
/// This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.
///
/// RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolInspectStatus(self: *Provider) !RPCResponse(TxPoolInspect) {
    return self.sendBasicRequest(TxPoolInspect, .txpool_inspect);
}

/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *Provider) !RPCResponse(TxPoolStatus) {
    return self.sendBasicRequest(TxPoolStatus, .txpool_status);
}

/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(
    self: *Provider,
    block_hash: Hash,
    index: usize,
) !RPCResponse(Block) {
    return self.getUncleByBlockHashAndIndexType(Block, block_hash, index);
}

/// Returns information about a uncle of a block by hash and uncle index position.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndexType(
    self: *Provider,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getUncleByBlockHashAndIndex,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const request_block = try self.parseRPCEvent(?T, response);

    const block_info = request_block.response orelse return error.InvalidBlockHashOrIndex;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}

/// Returns information about a uncle of a block by number and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndex(
    self: *Provider,
    opts: BlockNumberRequest,
    index: usize,
) !RPCResponse(Block) {
    return self.getUncleByBlockNumberAndIndexType(Block, opts, index);
}

/// Returns information about a uncle of a block by number and uncle index position.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndexType(
    self: *Provider,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    const request_block = try self.parseRPCEvent(?T, response);

    const block_info = request_block.response orelse return error.InvalidBlockNumberOrIndex;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}

/// Returns the number of uncles in a block from a block matching the given block hash.
///
/// RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)
pub fn getUncleCountByBlockHash(
    self: *Provider,
    block_hash: Hash,
) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
}

/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(
    self: *Provider,
    opts: BlockNumberRequest,
) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
}

/// Gets the decoded withdrawl event logs from a given transaction receipt hash.
pub fn getWithdrawMessages(self: *Provider, allocator: Allocator, tx_hash: Hash) !Message {
    const receipt_response = try self.getTransactionReceipt(tx_hash);
    defer receipt_response.deinit();

    const receipt = receipt_response.response;

    if (receipt != .op_receipt)
        return error.InvalidTransactionHash;

    var list = std.array_list.Managed(Withdrawal).init(allocator);
    errdefer list.deinit();

    // The hash for the event selector `MessagePassed`
    const hash: u256 = comptime @bitCast(zabi_utils.utils.hashToBytes("0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054") catch unreachable);

    for (receipt.op_receipt.logs) |logs| {
        const hash_topic: u256 = @bitCast(logs.topics[0] orelse return error.ExpectedTopicData);

        if (hash != hash_topic)
            continue;

        const decoded = try decoder.decodeAbiParameterLeaky(struct { u256, u256, []u8, [32]u8 }, allocator, logs.data, .{});
        const decoded_logs = try decoder_logs.decodeLogs(struct { Hash, u256, Address, Address }, logs.topics, .{});

        try list.append(.{
            .nonce = decoded_logs[1],
            .target = decoded_logs[2],
            .sender = decoded_logs[3],
            .value = decoded[0],
            .gasLimit = decoded[1],
            .data = decoded[2],
            .withdrawalHash = decoded[3],
        });
    }

    const messages = try list.toOwnedSlice();

    return .{
        .blockNumber = receipt.op_receipt.blockNumber.?,
        .messages = messages,
    };
}

/// Gets the decoded withdrawl event logs from a given transaction receipt hash.
pub fn getWithdrawMessagesL2(
    self: *Provider,
    allocator: Allocator,
    tx_hash: Hash,
) !Message {
    const contracts = self.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const receipt_message = try self.getTransactionReceipt(tx_hash);
    defer receipt_message.deinit();

    const receipt = receipt_message.response;

    switch (receipt_message.response) {
        .op_receipt => {},
        inline else => |tx_receipt| {
            const to = tx_receipt.to orelse return error.InvalidTransactionHash;

            const casted_to: u160 = @bitCast(to);
            const casted_l2: u160 = @bitCast(contracts.l2ToL1MessagePasser);

            if (casted_to != casted_l2)
                return error.InvalidTransactionHash;
        },
    }

    var list = std.array_list.Managed(Withdrawal).init(allocator);
    errdefer list.deinit();

    // The hash for the event selector `MessagePassed`
    const hash: Hash = comptime try zabi_utils.utils.hashToBytes("0x02a52367d10742d8032712c1bb8e0144ff1ec5ffda1ed7d70bb05a2744955054");

    const logs = switch (receipt) {
        inline else => |tx_receipt| tx_receipt.logs,
    };

    for (logs) |message| {
        const topic_hash: Hash = message.topics[0] orelse return error.ExpectedTopicData;
        if (std.mem.eql(u8, &hash, &topic_hash)) {
            const decoded = try decoder.decodeAbiParameterLeaky(struct { u256, u256, []u8, Hash }, allocator, message.data, .{});

            const decoded_logs = try decoder_logs.decodeLogs(struct { Hash, u256, Address, Address }, message.topics, .{});

            try list.ensureUnusedCapacity(1);
            list.appendAssumeCapacity(.{
                .nonce = decoded_logs[1],
                .target = decoded_logs[2],
                .sender = decoded_logs[3],
                .value = decoded[0],
                .gasLimit = decoded[1],
                .data = decoded[2],
                .withdrawalHash = decoded[3],
            });
        }
    }

    const messages = try list.toOwnedSlice();

    const block_info = switch (receipt) {
        inline else => |tx_receipt| tx_receipt.blockNumber,
    };

    return .{
        .blockNumber = block_info.?,
        .messages = messages,
    };
}

/// Runs the selected multicall3 contracts.
/// This enables to read from multiple contract by a single `eth_call`.
/// Uses the contracts created [here](https://www.multicall3.com/)
///
/// To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)
pub fn multicall3(
    rpc_client: *Provider,
    comptime targets: []const MulticallTargets,
    allocator: Allocator,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) !AbiDecoded([]const Result) {
    comptime std.debug.assert(targets.len == function_arguments.len);

    var abi_list = try std.array_list.Managed(Call3).initCapacity(allocator, targets.len);
    errdefer abi_list.deinit();

    inline for (targets, function_arguments) |target, argument| {
        const encoded = try target.function.encode(allocator, argument);

        const call3: Call3 = .{
            .target = target.target_address,
            .callData = encoded,
            .allowFailure = allow_failure,
        };

        abi_list.appendAssumeCapacity(call3);
    }

    const slice = try abi_list.toOwnedSlice();
    defer {
        for (slice) |s| allocator.free(s.callData);
        allocator.free(slice);
    }

    const encoded = try aggregate3_abi.encode(allocator, .{@ptrCast(slice)});
    defer allocator.free(encoded);

    const data = try rpc_client.sendEthCall(.{ .london = .{
        .to = rpc_client.network_config.multicall_contract,
        .data = encoded,
    } }, .{});
    defer data.deinit();

    return decoder.decodeAbiParameter(
        []const Result,
        allocator,
        data.response,
        .{ .allocate_when = .alloc_always },
    );
}

/// Creates a filter in the node, to notify when a new block arrives.
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *Provider) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newBlockFilter);
}

/// Creates a filter object, based on filter options, to notify when the state changes (logs).
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(
    self: *Provider,
    opts: LogRequest,
    tag: ?BalanceBlockTag,
) !RPCResponse(u128) {
    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { LogTagRequest }) = .{
            .params = .{.{
                .fromBlock = request_tag,
                .toBlock = request_tag,
                .address = opts.address,
                .blockHash = opts.blockHash,
                .topics = opts.topics,
            }},
            .method = .eth_newFilter,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_newFilter,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(u128, response);
}

/// Creates a filter in the node, to notify when new pending transactions arrive.
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *Provider) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newPendingTransactionFilter);
}

/// Executes a new message call immediately without creating a transaction on the block chain.\
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(
    self: *Provider,
    call_object: EthCall,
    opts: BlockNumberRequest,
) !RPCResponse(Hex) {
    return self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}

/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(
    self: *Provider,
    serialized_tx: Hex,
) !RPCResponse(Hash) {
    const request: EthereumRequest(struct { Hex }) = .{
        .params = .{serialized_tx},
        .method = .eth_sendRawTransaction,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(Hash, response);
}

/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
///
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstallFilter(
    self: *Provider,
    id: usize,
) !RPCResponse(bool) {
    const request: EthereumRequest(struct { usize }) = .{
        .params = .{id},
        .method = .eth_uninstallFilter,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(bool, response);
}

/// Unsubscribe from different Ethereum event types with a regular RPC call
///
/// with eth_unsubscribe as the method and the subscriptionId as the first parameter.
///
/// RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)
pub fn unsubscribe(self: *Provider, sub_id: u128) !RPCResponse(bool) {
    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{sub_id},
        .method = .eth_unsubscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(bool, response);
}

/// Waits until the next dispute game to be submitted based on the provided `l2BlockNumber`
/// This will keep pooling until it can get the `GameResult` or it exceeds the max retries.
pub fn waitForNextGame(
    self: *Provider,
    allocator: Allocator,
    limit: usize,
    interval_buffer: f64,
    l2BlockNumber: u64,
) !GameResult {
    const timings = try self.getSecondsUntilNextGame(allocator, interval_buffer, l2BlockNumber);
    std.Thread.sleep(@intCast(timings.seconds * std.time.ns_per_s));

    var retries: usize = 0;
    const game: GameResult = while (true) : (retries += 1) {
        if (retries > self.network_config.retries)
            return error.ExceedRetriesAmount;

        const output = self.getGame(limit, l2BlockNumber, .random) catch |err| switch (err) {
            error.EvmFailedToExecute,
            error.GameNotFound,
            => {
                std.Thread.sleep(self.network_config.pooling_interval);
                continue;
            },
            else => return err,
        };

        break output;
    };

    return game;
}

/// Waits until the next Provider output is posted.
/// This will keep pooling until it can get the ProviderOutput or it exceeds the max retries.
pub fn waitForNextProviderOutput(
    self: *Provider,
    allocator: Allocator,
    latest_l2_block: u64,
) !L2Output {
    const time = try self.getSecondsToNextProviderOutput(latest_l2_block);
    std.Thread.sleep(@intCast(time * 1000));

    var retries: usize = 0;
    const l2_output = while (true) : (retries += 1) {
        if (retries > self.network_config.retries)
            return error.ExceedRetriesAmount;

        const output = self.getProviderOutput(allocator, latest_l2_block) catch |err| switch (err) {
            error.EvmFailedToExecute => {
                std.Thread.sleep(self.network_config.retries);
                continue;
            },
            else => return err,
        };

        break output;
    };

    return l2_output;
}

/// Waits until a transaction gets mined and the receipt can be grabbed.\
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(
    self: *Provider,
    tx_hash: Hash,
    confirmations: u8,
) !RPCResponse(TransactionReceipt) {
    return self.waitForTransactionReceiptType(TransactionReceipt, tx_hash, confirmations);
}

/// Waits until a transaction gets mined and the receipt can be grabbed.\
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// Consider using this method if the provided `TransactionReceipt` types fail to json parse the request and
/// you know extractly the shape of the data that the receipt is expected to be like.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceiptType(
    self: *Provider,
    comptime T: type,
    tx_hash: Hash,
    confirmations: u8,
) !RPCResponse(T) {
    var tx: ?RPCResponse(Transaction) = null;
    defer if (tx) |tx_res| tx_res.deinit();

    const block_number_request = try self.getBlockNumber();
    defer block_number_request.deinit();

    var block_number = block_number_request.response;

    var receipt: ?RPCResponse(T) = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
        error.TransactionReceiptNotFound => null,
        else => return err,
    };
    errdefer if (receipt) |tx_receipt| tx_receipt.deinit();

    if (receipt) |tx_receipt| {
        if (confirmations == 0)
            return tx_receipt;
    }

    var retries: u8 = if (receipt != null) 1 else 0;
    var valid_confirmations: u8 = if (receipt != null) 1 else 0;
    while (true) : (retries += 1) {
        if (retries - valid_confirmations > self.network_config.retries)
            return error.FailedToGetReceipt;

        if (receipt) |tx_receipt| {
            const number: ?u64 = switch (tx_receipt.response) {
                inline else => |all| all.blockNumber,
            };
            // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
            if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations)) {
                receipt = tx_receipt;
                break;
            } else {
                valid_confirmations += 1;
                std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                continue;
            }
        }

        if (tx == null) {
            tx = self.getTransactionByHash(tx_hash) catch |err| switch (err) {
                // If it fails we keep trying
                error.TransactionNotFound => {
                    std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                    continue;
                },
                else => return err,
            };
        }

        switch (tx.?.response) {
            // Changes the block search to the one of the found transaction
            inline else => |tx_object| {
                if (tx_object.blockNumber) |number| block_number = number;
            },
        }

        receipt = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
            error.TransactionReceiptNotFound => {
                // Need to check if the transaction was replaced.
                const current_block = try self.getBlockByNumber(.{ .include_transaction_objects = true });
                defer current_block.deinit();

                const tx_info: struct { from: Address, nonce: u64 } = switch (tx.?.response) {
                    inline else => |transactions| .{ .from = transactions.from, .nonce = transactions.nonce },
                };

                const block_transactions = switch (current_block.response) {
                    inline else => |blocks| if (blocks.transactions) |block_txs| block_txs else {
                        std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                        continue;
                    },
                };

                const pending_transaction = switch (block_transactions) {
                    .hashes => {
                        std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                        continue;
                    },
                    .objects => |tx_objects| tx_objects,
                };

                const replaced: ?Transaction = for (pending_transaction) |pending| {
                    const pending_info: struct { from: Address, nonce: u64 } = switch (pending) {
                        inline else => |transactions| .{ .from = transactions.from, .nonce = transactions.nonce },
                    };

                    if (std.mem.eql(u8, &tx_info.from, &pending_info.from) and pending_info.nonce == tx_info.nonce)
                        break pending;
                } else null;

                // If the transaction was replace return it's receipt. Otherwise try again.
                if (replaced) |replaced_tx| {
                    receipt = switch (replaced_tx) {
                        inline else => |tx_object| try self.getTransactionReceipt(tx_object.hash),
                    };

                    provider_log.debug("Transaction was replace by a newer one", .{});

                    switch (replaced_tx) {
                        inline else => |replacement| switch (tx.?.response) {
                            inline else => |original| {
                                if (std.mem.eql(u8, &replacement.from, &original.from) and replacement.value == original.value)
                                    provider_log.debug("Original transaction was repriced", .{});

                                if (replacement.to) |replaced_to| {
                                    if (std.mem.eql(u8, &replacement.from, &replaced_to) and replacement.value == 0)
                                        provider_log.debug("Original transaction was canceled", .{});
                                }
                            },
                        },
                    }

                    // Here we are sure to have a valid receipt.
                    const valid_receipt = receipt.?.response;
                    const number: ?u64 = switch (valid_receipt) {
                        inline else => |all| all.blockNumber,
                    };
                    // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
                    if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations))
                        break;
                }

                std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                continue;
            },
            else => return err,
        };

        const valid_receipt = receipt.?.response;
        const number: ?u64 = switch (valid_receipt) {
            inline else => |all| all.blockNumber,
        };
        // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
        if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations)) {
            break;
        } else {
            valid_confirmations += 1;
            std.Thread.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
            continue;
        }
    }

    return if (receipt) |tx_receipt| tx_receipt else error.FailedToGetReceipt;
}

/// Waits until the withdrawal has finalized.
pub fn waitToFinalize(
    self: *Provider,
    allocator: Allocator,
    withdrawal_hash: Hash,
) !void {
    const version = try self.getPortalVersion(allocator);

    if (version.major < 3) {
        const time = try self.getSecondsToFinalize(allocator, withdrawal_hash);
        std.Thread.sleep(time * 1000);
        return;
    }

    const time = try self.getSecondsToFinalizeGame(allocator, withdrawal_hash);
    std.Thread.sleep(time * 1000);
}

/// Emits new blocks that are added to the blockchain.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
///
/// This is best use only for websocket or ipc connections
pub fn watchNewBlocks(self: *Provider) !RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newHeads},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(u128, response);
}

/// Emits logs attached to a new block that match certain topic filters and address.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)
///
/// This is best use only for websocket or ipc connections
pub fn watchLogs(self: *Provider, opts: WatchLogsRequest) !RPCResponse(u128) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    const request: EthereumRequest(struct { Subscriptions, WatchLogsRequest }) = .{
        .params = .{ .logs, opts },
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(u128, response);
}

/// Creates a new subscription for desired events. Sends data as soon as it occurs
///
/// This expects the method to be a valid websocket subscription method.
/// Since we have no way of knowing all possible or custom RPC methods that nodes can provide.
///
/// Returns the subscription Id.
///
/// This is best use only for websocket or ipc connections
pub fn watchSocketEvent(self: *Provider, method: []const u8) !RPCResponse(u128) {
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{method},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(u128, response);
}

/// Emits transaction hashes that are sent to the network and marked as "pending".
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)
///
/// This is best use only for websocket or ipc connections
pub fn watchTransactions(self: *Provider) !RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newPendingTransactions},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(u128, response);
}

// Sends specific block_number requests.
fn sendBlockNumberRequest(
    self: *Provider,
    opts: BlockNumberRequest,
    method: EthereumRpcMethods,
) !RPCResponse(usize) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64 }) = .{
            .params = .{number},
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag }) = .{
            .params = .{tag},
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(usize, response);
}

// Sends specific block_hash requests.
fn sendBlockHashRequest(
    self: *Provider,
    block_hash: Hash,
    method: EthereumRpcMethods,
) !RPCResponse(usize) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{block_hash},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(usize, response);
}

// Sends request specific for addresses.
fn sendAddressRequest(
    self: *Provider,
    comptime T: type,
    opts: BalanceRequest,
    method: EthereumRpcMethods,
) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{}, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(T, response);
}

// Sends requests where the params are empty.
fn sendBasicRequest(
    self: *Provider,
    comptime T: type,
    method: EthereumRpcMethods,
) !RPCResponse(T) {
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    try std.json.Stringify.value(request, .{}, &buf_writter);

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(T, response);
}

// Sends eth_call request
fn sendEthCallRequest(
    self: *Provider,
    comptime T: type,
    call_object: EthCall,
    opts: BlockNumberRequest,
    method: EthereumRpcMethods,
) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.Io.Writer.fixed(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &buf_writter);
    }

    const response = try self.vtable.sendRpcRequest(self, buf_writter.buffered());
    errdefer response.deinit();

    return self.parseRPCEvent(T, response);
}

fn parseRPCEvent(
    self: *Provider,
    comptime T: type,
    response: JsonParsed(Value),
) !RPCResponse(T) {
    _ = self;
    const parsed = std.json.parseFromValueLeaky(EthereumResponse(T), response.arena.allocator(), response.value, .{}) catch
        return error.UnexpectedErrorFound;

    switch (parsed) {
        .success => |res| return RPCResponse(T).fromJson(response.arena, res.result),
        .@"error" => |res| {
            provider_log.debug("RPC error response: {s}", .{res.@"error".message});

            if (res.@"error".data) |data|
                provider_log.debug("RPC error data response: {s}", .{data});

            switch (res.@"error".code) {
                .ContractErrorCode => return error.EvmFailedToExecute,
                .TooManyRequests => return error.TooManyRequestError,
                .InvalidInput => return error.InvalidInput,
                .MethodNotFound => return error.MethodNotFound,
                .ResourceNotFound => return error.ResourceNotFound,
                .InvalidRequest => return error.InvalidRequest,
                .ParseError => return error.ParseError,
                .LimitExceeded => return error.LimitExceeded,
                .InvalidParams => return error.InvalidParams,
                .InternalError => return error.InternalError,
                .MethodNotSupported => return error.MethodNotSupported,
                .ResourceUnavailable => return error.ResourceNotFound,
                .TransactionRejected => return error.TransactionRejected,
                .RpcVersionNotSupported => return error.RpcVersionNotSupported,
                .UserRejectedRequest => return error.UserRejectedRequest,
                .Unauthorized => return error.Unauthorized,
                .UnsupportedMethod => return error.UnsupportedMethod,
                .Disconnected => return error.Disconnected,
                .ChainDisconnected => return error.ChainDisconnected,
                _ => return error.UnexpectedRpcErrorCode,
            }
        },
    }
}

pub const WebsocketProvider = struct {
    pub const InitOptions = struct {
        /// Allocator to use to create the ChildProcess and other allocations
        allocator: Allocator,
        /// The chains config
        network_config: NetworkConfig,
        /// Callback function for when the connection is closed.
        onClose: ?*const fn () void = null,
        /// Callback function for everytime an event is parsed.
        onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null,
        /// Callback function for everytime an error is caught.
        onError: ?*const fn (args: []const u8) anyerror!void = null,
    };

    /// The allocator that will manage the connections memory
    allocator: Allocator,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void,
    /// Callback function that will run once a socket event is parsed
    onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void,
    provider: Provider,
    /// Channel used to communicate between threads on rpc events.
    rpc_channel: Stack(JsonParsed(Value)),
    /// Channel used to communicate between threads on subscription events.
    sub_channel: Channel(JsonParsed(Value)),
    /// Callback function that will run once a error is parsed.
    onError: ?*const fn (args: []const u8) anyerror!void,
    thread: ?std.Thread,
    /// The underlaying websocket client
    ws_client: WsClient,

    /// Populates the WebSocketHandler pointer.
    /// Starts the connection in a seperate process.
    pub fn init(opts: InitOptions) !WebsocketProvider {
        if (opts.network_config.endpoint != .uri)
            return error.InvalidEndpointConfig;

        const uri = opts.network_config.endpoint.uri;
        const hostname = switch (uri.host orelse return error.UnspecifiedHostName) {
            .raw => |raw| raw,
            .percent_encoded => |host| host,
        };

        var client = try WsClient.connect(opts.allocator, uri);
        try client.handshake(hostname);

        return .{
            .allocator = opts.allocator,
            .provider = .{
                .network_config = opts.network_config,
                .vtable = &.{
                    .sendRpcRequest = WebsocketProvider.sendRpcRequest,
                },
            },
            .onClose = opts.onClose,
            .onError = opts.onError,
            .onEvent = opts.onEvent,
            .rpc_channel = Stack(JsonParsed(Value)).init(opts.allocator, null),
            .sub_channel = Channel(JsonParsed(Value)).init(opts.allocator),
            .thread = null,
            .ws_client = client,
        };
    }

    /// If you are using the subscription channel this operation can take time
    /// as it will need to cleanup each node.
    pub fn deinit(self: *WebsocketProvider) void {
        // There may be lingering memory from the json parsed data
        // in the channels so we must clean then up.
        while (self.sub_channel.getOrNull()) |node|
            node.deinit();

        while (self.rpc_channel.popOrNull()) |node|
            node.deinit();

        // Deinits client and destroys any created pointers.
        self.sub_channel.deinit();
        self.rpc_channel.deinit();
        self.ws_client.deinit();

        if (self.thread) |thread|
            thread.join();

        self.ws_client.connection.destroyConnection(self.allocator);
    }

    /// Parses the `Value` in the sub-channel as a pending transaction hash event
    pub fn getPendingTransactionsSubEvent(self: *WebsocketProvider) !RPCResponse(EthereumSubscribeResponse(Hash)) {
        return self.parseSubscriptionEvent(Hash);
    }

    /// Parses the `Value` in the sub-channel as a log event
    pub fn getLogsSubEvent(self: *WebsocketProvider) !RPCResponse(EthereumSubscribeResponse(Log)) {
        return self.parseSubscriptionEvent(Log);
    }
    /// Parses the `Value` in the sub-channel as a new heads block event
    pub fn getNewHeadsBlockSubEvent(self: *WebsocketProvider) !RPCResponse(EthereumSubscribeResponse(Block)) {
        return self.parseSubscriptionEvent(Block);
    }

    /// Parses a subscription event `Value` into `T`.
    /// Usefull for events that currently zabi doesn't have custom support.
    pub fn parseSubscriptionEvent(self: *WebsocketProvider, comptime T: type) !RPCResponse(EthereumSubscribeResponse(T)) {
        const event = self.sub_channel.get();
        errdefer event.deinit();

        const parsed = try std.json.parseFromValueLeaky(
            EthereumSubscribeResponse(T),
            event.arena.allocator(),
            event.value,
            .{ .allocate = .alloc_always },
        );

        return RPCResponse(EthereumSubscribeResponse(T)).fromJson(event.arena, parsed);
    }

    /// Instanciates the read loop in a seperate thread.
    ///
    /// Will not work in single threaded mode.
    pub fn readLoopSeperateThread(self: *WebsocketProvider) !void {
        self.thread = try std.Thread.spawn(.{}, readLoopOwned, .{self});
    }

    /// ReadLoop used mainly to run in seperate threads.
    pub fn readLoopOwned(self: *WebsocketProvider) !void {
        return self.readLoop() catch |err| {
            provider_log.debug("Read loop reported error: {s}", .{@errorName(err)});
        };
    }

    /// Main read loop. This is a blocking operation.
    ///
    /// Best to call this in a seperate thread. Or use the event functions
    /// if you dont want to use threads.
    pub fn readLoop(self: *WebsocketProvider) !void {
        while (true) {
            const message = self.ws_client.readMessage() catch |err| {
                switch (err) {
                    error.EndOfStream,
                    => return err,
                    error.InvalidUtf8Payload => {
                        self.ws_client.close(1007);
                        return err;
                    },
                    else => {
                        self.ws_client.close(1002);
                        return err;
                    },
                }
            };

            switch (message.opcode) {
                .text,
                => {
                    const parsed = try std.json.parseFromSlice(Value, self.allocator, message.data, .{ .allocate = .alloc_always });
                    errdefer parsed.deinit();

                    if (parsed.value != .object) {
                        @branchHint(.unlikely);

                        provider_log.debug("Invalid message type. Expected `object` type. Exitting the loop", .{});
                        return error.InvalidMessageType;
                    }

                    // You need to check what type of event it is.
                    if (self.onEvent) |onEvent| {
                        onEvent(parsed) catch |err| {
                            provider_log.debug("Failed to process `onEvent` callback. Error found: {s}", .{@errorName(err)});
                            return error.UnexpectedError;
                        };
                    }

                    if (parsed.value.object.getKey("params") != null) {
                        self.sub_channel.put(parsed);
                        continue;
                    }

                    self.rpc_channel.push(parsed);
                },
                .ping => try self.ws_client.writeFrame(@constCast(message.data), .pong),
                // Ignore any other messages.
                .binary,
                .pong,
                .continuation,
                => continue,
                .connection_close => return self.ws_client.close(0),
                _ => return error.UnexpectedOpcode,
            }
        }
    }

    /// Write messages to the websocket server.
    pub fn writeSocketMessage(
        self: *WebsocketProvider,
        data: []u8,
    ) !void {
        return self.ws_client.writeFrame(data, .text);
    }

    /// Get the first event of the rpc channel.
    ///
    /// Only call this if you are sure that the channel has messages
    /// because this will block until a message is able to be fetched.
    pub fn getCurrentRpcEvent(self: *WebsocketProvider) JsonParsed(Value) {
        return self.rpc_channel.pop();
    }

    /// Get the first event of the subscription channel.
    ///
    /// Only call this if you are sure that the channel has messages
    /// because this will block until a message is able to be fetched.
    pub fn getCurrentSubscriptionEvent(self: *WebsocketProvider) JsonParsed(Value) {
        return self.sub_channel.get();
    }

    /// Writes message to websocket server and parses the reponse from it.
    /// This blocks until it gets the response back from the server.
    pub fn sendRpcRequest(self: *Provider, message: []u8) !JsonParsed(Value) {
        const provider: *WebsocketProvider = @alignCast(@fieldParentPtr("provider", self));

        var retries: u8 = 0;
        while (true) : (retries += 1) {
            if (retries > self.network_config.retries)
                return error.ReachedMaxRetryLimit;

            try provider.writeSocketMessage(message);

            const event = provider.getCurrentRpcEvent();

            if (event.value.object.get("error")) |val| {
                const code = val.object.get("code") orelse return error.InvalidErrorResponse;

                switch (code) {
                    .integer,
                    => |number| {
                        const error_enum = try std.meta.intToEnum(EthereumErrorCodes, number);

                        if (error_enum == .TooManyRequests) {
                            const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                            provider_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                            std.Thread.sleep(std.time.ns_per_ms * backoff);
                            continue;
                        }
                    },
                    .string,
                    .number_string,
                    => |number| {
                        const parsed = try std.fmt.parseInt(i64, number, 10);
                        const error_enum = try std.meta.intToEnum(EthereumErrorCodes, parsed);

                        if (error_enum == .TooManyRequests) {
                            const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                            provider_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                            std.Thread.sleep(std.time.ns_per_ms * backoff);
                            continue;
                        }
                    },

                    inline else => return error.InvalidErrorResponse,
                }
            }

            return event;
        }
    }
};

pub const HttpProvider = struct {
    /// Init options for defining the initial state of the http/s client.
    ///
    /// Consider using the network options defined [here](/api/clients/network#ethereum_mainnet) if you need a default network config.
    pub const InitOptions = struct {
        /// Allocator used to manage the memory arena.
        allocator: Allocator,
        /// The network config for the client to use.
        network_config: NetworkConfig,
    };

    /// Allocator used by this provider
    allocator: Allocator,
    /// The underlaying http client used to manage all the calls.
    client: HttpClient,
    /// The JSON RPC Provider interface.
    provider: Provider,

    /// Sets the clients initial state. This is the HTTP/S implementation of the JSON RPC client.
    ///
    /// Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.
    ///
    /// The client will handle request with 429 errors via exponential backoff
    /// but not the rest of the http error codes.
    pub fn init(opts: InitOptions) !HttpProvider {
        if (opts.network_config.endpoint != .uri)
            return error.InvalidEndpointConfig;

        return .{
            .client = http.Client{ .allocator = opts.allocator },
            .allocator = opts.allocator,
            .provider = .{
                .network_config = opts.network_config,
                .vtable = &.{
                    .sendRpcRequest = HttpProvider.sendRpcRequest,
                },
            },
        };
    }

    /// Clears all allocated memory and destroys any created pointers.
    pub fn deinit(self: *HttpProvider) void {
        std.debug.assert(self.provider.network_config.endpoint == .uri); // Invalid config.

        self.client.deinit();
    }

    /// Writes request to RPC server and parses the response according to the provided type.
    /// Handles 429 errors but not the rest.
    pub fn sendRpcRequest(
        self: *Provider,
        request: []const u8,
    ) !JsonParsed(Value) {
        const provider: *HttpProvider = @alignCast(@fieldParentPtr("provider", self));
        provider_log.debug("Preparing to send request body: {s}", .{request});

        var body: std.Io.Writer.Allocating = .init(provider.allocator);
        defer body.deinit();

        var retries: u8 = 0;
        while (true) : (retries += 1) {
            if (retries > self.network_config.retries)
                return error.ReachedMaxRetryLimit;

            const req = try provider.internalFetch(request, &body.writer);

            switch (req.status) {
                .ok => {
                    provider_log.debug("Got response from server: {s}", .{body.getWritten()});

                    return std.json.parseFromSlice(Value, provider.allocator, body.getWritten(), .{ .allocate = .alloc_always });
                },
                .too_many_requests => {
                    // Exponential backoff
                    const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                    provider_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                    // Clears any message that was written
                    body.shrinkRetainingCapacity(0);

                    std.Thread.sleep(std.time.ns_per_ms * backoff);
                    continue;
                },
                else => {
                    provider_log.debug("Unexpected server response. Server returned: {s} status", .{req.status.phrase() orelse @tagName(req.status)});
                    return error.UnexpectedServerResponse;
                },
            }
        }
    }

    /// Send http/s fetch to the providers endpoint.
    pub fn internalFetch(
        self: *HttpProvider,
        payload: []const u8,
        body: *std.Io.Writer,
    ) !FetchResult {
        const uri = self.provider.network_config.getNetworkUri() orelse return error.InvalidEndpointConfig;

        return self.client.fetch(.{
            .method = .POST,
            .payload = payload,
            .response_writer = body,
            .location = .{ .uri = uri },
            .headers = .{ .content_type = .{ .override = "application/json" } },
        });
    }
};

pub const IpcProvider = struct {
    pub const InitOptions = struct {
        /// Allocator to use to create the ChildProcess and other allocations
        allocator: Allocator,
        /// The chains config
        network_config: NetworkConfig,
        /// Callback function for when the connection is closed.
        onClose: ?*const fn () void = null,
        /// Callback function for everytime an event is parsed.
        onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null,
        /// Callback function for everytime an error is caught.
        onError: ?*const fn (args: []const u8) anyerror!void = null,
    };

    /// The allocator that will manage the connections memory
    allocator: Allocator,
    /// The IPC net stream to read and write requests.
    ipc_reader: IpcReader,
    thread: ?std.Thread,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void,
    /// Callback function that will run once a socket event is parsed
    onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void,
    /// Callback function that will run once a error is parsed.
    onError: ?*const fn (args: []const u8) anyerror!void,
    /// The chains config
    provider: Provider,
    /// Channel used to communicate between threads on subscription events.
    sub_channel: Channel(JsonParsed(Value)),
    /// Channel used to communicate between threads on rpc events.
    rpc_channel: Stack(JsonParsed(Value)),

    /// Populates the WebSocketHandler pointer.
    /// Starts the connection in a seperate process.
    pub fn init(opts: InitOptions) !IpcProvider {
        if (opts.network_config.endpoint != .path)
            return error.InvalidEndpointConfig;

        const path = opts.network_config.endpoint.path;

        const socket_stream = try std.net.connectUnixSocket(path);

        return .{
            .allocator = opts.allocator,
            .provider = .{
                .network_config = opts.network_config,
                .vtable = &.{
                    .sendRpcRequest = IpcProvider.sendRpcRequest,
                },
            },
            .ipc_reader = .{
                .buffer = zabi_utils.fifo.LinearFifo(u8, .Dynamic).init(opts.allocator),
                .stream = socket_stream,
                .overflow = 0,
            },
            .thread = null,
            .onClose = opts.onClose,
            .onError = opts.onError,
            .onEvent = opts.onEvent,
            .rpc_channel = Stack(JsonParsed(Value)).init(opts.allocator, null),
            .sub_channel = Channel(JsonParsed(Value)).init(opts.allocator),
        };
    }

    /// If you are using the subscription channel this operation can take time
    /// as it will need to cleanup each node.
    pub fn deinit(self: *IpcProvider) void {
        // There may be lingering memory from the json parsed data
        // in the channels so we must clean then up.
        while (self.sub_channel.getOrNull()) |node|
            node.deinit();

        while (self.rpc_channel.popOrNull()) |node|
            node.deinit();

        self.ipc_reader.deinit();
        self.sub_channel.deinit();
        self.rpc_channel.deinit();

        if (self.thread) |thread|
            thread.join();
    }

    /// Parses the `Value` in the sub-channel as a pending transaction hash event
    pub fn getPendingTransactionsSubEvent(self: *IpcProvider) !RPCResponse(EthereumSubscribeResponse(Hash)) {
        return self.parseSubscriptionEvent(Hash);
    }

    /// Parses the `Value` in the sub-channel as a log event
    pub fn getLogsSubEvent(self: *IpcProvider) !RPCResponse(EthereumSubscribeResponse(Log)) {
        return self.parseSubscriptionEvent(Log);
    }
    /// Parses the `Value` in the sub-channel as a new heads block event
    pub fn getNewHeadsBlockSubEvent(self: *IpcProvider) !RPCResponse(EthereumSubscribeResponse(Block)) {
        return self.parseSubscriptionEvent(Block);
    }

    /// Parses a subscription event `Value` into `T`.
    /// Usefull for events that currently zabi doesn't have custom support.
    pub fn parseSubscriptionEvent(self: *IpcProvider, comptime T: type) !RPCResponse(EthereumSubscribeResponse(T)) {
        const event = self.sub_channel.get();
        errdefer event.deinit();

        const parsed = try std.json.parseFromValueLeaky(
            EthereumSubscribeResponse(T),
            event.arena.allocator(),
            event.value,
            .{ .allocate = .alloc_always },
        );

        return RPCResponse(EthereumSubscribeResponse(T)).fromJson(event.arena, parsed);
    }

    /// Instanciates the read loop in a seperate thread.
    ///
    /// Will not work in single threaded mode.
    pub fn readLoopSeperateThread(self: *IpcProvider) !void {
        self.thread = try std.Thread.spawn(.{}, readLoopOwned, .{self});
    }

    /// ReadLoop used mainly to run in seperate threads.
    pub fn readLoopOwned(self: *IpcProvider) !void {
        return self.readLoop() catch |err| {
            provider_log.debug("Read loop reported error: {s}", .{@errorName(err)});
        };
    }

    /// Main read loop. This is a blocking operation.
    ///
    /// Best to call this in a seperate thread. Or use the event functions
    /// if you dont want to use threads.
    pub fn readLoop(self: *IpcProvider) !void {
        while (true) {
            const message = self.ipc_reader.readMessage() catch |err| switch (err) {
                error.EndOfStream,
                error.ConnectionResetByPeer,
                error.BrokenPipe,
                error.NotOpenForReading,
                => return error.Closed,
                else => return err,
            };

            if (message.len <= 1)
                continue;

            provider_log.debug("Got message: {s}", .{message});

            const parsed = std.json.parseFromSlice(Value, self.allocator, message, .{ .allocate = .alloc_always }) catch {
                if (self.onError) |onError|
                    onError(message) catch return error.UnexpectedError;

                return error.FailedToJsonParseResponse;
            };
            errdefer parsed.deinit();

            if (parsed.value != .object)
                return error.InvalidTypeMessage;

            // You need to check what type of event it is.
            if (self.onEvent) |onEvent|
                onEvent(parsed) catch return error.UnexpectedError;

            if (parsed.value.object.getKey("params") != null) {
                self.sub_channel.put(parsed);
                continue;
            }

            self.rpc_channel.push(parsed);
        }
    }

    /// Write messages to the websocket server.
    pub fn writeSocketMessage(
        self: *IpcProvider,
        data: []u8,
    ) !void {
        return self.ipc_reader.writeMessage(data);
    }

    /// Get the first event of the rpc channel.
    ///
    /// Only call this if you are sure that the channel has messages
    /// because this will block until a message is able to be fetched.
    pub fn getCurrentRpcEvent(self: *IpcProvider) JsonParsed(Value) {
        return self.rpc_channel.pop();
    }

    /// Get the first event of the subscription channel.
    ///
    /// Only call this if you are sure that the channel has messages
    /// because this will block until a message is able to be fetched.
    pub fn getCurrentSubscriptionEvent(self: *IpcProvider) JsonParsed(Value) {
        return self.sub_channel.get();
    }

    /// Writes message to websocket server and parses the reponse from it.
    /// This blocks until it gets the response back from the server.
    pub fn sendRpcRequest(self: *Provider, message: []u8) !JsonParsed(Value) {
        const provider: *IpcProvider = @alignCast(@fieldParentPtr("provider", self));

        var retries: u8 = 0;
        while (true) : (retries += 1) {
            if (retries > self.network_config.retries)
                return error.ReachedMaxRetryLimit;

            try provider.writeSocketMessage(message);

            const event = provider.getCurrentRpcEvent();

            if (event.value.object.get("error")) |val| {
                const code = val.object.get("code") orelse return error.InvalidErrorResponse;

                switch (code) {
                    .integer,
                    => |number| {
                        const error_enum = try std.meta.intToEnum(EthereumErrorCodes, number);

                        if (error_enum == .TooManyRequests) {
                            const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                            provider_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                            std.Thread.sleep(std.time.ns_per_ms * backoff);
                            continue;
                        }
                    },
                    .string,
                    .number_string,
                    => |number| {
                        const parsed = try std.fmt.parseInt(i64, number, 10);
                        const error_enum = try std.meta.intToEnum(EthereumErrorCodes, parsed);

                        if (error_enum == .TooManyRequests) {
                            const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                            provider_log.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                            std.Thread.sleep(std.time.ns_per_ms * backoff);
                            continue;
                        }
                    },

                    inline else => return error.InvalidErrorResponse,
                }
            }

            return event;
        }
    }
};
