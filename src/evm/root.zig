/// Set of EVM actions for contract instructions.
const actions = @import("actions.zig");
/// Set of function to analyse bytecode and create the jump table.
const analysis = @import("analysis.zig");
/// A set of possible bytecode states used by the interpreter.
const bytecode = @import("bytecode.zig");
/// A representation of a EVM contract.
const contract = @import("contract.zig");
/// The EVM enviroment.
const enviroment = @import("enviroment.zig");
/// A gas tracker and  gas calculation functions and constants.
const gas = @import("gas_tracker.zig");
/// The host interface that `Host` implementation must have.
const host = @import("host.zig");
/// Set of interpreter instructions.
const instructions = @import("instructions/root.zig");
/// A expandable memory buffer. Word size is 32.
const memory = @import("memory.zig");
/// Enum of the EVM opcodes and the instruction table.
const opcode = @import("opcodes.zig");
/// The EVM specifications by hardfork.
const specification = @import("specification.zig");

const Interpreter = @import("Interpreter.zig");

test {
    _ = @import("Interpreter.zig");
    _ = @import("analysis.zig");
    _ = @import("bytecode.zig");
    _ = @import("instructions/root.zig");
    _ = @import("memory.zig");
}
