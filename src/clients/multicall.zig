const abi = @import("../abi/abi.zig");
const meta_abi = @import("../meta/abi.zig");
const std = @import("std");
const types = @import("../types/ethereum.zig");

const AbiParametersToPrimative = meta_abi.AbiParametersToPrimative;
const Address = types.Address;
const Function = abi.Function;
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
