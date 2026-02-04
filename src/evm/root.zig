/// Set of EVM actions for contract instructions.
pub const actions = @import("actions.zig");
/// Set of function to analyse bytecode and create the jump table.
pub const analysis = @import("analysis.zig");
/// A set of possible bytecode states used by the interpreter.
pub const bytecode = @import("bytecode.zig");
/// A representation of a EVM contract.
pub const contract = @import("contract.zig");
/// EVM inner database.
pub const database = @import("database.zig");
/// The EVM enviroment.
pub const enviroment = @import("enviroment.zig");
/// A gas tracker and  gas calculation functions and constants.
pub const gas = @import("gas_tracker.zig");
/// The host interface that `Host` implementation must have.
/// Contains a implementation of a journaled state host.
pub const host = @import("host.zig");
/// Set of interpreter instructions.
pub const instructions = @import("instructions/root.zig");
/// EVM journaled state data structure.
pub const journal = @import("journal.zig");
/// A expandable memory buffer. Word size is 32.
pub const memory = @import("memory.zig");
/// Enum of the EVM opcodes and the instruction table.
pub const opcode = @import("opcodes.zig");
/// The EVM specifications by hardfork.
pub const specification = @import("specification.zig");

/// The EVM driver/orchestrator.
pub const EVM = @import("Evm.zig");

/// The EVM interpreter implementation.
pub const Interpreter = @import("Interpreter.zig");
