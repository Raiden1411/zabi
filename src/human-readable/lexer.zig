const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const Token = @import("tokens.zig").Tag;
const Syntax = Token.SoliditySyntax;

/// Custom Solidity Lexer that is used to generate tokens based
/// on the provided solidity signature. This is not a fully
/// solidity compatable Lexer.
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

    pub fn tokenSlice(self: *Lexer, start: usize, end: usize) []const u8 {
        return self.currentText[start..end];
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
