const abi = @import("../abi/abi.zig");
const param = @import("../abi/abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = @import("../meta/utils.zig").Extract;
const ParamType = @import("../abi/param_type.zig").ParamType;
const StateMutability = @import("../abi/state_mutability.zig").StateMutability;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("Parser.zig");

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
pub fn parseHumanReadable(comptime T: type, alloc: Allocator, source: [:0]const u8) Parser.ParseErrors!AbiParsed(T) {
    std.debug.assert(source.len > 0);

    var abi_parsed = AbiParsed(T){ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(abi_parsed.arena);

    abi_parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_parsed.arena.deinit();

    const allocator = abi_parsed.arena.allocator();

    var lex = Lexer.init(source);

    var list = Parser.TokenList{};
    defer list.deinit(allocator);

    while (true) {
        const tok = lex.scan();
        try list.append(allocator, .{ .token_type = tok.syntax, .start = tok.location.start, .end = tok.location.end });

        if (tok.syntax == .EndOfFileToken) break;
    }

    var parser: Parser = .{
        .alloc = allocator,
        .tokens = list.items(.token_type),
        .tokens_start = list.items(.start),
        .tokens_end = list.items(.end),
        .token_index = 0,
        .source = source,
        .structs = .{},
    };

    abi_parsed.value = try innerParse(T, &parser);

    return abi_parsed;
}

fn innerParse(comptime T: type, parser: *Parser) Parser.ParseErrors!T {
    return switch (T) {
        abi.Abi => parser.parseAbiProto(),
        abi.AbiItem => parser.parseAbiItemProto(),
        abi.Function => parser.parseFunctionFnProto(),
        abi.Event => parser.parseEventFnProto(),
        abi.Error => parser.parseErrorFnProto(),
        abi.Constructor => parser.parseConstructorFnProto(),
        abi.Fallback => parser.parseFallbackFnProto(),
        abi.Receive => parser.parseReceiveFnProto(),
        []const param.AbiParameter => parser.parseFuncParamsDecl(),
        []const param.AbiEventParameter => parser.parseEventParamsDecl(),
        inline else => @compileError("Provided type '" ++ @typeName(T) ++ "' is not supported for human readable parsing"),
    };
}
