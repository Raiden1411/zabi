
const abi = @import("../abi.zig");
const abiParameter = @import("../abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = @import("../types.zig").Extract;
const ParamType = @import("../param_type.zig").ParamType;
const StateMutability = @import("../state_mutability.zig").StateMutability;
const Lexer = @import("lexer.zig").Lexer;

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

pub fn parseHumanReadable(comptime T: type, alloc: Allocator, source: [:0]const u8) !AbiParsed(T) {
    var iter = Lexer.init(source);

    return parseHumanReadableFromTokenSource(T, alloc, &iter);
}

pub fn parseHumanReadableFromTokenSource(comptime T: type, alloc: Allocator, iterator: *Lexer) !AbiParsed(T) {
    var abi_parsed = AbiParsed(T){ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(abi_parsed.arena);
    abi_parsed.arena.* = ArenaAllocator.init(alloc);

    abi_parsed.value = try innerParse(T, alloc, iterator);

    return abi_parsed;
}

pub fn innerParse(comptime T: type, alloc: Allocator, iterator: *Lexer) !T {
    _ = iterator;
    _ = alloc;
    switch (T) {
        inline else => @compileError("Not implemented"),
    }
}
