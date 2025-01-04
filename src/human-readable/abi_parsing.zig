const abi = zabi_abi.abitypes;
const param = zabi_abi.abi_parameter;
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");
const zabi_abi = @import("zabi-abi");
const zabi_meta = @import("zabi-meta");

const Abi = abi.Abi;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = zabi_meta.utils.Extract;
const ParamType = zabi_abi.param_type.ParamType;
const StateMutability = zabi_abi.state_mutability.StateMutability;
const HumanAbi = @import("HumanAbi.zig");

pub fn AbiParsed(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

/// Main function to use when wanting to use the human readable parser
/// This function will allocate and use and ArenaAllocator for its allocations
/// Caller owns the memory and must free the memory.
/// Use the handy `deinit()` method provided by the return type
///
/// The return value will depend on the abi type selected.
/// The function will return an error if the provided type doesn't match the
/// tokens from the provided signature
pub fn parseHumanReadable(
    alloc: Allocator,
    source: [:0]const u8,
) HumanAbi.Errors!AbiParsed(Abi) {
    std.debug.assert(source.len > 0);

    var abi_parsed = AbiParsed(Abi){
        .arena = try alloc.create(ArenaAllocator),
        .value = undefined,
    };
    errdefer alloc.destroy(abi_parsed.arena);

    abi_parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_parsed.arena.deinit();

    const allocator = abi_parsed.arena.allocator();

    abi_parsed.value = try HumanAbi.parse(allocator, source);

    return abi_parsed;
}
