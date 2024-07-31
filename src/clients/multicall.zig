const abitypes = @import("../abi/abi.zig");
const meta_abi = @import("../meta/abi.zig");
const std = @import("std");
const types = @import("../types/ethereum.zig");

const AbiParametersToPrimative = meta_abi.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const Address = types.Address;
const Function = abitypes.Function;
const Hex = types.Hex;

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

pub const abi: Function = .{
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

pub const contract = @import("../utils/utils.zig").addressToBytes("0xcA11bde05977b3631167028862bE2a173976CA11") catch unreachable;
