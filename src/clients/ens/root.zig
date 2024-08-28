/// Set of abi items for interacting with the ENS contracts.
pub const abi = @import("abi_ens.zig");
/// Set of utils to interact with the ENS contracts.
pub const utils = @import("ens_utils.zig");
/// A public client to interact with ENS contracts.
pub const client = @import("ens.zig");

test "Ens Root" {
    _ = @import("ens_utils.test.zig");
    _ = @import("ens.test.zig");
}
