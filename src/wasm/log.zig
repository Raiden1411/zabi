const std = @import("std");
const wasm = @import("wasm.zig");

// Avoids collision with zig's namespace `log`
pub const JS = struct {
    extern "env" fn log(ptr: [*]const u8, len: usize) void;
    extern "env" fn panic(ptr: [*]const u8, len: usize) noreturn;
};

// The function std.log will call.
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    var buf: [2048]u8 = undefined;

    // Build the string
    const level_txt = comptime level.asText();
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const txt = level_txt ++ prefix ++ format;

    var allocated: bool = false;
    const str = nosuspend std.fmt.bufPrint(&buf, txt, args) catch str: {
        allocated = true;
        break :str std.fmt.allocPrint(wasm.allocator, txt, args) catch return;
    };
    defer if (allocated) wasm.allocator.free(str);

    // Send it over to the JS side
    JS.log(str.ptr, str.len);
}

/// Send message over to JS land and traps in wasm.
pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = stack_trace;
    _ = addr;

    JS.panic(message.ptr, message.len);
}
