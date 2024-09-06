const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");

comptime {
    if (!builtin.target.isWasm()) {
        @compileError("wasm.zig should only be analyzed for wasm32 builds");
    }
}

/// True if we're in shared memory mode. If true, then the memory buffer
/// in JS will be backed by a SharedArrayBuffer and some behaviors change.
pub const shared_mem = options.wasm_shared;

/// The allocator to use in wasm environments.
pub const allocator = if (builtin.is_test)
    std.testing.allocator
else
    std.heap.wasm_allocator;

var allocs: std.AutoHashMapUnmanaged([*]u8, usize) = .{};

/// Allocate len bytes and return a pointer to the memory in the host.
/// The data is not zeroed.
pub export fn malloc(len: usize) ?[*]u8 {
    return allocate(len) catch return null;
}

fn allocate(len: usize) ![*]u8 {
    // Create the allocation
    const slice = try allocator.alloc(u8, len);
    errdefer allocator.free(slice);

    // Store the size so we can deallocate later
    try allocs.putNoClobber(allocator, slice.ptr, slice.len);
    errdefer _ = allocs.remove(slice.ptr);

    return slice.ptr;
}

/// Free an allocation from malloc.
pub export fn free(ptr: ?[*]u8) void {
    if (ptr) |v| {
        if (allocs.get(v)) |len| {
            const slice = v[0..len];
            allocator.free(slice);
            _ = allocs.remove(v);
        }
    }
}
/// Send message over to JS land and traps in wasm.
pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = stack_trace;
    _ = addr;

    std.log.err("Paniced: {s}", .{message});
    @trap();
}
/// Handly type function to return slices with ptr and len.
pub fn Slice(comptime T: type) type {
    return packed struct(u64) {
        ptr: u32,
        len: u32,

        pub fn init(slice: []const T) Slice(T) {
            return .{
                .ptr = @intFromPtr(slice.ptr),
                .len = slice.len,
            };
        }
    };
}
/// JS String representation in wasm.
/// On JS side you will need to unwrap the values.
pub const String = Slice(u8);
