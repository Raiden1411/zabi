const std = @import("std");
const testing = std.testing;

const Explorer = @import("zabi").clients.BlockExplorer;
const QueryParameters = Explorer.QueryParameters;

test "All Ref Decls" {
    std.testing.refAllDecls(Explorer);
}
