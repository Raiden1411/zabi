/// Set of abi types converted to zig.
pub const abitypes = @import("abi.zig");
/// Abi parameters represented in zig.
pub const abi_parameter = @import("abi_parameter.zig");
/// Custom support for EIP712.
pub const eip712 = @import("eip712.zig");
/// Solidity types to zig types.
pub const param_type = @import("param_type.zig");
/// Function state mutability
pub const state_mutability = @import("state_mutability.zig");

test "Abi Root" {
    _ = @import("abi_parameter.test.zig");
    _ = @import("abi.test.zig");
    _ = @import("eip712.test.zig");
    _ = @import("param_type.test.zig");
    _ = @import("state_mutability.zig");
}
