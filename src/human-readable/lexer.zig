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
        invalid,
    };

    const TokenList = std.MultiArrayList(struct {
        token_type: Syntax,
        start: u32,
        end: u32,
    });

    pub fn init(text: [:0]const u8) Lexer {
        return .{
            .currentText = text,
            .position = 0,
        };
    }

    pub fn reset(
        self: *Lexer,
        newText: []const u8,
        pos: ?u32,
    ) void {
        self.currentText = newText;
        self.position = pos orelse 0;
    }

    pub fn tokenSlice(
        self: *Lexer,
        start: usize,
        end: usize,
    ) []const u8 {
        return self.currentText[start..end];
    }

    pub fn scan(self: *Lexer) Token {
        var result = Token{
            .syntax = undefined,
            .location = .{
                .start = self.position,
                .end = undefined,
            },
        };

        state: switch (State.start) {
            .start => switch (self.currentText[self.position]) {
                0 => {
                    if (self.position == self.currentText.len)
                        return .{
                            .syntax = .EndOfFileToken,
                            .location = .{
                                .start = self.position,
                                .end = self.position,
                            },
                        }
                    else
                        continue :state .invalid;
                },
                ' ', '\t', '\r', '\n' => {
                    result.location.start += 1;
                    self.position += 1;
                    continue :state .start;
                },
                ';' => {
                    result.syntax = .SemiColon;
                    self.position += 1;
                },
                ',' => {
                    result.syntax = .Comma;
                    self.position += 1;
                },
                '(' => {
                    result.syntax = .OpenParen;
                    self.position += 1;
                },
                ')' => {
                    result.syntax = .ClosingParen;
                    self.position += 1;
                },
                '{' => {
                    result.syntax = .OpenBrace;
                    self.position += 1;
                },
                '}' => {
                    result.syntax = .ClosingBrace;
                    self.position += 1;
                },
                '[' => {
                    result.syntax = .OpenBracket;
                    self.position += 1;
                },
                ']' => {
                    result.syntax = .ClosingBracket;
                    self.position += 1;
                },
                'a'...'z', 'A'...'Z', '_', '$' => {
                    result.syntax = .Identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.syntax = .Number;
                    continue :state .number;
                },
                else => continue :state .invalid,
            },
            .invalid => {
                self.position += 1;
                switch (self.currentText[self.position]) {
                    0 => if (self.position == self.currentText.len) {
                        result.syntax = .UnknowToken;
                    },
                    '\n' => result.syntax = .UnknowToken,
                    else => continue :state .invalid,
                }
            },
            .identifier => {
                self.position += 1;
                switch (self.currentText[self.position]) {
                    'a'...'z', 'A'...'Z', '_', '$', '0'...'9' => continue :state .identifier,
                    else => {
                        if (Token.keywords(self.currentText[result.location.start..self.position])) |syntax| {
                            result.syntax = syntax;
                        }

                        if (Token.typesKeyword(self.currentText[result.location.start..self.position])) |syntax| {
                            result.syntax = syntax;
                        }
                    },
                }
            },

            .number => {
                self.position += 1;
                switch (self.currentText[self.position]) {
                    '0'...'9' => continue :state .number,
                    else => {},
                }
            },
        }

        result.location.end = self.position;

        return result;
    }
};
