const enviroment = @import("enviroment.zig");
const gas = @import("gas_tracker.zig");
const std = @import("std");
const types = @import("zabi-types").ethereum;

const Address = types.Address;
const GasTracker = gas.GasTracker;
const InterpreterStatus = @import("Interpreter.zig").InterpreterStatus;
const TxEnviroment = enviroment.TxEnviroment;

/// Inputs for a call action.
pub const CallAction = struct {
    /// The calldata of this action.
    inputs: []u8,
    /// The return memory offset where the output of this call
    /// gets written to.
    return_memory_offset: struct { u64, u64 },
    /// The gas limit of this call.
    gas_limit: u64,
    /// The account address of bytecode that is going to be executed.
    bytecode_address: Address,
    /// Target address. This account's storage will get modified.
    target_address: Address,
    /// The address that is invoking this call.
    caller: Address,
    /// The call value. Depeding on the scheme value might not get transfered.
    value: CallValue,
    /// The call scheme.
    scheme: CallScheme,
    /// Whether this call is static or initialized inside a static call.
    is_static: bool,

    /// Creates an instance for this action.
    pub fn init(tx_env: TxEnviroment, gas_limit: u64) ?CallAction {
        const target = switch (tx_env.transact_to) {
            .call => |address| address,
            .create => return null,
        };

        return .{
            .inputs = tx_env.data,
            .gas_limit = gas_limit,
            .target_address = target,
            .bytecode_address = target,
            .caller = tx_env.caller,
            .value = .{ .transfer = tx_env.value },
            .scheme = .call,
            .is_static = false,
            .return_memory_offset = .{ 0, 0 },
        };
    }
};

/// Evm call value types.
pub const CallValue = union(enum) {
    /// The concrete value that will get transfered from the caller to the callee.
    transfer: u256,
    /// The transfer value that lives in limbo where the value gets set but
    /// it will **never** get transfered.
    limbo: u256,

    /// Gets the current value independent of the active union member.
    pub fn getCurrentValue(self: CallValue) u256 {
        return switch (self) {
            inline else => |value| value,
        };
    }
};

/// EVM Call scheme.
pub const CallScheme = enum {
    call,
    callcode,
    delegate,
    static,
};

/// Inputs for a create call.
pub const CreateAction = struct {
    /// Caller address of the EVM.
    caller: Address,
    /// The schema used for the create action
    scheme: CreateScheme,
    /// Value to transfer
    value: u256,
    /// The contract's init code.
    init_code: []u8,
    /// The gas limit of this call.
    gas_limit: u64,

    /// Creates an instance for this action.
    pub fn init(tx_env: TxEnviroment, gas_limit: u64) ?CallAction {
        switch (tx_env.transact_to) {
            .call => {},
            .create => return null,
        }

        return .{
            .caller = tx_env.caller,
            .gas_limit = gas_limit,
            .init_code = tx_env.data,
            .scheme = .create,
            .value = tx_env.value,
        };
    }
};

/// EVM Create scheme.
pub const CreateScheme = union(enum) {
    create,
    create2: u256,
};

/// The result of the interpreter operation
pub const ReturnAction = struct {
    /// The result of the instruction execution.
    result: InterpreterStatus,
    /// The return output slice.
    output: []u8,
    /// The tracker with gas usage.
    gas: GasTracker,
};
