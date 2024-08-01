const abitypes = @import("../abi/abi.zig");
const decoder = @import("../decoding/decoder.zig");
const encoder = @import("../encoding/encoder.zig");
const meta_abi = @import("../meta/abi.zig");
const std = @import("std");
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

const AbiParametersToPrimative = meta_abi.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const Address = types.Address;
const Chains = types.PublicChains;
const Clients = @import("wallet.zig").WalletClients;
const Function = abitypes.Function;
const Hex = types.Hex;
const IpcClient = @import("IPC.zig");
const PubClient = @import("Client.zig");
const RpcResponse = types.RPCResponse;
const WebSocketClient = @import("WebSocket.zig");

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

pub const Result = struct {
    /// Weather the call was successfull or not.
    success: bool,
    /// The return data from the function call.
    returnData: Hex,

    pub fn deinit(self: Result, allocator: Allocator) void {
        allocator.free(self.returnData);
    }
};

pub const MulticallTargets = struct {
    function: Function,
    target_address: Address,
};

pub fn MulticallArguments(comptime targets: []const MulticallTargets) type {
    if (targets.len == 0) return void;
    var fields: [targets.len]std.builtin.Type.StructField = undefined;

    for (targets, 0..) |target, i| {
        const Arguments = AbiParametersToPrimative(target.function.inputs);

        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = Arguments,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(Arguments) > 0) @alignOf(Arguments) else 0,
        };
    }
    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}

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

const multicall_contract_map = std.StaticStringMap(MulticallContract).initComptime(.{
    .{ "ethereum", .ethereum },
});

pub const MulticallContract = enum(u160) {
    ethereum = @bitCast(utils.addressToBytes("0xcA11bde05977b3631167028862bE2a173976CA11") catch unreachable),
    // goerli = 5,
    // op_mainnet = 10,
    // cronos = 25,
    // bnb = 56,
    // ethereum_classic = 61,
    // op_kovan = 69,
    // gnosis = 100,
    // polygon = 137,
    // fantom = 250,
    // boba = 288,
    // op_goerli = 420,
    // base = 8543,
    // anvil = 31337,
    // arbitrum = 42161,
    // arbitrum_nova = 42170,
    // celo = 42220,
    // avalanche = 43114,
    // zora = 7777777,
    // sepolia = 11155111,
    // op_sepolia = 11155420,
};

/// Wrapper around a rpc_client that exposes the multicall3 functions.
pub fn Multicall(comptime client: Clients) type {
    return struct {
        const Client = switch (client) {
            .http => PubClient,
            .websocket => WebSocketClient,
            .ipc => IpcClient,
        };

        const Self = @This();

        /// The underlaying rpc client used by this.
        rpc_client: *Client,
        /// The multicall contract address based on the client chain.
        multicall_contract: Address,

        /// Creates the initial state for the contract
        pub fn init(rpc_client: *Client) !Self {
            const chain = try std.meta.intToEnum(Chains, rpc_client.chain_id);
            const multicall_address: Address = @bitCast(@intFromEnum(multicall_contract_map.get(@tagName(chain)) orelse return error.InvalidChain));

            return .{
                .rpc_client = rpc_client,
                .multicall_contract = multicall_address,
            };
        }
        /// Runs the selected multicall3 contracts.
        /// This enables to read from multiple contract by a single `eth_call`.
        /// Uses the contracts created [here](https://www.multicall3.com/)
        ///
        /// To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)
        pub fn multicall3(
            self: *Self,
            comptime targets: []const MulticallTargets,
            function_arguments: MulticallArguments(targets),
            allow_failure: bool,
        ) !RpcResponse([]const Result) {
            comptime std.debug.assert(targets.len == function_arguments.len);

            const arena = try self.rpc_client.allocator.create(std.heap.ArenaAllocator);
            errdefer self.rpc_client.allocator.destroy(arena);

            arena.* = std.heap.ArenaAllocator.init(self.rpc_client.allocator);

            var abi_list = std.ArrayList(Call3).init(arena.allocator());
            errdefer abi_list.deinit();

            inline for (targets, function_arguments) |target, argument| {
                const encoded = try encoder.encodeAbiFunctionComptime(arena.allocator(), target.function, argument);
                errdefer arena.deinit();

                const call3: Call3 = .{
                    .target = target.target_address,
                    .callData = encoded,
                    .allowFailure = allow_failure,
                };

                try abi_list.append(call3);
            }

            // We don't free the memory here because we wrap it on a arena.
            const slice = try abi_list.toOwnedSlice();
            const encoded = try encoder.encodeAbiFunctionComptime(arena.allocator(), aggregate3_abi, .{@ptrCast(slice)});

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.multicall_contract,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            const decoded = try decoder.decodeAbiParametersRuntime(
                arena.allocator(),
                struct { []const Result },
                aggregate3_abi.outputs,
                data.response,
                .{ .allocate_when = .alloc_always },
            );

            return .{ .arena = arena, .response = decoded[0] };
        }
    };
}
