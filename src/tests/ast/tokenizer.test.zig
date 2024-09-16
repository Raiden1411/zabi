const scanner = @import("../../ast/tokenizer.zig");
const std = @import("std");
const testing = std.testing;

const Token = scanner.Token;
const Tokenizer = scanner.Tokenizer;

test "Keywords" {
    try testTokenize("foo payable struct", &.{ .identifier, .keyword_payable, .keyword_struct });
    try testTokenize("after of inline gwei", &.{ .reserved_after, .reserved_of, .reserved_inline, .keyword_gwei });
    try testTokenize(
        \\/**
        \\* This is a doc_comment.
        \\*/
        \\foo + bar;
    , &.{ .doc_comment_container, .identifier, .plus, .identifier, .semicolon });
}

test "Line comment with addition" {
    try testTokenize(
        \\//This is comment.
        \\foo + bar;
    , &.{ .identifier, .plus, .identifier, .semicolon });
    try testTokenize(
        \\//This is comment.
        \\//
        \\foo + bar;
    , &.{ .identifier, .plus, .identifier, .semicolon });
    try testTokenize("////", &.{});
    try testTokenize("// /", &.{});
}

test "Doc comments" {
    try testTokenize("/*", &.{.doc_comment_container});
    try testTokenize(
        \\/**
        \\* This is a doc_comment.
        \\*/
        \\foo + bar;
    , &.{ .doc_comment_container, .identifier, .plus, .identifier, .semicolon });
    try testTokenize(
        \\/**
        \\* This is a doc_comment.
        \\foo + bar;
    , &.{.doc_comment_container});
    try testTokenize(
        \\/**
        \\* This is a doc_comment.
        \\foo + bar;
        \\*/ foo;
    , &.{ .doc_comment_container, .identifier, .semicolon });
    try testTokenize("///", &.{.doc_comment});
}

test "Special arithemitic" {
    try testTokenize("foo--;", &.{ .identifier, .minus_minus, .semicolon });
    try testTokenize("foo++;", &.{ .identifier, .plus_plus, .semicolon });
    try testTokenize("uint foo += 10;", &.{ .keyword_uint, .identifier, .plus_equal, .number_literal, .semicolon });
    try testTokenize("uint foo ^= 10;", &.{ .keyword_uint, .identifier, .caret_equal, .number_literal, .semicolon });
    try testTokenize("uint foo -= 10;", &.{ .keyword_uint, .identifier, .minus_equal, .number_literal, .semicolon });
    try testTokenize("uint foo /= 10;", &.{ .keyword_uint, .identifier, .slash_equal, .number_literal, .semicolon });
    try testTokenize("uint foo |= 10;", &.{ .keyword_uint, .identifier, .pipe_equal, .number_literal, .semicolon });
    try testTokenize("uint foo &= 10;", &.{ .keyword_uint, .identifier, .ampersand_equal, .number_literal, .semicolon });
    try testTokenize("uint foo %= 10;", &.{ .keyword_uint, .identifier, .percent_equal, .number_literal, .semicolon });
}

test "Invalid assignment" {
    try testTokenize("uint foo &&= 10;", &.{ .keyword_uint, .identifier, .ampersand_ampersand, .equal, .number_literal, .semicolon });
    try testTokenize("uint foo ||= 10;", &.{ .keyword_uint, .identifier, .pipe_pipe, .equal, .number_literal, .semicolon });
    try testTokenize("uint foo **= 10;", &.{ .keyword_uint, .identifier, .asterisk_asterisk, .equal, .number_literal, .semicolon });
}

test "Angle brackets" {
    try testTokenize("<", &.{.angle_bracket_left});
    try testTokenize("<=", &.{.angle_bracket_left_equal});
    try testTokenize("<<", &.{.angle_bracket_left_angle_bracket_left});
    try testTokenize("<<=", &.{.angle_bracket_left_angle_bracket_left_equal});
    try testTokenize(">", &.{.angle_bracket_right});
    try testTokenize(">=", &.{.angle_bracket_right_equal});
    try testTokenize(">>", &.{.angle_bracket_right_angle_bracket_right});
    try testTokenize(">>=", &.{.angle_bracket_right_angle_bracket_right_equal});
    try testTokenize(">>>", &.{.angle_bracket_right_angle_bracket_right_angle_bracket_right});
    try testTokenize(">>>=", &.{.angle_bracket_right_angle_bracket_right_angle_bracket_right_equal});
}

test "Conditional" {
    try testTokenize("==", &.{.equal_equal});
    try testTokenize("!=", &.{.bang_equal});
    try testTokenize("!", &.{.bang});
    try testTokenize("~", &.{.tilde});
    try testTokenize("=>", &.{.equal_bracket_right});
    try testTokenize("->", &.{.arrow});
    try testTokenize(":=", &.{.colon_equal});
}

test "String literal" {
    try testTokenize("\"This is a string literal!\"", &.{.string_literal});
    try testTokenize("\"\"", &.{.string_literal});
    try testTokenize("\"", &.{.invalid});
}

test "Int Literals" {
    try testTokenize("10000000", &.{.number_literal});
    try testTokenize("1e6", &.{.number_literal});
    try testTokenize("1E6", &.{.number_literal});
    try testTokenize("1.6.", &.{ .number_literal, .period });
    try testTokenize("1.6", &.{.number_literal});
    try testTokenize("1.6.2", &.{.number_literal});
    try testTokenize("0x12312313432424", &.{.number_literal});
}

test "Signature" {
    try testTokenize("function changeOwner(address newOwner) public isOwner {}", &.{
        .keyword_function,
        .identifier,
        .l_paren,
        .keyword_address,
        .identifier,
        .r_paren,
        .keyword_public,
        .identifier,
        .l_brace,
        .r_brace,
    });
}

fn testTokenize(source: [:0]const u8, tokens: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);

    for (tokens) |token| {
        const actual_token = tokenizer.next();
        try testing.expectEqual(token, actual_token.tag);
    }

    const last_token = tokenizer.next();

    try testing.expectEqual(Token.Tag.eof, last_token.tag);
    try testing.expectEqual(source.len, last_token.location.start);
    try testing.expectEqual(source.len, last_token.location.end);
}
