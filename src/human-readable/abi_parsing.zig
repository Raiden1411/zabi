const abi = @import("../abi.zig");
const param = @import("../abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = @import("../types.zig").Extract;
const ParamType = @import("../param_type.zig").ParamType;
const StateMutability = @import("../state_mutability.zig").StateMutability;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig");

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
    var abi_parsed = AbiParsed(T){ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(abi_parsed.arena);

    abi_parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_parsed.arena.deinit();

    const allocator = abi_parsed.arena.allocator();

    var lex = Lexer.init(source);
    var list = Parser.TokenList{};
    errdefer list.deinit(allocator);

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
    };

    abi_parsed.value = try innerParse(T, &parser);

    return abi_parsed;
}

fn innerParse(comptime T: type, parser: *Parser) !T {
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
        inline else => @compileError("Provided type is not supported for human readable parsing"),
    };
}

test "Simple" {
    const slice =
        \\ function Foo((((((address bar))))))
        \\ event Bar((((((bool baz))))))
    ;

    const params = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer params.deinit();
}
