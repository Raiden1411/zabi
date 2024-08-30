test "EVM Interpreter root" {
    _ = @import("analysis.test.zig");
    _ = @import("interpreter.test.zig");
    _ = @import("bytecode.test.zig");
    _ = @import("memory.test.zig");

    // Per instructions tests.
    _ = @import("../../evm/instructions/root.zig");
}
