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

/// Taken from zig's std.
const Span = union(enum) {
    zero_one: Node.Index,
    multi: Node.Range,
};

/// Taken from zig's std.
const Association = enum {
    right,
    left,
    none,
};

/// Taken from zig's std.
const OperationInfo = struct {
    precedence: i8,
    tag: Node.Tag,
    association: Association = .left,
};

/// A table of binary operator information. Higher precedence numbers are
/// stickier. All operators at the same precedence level should have the same
/// associativity.
const oper_table = table: {
    @setEvalBranchQuota(2000);

    break :table std.enums.directEnumArrayDefault(Token.Tag, OperationInfo, .{ .precedence = -1, .tag = Node.Tag.root }, 0, .{
        .pipe_pipe = .{ .precedence = 10, .tag = .conditional_or },
        .ampersand_ampersand = .{ .precedence = 20, .tag = .conditional_and },

        .equal_equal = .{ .precedence = 30, .tag = .equal_equal, .association = .none },
        .bang_equal = .{ .precedence = 30, .tag = .bang_equal, .association = .none },
        .angle_bracket_left = .{ .precedence = 30, .tag = .less_than, .association = .none },
        .angle_bracket_right = .{ .precedence = 30, .tag = .greater_than, .association = .none },
        .angle_bracket_left_equal = .{ .precedence = 30, .tag = .less_or_equal, .association = .none },
        .angle_bracket_right_equal = .{ .precedence = 30, .tag = .greater_or_equal, .association = .none },

        .ampersand = .{ .precedence = 40, .tag = .bit_and },
        .caret = .{ .precedence = 40, .tag = .bit_xor },
        .pipe = .{ .precedence = 40, .tag = .bit_or },

        .angle_bracket_left_angle_bracket_left = .{ .precedence = 50, .tag = .shl },
        .angle_bracket_right_angle_bracket_right = .{ .precedence = 50, .tag = .sar },
        .angle_bracket_right_angle_bracket_right_angle_bracket_right = .{ .precedence = 50, .tag = .shr },

        .plus = .{ .precedence = 60, .tag = .add },
        .minus = .{ .precedence = 60, .tag = .sub },

        .asterisk = .{ .precedence = 70, .tag = .mul },
        .asterisk_asterisk = .{ .precedence = 70, .tag = .exponent, .association = .right },
        .slash = .{ .precedence = 70, .tag = .div },
        .percent = .{ .precedence = 70, .tag = .mod },
    });
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

/// Deinits the parser allocated memory
pub fn deinit(self: *Parser) void {
    self.errors.deinit(self.allocator);
    self.nodes.deinit(self.allocator);
    self.extra_data.deinit(self.allocator);
    self.scratch.deinit(self.allocator);
}
/// Parses a full solidity source file.
/// This is a custom implementation based on the provided solidity grammar.
///
/// If you find any bugs feel free to open an issue.
pub fn parseSource(self: *Parser) ParserErrors!void {
    try self.nodes.append(self.allocator, .{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });

    const members = try self.parseSourceUnits();

    if (self.token_tags[self.token_index] != .eof)
        try self.warnMessage(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{
                .expected_tag = .eof,
            },
        });

    self.nodes.items(.data)[0] = .{
        .lhs = members.start,
        .rhs = members.end,
    };
}
/// Parses solidity unit declaration according to the solidity grammar.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)
pub fn parseSourceUnits(self: *Parser) ParserErrors!Node.Range {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        while (self.consumeToken(.doc_comment_container)) |_| {}
        const doc_comment = try self.consumeDocComments();

        switch (self.token_tags[self.token_index]) {
            .eof, .r_brace => {
                if (doc_comment) |_|
                    try self.warn(.unattached_doc_comment);

                break;
            },
            else => {},
        }

        try self.scratch.append(self.allocator, try self.expectSourceUnitRecoverable());
    }

    return self.listToSpan(self.scratch.items[scratch..]);
}
/// Tries to parse a [source unit](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)
/// and if it fails tries to recover the parser by finding the next possible unit.
pub fn expectSourceUnitRecoverable(self: *Parser) ParserErrors!Node.Index {
    return self.expectSourceUnit() catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.ParsingError => {
            self.findNextSource();
            return null_node;
        },
    };
}
/// Expects to find a [source unit](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)
/// or it will fail parsing.
pub fn expectSourceUnit(self: *Parser) ParserErrors!Node.Index {
    const units = try self.parseSourceUnit();

    if (units == 0) {
        switch (self.token_tags[self.token_index]) {
            .eof,
            .r_brace,
            => return error.ParsingError,
            else => return self.fail(.expected_source_unit_expr),
        }
    }

    return units;
}
/// Tries to parse a [source unit](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)
///
/// Returns a `null_node` if it cannot find any.
pub fn parseSourceUnit(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .keyword_import => return self.parseImportDirective(),
        .keyword_pragma => return self.parsePragmaDirective(),
        .keyword_abstract => {
            const abstract = self.nextToken();
            _ = self.nextToken();
            const identifier = try self.expectToken(.identifier);

            switch (self.token_tags[self.token_index]) {
                .l_brace => {
                    const body = try self.expectContractBlock();
                    return self.addNode(.{
                        .tag = .abstract_decl,
                        .main_token = abstract,
                        .data = .{
                            .lhs = identifier,
                            .rhs = body,
                        },
                    });
                },
                .keyword_is => {
                    _ = self.nextToken();
                    const inheritance = try self.parseInheritanceSpecifiers();
                    const body = try self.expectContractBlock();

                    switch (inheritance) {
                        .zero_one => |elem| return self.addNode(.{
                            .tag = .abstract_decl_inheritance_one,
                            .main_token = abstract,
                            .data = .{
                                .lhs = try self.addExtraData(
                                    Node.ContractInheritanceOne{
                                        .identifier = identifier,
                                        .inheritance = elem,
                                    },
                                ),
                                .rhs = body,
                            },
                        }),
                        .multi => |elems| return self.addNode(.{
                            .tag = .abstract_decl_inheritance,
                            .main_token = abstract,
                            .data = .{
                                .lhs = try self.addExtraData(
                                    Node.ContractInheritance{
                                        .identifier = identifier,
                                        .inheritance_start = elems.start,
                                        .inheritance_end = elems.end,
                                    },
                                ),
                                .rhs = body,
                            },
                        }),
                    }
                },
                else => return self.failMsg(.{
                    .tag = .expected_token,
                    .token = self.token_index,
                    .extra = .{
                        .expected_tag = .l_brace,
                    },
                }),
            }
        },
        .keyword_interface,
        .keyword_contract,
        .keyword_library,
        => return self.parseContractProto(),
        .keyword_struct => return self.parseStruct(),
        .keyword_enum => return self.parseEnum(),
        .keyword_error => return self.parseError(),
        .keyword_event => return self.parseEvent(),
        .keyword_type => return self.parseUserTypeDefinition(),
        .keyword_using => return self.parseUsingDirective(),
        .keyword_function => return self.parseFunctionDecl(),
        else => return self.parseConstantVariableDecl(),
    }
}
/// Parses a `contract_decl`, `interface_decl`, or `library_decl` according to the [grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.contractDefinition)
/// Returns a `null_node` if it cannot find any.
pub fn parseContractProto(self: *Parser) ParserErrors!Node.Index {
    const tag: Node.Tag = switch (self.token_tags[self.token_index]) {
        .keyword_library => .library_decl,
        .keyword_interface => .interface_decl,
        .keyword_contract => .contract_decl,
        else => return null_node,
    };

    switch (tag) {
        .library_decl => {
            const token = self.nextToken();
            const identifier = try self.expectToken(.identifier);

            const body = try self.expectContractBlock();

            return self.addNode(.{
                .tag = tag,
                .main_token = token,
                .data = .{
                    .lhs = identifier,
                    .rhs = body,
                },
            });
        },
        .interface_decl,
        .contract_decl,
        => {
            const token = self.nextToken();
            const identifier = try self.expectToken(.identifier);

            switch (self.token_tags[self.token_index]) {
                .l_brace => {
                    const body = try self.expectContractBlock();
                    return self.addNode(.{
                        .tag = tag,
                        .main_token = token,
                        .data = .{
                            .lhs = identifier,
                            .rhs = body,
                        },
                    });
                },
                .keyword_is => {
                    _ = self.nextToken();
                    const inheritance = try self.parseInheritanceSpecifiers();
                    const body = try self.expectContractBlock();

                    switch (inheritance) {
                        .zero_one => |elem| return self.addNode(.{
                            .tag = if (tag == .contract_decl) .contract_decl_inheritance_one else .interface_decl_inheritance_one,
                            .main_token = token,
                            .data = .{
                                .lhs = try self.addExtraData(
                                    Node.ContractInheritanceOne{
                                        .identifier = identifier,
                                        .inheritance = if (elem == 0) return self.failMsg(.{
                                            .tag = .expected_token,
                                            .token = self.token_index,
                                            .extra = .{
                                                .expected_tag = .identifier,
                                            },
                                        }) else elem,
                                    },
                                ),
                                .rhs = body,
                            },
                        }),
                        .multi => |elems| return self.addNode(.{
                            .tag = if (tag == .contract_decl) .contract_decl_inheritance else .interface_decl_inheritance,
                            .main_token = token,
                            .data = .{
                                .lhs = try self.addExtraData(
                                    Node.ContractInheritance{
                                        .identifier = identifier,
                                        .inheritance_start = elems.start,
                                        .inheritance_end = elems.end,
                                    },
                                ),
                                .rhs = body,
                            },
                        }),
                    }
                },
                else => return self.failMsg(.{
                    .tag = .expected_token,
                    .token = self.token_index,
                    .extra = .{
                        .expected_tag = .l_brace,
                    },
                }),
            }
        },
        else => unreachable,
    }
}
/// Expects to parse a contract block otherwise it will fail.
pub fn expectContractBlock(self: *Parser) ParserErrors!Node.Index {
    const body = try self.parseContractBlock();

    if (body == 0)
        return self.fail(.expected_contract_block);

    return body;
}

/// .l_brace (contract_element) .r_brace
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.contractBodyElement)
pub fn parseContractBlock(self: *Parser) ParserErrors!Node.Index {
    const lbrace = self.consumeToken(.l_brace) orelse return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        while (self.consumeToken(.doc_comment_container)) |_| {}
        while (try self.consumeDocComments()) |_| {}

        if (self.token_tags[self.token_index] == .r_brace)
            break;

        const statement = try self.expectContractElementBodyRecoverable();

        if (statement == 0)
            break;

        try self.scratch.append(self.allocator, statement);
    }

    _ = self.consumeToken(.r_brace);
    const semicolon = (self.token_tags[self.token_index - 2] == .semicolon);

    const statements = self.scratch.items[scratch..];

    switch (statements.len) {
        0 => return self.addNode(.{
            .tag = .contract_block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = 0,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = if (semicolon) .contract_block_two_semicolon else .contract_block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = statements[0],
                .rhs = 0,
            },
        }),
        2 => return self.addNode(.{
            .tag = if (semicolon) .contract_block_two_semicolon else .contract_block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = statements[0],
                .rhs = statements[1],
            },
        }),
        else => {
            const span = try self.listToSpan(statements);

            return self.addNode(.{
                .tag = if (semicolon) .contract_block_semicolon else .contract_block,
                .main_token = lbrace,
                .data = .{
                    .lhs = span.start,
                    .rhs = span.end,
                },
            });
        },
    }
}
/// Tries to parse a contract block element. If it fails
/// tries to recover the parser by finding the next element.
pub fn expectContractElementBodyRecoverable(self: *Parser) ParserErrors!Node.Index {
    while (true) {
        return self.expectContractElementBody() catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParsingError => {
                self.findNextContractElement();
                switch (self.token_tags[self.token_index]) {
                    .r_brace => return null_node,
                    .eof => return err,
                    else => continue,
                }
            },
        };
    }
}
/// Tries to parse a contract block element. It fails if it cannot.
pub fn expectContractElementBody(self: *Parser) ParserErrors!Node.Index {
    const element = try self.parseContractElementBody();

    if (element == 0)
        return self.fail(.expected_contract_element);

    return element;
}
pub fn parseContractElementBody(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .keyword_constructor => return self.parseConstructor(),
        .keyword_enum => return self.parseEnum(),
        .keyword_struct => return self.parseStruct(),
        .keyword_event => return self.parseEvent(),
        .keyword_error => return self.parseError(),
        .keyword_type => return self.parseUserTypeDefinition(),
        .keyword_modifier => {
            const proto = try self.parseModifierProto();

            switch (self.token_tags[self.token_index]) {
                .semicolon => {
                    self.token_index += 1;
                    return proto;
                },
                .l_brace => {
                    const modifer_decl = try self.reserveNode(.modifier_decl);
                    errdefer self.unreserveNode(modifer_decl);

                    const block = try self.parseBlock();

                    std.debug.assert(block != 0);

                    return self.setNode(modifer_decl, .{
                        .tag = .modifier_decl,
                        .main_token = self.nodes.items(.main_token)[proto],
                        .data = .{
                            .lhs = proto,
                            .rhs = block,
                        },
                    });
                },
                else => {
                    try self.warn(.expected_semicolon_or_lbrace);

                    return proto;
                },
            }
        },
        .keyword_function => {
            const proto = switch (self.token_tags[self.token_index + 1]) {
                .identifier => try self.parseFullFunctionProto(),
                .l_paren => return self.parseStateVariableDecl(),
                else => return null_node,
            };

            switch (self.token_tags[self.token_index]) {
                .semicolon => {
                    self.token_index += 1;
                    return proto;
                },
                .l_brace => {
                    const modifer_decl = try self.reserveNode(.function_decl);
                    errdefer self.unreserveNode(modifer_decl);

                    const block = try self.parseBlock();

                    std.debug.assert(block != 0);

                    return self.setNode(modifer_decl, .{
                        .tag = .function_decl,
                        .main_token = self.nodes.items(.main_token)[proto],
                        .data = .{
                            .lhs = proto,
                            .rhs = block,
                        },
                    });
                },
                else => {
                    try self.warn(.expected_semicolon_or_lbrace);

                    return proto;
                },
            }
        },
        .keyword_fallback,
        .keyword_receive,
        => {
            const proto = try self.parseFullFunctionProto();

            switch (self.token_tags[self.token_index]) {
                .semicolon => {
                    self.token_index += 1;
                    return proto;
                },
                .l_brace => {
                    const modifer_decl = try self.reserveNode(.function_decl);
                    errdefer self.unreserveNode(modifer_decl);

                    const block = try self.parseBlock();

                    std.debug.assert(block != 0);

                    return self.setNode(modifer_decl, .{
                        .tag = .function_decl,
                        .main_token = self.nodes.items(.main_token)[proto],
                        .data = .{
                            .lhs = proto,
                            .rhs = block,
                        },
                    });
                },
                else => {
                    try self.warn(.expected_semicolon_or_lbrace);

                    return proto;
                },
            }
        },
        .keyword_using => return self.parseUsingDirective(),
        else => return self.parseStateVariableDecl(),
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.usingDirective)
pub fn parseUsingDirective(self: *Parser) ParserErrors!Node.Index {
    const using = self.consumeToken(.keyword_using) orelse return null_node;

    const path = path: {
        const path = try self.consumeIdentifierPath();

        if (path != 0)
            break :path Span{ .zero_one = path };

        break :path try self.parseUsingAlias();
    };

    const for_alias = try self.expectToken(.keyword_for);

    const alias = switch (self.token_tags[self.token_index]) {
        .asterisk => self.nextToken(),
        else => try self.expectTypeExpr(),
    };

    const global = self.consumeToken(.identifier) orelse null_node;
    try self.expectSemicolon();

    switch (path) {
        .zero_one => |elem| {
            if (elem == 0)
                return self.failMsg(.{
                    .tag = .expected_token,
                    .token = self.token_index,
                    .extra = .{
                        .expected_tag = .identifier,
                    },
                });

            return self.addNode(.{
                .tag = .using_directive,
                .main_token = using,
                .data = .{
                    .lhs = try self.addExtraData(Node.UsingDirective{
                        .aliases = elem,
                        .for_alias = for_alias,
                        .target_type = alias,
                    }),
                    .rhs = global,
                },
            });
        },
        .multi => |elems| return self.addNode(.{
            .tag = .using_directive_multi,
            .main_token = using,
            .data = .{
                .lhs = try self.addExtraData(Node.UsingDirectiveMulti{
                    .aliases_start = elems.start,
                    .aliases_end = elems.end,
                    .for_alias = for_alias,
                    .target_type = alias,
                }),
                .rhs = global,
            },
        }),
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.usingAliases)
pub fn parseUsingAlias(self: *Parser) ParserErrors!Span {
    _ = self.consumeToken(.l_brace) orelse return Span{ .zero_one = null_node };

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_brace)) |_| break;

        const path = try self.consumeIdentifierPath();

        if (path == 0) {
            return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{
                    .expected_tag = .identifier,
                },
            });
        }

        if (self.consumeToken(.keyword_as)) |as| {
            switch (self.token_tags[self.token_index]) {
                .asterisk,
                .ampersand,
                .minus,
                .plus,
                .slash,
                .tilde,
                .percent,
                .pipe,
                .equal_equal,
                .angle_bracket_left,
                .angle_bracket_left_equal,
                .angle_bracket_right,
                .angle_bracket_right_equal,
                .bang_equal,
                => try self.scratch.append(
                    self.allocator,
                    try self.addNode(.{
                        .tag = .using_alias_operator,
                        .main_token = self.nextToken(),
                        .data = .{
                            .lhs = path,
                            .rhs = as,
                        },
                    }),
                ),
                else => return self.fail(.expected_operator),
            }
        } else try self.scratch.append(self.allocator, path);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_brace)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_brace => {
                self.token_index += 1;
                break;
            },
            .r_paren, .colon, .semicolon => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_brace },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.constantVariableDeclaration)
pub fn parseConstantVariableDecl(self: *Parser) ParserErrors!Node.Index {
    const type_decl = try self.parseTypeExpr();

    if (type_decl == 0)
        return null_node;

    _ = self.consumeToken(.keyword_constant) orelse return null_node;
    const identifier = try self.expectToken(.identifier);

    _ = try self.expectToken(.equal);
    const expr = try self.expectExpr();
    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .constant_variable_decl,
        .main_token = identifier,
        .data = .{
            .lhs = type_decl,
            .rhs = expr,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.stateVariableDeclaration)
pub fn parseStateVariableDecl(self: *Parser) ParserErrors!Node.Index {
    const type_decl = try self.parseTypeExpr();

    if (type_decl == 0)
        return null_node;

    const state = try self.parseStateModifier();

    _ = try self.expectToken(.identifier);

    switch (self.token_tags[self.token_index]) {
        .equal => {
            _ = self.nextToken();

            const expr = try self.expectExpr();
            try self.expectSemicolon();

            return self.addNode(.{
                .tag = .state_variable_decl,
                .main_token = state,
                .data = .{
                    .lhs = type_decl,
                    .rhs = expr,
                },
            });
        },
        .semicolon => {
            _ = self.nextToken();

            return self.addNode(.{
                .tag = .state_variable_decl,
                .main_token = state,
                .data = .{
                    .lhs = type_decl,
                    .rhs = 0,
                },
            });
        },
        else => return self.fail(.expected_semicolon),
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.stateVariableDeclaration)
///
/// Parses specifically the state modifiers since solidity can have multiple
pub fn parseStateModifier(self: *Parser) ParserErrors!Node.Index {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .keyword_public,
            .keyword_private,
            .keyword_internal,
            .keyword_constant,
            .keyword_immutable,
            => {
                const node = try self.addNode(.{
                    .tag = .simple_specifiers,
                    .main_token = self.nextToken(),
                    .data = .{
                        .lhs = undefined,
                        .rhs = undefined,
                    },
                });

                try self.scratch.append(self.allocator, node);
            },
            .keyword_override => try self.scratch.append(
                self.allocator,
                try self.parseOverrideSpecifier(),
            ),
            else => break,
        }
    }

    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .state_modifiers,
        .main_token = try self.addExtraData(try self.listToSpan(slice)),
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.functionDefinition)
pub fn parseFunctionSpecifiers(self: *Parser) ParserErrors!Node.Index {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .keyword_virtual,
            .keyword_external,
            .keyword_public,
            .keyword_view,
            .keyword_pure,
            .keyword_payable,
            .keyword_private,
            .keyword_internal,
            => {
                const node = try self.addNode(.{
                    .tag = .simple_specifiers,
                    .main_token = self.nextToken(),
                    .data = .{
                        .lhs = undefined,
                        .rhs = undefined,
                    },
                });

                try self.scratch.append(self.allocator, node);
            },
            .keyword_override => try self.scratch.append(self.allocator, try self.parseOverrideSpecifier()),
            .identifier => {
                const identifier_path = try self.consumeIdentifierPath();
                const call = try self.parseCallExpression(identifier_path);

                if (call == 0) {
                    try self.scratch.append(self.allocator, identifier_path);
                    continue;
                }

                try self.scratch.append(self.allocator, call);
            },
            else => break,
        }
    }
    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .specifiers,
        .main_token = try self.addExtraData(try self.listToSpan(slice)),
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.modifierDefinition)
pub fn parseModifierSpecifiers(self: *Parser) ParserErrors!Node.Index {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    var state: union(enum) {
        seen_virtual,
        seen_override,
        none,
    } = .none;

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .keyword_virtual,
            => {
                if (state == .seen_virtual)
                    return self.fail(.already_seen_specifier);

                const node = try self.addNode(.{
                    .tag = .simple_specifiers,
                    .main_token = self.nextToken(),
                    .data = .{
                        .lhs = undefined,
                        .rhs = undefined,
                    },
                });

                try self.scratch.append(self.allocator, node);
                state = .seen_virtual;
            },
            .keyword_override => {
                if (state == .seen_override)
                    return self.fail(.already_seen_specifier);

                try self.scratch.append(self.allocator, try self.parseOverrideSpecifier());

                state = .seen_override;
            },
            else => break,
        }
    }
    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .modifier_specifiers,
        .main_token = try self.addExtraData(try self.listToSpan(slice)),
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.overrideSpecifier)
pub fn parseOverrideSpecifier(self: *Parser) ParserErrors!Node.Index {
    const override = self.consumeToken(.keyword_override) orelse
        return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    _ = self.consumeToken(.l_paren) orelse return override;

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;
        const inden = try self.consumeIdentifierPath();

        if (inden != 0)
            try self.scratch.append(self.allocator, inden);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .r_bracket, .r_brace, .semicolon => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .override_specifier,
        .main_token = override,
        .data = .{
            .lhs = try self.addExtraData(try self.listToSpan(slice)),
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.modifierDefinition)
pub fn parseModifierProto(self: *Parser) ParserErrors!Node.Index {
    const modifier = self.consumeToken(.keyword_modifier) orelse return null_node;

    const identifier = try self.expectToken(.identifier);
    const params = if (self.token_tags[self.token_index] != .l_paren) Span{ .zero_one = 0 } else try self.parseParseDeclList();
    const specifiers = try self.parseModifierSpecifiers();

    return switch (params) {
        .zero_one => |elem| return self.addNode(.{
            .tag = .modifier_proto_one,
            .main_token = modifier,
            .data = .{
                .lhs = try self.addExtraData(Node.ModifierProtoOne{
                    .param = elem,
                    .identifier = identifier,
                }),
                .rhs = specifiers,
            },
        }),

        .multi => |elems| return self.addNode(.{
            .tag = .modifier_proto,
            .main_token = modifier,
            .data = .{
                .lhs = try self.addExtraData(Node.ModifierProto{
                    .params_start = elems.start,
                    .params_end = elems.end,
                    .identifier = identifier,
                }),
                .rhs = specifiers,
            },
        }),
    };
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.functionDefinition)
pub fn parseFunctionDecl(self: *Parser) ParserErrors!Node.Index {
    const proto = try self.parseFullFunctionProto();

    switch (self.token_tags[self.token_index]) {
        .semicolon => {
            self.token_index += 1;
            return proto;
        },
        .l_brace => {
            const modifer_decl = try self.reserveNode(.function_decl);
            errdefer self.unreserveNode(modifer_decl);

            const block = try self.parseBlock();

            std.debug.assert(block != 0);

            return self.setNode(modifer_decl, .{
                .tag = .function_decl,
                .main_token = self.nodes.items(.main_token)[proto],
                .data = .{
                    .lhs = proto,
                    .rhs = block,
                },
            });
        },
        else => {
            try self.warn(.expected_semicolon_or_lbrace);

            return proto;
        },
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.functionDefinition)
pub fn parseFullFunctionProto(self: *Parser) ParserErrors!Node.Index {
    const function = switch (self.token_tags[self.token_index]) {
        .keyword_function,
        .keyword_fallback,
        .keyword_receive,
        => self.nextToken(),
        else => return null_node,
    };

    const fn_index = try self.reserveNode(.function_proto);
    errdefer self.unreserveNode(fn_index);

    const identifier = switch (self.token_tags[self.token_index]) {
        .identifier,
        .keyword_fallback,
        .keyword_receive,
        => self.nextToken(),
        else => switch (self.token_tags[function]) {
            .keyword_receive,
            .keyword_fallback,
            => null_node,
            else => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .identifier },
            }),
        },
    };

    const param_list = try self.parseParseDeclList();
    const specifiers = try self.parseFunctionSpecifiers();

    const returns = self.consumeToken(.keyword_returns) orelse null_node;

    if (returns != 0) {
        const return_params = try self.parseParseDeclList();

        return switch (param_list) {
            .zero_one => |param| self.setNode(fn_index, .{
                .tag = .function_proto_one,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProtoOne{
                        .param = param,
                        .specifiers = specifiers,
                        .identifier = identifier,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| if (r_param == 0)
                            return self.fail(.expected_return_type)
                        else
                            try self.addExtraData(Node.Range{
                                .start = r_param,
                                .end = r_param,
                            }),
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
            .multi => |params| self.setNode(fn_index, .{
                .tag = .function_proto,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProto{
                        .specifiers = specifiers,
                        .identifier = identifier,
                        .params_start = params.start,
                        .params_end = params.end,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| if (r_param == 0)
                            return self.fail(.expected_return_type)
                        else
                            try self.addExtraData(Node.Range{
                                .start = r_param,
                                .end = r_param,
                            }),
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
        };
    }

    return switch (param_list) {
        .zero_one => |param| self.setNode(fn_index, .{
            .tag = .function_proto_simple,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProtoOne{
                    .param = param,
                    .specifiers = specifiers,
                    .identifier = identifier,
                }),
                .rhs = returns,
            },
        }),
        .multi => |params| self.setNode(fn_index, .{
            .tag = .function_proto_multi,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProto{
                    .specifiers = specifiers,
                    .identifier = identifier,
                    .params_start = params.start,
                    .params_end = params.end,
                }),
                .rhs = returns,
            },
        }),
    };
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.constructorDefinition)
pub fn parseConstructor(self: *Parser) ParserErrors!Node.Index {
    const index = try self.expectToken(.keyword_constructor);
    const params = try self.parseParseDeclList();

    const specifiers = try self.parseFunctionSpecifiers();

    const block = try self.expectBlock();

    return switch (params) {
        .zero_one => |elem| self.addNode(.{
            .tag = .construct_decl_one,
            .main_token = index,
            .data = .{
                .lhs = try self.addExtraData(Node.ConstructorProtoOne{
                    .param = elem,
                    .specifiers = specifiers,
                }),
                .rhs = block,
            },
        }),
        .multi => |elems| self.addNode(.{
            .tag = .construct_decl,
            .main_token = index,
            .data = .{
                .lhs = try self.addExtraData(Node.ConstructorProto{
                    .params_start = elems.start,
                    .params_end = elems.end,
                    .specifiers = specifiers,
                }),
                .rhs = block,
            },
        }),
    };
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.inheritanceSpecifier)
pub fn parseInheritanceSpecifiers(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        const specificer = try self.consumeIdentifierPath();

        if (specificer != 0) {
            try self.scratch.append(self.allocator, specificer);

            const call = try self.parseCallExpression(specificer);

            if (call != 0)
                try self.scratch.append(self.allocator, call);
        }

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .l_brace)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .l_brace => break,
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects a block expression or it fails.
pub fn expectBlock(self: *Parser) ParserErrors!Node.Index {
    const block = try self.parseBlock();

    if (block == 0)
        return error.ParsingError;

    return block;
}
/// .l_brace (statement) .r_brace
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.block)
pub fn parseBlock(self: *Parser) ParserErrors!Node.Index {
    const lbrace = self.consumeToken(.l_brace) orelse return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        while (self.consumeToken(.doc_comment_container)) |_| {}
        while (try self.consumeDocComments()) |_| {}

        if (self.token_tags[self.token_index] == .r_brace)
            break;

        const statement = try self.expectStatementRecoverable();

        if (statement == 0)
            break;

        try self.scratch.append(self.allocator, statement);
    }

    _ = self.consumeToken(.r_brace);
    const semicolon = (self.token_tags[self.token_index - 2] == .semicolon);
    const statements = self.scratch.items[scratch..];

    switch (statements.len) {
        0 => return self.addNode(.{
            .tag = .block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = 0,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = if (semicolon) .block_two_semicolon else .block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = statements[0],
                .rhs = 0,
            },
        }),
        2 => return self.addNode(.{
            .tag = if (semicolon) .block_two_semicolon else .block_two,
            .main_token = lbrace,
            .data = .{
                .lhs = statements[0],
                .rhs = statements[1],
            },
        }),
        else => {
            const span = try self.listToSpan(statements);

            return self.addNode(.{
                .tag = if (semicolon) .block_semicolon else .block,
                .main_token = lbrace,
                .data = .{
                    .lhs = span.start,
                    .rhs = span.end,
                },
            });
        },
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.tryStatement)
pub fn expectTryStatement(self: *Parser) ParserErrors!Node.Index {
    const try_index = try self.expectToken(.keyword_try);

    const expr = try self.expectExpr();

    const returns = returns: {
        if (self.consumeToken(.keyword_returns)) |_| {
            const params = try self.parseParseDeclList();

            break :returns params;
        } else break :returns Span{ .zero_one = 0 };
    };

    const block = try self.expectBlock();

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        try self.scratch.append(self.allocator, try self.expectCatchStatement());

        if (self.token_tags[self.token_index] != .keyword_catch)
            break;
    }

    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .@"try",
        .main_token = try_index,
        .data = .{
            .lhs = try self.addExtraData(Node.Try{
                .returns = switch (returns) {
                    .zero_one => |elem| elem,
                    .multi => |elems| try self.addExtraData(Node.Range{
                        .start = elems.start,
                        .end = elems.end,
                    }),
                },
                .expression = expr,
                .block_statement = block,
            }),
            .rhs = try self.addExtraData(try self.listToSpan(slice)),
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.catchClause)
pub fn expectCatchStatement(self: *Parser) ParserErrors!Node.Index {
    const catch_index = try self.expectToken(.keyword_catch);

    _ = self.consumeToken(.identifier);

    const body = body: {
        if (self.token_tags[self.token_index] == .l_paren) {
            const params = try self.parseParseDeclList();

            break :body params;
        } else break :body Span{ .zero_one = 0 };
    };

    const block = try self.expectBlock();

    return self.addNode(.{
        .tag = .@"catch",
        .main_token = catch_index,
        .data = .{
            .lhs = switch (body) {
                .zero_one => |elem| elem,
                .multi => |elems| try self.addExtraData(Node.Range{
                    .start = elems.start,
                    .end = elems.end,
                }),
            },
            .rhs = block,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.forStatement)
pub fn expectForStatement(self: *Parser) ParserErrors!Node.Index {
    const for_index = try self.expectToken(.keyword_for);

    _ = try self.expectToken(.l_paren);

    const first = try self.parseAssignExpr();
    try self.expectSemicolon();

    const two = try self.parseExpr();
    try self.expectSemicolon();

    const three = try self.parseExpr();

    _ = try self.expectToken(.r_paren);

    const then_expr = try self.expectStatement();

    return self.addNode(.{
        .tag = .@"for",
        .main_token = for_index,
        .data = .{
            .lhs = try self.addExtraData(Node.For{
                .condition_one = first,
                .condition_two = two,
                .condition_three = three,
            }),
            .rhs = then_expr,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.doWhileStatement)
pub fn expectDoStatement(self: *Parser) ParserErrors!Node.Index {
    const do_index = try self.expectToken(.keyword_do);
    const then_expr = try self.expectStatement();

    _ = try self.expectToken(.keyword_while);
    _ = try self.expectToken(.l_paren);

    const while_expr = try self.expectExpr();

    _ = try self.expectToken(.r_paren);

    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .do_while,
        .main_token = do_index,
        .data = .{
            .lhs = then_expr,
            .rhs = while_expr,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.whileStatement)
pub fn expectWhileStatement(self: *Parser) ParserErrors!Node.Index {
    const while_index = try self.expectToken(.keyword_while);
    _ = try self.expectToken(.l_paren);
    const expr = try self.expectExpr();
    _ = try self.expectToken(.r_paren);

    const then_expr = expr: {
        const block = try self.parseBlock();
        if (block != 0) break :expr block;

        const assign = try self.expectStatement();

        break :expr assign;
    };

    return self.addNode(.{
        .tag = .@"while",
        .main_token = while_index,
        .data = .{
            .lhs = expr,
            .rhs = then_expr,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.ifStatement)
pub fn expectIfStatement(self: *Parser) ParserErrors!Node.Index {
    const if_stmt = try self.expectToken(.keyword_if);
    _ = try self.expectToken(.l_paren);
    const expr = try self.expectExpr();
    _ = try self.expectToken(.r_paren);

    const then_expr = expr: {
        const block = try self.parseBlock();
        if (block != 0) break :expr block;

        const assign = try self.expectStatement();

        break :expr assign;
    };

    _ = self.consumeToken(.keyword_else) orelse {
        return self.addNode(.{
            .tag = .if_simple,
            .main_token = if_stmt,
            .data = .{
                .lhs = expr,
                .rhs = then_expr,
            },
        });
    };

    const else_stmt = try self.expectStatement();

    return self.addNode(.{
        .tag = .@"if",
        .main_token = if_stmt,
        .data = .{
            .lhs = expr,
            .rhs = try self.addExtraData(Node.If{
                .then_expression = then_expr,
                .else_expression = else_stmt,
            }),
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.emitStatement)
pub fn expectEmitStatement(self: *Parser) ParserErrors!Node.Index {
    const emit = try self.expectToken(.keyword_emit);

    const expr = try self.parseSuffixExpr();

    switch (self.nodes.items(.tag)[expr]) {
        .call_one,
        .call,
        => {},
        else => return self.fail(.expected_function_call),
    }

    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .emit,
        .main_token = emit,
        .data = .{
            .lhs = expr,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.returnStatement)
pub fn expectReturnStatement(self: *Parser) ParserErrors!Node.Index {
    const return_token = try self.expectToken(.keyword_return);

    const expr = try self.parseExpr();
    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .@"return",
        .main_token = return_token,
        .data = .{
            .lhs = expr,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.breakStatement)
pub fn expectBreakStatement(
    self: *Parser,
    is_yul: bool,
) ParserErrors!Node.Index {
    const break_token = try self.expectToken(.keyword_break);

    if (!is_yul)
        try self.expectSemicolon();

    return self.addNode(.{
        .tag = .@"break",
        .main_token = break_token,
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.continueStatement)
pub fn expectContinueStatement(
    self: *Parser,
    is_yul: bool,
) ParserErrors!Node.Index {
    const continue_token = try self.expectToken(.keyword_continue);

    if (!is_yul)
        try self.expectSemicolon();

    return self.addNode(.{
        .tag = .@"continue",
        .main_token = continue_token,
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.continueStatement)
pub fn expectLeaveStatement(self: *Parser) ParserErrors!Node.Index {
    const continue_token = try self.expectToken(.keyword_leave);

    return self.addNode(.{
        .tag = .leave,
        .main_token = continue_token,
        .data = .{
            .lhs = undefined,
            .rhs = undefined,
        },
    });
}
/// Parses the statement and if it finds a `ParserError` it will try to continue parsing
/// by trying to find the next statement.
pub fn expectStatementRecoverable(self: *Parser) ParserErrors!Node.Index {
    while (true) {
        return self.expectStatement() catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParsingError => {
                self.findNextStatement();
                switch (self.token_tags[self.token_index]) {
                    .r_brace => return null_node,
                    .eof => return err,
                    else => continue,
                }
            },
        };
    }
}
/// Expects a `statement` or it fails.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.statement)
pub fn expectStatement(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .keyword_if => return self.expectIfStatement(),
        .keyword_for => return self.expectForStatement(),
        .keyword_do => return self.expectDoStatement(),
        .keyword_while => return self.expectWhileStatement(),
        .keyword_try => return self.expectTryStatement(),
        .keyword_emit => return self.expectEmitStatement(),
        .keyword_return => return self.expectReturnStatement(),
        .keyword_continue => return self.expectContinueStatement(false),
        .keyword_break => return self.expectBreakStatement(false),
        .keyword_unchecked => {
            const token = self.nextToken();

            const block = try self.expectBlock();

            const unchecked = try self.addNode(.{
                .tag = .unchecked_block,
                .main_token = token,
                .data = .{
                    .lhs = block,
                    .rhs = undefined,
                },
            });

            return unchecked;
        },
        .keyword_assembly => return self.expectAssemblyStatement(),
        else => {},
    }

    const block = try self.parseBlock();

    if (block != 0)
        return block;

    const assign = try self.expectAssignExpr();
    try self.expectSemicolon();

    return assign;
}
/// Expects to find an expression or it will fail.
pub fn expectAssignExpr(self: *Parser) ParserErrors!Node.Index {
    const expr = try self.parseAssignExpr();

    if (expr == 0)
        return self.fail(.expected_statement);

    return expr;
}
/// expr <-
///      \ .assign_mul,
///      \ .assign_bit_and,
///      \ .assign_mod,
///      \ .assign_div,
///      \ .assign_add,
///      \ .assign_sub,
///      \ .assign_sar,
///      \ .assign_shr,
///      \ .assign_shl,
///      \ .assign_bit_or,
///      \ .assign_bit_xor,
///      \ .assign, .expr, .semicolon,
pub fn parseAssignExpr(self: *Parser) ParserErrors!Node.Index {
    const decl = decl: {
        const expr = try self.parseExpr();

        if (expr != 0)
            break :decl expr;

        break :decl try self.parseVariableDeclaration();
    };

    const tag = assignOperationNode(self.token_tags[self.token_index]) orelse
        return decl;

    if (tag == .yul_assign)
        return self.fail(.expected_expr);

    const node = try self.addNode(.{
        .tag = tag,
        .main_token = self.nextToken(),
        .data = .{
            .lhs = decl,
            .rhs = try self.expectExpr(),
        },
    });

    return node;
}
/// .variable_decl
/// \ .expr
/// <- .equal, .expr, .semicolon;
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.variableDeclarationStatement)
pub fn expectVariableDeclarationStatement(self: *Parser) ParserErrors!Node.Index {
    const decl = decl: {
        const var_decl = try self.parseVariableDeclaration();

        if (var_decl != 0)
            break :decl var_decl;

        break :decl try self.parseExpr();
    };

    if (decl == 0)
        return self.fail(.expected_statement);

    const equal = try self.expectToken(.equal);
    const rhs = try self.expectExpr();

    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .assign,
        .main_token = equal,
        .data = .{
            .lhs = decl,
            .rhs = rhs,
        },
    });
}
/// Parses the `PrimaryExpr` and the suffix and if its accessing an array or calling a method.
///
/// Example: [foo.bar(1 + 2, baz)]
pub fn parseSuffixExpr(self: *Parser) ParserErrors!Node.Index {
    var res = try self.parsePrimaryExpr();

    if (res == 0) return res;

    while (true) {
        const suffix = try self.parseSuffix(res);

        if (suffix != 0) {
            res = suffix;
            continue;
        }

        const call = try self.parseCallExpression(res);

        if (call == 0)
            return res;

        res = call;
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.callArgumentList)
pub fn parseCallExpression(
    self: *Parser,
    lhs: Node.Index,
) ParserErrors!Node.Index {
    const l_paren = self.consumeToken(.l_paren) orelse return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;

        const struct_init = try self.parseCurlySuffixExpr(0);

        if (struct_init != 0)
            try self.scratch.append(self.allocator, struct_init)
        else {
            const param = try self.expectExpr();
            try self.scratch.append(self.allocator, param);
        }

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon,
            .r_brace,
            .r_bracket,
            => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const params = self.scratch.items[scratch..];

    switch (params.len) {
        0 => return self.addNode(.{
            .tag = .call_one,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = .call_one,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = params[0],
            },
        }),
        else => return self.addNode(.{
            .tag = .call,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = try self.addExtraData(try self.listToSpan(params)),
            },
        }),
    }
}
/// Suffix
///     <- .l_bracket, expr?, r_bracket
///      / .dot identifier
///      / .minus_minus
///      / .plus_plus
///      / .l_brace, struct elems, r_brace
pub fn parseSuffix(
    self: *Parser,
    lhs: Node.Index,
) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .l_bracket => {
            const bracket = self.nextToken();
            const expr = try self.parseSuffixExpr();
            _ = try self.expectToken(.r_bracket);

            return self.addNode(.{
                .tag = .array_access,
                .main_token = bracket,
                .data = .{
                    .lhs = lhs,
                    .rhs = expr,
                },
            });
        },
        .period => switch (self.token_tags[self.token_index + 1]) {
            .identifier => return self.addNode(.{
                .tag = .field_access,
                .main_token = self.nextToken(),
                .data = .{
                    .lhs = lhs,
                    .rhs = self.nextToken(),
                },
            }),
            else => {
                self.token_index += 1;
                try self.warn(.expected_suffix);

                return null_node;
            },
        },
        .minus_minus => return self.addNode(.{
            .tag = .decrement,
            .main_token = self.nextToken(),
            .data = .{
                .lhs = lhs,
                .rhs = undefined,
            },
        }),
        .plus_plus => return self.addNode(.{
            .tag = .increment,
            .main_token = self.nextToken(),
            .data = .{
                .lhs = lhs,
                .rhs = undefined,
            },
        }),
        .l_brace => return self.parseCurlySuffixExpr(lhs),
        else => return null_node,
    }
}
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.callArgumentList)
pub fn parseCurlySuffixExpr(self: *Parser, lhs: Node.Index) ParserErrors!Node.Index {
    const l_brace = self.consumeToken(.l_brace) orelse return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_brace)) |_| break;
        _ = try self.expectToken(.identifier);

        if (self.token_tags[self.token_index] != .colon)
            return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .colon },
            });

        _ = self.nextToken();
        const params = try self.expectExpr();
        try self.scratch.append(self.allocator, params);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_brace)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_brace => {
                self.token_index += 1;
                break;
            },
            .colon,
            .semicolon,
            .r_bracket,
            => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_brace },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    switch (slice.len) {
        0 => return self.addNode(.{
            .tag = .struct_init_one,
            .main_token = l_brace,
            .data = .{
                .lhs = lhs,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = .struct_init_one,
            .main_token = l_brace,
            .data = .{
                .lhs = lhs,
                .rhs = slice[0],
            },
        }),
        else => return self.addNode(.{
            .tag = .struct_init,
            .main_token = l_brace,
            .data = .{
                .lhs = lhs,
                .rhs = try self.addExtraData(try self.listToSpan(slice)),
            },
        }),
    }
}
/// Expects an expression if it's a null node it will return an error.
pub fn expectExpr(self: *Parser) ParserErrors!Node.Index {
    const expr = try self.parseExpr();

    if (expr == 0)
        return self.fail(.expected_expr);

    return expr;
}
/// Parses an expression if it can find it or returns a null node.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.expression)
pub fn parseExpr(self: *Parser) ParserErrors!Node.Index {
    return self.parseExprPrecedence(0);
}
/// Parses expression based on precedence.
///
/// Example: foo + bar * baz
pub fn parseExprPrecedence(
    self: *Parser,
    min_precedence: i32,
) ParserErrors!Node.Index {
    std.debug.assert(min_precedence >= 0);

    var node = try self.parsePrefixExpr();

    if (node == 0)
        return null_node;

    var banned_precedence: i8 = -1;

    while (true) {
        const token_tag = self.token_tags[self.token_index];
        const info = oper_table[@as(usize, @intCast(@intFromEnum(token_tag)))];

        if (info.precedence < min_precedence)
            break;

        if (info.precedence == banned_precedence)
            return self.fail(.chained_comparison_operators);

        const oper_token = self.nextToken();

        const rhs = try self.parseExprPrecedence(info.precedence + 1);

        if (rhs == 0) {
            try self.warn(.expected_expr);
            return node;
        }

        node = if (info.association == .right) try self.addNode(.{
            .tag = info.tag,
            .main_token = oper_token,
            .data = .{
                .lhs = rhs,
                .rhs = node,
            },
        }) else try self.addNode(.{
            .tag = info.tag,
            .main_token = oper_token,
            .data = .{
                .lhs = node,
                .rhs = rhs,
            },
        });

        if (info.association == .none)
            banned_precedence = info.precedence;
    }

    return node;
}
/// PrimaryExpr
///     <- .keyword_new, expr?, r_bracket
///      / .keyword_type
///      / .keyword_payable
///      / .identifier
///      / .number_literal,
///      / .string_literal,
///      / .l_paren, (expression?, comma?)*, .r_param
///      / .l_bracket, (expression?, comma?)*, .r_bracket
pub fn parsePrimaryExpr(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .keyword_new => {
            const new = self.nextToken();
            const type_expr = try self.expectTypeExpr();

            return self.addNode(.{
                .tag = .new_decl,
                .main_token = new,
                .data = .{
                    .lhs = type_expr,
                    .rhs = undefined,
                },
            });
        },
        .keyword_type => {
            const type_key = self.nextToken();
            _ = try self.expectToken(.l_paren);
            const type_expr = try self.expectTypeExpr();

            _ = try self.expectToken(.r_paren);

            return self.addNode(.{
                .tag = .type_decl,
                .main_token = type_key,
                .data = .{
                    .lhs = type_expr,
                    .rhs = undefined,
                },
            });
        },
        .keyword_payable => {
            const payable = self.nextToken();
            _ = try self.expectToken(.l_paren);
            const expr = try self.parseSuffixExpr();

            _ = try self.expectToken(.r_paren);

            return self.addNode(.{
                .tag = .payable_decl,
                .main_token = payable,
                .data = .{
                    .lhs = expr,
                    .rhs = undefined,
                },
            });
        },
        .number_literal => {
            switch (self.token_tags[self.token_index + 1]) {
                .keyword_gwei,
                .keyword_wei,
                .keyword_hours,
                .keyword_seconds,
                .keyword_minutes,
                .keyword_ether,
                .keyword_days,
                .keyword_weeks,
                .keyword_years,
                => return self.addNode(.{
                    .tag = .number_literal_sub_denomination,
                    .main_token = self.nextToken(),
                    .data = .{
                        .lhs = self.nextToken(),
                        .rhs = undefined,
                    },
                }),
                else => return self.addNode(.{
                    .tag = .number_literal,
                    .main_token = self.nextToken(),
                    .data = .{
                        .rhs = undefined,
                        .lhs = undefined,
                    },
                }),
            }
        },
        .string_literal => return self.addNode(.{
            .tag = .string_literal,
            .main_token = self.nextToken(),
            .data = .{
                .rhs = undefined,
                .lhs = undefined,
            },
        }),
        .l_paren => {
            const index = self.nextToken();
            const scratch = self.scratch.items.len;
            defer self.scratch.shrinkRetainingCapacity(scratch);

            while (true) {
                if (self.consumeToken(.r_paren)) |_| break;

                const expr = try self.parseExpr();

                if (expr != 0)
                    try self.scratch.append(self.allocator, expr);

                switch (self.token_tags[self.token_index]) {
                    .comma => self.token_index += 1,
                    .r_paren => {
                        self.token_index += 1;
                        break;
                    },

                    .colon, .r_brace, .r_bracket => return self.failMsg(.{
                        .tag = .expected_token,
                        .token = self.token_index,
                        .extra = .{ .expected_tag = .r_paren },
                    }),
                    else => try self.warn(.expected_comma_after),
                }
            }

            const exprs = self.scratch.items[scratch..];

            return switch (exprs.len) {
                0 => self.addNode(.{
                    .tag = .tuple_init_one,
                    .main_token = index,
                    .data = .{
                        .lhs = 0,
                        .rhs = self.token_index - 1,
                    },
                }),
                1 => self.addNode(.{
                    .tag = .tuple_init_one,
                    .main_token = index,
                    .data = .{
                        .lhs = exprs[0],
                        .rhs = self.token_index - 1,
                    },
                }),
                else => self.addNode(.{
                    .tag = .tuple_init,
                    .main_token = index,
                    .data = .{
                        .lhs = try self.addExtraData(try self.listToSpan(exprs)),
                        .rhs = self.token_index - 1,
                    },
                }),
            };
        },
        .l_bracket => {
            const index = self.nextToken();
            const scratch = self.scratch.items.len;
            defer self.scratch.shrinkRetainingCapacity(scratch);

            while (true) {
                if (self.consumeToken(.r_bracket)) |_| break;
                const expr = try self.parseExpr();

                if (expr != 0)
                    try self.scratch.append(self.allocator, expr);

                switch (self.token_tags[self.token_index]) {
                    .comma => {
                        if (self.token_tags[self.token_index + 1] == .r_bracket)
                            try self.warn(.trailing_comma);

                        self.token_index += 1;
                    },
                    .r_bracket => {
                        self.token_index += 1;
                        break;
                    },

                    .colon, .r_brace, .r_paren => return self.failMsg(.{
                        .tag = .expected_token,
                        .token = self.token_index,
                        .extra = .{ .expected_tag = .r_bracket },
                    }),
                    else => try self.warn(.expected_comma_after),
                }
            }

            const exprs = self.scratch.items[scratch..];

            return switch (exprs.len) {
                0 => self.addNode(.{
                    .tag = .array_init_one,
                    .main_token = index,
                    .data = .{
                        .lhs = 0,
                        .rhs = self.token_index - 1,
                    },
                }),
                1 => self.addNode(.{
                    .tag = .array_init_one,
                    .main_token = index,
                    .data = .{
                        .lhs = exprs[0],
                        .rhs = self.token_index - 1,
                    },
                }),
                else => self.addNode(.{
                    .tag = .array_init,
                    .main_token = index,
                    .data = .{
                        .lhs = try self.addExtraData(try self.listToSpan(exprs)),
                        .rhs = self.token_index - 1,
                    },
                }),
            };
        },
        else => return self.parseVariableDeclaration(),
    }
}
/// Expects a PrefixExpr or returns an error.
pub fn expectPrefixExpr(self: *Parser) ParserErrors!Node.Index {
    const node = try self.parsePrefixExpr();

    if (node == 0) {
        return self.fail(.expected_prefix_expr);
    }

    return node;
}
/// PrefixExpr
///     <- .bang
///      / .minus_minus
///      / .plus_plus
///      / .keyword_delete
///      / .tilde,
///      / . PrimaryExpr,
pub fn parsePrefixExpr(self: *Parser) ParserErrors!Node.Index {
    const tag: Node.Tag = switch (self.token_tags[self.token_index]) {
        .bang => .conditional_not,
        .minus => .negation,
        .minus_minus => .decrement_front,
        .plus_plus => .increment_front,
        .keyword_delete => .delete,
        .tilde => .bit_not,
        else => return self.parseSuffixExpr(),
    };

    return self.addNode(.{
        .tag = tag,
        .main_token = self.nextToken(),
        .data = .{
            .lhs = try self.expectPrefixExpr(),
            .rhs = undefined,
        },
    });
}
/// .keyword_type, .identifier, .keyword_as, .type_expr
pub fn parseUserTypeDefinition(self: *Parser) ParserErrors!Node.Index {
    const keyword = self.consumeToken(.keyword_type) orelse return null_node;
    const identifier = try self.expectToken(.identifier);

    _ = try self.expectToken(.keyword_is);

    const elem_type = try self.consumeElementaryType();

    if (elem_type == 0)
        return self.fail(.expected_type_expr);

    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .user_defined_type,
        .main_token = keyword,
        .data = .{
            .lhs = identifier,
            .rhs = elem_type,
        },
    });
}
/// .keyword_error, .identifier, .l_paren, (error_param?), .r_paren
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.errorDefinition)
pub fn parseError(self: *Parser) ParserErrors!Node.Index {
    const err = try self.expectToken(.keyword_error);

    const error_index = try self.reserveNode(.error_proto_multi);
    errdefer self.unreserveNode(error_index);

    const identifier = try self.expectToken(.identifier);
    const params = try self.parseErrorParamDecls();
    try self.expectSemicolon();

    return switch (params) {
        .zero_one => |elem| return self.setNode(error_index, .{
            .tag = .error_proto_simple,
            .main_token = err,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| return self.setNode(error_index, .{
            .tag = .error_proto_multi,
            .main_token = err,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.Range{
                    .start = elems.start,
                    .end = elems.end,
                }),
            },
        }),
    };
}
/// Parses all `error_variable_decl` nodes and returns the total amount of it.
pub fn parseErrorParamDecls(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;
        const field = try self.expectErrorParam();

        if (field != 0)
            try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `error_variable_decl` orelse it will fail.
pub fn expectErrorParam(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseErrorParam();

    if (field == 0)
        return self.fail(.expected_error_param);

    return field;
}
/// .TYPE, .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.errorParameter)
pub fn parseErrorParam(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.expectTypeExpr();
    const identifier = self.consumeToken(.identifier) orelse null_node;

    return self.addNode(.{
        .tag = .error_variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = identifier,
            .rhs = 0,
        },
    });
}
/// .keyword_event, .identifier, .l_paren, (event_variable_decl_list)?, .r_paren, .keyword_anonymous
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.eventDefinition)
pub fn parseEvent(self: *Parser) ParserErrors!Node.Index {
    const event = try self.expectToken(.keyword_event);

    const event_index = try self.reserveNode(.event_proto_multi);
    errdefer self.unreserveNode(event_index);

    const identifier = try self.expectToken(.identifier);

    const params = try self.parseEventParamDecls();

    const anonymous = self.consumeToken(.keyword_anonymous) orelse null_node;
    try self.expectSemicolon();

    return switch (params) {
        .zero_one => |elem| return self.setNode(event_index, .{
            .tag = .event_proto_simple,
            .main_token = event,
            .data = .{
                .lhs = try self.addExtraData(Node.EventProtoOne{
                    .params = elem,
                    .anonymous = anonymous,
                }),
                .rhs = identifier,
            },
        }),
        .multi => |elems| return self.setNode(event_index, .{
            .tag = .event_proto_multi,
            .main_token = event,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.EventProto{
                    .params_start = elems.start,
                    .params_end = elems.end,
                    .anonymous = anonymous,
                }),
            },
        }),
    };
}
/// Parses all `event_variable_decl` nodes and returns the total amount of it.
pub fn parseEventParamDecls(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;
        const field = try self.expectEventParam();

        if (field != 0)
            try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `event_variable_decl` orelse it will fail.
pub fn expectEventParam(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseEventParam();

    if (field == 0)
        return self.fail(.expected_event_param);

    return field;
}
/// .TYPE, .keyword_indexed?, .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.eventParameter)
pub fn parseEventParam(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.expectTypeExpr();
    const indexed = self.consumeToken(.keyword_indexed) orelse null_node;
    const identifier = self.consumeToken(.identifier) orelse null_node;

    return self.addNode(.{
        .tag = .event_variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = indexed,
            .rhs = identifier,
        },
    });
}
/// .keyword_struct, .identifier, .l_brace, (struct_field_list), .r_brace
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.structDefinition)
pub fn parseStruct(self: *Parser) ParserErrors!Node.Index {
    const struct_token = try self.expectToken(.keyword_struct);
    const identifier = try self.expectToken(.identifier);

    const fields = try self.parseStructFields();

    return switch (fields) {
        .zero_one => |elem| self.addNode(.{
            .tag = .struct_decl_one,
            .main_token = struct_token,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| self.addNode(.{
            .tag = .struct_decl,
            .main_token = struct_token,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(Node.Range{
                    .start = elems.start,
                    .end = elems.end,
                }),
            },
        }),
    };
}
/// Parses all `struct_field` nodes and returns the total amount of it.
pub fn parseStructFields(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_brace);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        while (self.consumeToken(.doc_comment_container)) |_| {}
        while (try self.consumeDocComments()) |_| {}

        if (self.consumeToken(.r_brace)) |_| break;

        const field = try self.expectStructField();

        if (field != 0)
            try self.scratch.append(self.allocator, field);
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}
/// Expects to find a `struct_field` orelse it will fail.
pub fn expectStructField(self: *Parser) ParserErrors!Node.Index {
    const field = try self.parseStructField();

    if (field == 0)
        return self.fail(.expected_struct_field);

    return field;
}
/// .TYPE, .identifier, .semicolon
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.structMember)
pub fn parseStructField(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.expectTypeExpr();
    const identifier = try self.expectToken(.identifier);
    try self.expectSemicolon();

    return self.addNode(.{
        .tag = .struct_field,
        .main_token = type_expr,
        .data = .{
            .lhs = undefined,
            .rhs = identifier,
        },
    });
}

/// .l_paren, .param_decl, .r_paren
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.parameterList)
pub fn parseParseDeclList(self: *Parser) ParserErrors!Span {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;

        const param = try self.expectVariableParamDeclaration();

        if (param != 0)
            try self.scratch.append(self.allocator, param);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon, .r_brace, .r_bracket => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const params = self.scratch.items[scratch..];

    return switch (params.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = params[0] },
        else => Span{ .multi = try self.listToSpan(params) },
    };
}
/// Fails if no variable declaration is found.
pub fn expectVariableParamDeclaration(self: *Parser) ParserErrors!Node.Index {
    const variable = try self.parseVariableDeclaration();

    if (variable == 0)
        return self.fail(.expected_variable_decl);

    return variable;
}
/// .type_expr <- .storage_modifier? <- .identifier?
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.variableDeclaration)
pub fn parseVariableDeclaration(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.parseTypeExpr();
    const storage = self.consumeStorageLocation() orelse null_node;
    const identifier = self.consumeToken(.identifier) orelse null_node;

    if (type_expr == 0 and storage == 0 and identifier == 0)
        return null_node;

    return self.addNode(.{
        .tag = .variable_decl,
        .main_token = type_expr,
        .data = .{
            .lhs = storage,
            .rhs = identifier,
        },
    });
}
/// Parses a type expression or fails.
pub fn expectTypeExpr(self: *Parser) ParserErrors!Node.Index {
    const type_expr = try self.parseTypeExpr();

    if (type_expr == 0)
        return self.fail(.expected_type_expr);

    return type_expr;
}
/// / .elementary_type
/// / .keyword_mapping
/// / .identifier_path
/// / .function_proto
/// / TYPE, .l_bracket, expression, .r_bracket
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.typeName)
pub fn parseTypeExpr(self: *Parser) ParserErrors!Node.Index {
    const type_expr = switch (self.token_tags[self.token_index]) {
        .keyword_function => try self.parseFunctionType(),
        .keyword_mapping => try self.parseMapping(),
        .identifier => try self.consumeIdentifierPath(),
        else => try self.consumeElementaryType(),
    };

    if (type_expr == 0)
        return type_expr;

    if (self.token_tags[self.token_index] != .l_bracket)
        return type_expr;

    const l_brace = self.token_index;

    const expr = try self.parseExpr();

    return self.addNode(.{
        .tag = .array_type,
        .main_token = l_brace,
        .data = .{
            .lhs = type_expr,
            .rhs = expr,
        },
    });
}
/// .keyword_function <- (?param_decl list) <- ?visibility <- ?mutability <- ?returns <- ?(param_decl list)
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.functionTypeName)
pub fn parseFunctionType(self: *Parser) ParserErrors!Node.Index {
    const function = self.consumeToken(.keyword_function) orelse return null_node;

    const fn_index = try self.reserveNode(.function_proto);
    errdefer self.unreserveNode(fn_index);

    const param_list = try self.parseParseDeclList();
    const visibility = self.consumeVisibilityModifier() orelse null_node;
    const mutability = self.consumeStateMutability() orelse null_node;

    const returns = self.consumeToken(.keyword_returns) orelse null_node;

    if (returns != 0) {
        const return_params = try self.parseParseDeclList();

        return switch (param_list) {
            .zero_one => |param| self.setNode(fn_index, .{
                .tag = .function_type_one,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProtoTypeOne{
                        .param = param,
                        .visibility = visibility,
                        .mutability = mutability,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| if (r_param == 0) return self.fail(.expected_return_type) else try self.addExtraData(Node.Range{
                            .start = r_param,
                            .end = r_param,
                        }),
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
            .multi => |params| self.setNode(fn_index, .{
                .tag = .function_type,
                .main_token = function,
                .data = .{
                    .lhs = try self.addExtraData(Node.FnProtoType{
                        .mutability = mutability,
                        .visibility = visibility,
                        .params_start = params.start,
                        .params_end = params.end,
                    }),
                    .rhs = switch (return_params) {
                        .zero_one => |r_param| if (r_param == 0) return self.fail(.expected_return_type) else try self.addExtraData(Node.Range{
                            .start = r_param,
                            .end = r_param,
                        }),
                        .multi => |r_params| try self.addExtraData(r_params),
                    },
                },
            }),
        };
    }

    return switch (param_list) {
        .zero_one => |param| self.setNode(fn_index, .{
            .tag = .function_type_simple,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProtoTypeOne{
                    .param = param,
                    .visibility = visibility,
                    .mutability = mutability,
                }),
                .rhs = returns,
            },
        }),
        .multi => |params| self.setNode(fn_index, .{
            .tag = .function_type_multi,
            .main_token = function,
            .data = .{
                .lhs = try self.addExtraData(Node.FnProtoType{
                    .mutability = mutability,
                    .visibility = visibility,
                    .params_start = params.start,
                    .params_end = params.end,
                }),
                .rhs = returns,
            },
        }),
    };
}
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
        return self.failMsg(.{
            .tag = .expected_pragma_version,
            .token = pragma,
            .extra = .{ .expected_tag = .number_literal },
        });

    return self.addNode(.{
        .tag = .pragma_directive,
        .main_token = pragma,
        .data = .{
            .lhs = start,
            .rhs = end,
        },
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
            .caret,
            => {
                self.token_index += 1;
                _ = try self.expectToken(.number_literal);
            },
            .number_literal => self.token_index += 1,
            .period => self.token_index += 1,
            else => break self.token_index,
        }
    };

    return end;
}
/// keyword_import
///     <- .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
///      \ .string_literal (path)
///         \ semicolon
///         \ keyword_as <- identifier <- semicolon
///     \ .l_brace <- (Symbols)* <- .r_brace <- .identifier (from) <- .string_literal (path)
///
/// Import [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.importDirective)
pub fn parseImportDirective(self: *Parser) ParserErrors!Node.Index {
    const import = self.consumeToken(.keyword_import) orelse return null_node;

    switch (self.token_tags[self.token_index]) {
        .asterisk => return self.parseImportAsterisk(import),
        .l_brace => return self.parseImportSymbol(import),
        .string_literal => return self.parseImportPath(import),
        else => return self.fail(.expected_import_path_alias_asterisk),
    }
}
/// .asterisk <- keyword_as <- identifier <- identifier (from) <- string_literal (path)
pub fn parseImportAsterisk(
    self: *Parser,
    import: TokenIndex,
) ParserErrors!Node.Index {
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
            .data = .{ .lhs = literal, .rhs = 0 },
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
        else => return self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_tag = .semicolon },
        }),
    }
}
/// Symbols <- .identifier <- .string_literal
pub fn parseImportSymbol(
    self: *Parser,
    import: Node.Index,
) ParserErrors!Node.Index {
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

    while (true) {
        const identifier = try self.expectToken(.identifier);
        try self.scratch.append(self.allocator, identifier);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_brace)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_brace => {
                self.token_index += 1;
                break;
            },
            .colon, .r_bracket, .r_paren => return self.failMsg(.{
                .tag = .expected_r_brace,
                .token = self.token_index,
            }),
            else => try self.warn(.expected_comma_after),
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
            .tag = .enum_decl_one,
            .data = .{
                .lhs = name,
                .rhs = identifier,
            },
        }),
        .multi => |identifiers| return self.addNode(.{
            .main_token = main,
            .tag = .enum_decl,
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
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.identifierPath)
pub fn parseIdentifierPath(
    self: *Parser,
    lhs: Node.Index,
) Allocator.Error!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .period => switch (self.token_tags[self.token_index + 1]) {
            .identifier => return self.addNode(.{
                .tag = .field_access,
                .main_token = self.nextToken(),
                .data = .{
                    .lhs = lhs,
                    .rhs = self.nextToken(),
                },
            }),
            else => {
                self.token_index += 1;
                try self.warn(.expected_suffix);

                return null_node;
            },
        },
        else => return null_node,
    }
}
/// .keyword_mapping <- .l_paren <- .mapping_elements <- .equal_bracket_right <- .mapping_elements <- .r_paren <- (if not nested).semicolon;
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.mappingType)
pub fn parseMapping(self: *Parser) ParserErrors!Node.Index {
    const mapping = try self.expectToken(.keyword_mapping);
    _ = try self.expectToken(.l_paren);

    const mapping_index = try self.reserveNode(.mapping_decl);
    errdefer self.unreserveNode(mapping_index);

    const child_one = try self.parseMappingTypes();

    if (child_one == 0)
        return self.fail(.expected_elementary_or_identifier_path);

    _ = self.consumeToken(.identifier);
    _ = try self.expectToken(.equal_bracket_right);

    const child_two = try self.parseTypeExpr();

    if (child_two == 0)
        return self.fail(.expected_type_expr);

    _ = try self.expectToken(.r_paren);
    _ = self.consumeToken(.identifier);

    return self.setNode(mapping_index, .{
        .tag = .mapping_decl,
        .main_token = mapping,
        .data = .{
            .lhs = child_one,
            .rhs = child_two,
        },
    });
}
/// Mapping types
///     <- .elementary_type
///      / .identifier_path (.identifier, .period, .identifier ...)
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.mappingKeyType)
pub fn parseMappingTypes(self: *Parser) Allocator.Error!Node.Index {
    const elementary_type = try self.consumeElementaryType();

    if (elementary_type == 0)
        return self.consumeIdentifierPath();

    return elementary_type;
}
/// .identifier, .period, .identifier ...
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.identifierPath)
pub fn consumeIdentifierPath(self: *Parser) Allocator.Error!Node.Index {
    var identifier = self.consumeToken(.identifier) orelse return null_node;

    const node = try self.addNode(.{
        .tag = .identifier,
        .main_token = identifier,
        .data = .{
            .rhs = undefined,
            .lhs = undefined,
        },
    });

    if (self.token_tags[self.token_index] != .period)
        return node;

    while (true) {
        const suffix = try self.parseIdentifierPath(node);

        if (suffix != 0) {
            identifier = suffix;
            continue;
        }

        return identifier;
    }
}
/// Consume a solidity primary type.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.elementaryTypeName)
pub fn consumeElementaryType(self: *Parser) Allocator.Error!Node.Index {
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
        => self.addNode(.{
            .tag = .elementary_type,
            .main_token = self.nextToken(),
            .data = .{
                .rhs = undefined,
                .lhs = undefined,
            },
        }),
        else => null_node,
    };
}
/// Consume visibility modifiers.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.visibility)
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
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.stateMutability)
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
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.dataLocation)
pub fn consumeStorageLocation(self: *Parser) ?TokenIndex {
    return switch (self.token_tags[self.token_index]) {
        .keyword_memory,
        .keyword_storage,
        .keyword_calldata,
        .keyword_payable,
        => self.nextToken(),
        else => null,
    };
}
/// Consumes all doc_comment tokens.
pub fn consumeDocComments(self: *Parser) Allocator.Error!?TokenIndex {
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

// Yul parser

/// Expects to parse a assembly statement. Fails if it can't
pub fn expectAssemblyStatement(self: *Parser) ParserErrors!Node.Index {
    const node = try self.parseAssemblyStatement();

    if (node == 0)
        return self.fail(.expected_statement);

    return node;
}
/// Parses a solidity assembly_decl with the evm flags if present and the yul statements.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.assemblyStatement)
pub fn parseAssemblyStatement(self: *Parser) ParserErrors!Node.Index {
    const evm_asm = self.consumeToken(.keyword_assembly) orelse
        return null_node;

    // Consume "evmasm" string_literal
    _ = self.consumeToken(.string_literal);

    const asm_flags = try self.parseAssemblyFlags();

    const block = try self.parseAssemblyBlock();

    return self.addNode(.{
        .tag = .assembly_decl,
        .main_token = evm_asm,
        .data = .{
            .lhs = asm_flags,
            .rhs = block,
        },
    });
}
/// Parses the assembly string flags.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.assemblyFlags)
pub fn parseAssemblyFlags(self: *Parser) ParserErrors!Node.Index {
    const l_paren = self.consumeToken(.l_paren) orelse
        return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        const flag = try self.expectToken(.string_literal);
        try self.scratch.append(self.allocator, flag);

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => break,
            .colon, .r_bracket, .r_brace => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const r_paren = try self.expectToken(.r_paren);
    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .main_token = l_paren,
        .tag = .assembly_flags,
        .data = .{
            .lhs = try self.addExtraData(try self.listToSpan(slice)),
            .rhs = r_paren,
        },
    });
}
/// Expects to parse an assembly block if not it will fail.
pub fn expectAssemblyBlock(self: *Parser) ParserErrors!Node.Index {
    const node = try self.parseAssemblyBlock();

    if (node == 0)
        return self.fail(.expected_yul_statement);

    return node;
}
/// Parses an assembly block statement.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulBlock)
pub fn parseAssemblyBlock(self: *Parser) ParserErrors!Node.Index {
    const l_brace = self.consumeToken(.l_brace) orelse
        return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_brace)) |_| break;

        const statement = try self.expectYulStatementRecoverable();

        if (statement == 0)
            break;

        try self.scratch.append(self.allocator, statement);
    }

    const statements = self.scratch.items[scratch..];

    switch (statements.len) {
        0 => return self.addNode(.{
            .tag = .asm_block_two,
            .main_token = l_brace,
            .data = .{
                .lhs = 0,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = .asm_block_two,
            .main_token = l_brace,
            .data = .{
                .lhs = statements[0],
                .rhs = 0,
            },
        }),
        2 => return self.addNode(.{
            .tag = .asm_block_two,
            .main_token = l_brace,
            .data = .{
                .lhs = statements[0],
                .rhs = statements[1],
            },
        }),
        else => {
            const span = try self.listToSpan(statements);

            return self.addNode(.{
                .tag = .asm_block,
                .main_token = l_brace,
                .data = .{
                    .lhs = span.start,
                    .rhs = span.end,
                },
            });
        },
    }
}
/// Parses the statement and if it finds a `ParserError` it will try to continue parsing
/// by trying to find the next statement.
pub fn expectYulStatementRecoverable(self: *Parser) ParserErrors!Node.Index {
    while (true) {
        return self.expectYulStatement() catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParsingError => {
                self.findNextStatement();
                switch (self.token_tags[self.token_index]) {
                    .r_brace => return null_node,
                    .eof => return err,
                    else => continue,
                }
            },
        };
    }
}
/// Expects a `yul_statement` or it fails.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulStatement)
pub fn expectYulStatement(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .keyword_if => return self.expectYulIfStatement(),
        .keyword_for => return self.expectYulForStatement(),
        .reserved_switch => return self.expectYulSwitchStatement(),
        .reserved_let => return self.expectYulVariableDeclaration(),
        .keyword_leave => return self.expectLeaveStatement(),
        .keyword_continue => return self.expectContinueStatement(true),
        .keyword_break => return self.expectBreakStatement(true),
        .keyword_function => return self.expectYulFunctionDecl(),
        else => {},
    }

    const block = try self.parseAssemblyBlock();

    if (block != 0)
        return block;

    const assign = try self.expectYulAssignExpr();

    return assign;
}
/// Expects to find an yul assignment statement or it will fail.
pub fn expectYulAssignExpr(self: *Parser) ParserErrors!Node.Index {
    const expr = try self.parseYulAssignExpr();

    if (expr == 0)
        return self.fail(.expected_yul_statement);

    return expr;
}
/// Parses a yul assignment statement.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulExpression)
pub fn parseYulAssignExpr(self: *Parser) ParserErrors!Node.Index {
    const decl = try self.parseYulExpr();

    switch (self.token_tags[self.token_index]) {
        .comma => {
            const scratch = self.scratch.items.len;
            defer self.scratch.shrinkRetainingCapacity(scratch);

            try self.scratch.append(self.allocator, decl);
            _ = self.nextToken();

            while (true) {
                const yul_path = try self.consumeIdentifierPath();

                if (yul_path == 0)
                    return self.fail(.expected_yul_expression);

                try self.scratch.append(self.allocator, yul_path);

                switch (self.token_tags[self.token_index]) {
                    .comma => self.token_index += 1,
                    else => break,
                }
            }

            const main = self.nextToken();
            const tag = assignOperationNode(self.token_tags[main]) orelse
                return self.fail(.expected_yul_assignment);

            if (tag != .yul_assign)
                return self.fail(.expected_yul_assignment);

            const identifier = self.consumeToken(.identifier) orelse
                return self.fail(.expected_yul_function_call);

            const node = try self.addNode(.{
                .tag = .identifier,
                .main_token = identifier,
                .data = .{
                    .rhs = undefined,
                    .lhs = undefined,
                },
            });

            const slice = self.scratch.items[scratch..];

            return self.addNode(.{
                .tag = .yul_assign_multi,
                .main_token = main,
                .data = .{
                    .lhs = try self.addExtraData(try self.listToSpan(slice)),
                    .rhs = try self.parseYulCallExpression(node),
                },
            });
        },
        else => {
            const tag = assignOperationNode(self.token_tags[self.token_index]) orelse
                return decl;

            if (tag != .yul_assign)
                return self.fail(.expected_yul_assignment);

            return self.addNode(.{
                .tag = tag,
                .main_token = self.nextToken(),
                .data = .{
                    .lhs = decl,
                    .rhs = try self.expectYulExpr(),
                },
            });
        },
    }
}
/// Expects to find a yul expression
pub fn expectYulExpr(self: *Parser) ParserErrors!Node.Index {
    const node = try self.parseYulExpr();

    if (node == 0)
        return self.fail(.expected_yul_expression);

    return node;
}
/// Parses a yul expression.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulExpression)
pub fn parseYulExpr(self: *Parser) ParserErrors!Node.Index {
    switch (self.token_tags[self.token_index]) {
        .identifier => switch (self.token_tags[self.token_index + 1]) {
            .period => return self.consumeIdentifierPath(),
            .l_paren => {
                const node = try self.addNode(.{
                    .tag = .identifier,
                    .main_token = self.nextToken(),
                    .data = .{
                        .rhs = undefined,
                        .lhs = undefined,
                    },
                });

                return self.parseYulCallExpression(node);
            },
            else => return self.addNode(.{
                .tag = .identifier,
                .main_token = self.nextToken(),
                .data = .{
                    .rhs = undefined,
                    .lhs = undefined,
                },
            }),
        },
        .number_literal => return self.addNode(.{
            .tag = .number_literal,
            .main_token = self.nextToken(),
            .data = .{
                .rhs = undefined,
                .lhs = undefined,
            },
        }),
        .string_literal => return self.addNode(.{
            .tag = .string_literal,
            .main_token = self.nextToken(),
            .data = .{
                .rhs = undefined,
                .lhs = undefined,
            },
        }),
        .reserved_byte,
        .keyword_return,
        => switch (self.token_tags[self.token_index + 1]) {
            .l_paren => {
                const node = try self.addNode(.{
                    .tag = .identifier,
                    .main_token = self.nextToken(),
                    .data = .{
                        .rhs = undefined,
                        .lhs = undefined,
                    },
                });

                return self.parseYulCallExpression(node);
            },
            else => return self.addNode(.{
                .tag = .identifier,
                .main_token = self.nextToken(),
                .data = .{
                    .rhs = undefined,
                    .lhs = undefined,
                },
            }),
        },
        else => return null_node,
    }
}
/// Parses a yul function call expression.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulFunctionCall)
pub fn parseYulCallExpression(
    self: *Parser,
    lhs: Node.Index,
) ParserErrors!Node.Index {
    const l_paren = self.consumeToken(.l_paren) orelse return null_node;

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;

        try self.scratch.append(self.allocator, try self.expectYulExpr());

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon,
            .r_brace,
            .r_bracket,
            => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const params = self.scratch.items[scratch..];

    switch (params.len) {
        0 => return self.addNode(.{
            .tag = .yul_call_one,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = 0,
            },
        }),
        1 => return self.addNode(.{
            .tag = .yul_call_one,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = params[0],
            },
        }),
        else => return self.addNode(.{
            .tag = .yul_call,
            .main_token = l_paren,
            .data = .{
                .lhs = lhs,
                .rhs = try self.addExtraData(try self.listToSpan(params)),
            },
        }),
    }
}
/// Expects to parse a yul variable declaration.
pub fn expectYulVariableDeclaration(self: *Parser) ParserErrors!Node.Index {
    const node = try self.parseYulVariableDeclaration();

    if (node == 0)
        return self.fail(.expected_yul_statement);

    return node;
}
/// Parses a yul variable declaration expression.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulVariableDeclaration)
pub fn parseYulVariableDeclaration(self: *Parser) ParserErrors!Node.Index {
    const let = self.consumeToken(.reserved_let) orelse
        return null_node;

    const decl = try self.consumeIdentifierPath();

    if (decl == 0)
        return self.fail(.expected_yul_expression);

    switch (self.token_tags[self.token_index]) {
        .comma => {
            const scratch = self.scratch.items.len;
            defer self.scratch.shrinkRetainingCapacity(scratch);

            try self.scratch.append(self.allocator, decl);
            _ = self.nextToken();

            while (true) {
                const yul_path = try self.consumeIdentifierPath();

                if (yul_path == 0)
                    return self.fail(.expected_yul_expression);

                try self.scratch.append(self.allocator, yul_path);

                switch (self.token_tags[self.token_index]) {
                    .comma => self.token_index += 1,
                    else => break,
                }
            }

            const main = self.nextToken();
            const slice = self.scratch.items[scratch..];

            const tag = assignOperationNode(self.token_tags[main]) orelse {
                return self.addNode(.{
                    .tag = .yul_var_decl_multi,
                    .main_token = let,
                    .data = .{
                        .lhs = try self.addExtraData(try self.listToSpan(slice)),
                        .rhs = 0,
                    },
                });
            };

            if (tag != .yul_assign)
                return self.fail(.expected_yul_assignment);

            const identifier = self.consumeToken(.identifier) orelse
                return self.fail(.expected_yul_function_call);

            const node = try self.addNode(.{
                .tag = .identifier,
                .main_token = identifier,
                .data = .{
                    .rhs = undefined,
                    .lhs = undefined,
                },
            });

            return self.addNode(.{
                .tag = .yul_var_decl_multi,
                .main_token = let,
                .data = .{
                    .lhs = try self.addExtraData(try self.listToSpan(slice)),
                    .rhs = try self.parseYulCallExpression(node),
                },
            });
        },
        else => {
            const tag = assignOperationNode(self.token_tags[self.nextToken()]) orelse
                return self.addNode(.{
                .tag = .yul_var_decl,
                .main_token = let,
                .data = .{
                    .lhs = decl,
                    .rhs = 0,
                },
            });

            if (tag != .yul_assign)
                return self.fail(.expected_yul_assignment);

            return self.addNode(.{
                .tag = .yul_var_decl,
                .main_token = let,
                .data = .{
                    .lhs = decl,
                    .rhs = try self.expectYulExpr(),
                },
            });
        },
    }
}
/// Parses a yul if statement.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulIfStatement)
pub fn expectYulIfStatement(self: *Parser) ParserErrors!Node.Index {
    const if_ident = try self.expectToken(.keyword_if);

    const expression = try self.expectYulExpr();
    const block = try self.expectAssemblyBlock();

    return self.addNode(
        .{
            .tag = .yul_if,
            .main_token = if_ident,
            .data = .{
                .lhs = expression,
                .rhs = block,
            },
        },
    );
}
/// Parses a yul for statement.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulIfStatement)
pub fn expectYulForStatement(self: *Parser) ParserErrors!Node.Index {
    const for_iden = try self.expectToken(.keyword_for);

    const block_1 = try self.expectAssemblyBlock();
    const expression = try self.expectYulExpr();
    const block_2 = try self.expectAssemblyBlock();
    const block_3 = try self.expectAssemblyBlock();

    return self.addNode(
        .{
            .tag = .yul_for,
            .main_token = for_iden,
            .data = .{
                .lhs = try self.addExtraData(Node.For{
                    .condition_one = block_1,
                    .condition_two = expression,
                    .condition_three = block_2,
                }),
                .rhs = block_3,
            },
        },
    );
}
/// Parses a yul switch statement fails if it's not possible.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulSwitchStatement)
pub fn expectYulSwitchStatement(self: *Parser) ParserErrors!Node.Index {
    const switch_iden = try self.expectToken(.reserved_switch);
    const expression = try self.expectYulExpr();

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .reserved_default => {
                const token = self.nextToken();
                const node = try self.addNode(.{
                    .tag = .yul_switch_default,
                    .main_token = token,
                    .data = .{
                        .lhs = 0,
                        .rhs = try self.expectAssemblyBlock(),
                    },
                });

                try self.scratch.append(self.allocator, node);
                break;
            },
            .reserved_case => {
                const token = self.nextToken();
                const literal = self.nextToken();

                switch (self.token_tags[literal]) {
                    .number_literal,
                    .string_literal,
                    .identifier,
                    => {},
                    else => return self.fail(.expected_yul_literal),
                }

                const node = try self.addNode(.{
                    .tag = .yul_switch_case,
                    .main_token = token,
                    .data = .{
                        .lhs = literal,
                        .rhs = try self.expectAssemblyBlock(),
                    },
                });

                try self.scratch.append(self.allocator, node);
            },
            else => break,
        }
    }

    const slice = self.scratch.items[scratch..];

    return self.addNode(.{
        .tag = .yul_switch,
        .main_token = switch_iden,
        .data = .{
            .lhs = expression,
            .rhs = try self.addExtraData(try self.listToSpan(slice)),
        },
    });
}
/// Parses a yul function definition. Fails if it cannot.
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulFunctionDefinition)
pub fn expectYulFunctionDecl(self: *Parser) ParserErrors!Node.Index {
    const func = try self.expectToken(.keyword_function);
    const name = try self.expectToken(.identifier);

    const params = try self.parseYulFunctionParams();

    if (self.consumeToken(.arrow)) |_| {
        const returns = try self.parseYulReturnType();
        const body = try self.expectAssemblyBlock();

        return self.addNode(.{
            .tag = .yul_full_function_decl,
            .main_token = func,
            .data = .{
                .lhs = try self.addExtraData(Node.YulFullFnProto{
                    .identifier = name,
                    .params_start = params.start,
                    .params_end = params.end,
                    .returns_start = returns.start,
                    .returns_end = returns.end,
                }),
                .rhs = body,
            },
        });
    }

    const body = try self.expectAssemblyBlock();

    return self.addNode(.{
        .tag = .yul_function_decl,
        .main_token = func,
        .data = .{
            .lhs = try self.addExtraData(Node.YulFnProto{
                .identifier = name,
                .params_start = params.start,
                .params_end = params.end,
            }),
            .rhs = body,
        },
    });
}
/// .l_paren, .identifier, .r_paren
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulFunctionDefinition)
pub fn parseYulFunctionParams(self: *Parser) ParserErrors!Node.Range {
    _ = try self.expectToken(.l_paren);

    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.r_paren)) |_| break;

        try self.scratch.append(self.allocator, try self.expectToken(.identifier));

        switch (self.token_tags[self.token_index]) {
            .comma => {
                if (self.token_tags[self.token_index + 1] == .r_paren)
                    try self.warn(.trailing_comma);

                self.token_index += 1;
            },
            .r_paren => {
                self.token_index += 1;
                break;
            },
            .colon,
            .r_brace,
            .r_bracket,
            => return self.failMsg(.{
                .tag = .expected_token,
                .token = self.token_index,
                .extra = .{ .expected_tag = .r_paren },
            }),
            else => try self.warn(.expected_comma_after),
        }
    }

    const params = self.scratch.items[scratch..];

    return self.listToSpan(params);
}
/// loop -> .identifier
///
/// [Grammar](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.yulFunctionDefinition)
pub fn parseYulReturnType(self: *Parser) ParserErrors!Node.Range {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        try self.scratch.append(self.allocator, try self.expectToken(.identifier));

        switch (self.token_tags[self.token_index]) {
            .comma => self.token_index += 1,
            else => break,
        }
    }

    const params = self.scratch.items[scratch..];

    return self.listToSpan(params);
}

// Internal parser actions.

/// Checks if the given tokens are on the same line.
fn tokensOnSameLine(
    self: *Parser,
    token1: TokenIndex,
    token2: TokenIndex,
) bool {
    return std.mem.indexOfScalar(u8, self.source[self.token_starts[token1]..self.token_starts[token2]], '\n') == null;
}
/// Same as `consumeToken` but returns error instead.
fn expectToken(
    self: *Parser,
    token: Token.Tag,
) ParserErrors!TokenIndex {
    if (self.token_tags[self.token_index] != token) {
        return self.failMsg(.{
            .tag = .expected_token,
            .token = self.token_index,
            .extra = .{ .expected_tag = token },
        });
    }
    return self.nextToken();
}
/// Returns error if current token is not semicolon.
fn expectSemicolon(self: *Parser) ParserErrors!void {
    if (self.token_tags[self.token_index] != .semicolon) {
        return self.failMsg(.{
            .tag = .expected_semicolon,
            .token = self.token_index,
        });
    }
    _ = self.nextToken();
    return;
}
/// Advances the parser index if the token matches else return null
fn consumeToken(self: *Parser, token: Token.Tag) ?TokenIndex {
    return if (self.token_tags[self.token_index] == token) self.nextToken() else null;
}
/// Advances the parser index and returns old.
fn nextToken(self: *Parser) TokenIndex {
    const index = self.token_index;
    self.token_index += 1;

    return index;
}

// Node actions.

/// Adds the extra data struct type into the `extra_data` arraylist.
fn addExtraData(
    self: *Parser,
    extra: anytype,
) Allocator.Error!Node.Index {
    const fields = std.meta.fields(@TypeOf(extra));

    try self.extra_data.ensureUnusedCapacity(self.allocator, fields.len);
    const result: u32 = @intCast(self.extra_data.items.len);

    inline for (fields) |field| {
        comptime std.debug.assert(field.type == Node.Index);
        self.extra_data.appendAssumeCapacity(@field(extra, field.name));
    }

    return result;
}
/// Converts a slice into a `Range`
fn listToSpan(
    self: *Parser,
    list: []const Node.Index,
) Allocator.Error!Node.Range {
    try self.extra_data.appendSlice(self.allocator, list);

    return .{
        .start = @as(Node.Index, @intCast(self.extra_data.items.len - list.len)),
        .end = @as(Node.Index, @intCast(self.extra_data.items.len)),
    };
}
/// Tries to find the next statemetn based on the current token.
fn findNextStatement(self: *Parser) void {
    var depth: u32 = 0;

    while (true) {
        const token = self.nextToken();
        switch (self.token_tags[token]) {
            .l_brace => depth += 1,
            .r_brace => {
                if (depth == 0) {
                    self.token_index -= 1;
                    return;
                }
            },
            .semicolon => {
                if (depth == 0)
                    return;
            },
            .eof => {
                self.token_index -= 1;
                return;
            },
            else => {},
        }
    }
}
/// Tries to find the next source element based on the current token.
fn findNextSource(self: *Parser) void {
    var depth: u32 = 0;

    while (true) {
        const token = self.nextToken();
        switch (self.token_tags[token]) {
            .keyword_pragma,
            .keyword_import,
            .keyword_type,
            .keyword_abstract,
            .keyword_contract,
            .keyword_library,
            .keyword_interface,
            .keyword_function,
            .keyword_error,
            .keyword_event,
            .keyword_using,
            => {
                if (depth == 0) {
                    self.token_index -= 1;
                    return;
                }
            },
            .comma, .semicolon => {
                // this decl was likely meant to end here
                if (depth == 0) {
                    return;
                }
            },
            .l_paren, .l_bracket, .l_brace => depth += 1,
            .r_paren, .r_bracket => {
                if (depth != 0) depth -= 1;
            },
            .r_brace => {
                if (depth == 0) {
                    // end of container, exit
                    self.token_index -= 1;
                    return;
                }
                depth -= 1;
            },
            .eof => {
                self.token_index -= 1;
                return;
            },
            else => {
                if (self.token_index + 1 >= self.token_tags.len)
                    return;

                switch (self.token_tags[self.token_index + 1]) {
                    .keyword_constant,
                    => {
                        if (depth == 0)
                            return;
                    },
                    else => {},
                }
            },
        }
    }
}
/// Tries to find the next contract element based on the current token.
fn findNextContractElement(self: *Parser) void {
    var depth: u32 = 0;

    while (true) {
        const token = self.nextToken();
        switch (self.token_tags[token]) {
            .keyword_constructor,
            .keyword_type,
            .keyword_function,
            .keyword_receive,
            .keyword_fallback,
            .keyword_modifier,
            .keyword_error,
            .keyword_event,
            .keyword_mapping,
            .keyword_using,
            => {
                if (depth == 0) {
                    self.token_index -= 1;
                    return;
                }
            },
            .comma, .semicolon => {
                // this decl was likely meant to end here
                if (depth == 0) {
                    return;
                }
            },
            .l_paren, .l_bracket, .l_brace => depth += 1,
            .r_paren, .r_bracket => {
                if (depth != 0) depth -= 1;
            },
            .r_brace => {
                if (depth == 0) {
                    // end of container, exit
                    self.token_index -= 1;
                    return;
                }
                depth -= 1;
            },
            .eof => {
                self.token_index -= 1;
                return;
            },
            else => {
                switch (self.token_tags[self.token_index + 1]) {
                    .keyword_public,
                    .keyword_private,
                    .keyword_internal,
                    .keyword_constant,
                    .keyword_override,
                    .keyword_immutable,
                    .period,
                    => {
                        if (depth == 0) {
                            return;
                        }
                    },
                    else => {},
                }
            },
        }
    }
}
/// Adds a node into the list.
fn addNode(
    self: *Parser,
    child: Node,
) Allocator.Error!Node.Index {
    const index = @as(Node.Index, @intCast(self.nodes.len));
    try self.nodes.append(self.allocator, child);

    return index;
}
/// Sets a node based on the provided index.
fn setNode(
    self: *Parser,
    index: usize,
    child: Node,
) Node.Index {
    self.nodes.set(index, child);

    return @as(Node.Index, @intCast(index));
}
/// Reserves a node index on the arraylist.
fn reserveNode(
    self: *Parser,
    tag: Ast.Node.Tag,
) Allocator.Error!usize {
    try self.nodes.resize(self.allocator, self.nodes.len + 1);
    self.nodes.items(.tag)[self.nodes.len - 1] = tag;
    return self.nodes.len - 1;
}
/// Unreserves the node and sets a empty node into it if the element is not in the end.
fn unreserveNode(
    self: *Parser,
    index: usize,
) void {
    if (self.nodes.len == index) {
        self.nodes.resize(self.allocator, self.nodes.len - 1) catch unreachable;
    } else {
        self.nodes.items(.tag)[index] = .unreachable_node;
        self.nodes.items(.main_token)[index] = self.token_index;
    }
}
/// Appends an error to the `errors` arraylist. Continue with parsing.
fn warn(
    self: *Parser,
    fail_tag: Ast.Error.Tag,
) Allocator.Error!void {
    @branchHint(.cold);

    try self.warnMessage(.{
        .tag = fail_tag,
        .token = self.token_index,
    });
}
/// Appends an error to the `errors` arraylist. Continue with parsing.
fn warnMessage(self: *Parser, message: Ast.Error) Allocator.Error!void {
    @branchHint(.cold);

    switch (message.tag) {
        .expected_semicolon,
        .expected_token,
        .expected_r_brace,
        .expected_comma_after,
        .same_line_doc_comment,
        .expected_suffix,
        .trailing_comma,
        .expected_source_unit_expr,
        .expected_return_type,
        .expected_statement,
        .expected_block_or_assignment_statement,
        .expected_type_expr,
        .expected_operator,
        .expected_contract_block,
        .expected_event_param,
        .expected_error_param,
        .expected_prefix_expr,
        .expected_struct_field,
        .expected_variable_decl,
        .expected_pragma_version,
        .expected_import_path_alias_asterisk,
        .expected_contract_element,
        .expected_else_or_semicolon,
        .expected_semicolon_or_lbrace,
        .expected_function_call,
        .expected_elementary_or_identifier_path,
        .expected_expr,
        .expected_yul_assignment,
        .expected_yul_expression,
        .expected_yul_function_call,
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
/// Appends an error to the `errors` arraylist and returns the error.
fn fail(
    self: *Parser,
    fail_tag: Ast.Error.Tag,
) ParserErrors {
    @branchHint(.cold);

    return self.failMsg(.{
        .tag = fail_tag,
        .token = self.token_index,
    });
}
/// Appends an error to the `errors` arraylist and returns the error.
fn failMsg(
    self: *Parser,
    message: Ast.Error,
) ParserErrors {
    @branchHint(.cold);
    try self.warnMessage(message);

    return error.ParsingError;
}
/// Converts assignment tokens into node tokens.
fn assignOperationNode(tag: Token.Tag) ?Node.Tag {
    return switch (tag) {
        .asterisk_equal => .assign_mul,
        .ampersand_equal => .assign_bit_and,
        .percent_equal => .assign_mod,
        .slash_equal => .assign_div,
        .plus_equal => .assign_add,
        .minus_equal => .assign_sub,
        .angle_bracket_right_angle_bracket_right_equal => .assign_sar,
        .angle_bracket_right_angle_bracket_right_angle_bracket_right_equal => .assign_shr,
        .angle_bracket_left_angle_bracket_left_equal => .assign_shl,
        .pipe_equal => .assign_bit_or,
        .caret_equal => .assign_bit_xor,
        .equal => .assign,
        .colon_equal => .yul_assign,
        else => null,
    };
}
