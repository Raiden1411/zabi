const std = @import("std");

const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const Node = Ast.Node;
const TokenIndex = Ast.TokenIndex;
const TokenTag = @import("tokens.zig").Tag.SoliditySyntax;

const Parser = @This();

/// Errors that can happing whilest parsing the source code.
pub const ParserErrors = error{ParsingError} || Allocator.Error;

const null_node: Node.Index = 0;

const Span = union(enum) {
    zero_one: Node.Index,
    multi: Node.Range,
};

allocator: Allocator,
source: [:0]const u8,
token_index: TokenIndex,
token_tags: []const TokenTag,
nodes: Ast.NodeList,
extra: std.ArrayListUnmanaged(Node.Index),
scratch: std.ArrayListUnmanaged(Node.Index),

pub fn deinit(self: *Parser) void {
    self.nodes.deinit(self.allocator);
    self.extra.deinit(self.allocator);
    self.scratch.deinit(self.allocator);
}

pub fn parseSource(self: *Parser) ParserErrors!void {
    try self.nodes.append(self.allocator, .{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });

    const members = try self.parseUnits();

    if (self.token_tags[self.token_index] != .EndOfFileToken)
        return error.ParsingError;

    self.nodes.items(.data)[0] = .{
        .lhs = members.start,
        .rhs = members.end,
    };
}

pub fn parseUnits(self: *Parser) ParserErrors!Node.Range {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .EndOfFileToken => break,
            else => {},
        }

        try self.scratch.append(self.allocator, try self.expectUnit());
    }

    const slice = self.scratch.items[scratch..];

    return self.listToSpan(slice);
}

pub fn expectUnit(self: *Parser) ParserErrors!Node.Index {
    const unit = try self.parseUnit();

    if (unit == 0)
        return error.ParsingError;

    return unit;
}

pub fn parseUnit(self: *Parser) ParserErrors!Node.Index {
    return switch (self.token_tags[self.token_index]) {
        .Function,
        .Fallback,
        .Receive,
        => self.parseFunctionProto(),
        .Constructor => self.parseConstructorProto(),
        .Event => self.parseEventProto(),
        .Error => self.parseErrorProto(),
        .Struct => self.parseStructDecl(),
        else => return null_node,
    };
}

pub fn parseFunctionProto(self: *Parser) ParserErrors!Node.Index {
    const keyword = self.consumeToken(.Function) orelse return null_node;

    const reserve = try self.reserveNode(.function_proto);
    errdefer self.unreserveNode(reserve);

    const identifier = switch (self.token_tags[self.token_index]) {
        .Identifier,
        .Fallback,
        .Receive,
        => self.nextToken(),
        else => return null_node,
    };

    _ = try self.expectToken(.OpenParen);

    const params = try self.parseVariableDecls();
    const specifiers = try self.parseSpecifiers();

    if (self.consumeToken(.Returns)) |_| {
        _ = try self.expectToken(.OpenParen);
        const returns = try self.parseReturnParams();

        return switch (params) {
            .zero_one => |elem| return self.setNode(reserve, .{
                .tag = .function_proto_one,
                .main_token = keyword,
                .data = .{
                    .lhs = try self.addExtraData(Node.FunctionProtoOne{
                        .specifiers = specifiers,
                        .identifier = identifier,
                        .param = elem,
                    }),
                    .rhs = try self.addExtraData(returns),
                },
            }),
            .multi => |elem| return self.setNode(reserve, .{
                .tag = .function_proto,
                .main_token = keyword,
                .data = .{
                    .lhs = try self.addExtraData(Node.FunctionProto{
                        .specifiers = specifiers,
                        .identifier = identifier,
                        .params_start = elem.start,
                        .params_end = elem.end,
                    }),
                    .rhs = try self.addExtraData(returns),
                },
            }),
        };
    }

    return switch (params) {
        .zero_one => |elem| return self.setNode(reserve, .{
            .tag = .function_proto_simple,
            .main_token = keyword,
            .data = .{
                .lhs = try self.addExtraData(Node.FunctionProtoSimple{
                    .identifier = identifier,
                    .param = elem,
                }),
                .rhs = specifiers,
            },
        }),
        .multi => |elem| return self.setNode(reserve, .{
            .tag = .function_proto_multi,
            .main_token = keyword,
            .data = .{
                .lhs = try self.addExtraData(Node.FunctionProtoMulti{
                    .identifier = identifier,
                    .params_start = elem.start,
                    .params_end = elem.end,
                }),
                .rhs = specifiers,
            },
        }),
    };
}

pub fn parseConstructorProto(self: *Parser) ParserErrors!Node.Index {
    const constructor_keyword = self.consumeToken(.Constructor) orelse return null_node;

    const reserve = try self.reserveNode(.constructor_proto_multi);
    errdefer self.unreserveNode(reserve);

    _ = try self.expectToken(.OpenParen);

    const params = try self.parseVariableDecls();

    const specifiers = try self.parseSpecifiers();

    return switch (params) {
        .zero_one => |elem| self.setNode(reserve, .{
            .tag = .constructor_proto_simple,
            .main_token = constructor_keyword,
            .data = .{
                .lhs = elem,
                .rhs = specifiers,
            },
        }),
        .multi => |elems| self.setNode(reserve, .{
            .tag = .constructor_proto_multi,
            .main_token = constructor_keyword,
            .data = .{
                .lhs = try self.addExtraData(elems),
                .rhs = specifiers,
            },
        }),
    };
}

pub fn parseSpecifiers(self: *Parser) Allocator.Error!Node.Index {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        switch (self.token_tags[self.token_index]) {
            .Public,
            .Pure,
            .Payable,
            .View,
            .Virtual,
            .Override,
            .Internal,
            .Private,
            .External,
            => try self.scratch.append(self.allocator, self.nextToken()),
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

pub fn parseErrorProto(self: *Parser) ParserErrors!Node.Index {
    const error_keyword = self.consumeToken(.Error) orelse return null_node;

    const reserve = try self.reserveNode(.error_proto_multi);
    errdefer self.unreserveNode(reserve);

    const identifier = try self.expectToken(.Identifier);

    _ = try self.expectToken(.OpenParen);

    const params = try self.parseErrorVarDecls();

    return switch (params) {
        .zero_one => |elem| self.setNode(reserve, .{
            .tag = .error_proto_simple,
            .main_token = error_keyword,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| self.setNode(reserve, .{
            .tag = .error_proto_multi,
            .main_token = error_keyword,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(elems),
            },
        }),
    };
}

pub fn parseEventProto(self: *Parser) ParserErrors!Node.Index {
    const event_keyword = self.consumeToken(.Event) orelse return null_node;

    const reserve = try self.reserveNode(.event_proto_multi);
    errdefer self.unreserveNode(reserve);

    const identifier = try self.expectToken(.Identifier);

    _ = try self.expectToken(.OpenParen);

    const params = try self.parseEventVarDecls();

    _ = self.consumeToken(.Anonymous);

    return switch (params) {
        .zero_one => |elem| self.setNode(reserve, .{
            .tag = .event_proto_simple,
            .main_token = event_keyword,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| self.setNode(reserve, .{
            .tag = .event_proto_multi,
            .main_token = event_keyword,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(elems),
            },
        }),
    };
}

pub fn parseEventVarDecls(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.ClosingParen)) |_| break;

        const field = try self.expectEventVarDecl();
        try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .Comma => {
                if (self.token_tags[self.token_index + 1] == .ClosingParen)
                    return error.ParsingError;
                self.token_index += 1;
            },
            .ClosingParen => {
                self.token_index += 1;
                break;
            },
            else => return error.ParsingError,
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}

pub fn parseErrorVarDecls(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.ClosingParen)) |_| break;

        const field = try self.expectErrorVarDecl();
        try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .Comma => {
                if (self.token_tags[self.token_index + 1] == .ClosingParen)
                    return error.ParsingError;
                self.token_index += 1;
            },
            .ClosingParen => {
                self.token_index += 1;
                break;
            },
            else => return error.ParsingError,
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}

pub fn parseReturnParams(self: *Parser) ParserErrors!Node.Range {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.ClosingParen)) |_| break;

        const field = try self.expectVarDecl();
        try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .Comma => {
                if (self.token_tags[self.token_index + 1] == .ClosingParen)
                    return error.ParsingError;
                self.token_index += 1;
            },
            .ClosingParen => {
                self.token_index += 1;
                break;
            },
            else => return error.ParsingError,
        }
    }

    const slice = self.scratch.items[scratch..];

    if (slice.len == 0)
        return error.ParsingError;

    return self.listToSpan(slice);
}

pub fn parseVariableDecls(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.ClosingParen)) |_| break;

        const field = try self.expectVarDecl();
        try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .Comma => {
                if (self.token_tags[self.token_index + 1] == .ClosingParen)
                    return error.ParsingError;
                self.token_index += 1;
            },
            .ClosingParen => {
                self.token_index += 1;
                break;
            },
            else => return error.ParsingError,
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}

pub fn expectErrorVarDecl(self: *Parser) ParserErrors!Node.Index {
    const index = try self.parseErrorVarDecl();

    if (index == 0)
        return error.ParsingError;

    return index;
}

pub fn parseErrorVarDecl(self: *Parser) ParserErrors!Node.Index {
    const sol_type = try self.parseType();

    if (sol_type == 0)
        return null_node;

    const identifier = try self.expectToken(.Identifier);

    return self.addNode(.{
        .tag = .error_var_decl,
        .main_token = identifier,
        .data = .{
            .lhs = sol_type,
            .rhs = undefined,
        },
    });
}

pub fn expectEventVarDecl(self: *Parser) ParserErrors!Node.Index {
    const index = try self.parseEventVarDecl();

    if (index == 0)
        return error.ParsingError;

    return index;
}

pub fn parseEventVarDecl(self: *Parser) ParserErrors!Node.Index {
    const sol_type = try self.parseType();

    if (sol_type == 0)
        return null_node;

    const modifier = switch (self.token_tags[self.token_index]) {
        .Indexed,
        => self.nextToken(),
        else => null_node,
    };

    const identifier = try self.expectToken(.Identifier);

    return self.addNode(.{
        .tag = .event_var_decl,
        .main_token = modifier,
        .data = .{
            .lhs = sol_type,
            .rhs = identifier,
        },
    });
}

pub fn expectVarDecl(self: *Parser) ParserErrors!Node.Index {
    const index = try self.parseVariableDecl();

    if (index == 0)
        return error.ParsingError;

    return index;
}

pub fn parseVariableDecl(self: *Parser) ParserErrors!Node.Index {
    const sol_type = try self.parseType();

    if (sol_type == 0)
        return null_node;

    const modifier = switch (self.token_tags[self.token_index]) {
        .Calldata,
        .Storage,
        .Memory,
        => self.nextToken(),
        else => null_node,
    };

    const identifier = self.consumeToken(.Identifier) orelse null_node;

    return self.addNode(.{
        .tag = .var_decl,
        .main_token = modifier,
        .data = .{
            .lhs = sol_type,
            .rhs = identifier,
        },
    });
}

pub fn parseStructDecl(self: *Parser) ParserErrors!Node.Index {
    const struct_index = self.consumeToken(.Struct) orelse return null_node;

    const reserve = try self.reserveNode(.struct_decl);
    errdefer self.unreserveNode(reserve);

    const identifier = try self.expectToken(.Identifier);

    _ = try self.expectToken(.OpenBrace);

    const fields = try self.parseStructFields();

    return switch (fields) {
        .zero_one => |elem| self.setNode(reserve, .{
            .tag = .struct_decl_one,
            .main_token = struct_index,
            .data = .{
                .lhs = identifier,
                .rhs = elem,
            },
        }),
        .multi => |elems| self.setNode(reserve, .{
            .tag = .struct_decl,
            .main_token = struct_index,
            .data = .{
                .lhs = identifier,
                .rhs = try self.addExtraData(elems),
            },
        }),
    };
}

pub fn parseStructFields(self: *Parser) ParserErrors!Span {
    const scratch = self.scratch.items.len;
    defer self.scratch.shrinkRetainingCapacity(scratch);

    while (true) {
        if (self.consumeToken(.ClosingBrace)) |_| break;

        const field = try self.expectStructField();
        try self.scratch.append(self.allocator, field);

        switch (self.token_tags[self.token_index]) {
            .ClosingBrace => {
                self.token_index += 1;
                break;
            },
            else => {},
        }
    }

    const slice = self.scratch.items[scratch..];

    return switch (slice.len) {
        0 => Span{ .zero_one = 0 },
        1 => Span{ .zero_one = slice[0] },
        else => Span{ .multi = try self.listToSpan(slice) },
    };
}

pub fn expectStructField(self: *Parser) ParserErrors!Node.Index {
    const field_type = try self.expectType();
    const identifier = try self.expectToken(.Identifier);

    _ = try self.expectToken(.SemiColon);

    return self.addNode(.{
        .tag = .struct_field,
        .main_token = identifier,
        .data = .{
            .lhs = field_type,
            .rhs = undefined,
        },
    });
}

pub fn expectType(self: *Parser) ParserErrors!Node.Index {
    const index = try self.parseType();

    if (index == 0)
        return error.ParsingError;

    return index;
}

pub fn parseType(self: *Parser) Allocator.Error!Node.Index {
    const sol_type = switch (self.token_tags[self.token_index]) {
        .Identifier => try self.addNode(.{
            .tag = .identifier,
            .main_token = self.nextToken(),
            .data = .{
                .lhs = undefined,
                .rhs = undefined,
            },
        }),
        else => self.consumeElementaryType(),
    };

    return sol_type;
}

pub fn consumeElementaryType(self: *Parser) Allocator.Error!Node.Index {
    return switch (self.token_tags[self.token_index]) {
        .Address,
        .Bool,
        .Tuple,
        .String,
        .Bytes,
        .Bytes1,
        .Bytes2,
        .Bytes3,
        .Bytes4,
        .Bytes5,
        .Bytes6,
        .Bytes7,
        .Bytes8,
        .Bytes9,
        .Bytes10,
        .Bytes11,
        .Bytes12,
        .Bytes13,
        .Bytes14,
        .Bytes15,
        .Bytes16,
        .Bytes17,
        .Bytes18,
        .Bytes19,
        .Bytes20,
        .Bytes21,
        .Bytes22,
        .Bytes23,
        .Bytes24,
        .Bytes25,
        .Bytes26,
        .Bytes27,
        .Bytes28,
        .Bytes29,
        .Bytes30,
        .Bytes31,
        .Bytes32,
        .Uint,
        .Uint8,
        .Uint16,
        .Uint24,
        .Uint32,
        .Uint40,
        .Uint48,
        .Uint56,
        .Uint64,
        .Uint72,
        .Uint80,
        .Uint88,
        .Uint96,
        .Uint104,
        .Uint112,
        .Uint120,
        .Uint128,
        .Uint136,
        .Uint144,
        .Uint152,
        .Uint160,
        .Uint168,
        .Uint176,
        .Uint184,
        .Uint192,
        .Uint200,
        .Uint208,
        .Uint216,
        .Uint224,
        .Uint232,
        .Uint240,
        .Uint248,
        .Uint256,
        .Int,
        .Int8,
        .Int16,
        .Int24,
        .Int32,
        .Int40,
        .Int48,
        .Int56,
        .Int64,
        .Int72,
        .Int80,
        .Int88,
        .Int96,
        .Int104,
        .Int112,
        .Int120,
        .Int128,
        .Int136,
        .Int144,
        .Int152,
        .Int160,
        .Int168,
        .Int176,
        .Int184,
        .Int192,
        .Int200,
        .Int208,
        .Int216,
        .Int224,
        .Int232,
        .Int240,
        .Int248,
        .Int256,
        => self.addNode(.{
            .tag = .elementary_type,
            .main_token = self.nextToken(),
            .data = .{
                .lhs = undefined,
                .rhs = undefined,
            },
        }),
        else => null_node,
    };
}
// Internal parser actions

fn consumeToken(self: *Parser, expected: TokenTag) ?TokenIndex {
    return if (self.token_tags[self.token_index] == expected) self.nextToken() else null;
}

fn expectToken(self: *Parser, expected: TokenTag) error{ParsingError}!TokenIndex {
    return if (self.token_tags[self.token_index] == expected) self.nextToken() else return error.ParsingError;
}

fn nextToken(self: *Parser) TokenIndex {
    const index = self.token_index;

    self.token_index += 1;

    return index;
}

// Node actions

/// Appends node to the list and returns the index.
fn addNode(self: *Parser, node: Node) Allocator.Error!Node.Index {
    const index = @as(Node.Index, @intCast(self.nodes.len));
    try self.nodes.append(self.allocator, node);

    return index;
}
/// Sets a node based on the provided index.
fn setNode(self: *Parser, index: usize, child: Node) Node.Index {
    self.nodes.set(index, child);

    return @as(Node.Index, @intCast(index));
}
/// Reserves a node index on the arraylist.
fn reserveNode(self: *Parser, tag: Ast.Node.Tag) Allocator.Error!usize {
    try self.nodes.resize(self.allocator, self.nodes.len + 1);
    self.nodes.items(.tag)[self.nodes.len - 1] = tag;
    return self.nodes.len - 1;
}
/// Unreserves the node and sets a empty node into it if the element is not in the end.
fn unreserveNode(self: *Parser, index: usize) void {
    if (self.nodes.len == index) {
        self.nodes.resize(self.allocator, self.nodes.len - 1) catch unreachable;
    } else {
        self.nodes.items(.tag)[index] = .unreachable_node;
        self.nodes.items(.main_token)[index] = self.token_index;
    }
}

fn addExtraData(self: *Parser, extra: anytype) Allocator.Error!Node.Index {
    const fields = std.meta.fields(@TypeOf(extra));

    try self.extra.ensureUnusedCapacity(self.allocator, fields.len);
    const result: u32 = @intCast(self.extra.items.len);

    inline for (fields) |field| {
        std.debug.assert(field.type == Node.Index);
        self.extra.appendAssumeCapacity(@field(extra, field.name));
    }

    return result;
}

fn listToSpan(self: *Parser, slice: []const Node.Index) Allocator.Error!Node.Range {
    try self.extra.appendSlice(self.allocator, slice);

    return Node.Range{
        .start = @as(Node.Index, @intCast(self.extra.items.len - slice.len)),
        .end = @as(Node.Index, @intCast(self.extra.items.len)),
    };
}
