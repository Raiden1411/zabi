const std = @import("std");
const testing = std.testing;

const Lexer = @import("zabi-human").Lexer;
const Syntax = @import("zabi-human").tokens.Tag.SoliditySyntax;

test "It can tokenize" {
    var lex = Lexer.init("function");

    const token = lex.scan();

    try testing.expect(token.syntax == .Function);
    try testing.expect(token.location.start == 0);
    try testing.expect(token.location.end == 8);
}

test "Tokenize parameter" {
    try testTokenizer("address", &.{.Address});
    try testTokenizer("address owner", &.{ .Address, .Identifier });
    try testTokenizer("address[] calldata owner", &.{ .Address, .OpenBracket, .ClosingBracket, .Calldata, .Identifier });
    try testTokenizer("address indexed owner", &.{ .Address, .Indexed, .Identifier });
}

test "Tokenize parameters" {
    try testTokenizer("address, address", &.{ .Address, .Comma, .Address });
    try testTokenizer("address owner, address foo", &.{ .Address, .Identifier, .Comma, .Address, .Identifier });
    try testTokenizer("((address))", &.{ .OpenParen, .OpenParen, .Address, .ClosingParen, .ClosingParen });
}

test "Function signature" {
    try testTokenizer("function foo()", &.{ .Function, .Identifier, .OpenParen, .ClosingParen });
    try testTokenizer("function foo(address owner)", &.{ .Function, .Identifier, .OpenParen, .Address, .Identifier, .ClosingParen });
    try testTokenizer("function foo(address) external", &.{ .Function, .Identifier, .OpenParen, .Address, .ClosingParen, .External });
    try testTokenizer("function foo() external view", &.{ .Function, .Identifier, .OpenParen, .ClosingParen, .External, .View });
    try testTokenizer("function foo(bool) external pure returns(string memory)", &.{ .Function, .Identifier, .OpenParen, .Bool, .ClosingParen, .External, .Pure, .Returns, .OpenParen, .String, .Memory, .ClosingParen });
}

test "Other signatures" {
    try testTokenizer("event Foo(address indexed bar)", &.{ .Event, .Identifier, .OpenParen, .Address, .Indexed, .Identifier, .ClosingParen });
    try testTokenizer("error Foo(address bar)", &.{ .Error, .Identifier, .OpenParen, .Address, .Identifier, .ClosingParen });
    try testTokenizer("struct Foo{address bar;}", &.{ .Struct, .Identifier, .OpenBrace, .Address, .Identifier, .SemiColon, .ClosingBrace });
    try testTokenizer("constructor(string memory bar)", &.{ .Constructor, .OpenParen, .String, .Memory, .Identifier, .ClosingParen });
    try testTokenizer("receive() external payable", &.{ .Receive, .OpenParen, .ClosingParen, .External, .Payable });
    try testTokenizer("fallback() external", &.{ .Fallback, .OpenParen, .ClosingParen, .External });
}

fn testTokenizer(source: [:0]const u8, tokens: []const Syntax) !void {
    var lexer = Lexer.init(source);

    for (tokens) |token| {
        const tok = lexer.scan();
        try testing.expectEqual(tok.syntax, token);
    }

    const lastToken = lexer.scan();

    try testing.expectEqual(source.len, lastToken.location.start);
    try testing.expectEqual(source.len, lastToken.location.end);
    try testing.expectEqual(lastToken.syntax, .EndOfFileToken);
}
