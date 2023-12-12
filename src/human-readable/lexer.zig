const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const Token = @import("tokens.zig").Tag;
const Syntax = Token.SoliditySyntax;

pub const Lexer = struct {
    position: u32,
    currentText: [:0]const u8,

    const State = enum {
        start,
        identifier,
        number,
    };

    const TokenList = std.MultiArrayList(struct {
        token_type: Syntax,
        start: u32,
        end: u32,
    });

    pub fn init(text: [:0]const u8) Lexer {
        return .{ .currentText = text, .position = 0 };
    }

    pub fn reset(self: *Lexer, newText: []const u8, pos: ?u32) void {
        self.currentText = newText;
        self.position = pos orelse 0;
    }

    pub fn scan(self: *Lexer) Token {
        var result = Token{ .syntax = .EndOfFileToken, .location = .{
            .start = self.position,
            .end = undefined,
        } };

        var state: State = .start;

        while (true) : (self.position += 1) {
            const char = self.currentText[self.position];

            switch (state) {
                .start => switch (char) {
                    0 => {
                        if (self.position != self.currentText.len) {
                            result.syntax = .UnknowToken;
                            result.location.start = self.position;
                            self.position += 1;
                            result.location.end = self.position;

                            return result;
                        }

                        break;
                    },
                    ' ', '\t', '\r', '\n' => {
                        result.location.start += 1;
                    },
                    ';' => {
                        result.syntax = .SemiColon;
                        self.position += 1;
                        break;
                    },
                    ',' => {
                        result.syntax = .Comma;
                        self.position += 1;
                        break;
                    },
                    '(' => {
                        result.syntax = .OpenParen;
                        self.position += 1;
                        break;
                    },
                    ')' => {
                        result.syntax = .ClosingParen;
                        self.position += 1;
                        break;
                    },
                    '{' => {
                        result.syntax = .OpenBrace;
                        self.position += 1;
                        break;
                    },
                    '}' => {
                        result.syntax = .ClosingBrace;
                        self.position += 1;
                        break;
                    },
                    '[' => {
                        result.syntax = .OpenBracket;
                        self.position += 1;
                        break;
                    },
                    ']' => {
                        result.syntax = .ClosingBracket;
                        self.position += 1;
                        break;
                    },
                    'a'...'z', 'A'...'Z', '_', '$' => {
                        state = .identifier;
                        result.syntax = .Identifier;
                    },
                    '0'...'9' => {
                        state = .number;
                        result.syntax = .Number;
                    },
                    else => {
                        result.syntax = .UnknowToken;
                        result.location.end = self.position;

                        self.position += 1;

                        return result;
                    },
                },

                .identifier => switch (char) {
                    'a'...'z', 'A'...'Z', '_', '$', '0'...'9' => {},
                    else => {
                        if (Token.keywords(self.currentText[result.location.start..self.position])) |syntax| {
                            result.syntax = syntax;
                        }

                        if (Token.typesKeyword(self.currentText[result.location.start..self.position])) |syntax| {
                            result.syntax = syntax;
                        }

                        break;
                    },
                },

                .number => switch (char) {
                    '0'...'9' => {},
                    else => break,
                },
            }
        }

        if (result.syntax == .EndOfFileToken) {
            result.location.start = self.position;
        }

        result.location.end = self.position;

        return result;
    }
};

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
