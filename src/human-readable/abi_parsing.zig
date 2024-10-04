const abi = @import("../abi/abi.zig");
const param = @import("../abi/abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");

const Abi = abi.Abi;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = @import("../meta/utils.zig").Extract;
const ParamType = @import("../abi/param_type.zig").ParamType;
const StateMutability = @import("../abi/state_mutability.zig").StateMutability;
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
pub fn parseHumanReadable(alloc: Allocator, source: [:0]const u8) !AbiParsed(Abi) {
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

// fn innerParse(comptime T: type, parser: *Parser) Parser.ParseErrors!T {
//     return switch (T) {
//         abi.Abi => parser.parseAbiProto(),
//         abi.AbiItem => parser.parseAbiItemProto(),
//         abi.Function => parser.parseFunctionFnProto(),
//         abi.Event => parser.parseEventFnProto(),
//         abi.Error => parser.parseErrorFnProto(),
//         abi.Constructor => parser.parseConstructorFnProto(),
//         abi.Fallback => parser.parseFallbackFnProto(),
//         abi.Receive => parser.parseReceiveFnProto(),
//         []const param.AbiParameter => parser.parseFuncParamsDecl(),
//         []const param.AbiEventParameter => parser.parseEventParamsDecl(),
//         inline else => @compileError("Provided type '" ++ @typeName(T) ++ "' is not supported for human readable parsing"),
//     };
// }
