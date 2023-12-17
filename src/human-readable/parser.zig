const std = @import("std");
const testing = std.testing;
const abi = @import("../abi.zig");
const AbiParameter = @import("../abi_parameter.zig").AbiParameter;
const AbiEventParameter = @import("../abi_parameter.zig").AbiEventParameter;
const Alloc = std.mem.Allocator;
const Lexer = @import("lexer.zig").Lexer;
const StateMutability = @import("../state_mutability.zig").StateMutability;
const ParamErrors = @import("../param_type.zig").ParamErrors;
const ParamType = @import("../param_type.zig").ParamType;
const Tokens = @import("tokens.zig").Tag.SoliditySyntax;

pub const TokenList = std.MultiArrayList(struct {
    token_type: Tokens,
    start: u32,
    end: u32,
});

pub const ParseError = error{ InvalidDataLocation, UnexceptedToken, InvalidType, ExpectedCommaAfterParam, EmptyReturnParams } || ParamErrors;

const Parser = @This();

alloc: Alloc,
tokens: []const Tokens,
tokens_start: []const u32,
tokens_end: []const u32,
token_index: u32,
source: []const u8,

pub fn parseAbiProto(p: *Parser) !abi.Abi {
    var abi_list = std.ArrayList(abi.AbiItem).init(p.alloc);
    errdefer abi_list.deinit();

    while (true) {
        try abi_list.append(try p.parseAbiItemProto());

        if (p.tokens[p.token_index] == .EndOfFileToken) break;
    }

    return abi_list.toOwnedSlice();
}

pub fn parseAbiItemProto(p: *Parser) !abi.AbiItem {
    return switch (p.tokens[p.token_index]) {
        .Function => .{ .abiFunction = try p.parseFunctionFnProto() },
        .Event => .{ .abiEvent = try p.parseEventFnProto() },
        .Error => .{ .abiError = try p.parseErrorFnProto() },
        .Constructor => .{ .abiConstructor = try p.parseConstructorFnProto() },
        .Fallback => .{ .abiFallback = try p.parseFallbackFnProto() },
        .Receive => .{ .abiReceive = try p.parseReceiveFnProto() },
        inline else => error.UnexceptedToken,
    };
}

pub fn parseFunctionFnProto(p: *Parser) !abi.Function {
    _ = try p.expectToken(.Function);
    const name = p.parseIdentifier().?;

    _ = try p.expectToken(.OpenParen);

    const inputs: []const AbiParameter = if (p.tokens[p.token_index] == .ClosingParen) &.{} else try p.parseFuncParamsDecl();
    errdefer p.alloc.free(inputs);

    _ = try p.expectToken(.ClosingParen);

    try p.parseVisibility();

    const state: StateMutability = switch (p.tokens[p.token_index]) {
        .Payable => .payable,
        .View => .view,
        .Pure => .pure,
        inline else => .nonpayable,
    };

    if (state != .nonpayable) _ = p.nextToken();

    if (p.consumeToken(.Returns)) |_| {
        _ = try p.expectToken(.OpenParen);

        const outputs: []const AbiParameter = if (p.tokens[p.token_index] == .ClosingParen) return error.EmptyReturnParams else try p.parseFuncParamsDecl();
        errdefer p.alloc.free(outputs);

        _ = try p.expectToken(.ClosingParen);

        _ = try p.expectToken(.EndOfFileToken);

        return .{ .type = .function, .name = name, .inputs = inputs, .outputs = outputs, .stateMutability = state };
    }

    return .{ .type = .function, .name = name, .inputs = inputs, .outputs = &.{}, .stateMutability = state };
}

pub fn parseEventFnProto(p: *Parser) !abi.Event {
    _ = try p.expectToken(.Event);
    const name = p.parseIdentifier().?;

    _ = try p.expectToken(.OpenParen);

    const inputs: []const AbiEventParameter = if (p.tokens[p.token_index] == .ClosingParen) &.{} else try p.parseEventParamsDecl();
    errdefer p.alloc.free(inputs);

    _ = try p.expectToken(.ClosingParen);

    return .{ .type = .event, .inputs = inputs, .name = name };
}

pub fn parseErrorFnProto(p: *Parser) !abi.Error {
    _ = try p.expectToken(.Error);
    const name = p.parseIdentifier().?;

    _ = try p.expectToken(.OpenParen);

    const inputs: []const AbiParameter = if (p.tokens[p.token_index] == .ClosingParen) &.{} else try p.parseErrorParamsDecl();
    errdefer p.alloc.free(inputs);

    _ = try p.expectToken(.ClosingParen);

    return .{ .type = .@"error", .inputs = inputs, .name = name };
}

pub fn parseConstructorFnProto(p: *Parser) !abi.Constructor {
    _ = try p.expectToken(.Constructor);

    _ = try p.expectToken(.OpenParen);

    const inputs: []const AbiParameter = if (p.tokens[p.token_index] == .ClosingParen) &.{} else try p.parseFuncParamsDecl();
    errdefer p.alloc.free(inputs);

    _ = try p.expectToken(.ClosingParen);

    switch (p.tokens[p.token_index]) {
        .Payable => {
            if (p.tokens[p.token_index + 1] != .EndOfFileToken) return error.UnexceptedToken;

            return .{ .type = .constructor, .stateMutability = .payable, .inputs = inputs };
        },
        .EndOfFileToken => return .{ .type = .constructor, .stateMutability = .nonpayable, .inputs = inputs },

        inline else => return error.UnexceptedToken,
    }
}

pub fn parseFallbackFnProto(p: *Parser) !abi.Fallback {
    _ = try p.expectToken(.Fallback);
    _ = try p.expectToken(.OpenParen);
    _ = try p.expectToken(.ClosingParen);

    switch (p.tokens[p.token_index]) {
        .Payable => {
            if (p.tokens[p.token_index + 1] != .EndOfFileToken) return error.UnexceptedToken;

            return .{ .type = .fallback, .stateMutability = .payable };
        },
        .EndOfFileToken => return .{ .type = .fallback, .stateMutability = .nonpayable },
        inline else => return error.UnexceptedToken,
    }
}

pub fn parseReceiveFnProto(p: *Parser) !abi.Receive {
    _ = try p.expectToken(.Receive);
    _ = try p.expectToken(.OpenParen);
    _ = try p.expectToken(.ClosingParen);
    _ = try p.expectToken(.External);
    _ = try p.expectToken(.Payable);

    return .{ .type = .receive, .stateMutability = .payable };
}

pub fn parseFuncParamsDecl(p: *Parser) ![]const AbiParameter {
    var param_list = std.ArrayList(AbiParameter).init(p.alloc);
    errdefer param_list.deinit();

    while (true) {
        const tuple_param = if (p.consumeToken(.OpenParen) != null) try p.parseTuple(AbiParameter) else null;
        if (tuple_param != null) {
            try param_list.append(tuple_param.?);

            switch (p.tokens[p.token_index]) {
                .Comma => p.token_index += 1,
                .ClosingParen => break,
                .EndOfFileToken => break,
                inline else => return error.ExpectedCommaAfterParam,
            }

            continue;
        }

        const abitype = try p.parseTypeExpr();
        errdefer ParamType.freeArrayParamType(abitype, p.alloc);

        const location = p.parseDataLocation();
        if (location) |tok| {
            _ = p.consumeToken(tok);
            switch (tok) {
                .Indexed => return error.InvalidDataLocation,
                .Memory, .Calldata, .Storage => {
                    const isValid = switch (abitype) {
                        .string, .bytes => true,
                        .dynamicArray => true,
                        .fixedArray => true,
                        inline else => false,
                    };

                    if (!isValid) return error.InvalidDataLocation;
                },
                inline else => {},
            }
        }

        const name = p.parseIdentifier() orelse "";
        const param = .{ .type = abitype, .name = name, .internal_type = null, .components = null };

        try param_list.append(param);

        switch (p.tokens[p.token_index]) {
            .Comma => p.token_index += 1,
            .ClosingParen => break,
            .EndOfFileToken => break,
            inline else => return error.ExpectedCommaAfterParam,
        }
    }

    return try param_list.toOwnedSlice();
}

pub fn parseEventParamsDecl(p: *Parser) ![]const AbiEventParameter {
    var param_list = std.ArrayList(AbiEventParameter).init(p.alloc);
    errdefer param_list.deinit();

    while (true) {
        const tuple_param = if (p.consumeToken(.OpenParen) != null) try p.parseTuple(AbiEventParameter) else null;
        if (tuple_param != null) {
            try param_list.append(tuple_param.?);

            switch (p.tokens[p.token_index]) {
                .Comma => p.token_index += 1,
                .ClosingParen => break,
                .EndOfFileToken => break,
                inline else => return error.ExpectedCommaAfterParam,
            }

            continue;
        }

        const abitype = try p.parseTypeExpr();
        errdefer ParamType.freeArrayParamType(abitype, p.alloc);

        const location = p.parseDataLocation();
        const indexed = indexed: {
            if (location) |tok| {
                switch (tok) {
                    .Indexed => break :indexed true,
                    inline else => return error.InvalidDataLocation,
                }
            } else break :indexed false;
        };

        const name = p.parseIdentifier() orelse "";
        const param = .{ .type = abitype, .name = name, .indexed = indexed, .internal_type = null, .components = null };

        try param_list.append(param);

        switch (p.tokens[p.token_index]) {
            .Comma => p.token_index += 1,
            .ClosingParen => break,
            inline else => return error.ExpectedCommaAfterParam,
        }
    }

    return try param_list.toOwnedSlice();
}

fn parseErrorParamsDecl(p: *Parser) ParseError![]const AbiParameter {
    var param_list = std.ArrayList(AbiParameter).init(p.alloc);
    errdefer param_list.deinit();

    while (true) {
        const tuple_param = if (p.consumeToken(.OpenParen) != null) try p.parseTuple(AbiParameter) else null;
        if (tuple_param != null) {
            try param_list.append(tuple_param.?);

            switch (p.tokens[p.token_index]) {
                .Comma => p.token_index += 1,
                .ClosingParen => break,
                .EndOfFileToken => break,
                inline else => return error.ExpectedCommaAfterParam,
            }

            continue;
        }

        const abitype = try p.parseTypeExpr();
        errdefer ParamType.freeArrayParamType(abitype, p.alloc);

        const location = p.parseDataLocation();
        if (location != null) return error.InvalidDataLocation;

        const name = p.parseIdentifier() orelse "";
        const param: AbiParameter = .{ .type = abitype, .name = name, .internal_type = null, .components = null };

        try param_list.append(param);

        switch (p.tokens[p.token_index]) {
            .Comma => p.token_index += 1,
            .ClosingParen => break,
            .EndOfFileToken => break,
            inline else => return error.ExpectedCommaAfterParam,
        }
    }

    return try param_list.toOwnedSlice();
}

fn parseTuple(p: *Parser, comptime T: type) ParseError!T {
    const components = try p.parseErrorParamsDecl();
    errdefer p.alloc.free(components);

    _ = try p.expectToken(.ClosingParen);
    const start = p.token_index;
    const end = try p.parseArrayType();
    const array_slice = if (end) |arr| p.source[p.tokens_start[start]..p.tokens_end[arr]] else null;

    const type_name = try std.fmt.allocPrintZ(p.alloc, "tuple{s}", .{array_slice orelse ""});
    defer p.alloc.free(type_name);

    const abitype = try ParamType.typeToUnion(type_name, p.alloc);
    errdefer ParamType.freeArrayParamType(abitype, p.alloc);

    const location = p.parseDataLocation();
    const name = p.parseIdentifier() orelse "";

    return switch (T) {
        AbiParameter => {
            if (location != null) return error.InvalidDataLocation;
            return .{ .type = abitype, .name = name, .internal_type = null, .components = components };
        },
        AbiEventParameter => .{ .type = abitype, .name = name, .internal_type = null, .indexed = location == .Indexed, .components = components },
        inline else => error.InvalidType,
    };
}

fn parseTypeExpr(p: *Parser) !ParamType {
    const index = p.nextToken();
    const tok = p.tokens[index];

    if (tok.lexToken()) |type_name| {
        const slice = if (try p.parseArrayType()) |arr| p.source[p.tokens_start[index]..p.tokens_end[arr]] else type_name;

        return try ParamType.typeToUnion(slice, p.alloc);
    }

    return error.UnexceptedToken;
}

fn parseArrayType(p: *Parser) !?u32 {
    while (true) {
        const token = p.nextToken();

        switch (p.tokens[token]) {
            .OpenBracket => continue,
            .Number => {
                _ = try p.expectToken(.ClosingBracket);
                p.token_index -= 1;
            },
            .ClosingBracket => switch (p.tokens[p.token_index]) {
                .OpenBracket => continue,
                else => return token,
            },
            inline else => {
                p.token_index -= 1;
                return null;
            },
        }
    }
}

fn parseDataLocation(p: *Parser) ?Tokens {
    const tok = p.tokens[p.token_index];

    return switch (tok) {
        .Indexed, .Calldata, .Storage, .Memory => tok,
        inline else => null,
    };
}

fn parseVisibility(p: *Parser) !void {
    const external = p.consumeToken(.External) orelse 0;
    const public = p.consumeToken(.Public) orelse 0;

    if (external != 0 and public != 0) {
        return error.UnexceptedToken;
    }
}

fn parseIdentifier(p: *Parser) ?[]const u8 {
    return if (p.consumeToken(.Identifier)) |ident| p.source[p.tokens_start[ident]..p.tokens_end[ident]] else null;
}

fn expectToken(p: *Parser, expected: Tokens) !u32 {
    if (p.tokens[p.token_index] != expected) return error.UnexceptedToken;

    return p.nextToken();
}

fn consumeToken(p: *Parser, tok: Tokens) ?u32 {
    return if (p.tokens[p.token_index] == tok) p.nextToken() else null;
}

fn nextToken(p: *Parser) u32 {
    const index = p.token_index;
    p.token_index += 1;

    return index;
}

// test "Simple" {
//     var lex = Lexer.init("function Foo(address bar) view returns(address baz)");
//     var list = Parser.TokenList{};
//     defer list.deinit(testing.allocator);
//
//     while (true) {
//         const tok = lex.scan();
//         try list.append(testing.allocator, .{ .token_type = tok.syntax, .start = tok.location.start, .end = tok.location.end });
//
//         if (tok.syntax == .EndOfFileToken) break;
//     }
//
//     var parser: Parser = .{
//         .alloc = testing.allocator,
//         .tokens = list.items(.token_type),
//         .tokens_start = list.items(.start),
//         .tokens_end = list.items(.end),
//         .token_index = 0,
//         .source = lex.currentText,
//     };
//
//     const params = try parser.parseAbiProto();
//
//     std.debug.print("\nParsing signature: {s}\n", .{parser.source});
//     std.debug.print("FOOO: {any}\n", .{params});
// }
