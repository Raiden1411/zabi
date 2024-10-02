const tokenizer = @import("../../human-readable/lexer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../human-readable/ParserNew.zig");
const Ast = @import("../../human-readable/Ast.zig");

test "Pragma" {
    var tokens: Ast.TokenList = .empty;
    defer tokens.deinit(testing.allocator);

    var parser: Parser = undefined;
    defer parser.deinit();

    try buildParser("function Bar(address bar, uint bar) view external pure returns(address bar)", &tokens, &parser);

    _ = try parser.parseUnit();

    std.debug.print("FOOOOO: {any}\n", .{parser.nodes.items(.tag)});
}

fn buildParser(source: [:0]const u8, tokens: *Ast.TokenList, parser: *Parser) !void {
    var lexer = tokenizer.Lexer.init(source);

    while (true) {
        const token = lexer.scan();

        try tokens.append(testing.allocator, token.syntax);

        if (token.syntax == .EndOfFileToken) break;
    }

    parser.* = .{
        .source = source,
        .allocator = testing.allocator,
        .token_index = 0,
        .token_tags = tokens.items,
        .nodes = .{},
        .scratch = .empty,
        .extra = .empty,
    };

    try parser.nodes.append(testing.allocator, .{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });
}
