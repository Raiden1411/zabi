const tokenizer = @import("../../ast/tokenizer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../ast/Parser.zig");
const Ast = @import("../../ast/Ast.zig");

test "Pragma" {
    var tokens: Ast.TokenList = .{};
    defer tokens.deinit(testing.allocator);

    var parser: Parser = undefined;
    defer parser.deinit();

    try buildParser("pragma solidity >=0.8.20 <=0.8.0;", &tokens, &parser);

    _ = try parser.parsePragmaDirective();
}

test "Import" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_path, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import \"foo/bar/baz\" as Baz;", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_path_identifier, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import * as console from \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_asterisk, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import {fooo, bar, bazz} from \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_symbol, parser.nodes.items(.tag)[import]);
    }
}

test "Enum" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum foo{bar, baz}", &tokens, &parser);

        const enum_tag = try parser.parseEnum();

        try testing.expectEqual(.container_decl, parser.nodes.items(.tag)[enum_tag]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum foo{bar, baz,}", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEnum());
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum{bar, baz}", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEnum());
    }
}

test "Mapping" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => mapping(uint => int)foo)bar;", &tokens, &parser);

        const mapping = try parser.parseMapping(false);

        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => mapping(uint => int)foo;)bar;", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping(false));
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => )bar;", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping(false));
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping( => uint )bar;", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping(false));
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => address)bar;", &tokens, &parser);

        const mapping = try parser.parseMapping(false);

        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => foo.bar)bar;", &tokens, &parser);

        const mapping = try parser.parseMapping(false);

        const data = parser.nodes.items(.data)[mapping];
        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
        try testing.expectEqual(.elementary_type, parser.nodes.items(.tag)[data.lhs]);
        try testing.expectEqual(.field_access, parser.nodes.items(.tag)[data.rhs]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(foo.bar => uint)bar;", &tokens, &parser);

        const mapping = try parser.parseMapping(false);

        const data = parser.nodes.items(.data)[mapping];
        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
        try testing.expectEqual(.field_access, parser.nodes.items(.tag)[data.lhs]);
    }
}

test "Function Type" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function() external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_proto_simple, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address bar) external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_proto_simple, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar, foo.bar calldata baz) external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_proto_multi, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar) external payable returns()", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_proto_one, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar, bar calldata baz) external payable returns(bool, string memory)", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_proto, parser.nodes.items(.tag)[fn_proto]);
    }
}

fn buildParser(source: [:0]const u8, tokens: *Ast.TokenList, parser: *Parser) !void {
    var lexer = tokenizer.Tokenizer.init(source);

    while (true) {
        const token = lexer.next();

        try tokens.append(testing.allocator, .{
            .tag = token.tag,
            .start = @intCast(token.location.start),
        });

        if (token.tag == .eof) break;
    }

    parser.* = .{
        .source = source,
        .allocator = testing.allocator,
        .token_index = 0,
        .token_tags = tokens.items(.tag),
        .token_starts = tokens.items(.start),
        .nodes = .{},
        .errors = .{},
        .scratch = .{},
        .extra_data = .{},
    };
}
