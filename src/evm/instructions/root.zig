/// Arithmetic interpreter instructions
pub const arithmetic = @import("arithmetic.zig");
/// Bitwise interpreter instructions
pub const bitwise = @import("bitwise.zig");
/// Contract interpreter instructions
pub const contract = @import("contract.zig");
/// Control interpreter instructions
pub const control = @import("control.zig");
/// Enviroment host interpreter instructions
pub const enviroment = @import("enviroment.zig");
/// Host interpreter instructions
pub const host = @import("host.zig");
/// Memory interpreter instructions
pub const memory = @import("memory.zig");
/// Stack interpreter instructions
pub const stack = @import("stack.zig");
/// System interpreter instructions
pub const system = @import("system.zig");

test {
    _ = @import("arithmetic.zig");
    _ = @import("bitwise.zig");
    _ = @import("contract.zig");
    _ = @import("control.zig");
    _ = @import("enviroment.zig");
    _ = @import("host.zig");
    _ = @import("memory.zig");
    _ = @import("stack.zig");
    _ = @import("system.zig");
}
