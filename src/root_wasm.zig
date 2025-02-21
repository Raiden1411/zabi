// This is the main file for the WASM module. The WASM module has to
// export a C ABI compatible API.
const std = @import("std");
const builtin = @import("builtin");

comptime {
    _ = @import("wasm/wasm.zig");
    _ = @import("wasm/evm.zig");
    _ = @import("wasm/utils.zig");
    _ = @import("wasm/formatter.zig");
}

/// So that we can log from zig to js.
pub const std_options: std.Options = .{
    .logFn = @import("wasm/log.zig").log,
};
