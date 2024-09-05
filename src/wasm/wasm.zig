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
///
/// The return values of this should NOT be sent to the host environment
/// unless toHostOwned is called on them. In this case, the caller is expected
/// to call free. If a pointer is NOT host-owned, then the wasm module is
/// expected to call the normal alloc.free/destroy functions.
pub const allocator = if (builtin.is_test)
    std.testing.allocator
else
    std.heap.wasm_allocator;

/// For host-owned allocations:
/// We need to keep track of our own pointer lengths because Zig
/// allocators usually don't do this and we need to be able to send
/// a direct pointer back to the host system. A more appropriate thing
/// to do would be to probably make a custom allocator that keeps track
/// of size.
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
