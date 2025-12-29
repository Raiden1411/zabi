const std = @import("std");
const testing = std.testing;

const Explorer = @import("zabi").clients.BlockExplorer;
const QueryParameters = Explorer.QueryParameters;

test "All Ref Decls" {
    // TODO: Readd this once arm64 llvm bugs have been fixed
    if (@import("builtin").cpu.arch.isAARCH64())
        return error.SkipZigTest;

    std.testing.refAllDecls(Explorer);
}
