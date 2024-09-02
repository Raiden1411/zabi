const abitypes = @import("../abi/abi.zig");
const decoder = @import("../decoding/decoder.zig");
const encoder = @import("../encoding/encoder.zig");
const meta_abi = @import("../meta/abi.zig");
const std = @import("std");
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

const AbiDecoded = decoder.AbiDecoded;
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
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(Arguments) > 0) @alignOf(Arguments) else 0,
        };
    }
    return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
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

/// Wrapper around a rpc_client that exposes the multicall3 functions.
pub fn Multicall(comptime client: Clients) type {
    return struct {
        const Client = switch (client) {
            .http => PubClient,
            .websocket => WebSocketClient,
            .ipc => IpcClient,
        };

        const Self = @This();

        /// Set of possible errors when running the multicall client.
        pub const Error = Client.BasicRequestErrors || encoder.EncodeErrors || decoder.DecoderErrors;

        /// The underlaying rpc client used by this.
        rpc_client: *Client,

        /// Creates the initial state for the contract
        pub fn init(rpc_client: *Client) !Self {
            return .{
                .rpc_client = rpc_client,
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
        ) Self.Error!AbiDecoded([]const Result) {
            comptime std.debug.assert(targets.len == function_arguments.len);

            var abi_list = std.ArrayList(Call3).init(self.rpc_client.allocator);
            errdefer abi_list.deinit();

            inline for (targets, function_arguments) |target, argument| {
                const encoded = try encoder.encodeAbiFunctionComptime(self.rpc_client.allocator, target.function, argument);

                const call3: Call3 = .{
                    .target = target.target_address,
                    .callData = encoded,
                    .allowFailure = allow_failure,
                };

                try abi_list.append(call3);
            }

            // We don't free the memory here because we wrap it on a arena.
            const slice = try abi_list.toOwnedSlice();
            defer {
                for (slice) |s| self.rpc_client.allocator.free(s.callData);
                self.rpc_client.allocator.free(slice);
            }

            const encoded = try encoder.encodeAbiFunctionComptime(self.rpc_client.allocator, aggregate3_abi, .{@ptrCast(slice)});
            defer self.rpc_client.allocator.free(encoded);

            const data = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.rpc_client.network_config.multicall_contract,
                .data = encoded,
            } }, .{});
            defer data.deinit();

            return decoder.decodeAbiParameter(
                []const Result,
                self.rpc_client.allocator,
                data.response,
                .{ .allocate_when = .alloc_always },
            );
        }
    };
}
