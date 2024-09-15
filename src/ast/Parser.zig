const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Ast = @import("Ast.zig");
const AstError = Ast.Error;
const Node = Ast.Node;
const NodeList = Ast.NodeList;
const NodeOffset = Ast.Offset;
const Token = tokenizer.Token;
const Tokenizer = tokenizer.Tokenizer;
const TokenIndex = Ast.TokenIndex;
const Parser = @This();

/// Errors that can happing whilest parsing the source code.
pub const ParserErrors = error{ParsingError} || Allocator.Error;

const null_node: Node.Index = 0;

const Span = union(enum) {
    zero_one: Node.Index,
    multi: Node.Range,
};

/// Allocator used in parsing.
allocator: Allocator,
/// Source code to parse.
source: []const u8,
/// All of the token tags.
token_tags: []const Token.Tag,
/// All of the token starts in the source code.
token_starts: []const NodeOffset,
/// Struct of arrays that contain all of the nodes information
nodes: NodeList,
/// Current index in the `token_tags` slice.
token_index: TokenIndex,
/// List of ast errors that the parser catches but doesn't fail on.
errors: ArrayListUnmanaged(AstError),
/// Extra data for ast nodes.
extra_data: ArrayListUnmanaged(Node.Index),
/// Scratch space to temporaly use.
scratch: ArrayListUnmanaged(Node.Index),

/// Pragma Keyword <- Solidity keyword <- version range <- semicolon
///
/// Pragma [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityLexer.PragmaToken)
pub fn parsePragmaDirective(self: *Parser) ParserErrors!Node.Index {
    const pragma = self.consumeToken(.keyword_pragma) orelse return null_node;

    _ = try self.expectToken(.keyword_solidity);

    const start = self.token_index;
    const end = try self.parsePragmaVersion();

    _ = try self.expectToken(.semicolon);

    if (start == end)
        try self.failMsg(.{
            .tag = .expected_pragma_version,
            .token = pragma,
            .extra = .{ .expected_tag = .number_literal },
        });

    return self.addNode(.{
        .tag = .pragma_directive,
        .main_token = pragma,
        .data = .{ .lhs = start, .rhs = end },
    });
}
/// Parses the pragma version. Breaks instantly if version is just the number literal.
pub fn parsePragmaVersion(self: *Parser) ParserErrors!TokenIndex {
    const end = while (true) {
        switch (self.token_tags[self.token_index]) {
            .equal,
            .angle_bracket_right,
            .angle_bracket_right_equal,
            .angle_bracket_left,
            .angle_bracket_left_equal,
            => {
                self.token_index += 1;
                _ = self.expectToken(.number_literal);
            },
            .number_literal => break self.nextToken(),
            else => break self.token_index,
        }
    };

    return end;
}
/// keyword_import
///     | .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
///     | .string_literal (path)
///         | semicolon
///         | keyword_as <- identifier <- semicolon
///     | .l_brace <- (Symbols)* <- .r_brace <- .identifier (from) <- .string_literal (path)
///
/// Import [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.importDirective)
pub fn parseImportDirective(self: *Parser) ParserErrors!Node.Index {
    const import = self.consumeToken(.keyword_import) orelse return null_node;

    switch (self.token_tags[self.token_index]) {
        .asterisk => return self.parseImportAsterisk(import),
        .l_brace => return self.parseImportSymbol(import),
        .string_literal => return self.parseImportPath(import),
        else => try self.failMsg(.{
            .tag = .expected_import_path_alias_asterisk,
            .token = self.token_index,
        }),
    }
}
/// .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
pub fn parseImportAsterisk(self: *Parser, import: TokenIndex) ParserErrors!Node.Index {
    _ = self.consumeToken(.asterisk);

    _ = try self.expectToken(.keyword_as);
    const identifier = try self.expectToken(.identifier);
    const from = try self.expectToken(.identifier);
    const path = try self.expectToken(.string_literal);

    return self.addNode(.{
        .main_token = import,
        .tag = .import_directive_asterisk,
        .data = .{
            .lhs = try self.addExtraData(Node.ImportAsterisk{
                .identifier = identifier,
                .from = from,
            }),
            .rhs = path,
        },
    });
}
/// .string_literal
///     | semicolon
///     | keyword_as <- identifier <- semicolon
pub fn parseImportPath(self: *Parser, import: TokenIndex) ParserErrors!Node.Index {
    const literal = try self.expectToken(.string_literal);

    switch (self.token_tags[self.token_index]) {
        .semicolon => return self.addNode(.{
            .tag = .import_directive_path,
            .main_token = import,
            .data = .{ .lhs = 0, .rhs = literal },
        }),
        .keyword_as => {
            _ = self.consumeToken(.keyword_as);
            const identifier = try self.expectToken(.identifier);
            _ = try self.expectSemicolon();

            return self.addNode(.{
                .tag = .import_directive_path_identifier,
                .main_token = import,
                .data = .{ .lhs = literal, .rhs = identifier },
            });
        },
        else => try self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_token = .semicolon },
        }),
    }
}
/// Symbols <- .identifier <- .string_literal
pub fn parseImportSymbol(self: *Parser, import: Node.Index) ParserErrors!Node.Index {
    const span = try self.parseIdentifierBlock();

    const from = try self.expectToken(.identifier);
    const path = try self.expectToken(.string_literal);
    _ = try self.expectToken(.semicolon);

    return switch (span) {
        .zero_one => |symbol| return self.addNode(.{
            .main_token = import,
            .tag = .import_directive_symbol_one,
            .data = .{
                .lhs = try self.addExtraData(Node.ImportSymbolOne{
                    .from = from,
                    .symbol = symbol,
                }),
                .rhs = path,
            },
        }),
        .multi => |symbols| return self.addNode(.{
            .main_token = import,
            .tag = .import_directive_symbol,
            .data = .{
                .lhs = try self.addExtraData(Node.ImportSymbol{
                    .from = from,
                    .symbol_start = symbols.start,
                    .symbol_end = symbols.end,
                }),
                .rhs = path,
            },
        }),
    };
}
/// .l_brace <- .identifier (COMMA)* <- .r_brace
pub fn parseIdentifierBlock(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_brace);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (self.consumeToken(.doc_comment_container)) |_| {}

    while (true) {
        _ = try self.consumeDocComments();

        const identifier = try self.expectToken(.identifier);
        try self.scratch.append(self.allocator, identifier);

        switch (self.token_tags[self.token_index]) {
            .comma => self.token_index += 1,
            .r_brace => {
                self.token_index += 1;
                break;
            },
            .colon, .r_bracket, .r_paren => try self.failMsg(.{
                .tag = .expected_r_brace,
                .token = self.token_index,
            }),
            else => try self.warnMessage(.{
                .tag = .expected_comma_after,
                .token = self.token_index,
            }),
        }
    }

    const identifiers = self.scratch.items[scratch..];

    return switch (identifiers.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = identifiers[0] },
        else => Span{ .multi = try self.listToSpan(identifiers) },
    };
}
/// .keyword_enum <- .identifier <- .l_brace <- (BLOCK)* <- r_brace.
///
/// Enum [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.enumDefinition)
pub fn parseEnum(self: *Parser) ParserErrors!Node.Index {
    const main = try self.expectToken(.keyword_enum);
    const name = try self.expectToken(.identifier);

    const members = try self.parseIdentifierBlock();

    return switch (members) {
        .zero_one => |identifier| return self.addNode(.{
            .main_token = main,
            .tag = .container_decl,
            .data = .{
                .lhs = name,
                .rhs = identifier,
            },
        }),
        .multi => |identifiers| return self.addNode(.{
            .main_token = main,
            .tag = .container_decl,
            .data = .{
                .lhs = name,
                .rhs = try self.addExtraData(Node.Range{
                    .start = identifiers.start,
                    .end = identifiers.end,
                }),
            },
        }),
    };
}
/// .identifier (.period)*
pub fn parseIdentifierPath(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        const identifier = self.expectToken(.identifier);
        try self.scratch.append(self.allocator, identifier);

        switch (self.token_tags[self.token_index]) {
            .period => self.token_index += 1,
            else => self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_tags[self.token_index],
                .extra = .{ .expected_tag = .period },
            }),
        }
    }

    const identifiers = self.scratch.items[scratch..];

    return switch (identifiers.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = identifiers[0] },
        else => Span{ .multi = try self.listToSpan(identifiers) },
    };
}
pub fn parseMappingElement(self: *Parser) ParserErrors!Span {
    const elementary = self.consumeElementaryType();

    return if (elementary) |elem|
        Span{ .zero_one = elem }
    else
        self.parseIdentifierPath();
}
/// Expectes a solidity primary type.
pub fn expectElementaryType(self: *Parser) error{ParseError}!TokenIndex {
    return if (self.consumeElementaryType()) |index| index else error.ParseError;
}
/// Consume a solidity primary type.
pub fn consumeElementaryType(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_address,
        .keyword_bool,
        .keyword_string,
        .keyword_bytes,
        .keyword_bytes1,
        .keyword_bytes2,
        .keyword_bytes3,
        .keyword_bytes4,
        .keyword_bytes5,
        .keyword_bytes6,
        .keyword_bytes7,
        .keyword_bytes8,
        .keyword_bytes9,
        .keyword_bytes10,
        .keyword_bytes11,
        .keyword_bytes12,
        .keyword_bytes13,
        .keyword_bytes14,
        .keyword_bytes15,
        .keyword_bytes16,
        .keyword_bytes17,
        .keyword_bytes18,
        .keyword_bytes19,
        .keyword_bytes20,
        .keyword_bytes21,
        .keyword_bytes22,
        .keyword_bytes23,
        .keyword_bytes24,
        .keyword_bytes25,
        .keyword_bytes26,
        .keyword_bytes27,
        .keyword_bytes28,
        .keyword_bytes29,
        .keyword_bytes30,
        .keyword_bytes31,
        .keyword_bytes32,
        .keyword_uint,
        .keyword_uint8,
        .keyword_uint16,
        .keyword_uint24,
        .keyword_uint32,
        .keyword_uint40,
        .keyword_uint48,
        .keyword_uint56,
        .keyword_uint64,
        .keyword_uint72,
        .keyword_uint80,
        .keyword_uint88,
        .keyword_uint96,
        .keyword_uint104,
        .keyword_uint112,
        .keyword_uint120,
        .keyword_uint128,
        .keyword_uint136,
        .keyword_uint144,
        .keyword_uint152,
        .keyword_uint160,
        .keyword_uint168,
        .keyword_uint176,
        .keyword_uint184,
        .keyword_uint192,
        .keyword_uint200,
        .keyword_uint208,
        .keyword_uint216,
        .keyword_uint224,
        .keyword_uint232,
        .keyword_uint240,
        .keyword_uint248,
        .keyword_uint256,
        .keyword_int,
        .keyword_int8,
        .keyword_int16,
        .keyword_int24,
        .keyword_int32,
        .keyword_int40,
        .keyword_int48,
        .keyword_int56,
        .keyword_int64,
        .keyword_int72,
        .keyword_int80,
        .keyword_int88,
        .keyword_int96,
        .keyword_int104,
        .keyword_int112,
        .keyword_int120,
        .keyword_int128,
        .keyword_int136,
        .keyword_int144,
        .keyword_int152,
        .keyword_int160,
        .keyword_int168,
        .keyword_int176,
        .keyword_int184,
        .keyword_int192,
        .keyword_int200,
        .keyword_int208,
        .keyword_int216,
        .keyword_int224,
        .keyword_int232,
        .keyword_int240,
        .keyword_int248,
        .keyword_int256,
        => self.nextToken(),
        else => null,
    };
}
/// Consume visibility modifiers.
pub fn consumeVisibilityModifier(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_external,
        .keyword_internal,
        .keyword_private,
        .keyword_public,
        => self.nextToken(),

        else => null,
    };
}
/// Consume state mutability modifiers.
pub fn consumeStateMutability(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_payable,
        .keyword_view,
        .keyword_pure,
        => self.nextToken(),

        else => null,
    };
}
/// Consumes storage location modifiers.
pub fn consumeStorageLocation(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_memory,
        .keyword_storage,
        .keyword_calldata,
        => self.nextToken(),
        else => null,
    };
}
/// Consumes all doc_comment tokens.
pub fn consumeDocComments(self: *Parser) ?TokenIndex {
    if (self.consumeToken(.doc_comment)) |token| {
        var first_token = token;

        if (token > 0 and self.tokensOnSameLine(first_token - 1, token)) {
            try self.warnMessage(.{ .tag = .same_line_doc_comment, .token = token });

            first_token = self.consumeToken(.doc_comment) orelse return null;
        }

        while (self.consumeToken(.doc_comment)) |_| {}
        return first_token;
    }

    return null;
}

// Internal parser actions.

fn tokensOnSameLine(self: *Parser, token1: TokenIndex, token2: TokenIndex) bool {
    return std.mem.indexOfScalar(u8, self.source[self.token_starts[token1]..self.token_starts[token2]], '\n') == null;
}

fn expectToken(self: *Parser, token: Token.Tag) ParserErrors!TokenIndex {
    if (self.token_tags[self.token_index] != token) {
        return self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_tag = token },
        });
    }
    return self.nextToken();
}

fn expectSemicolon(self: *Parser) ParserErrors!void {
    if (self.token_tags[self.token_index] != .semicolon) {
        self.warnMessage(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_token = .semicolon },
        });
    }
    _ = self.nextToken();
    return;
}

fn consumeToken(self: *Parser, token: Token.Tag) ?TokenIndex {
    return if (self.token_tags[self.token_index] == token) self.nextToken() else null;
}

fn nextToken(self: *Parser) TokenIndex {
    const index = self.token_index;
    self.token_index += 1;

    return index;
}

// Node actions.

fn addExtraData(self: *Parser, extra: anytype) Allocator.Error!Node.Index {
    const fields = std.meta.fields(@TypeOf(extra));

    try self.extra_data.ensureUnusedCapacity(self.allocator, fields.len);
    const result: u32 = @intCast(self.extra_data.items.len);

    inline for (fields) |field| {
        comptime std.debug.assert(field.type == Node.Index);
        self.extra_data.appendAssumeCapacity(@field(extra, field.name));
    }

    return result;
}

fn listToSpan(self: *Parser, list: []const Node.Index) !Node.Range {
    try self.extra_data.appendSlice(self.allocator, list);

    return Node.SubRange{
        .start = @as(Node.Index, @intCast(self.extra_data.items.len - list.len)),
        .end = @as(Node.Index, @intCast(self.extra_data.items.len)),
    };
}

fn addNode(self: *Parser, child: Node) Allocator.Error!Node.Index {
    const index = @as(Node.Index, self.nodes.len);
    try self.nodes.append(child);

    return index;
}

fn setNode(self: *Parser, child: Node, index: usize) Node.Index!void {
    try self.nodes.set(index, child);
    return @as(Node.Index, index);
}

fn reserveNode(self: *Parser, tag: Ast.Node.Tag) !usize {
    try self.nodes.resize(self.allocator, self.nodes.len + 1);
    self.nodes.items(.tag)[self.nodes.len - 1] = tag;
    return self.nodes.len - 1;
}

fn warnMessage(self: *Parser, message: Ast.Error) Allocator.Error!void {
    @branchHint(.cold);

    switch (message.tag) {
        .expected_semicolon,
        .expected_token,
        .expected_pragma_version,
        .expected_r_brace,
        .expected_comma_after,
        .expected_import_path_alias_asterisk,
        => if (message.token != 0 and !self.tokensOnSameLine(message.token - 1, message.token)) {
            var copy = message;
            copy.token_is_prev = true;
            copy.token -= 1;
            return self.errors.append(self.allocator, copy);
        },
        else => {},
    }
    try self.errors.append(self.allocator, message);
}

fn failMsg(self: *Parser, message: Ast.Error) ParserErrors!void {
    @branchHint(.cold);
    try self.warnMessage(message);

    return error.ParseError;
}
