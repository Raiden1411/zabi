/// Set of abi meta programming functions to convert
/// abi items into zig types.
pub const abi = @import("abi.zig");
/// The custom json parser/stringfy that enables the clients.
pub const json = @import("json.zig");
/// Custom meta functions that we use to facilitate development at the expense of
/// some compile time overhead.
pub const utils = @import("utils.zig");

test "Meta programming root" {
    _ = @import("abi.test.zig");
    _ = @import("json.test.zig");
    _ = @import("utils.test.zig");
}
