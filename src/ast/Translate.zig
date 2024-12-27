const std = @import("std");

const Allocator = std.mem.Allocator;
const SolidityAst = @import("Ast.zig");
const Node = SolidityAst.Node;
const ArrayList = std.ArrayList(u8);

const Translator = @This();

/// Writer stream that applies auto indents and punctuation.
pub const PuncAndIndenStream = AutoPunctuationAndIndentStream(ArrayList.Writer);

/// Set of errors that can happen when running the translation.
pub const TranslateErrors = error{
    InvalidNode,
    UnsupportedExpressionNode,
    InvalidVariableDeclaration,
    InvalidFunctionType,
    ExpectedIdentifier,
} || Allocator.Error;

/// Solidity abstract syntax tree that will be used for translating.
ast: SolidityAst,
/// Writer that applies auto indents and punctuation.
writer: *PuncAndIndenStream,

/// Sets the initial state of the `Translator`.
pub fn init(solidity_ast: SolidityAst, list: *PuncAndIndenStream) Translator {
    return .{
        .ast = solidity_ast,
        .writer = list,
    };
}

/// Translates a solidity array type to a zig type.
pub fn translateArrayType(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];
    std.debug.assert(node_tag == .array_type);

    const array = self.ast.arrayType(node);
    const data = self.ast.nodes.items(.data);

    var current: Node.Index = array.ast.expr;

    while (true) {
        try self.writer.reset();
        switch (nodes[current]) {
            .array_init_one => {
                try self.writer.writer().writeByte('[');

                if (data[current].lhs == 0) {
                    try self.writer.writer().writeAll("]const");
                    self.writer.setPunctuation(.space);
                } else {
                    try self.renderLiteralNode(data[current].lhs);
                    try self.writer.writer().writeByte(']');
                }
                current = data[current].lhs;
            },
            .array_access => {
                try self.writer.writer().writeByte('[');

                if (data[current].rhs != 0) {
                    try self.renderLiteralNode(data[current].rhs);
                    try self.writer.writer().writeByte(']');
                } else {
                    try self.writer.writer().writeAll("]const");
                    self.writer.setPunctuation(.space);
                }

                current = data[current].lhs;
            },
            else => break,
        }
    }

    try self.writer.reset();
    return self.translateSolidityType(array.ast.type_expr);
}
/// Translates a solidity type into the zig representation of the type.
pub fn translateSolidityType(self: Translator, node: Node.Index) TranslateErrors!void {
    const node_tag = self.ast.nodes.items(.tag)[node];

    switch (node_tag) {
        .elementary_type => return self.translateElementaryType(node),
        .mapping_decl => return self.translateMappingType(node),
        .function_type_simple => return self.translateFunctionTypeSimple(node),
        .function_type_multi => return self.translateFunctionTypeMulti(node),
        .function_type_one => return self.translateFunctionTypeOne(node),
        .function_type => return self.translateFunctionType(node),
        .identifier => return self.renderLiteralNode(node),
        .field_access => return self.translateSolidityType(self.ast.nodes.items(.data)[node].lhs),
        .array_type => return self.translateArrayType(node),
        else => return error.InvalidNode,
    }
}
/// Translates the elementary types of solidity to zig ones.
pub fn translateElementaryType(self: Translator, node: Node.Index) Allocator.Error!void {
    const node_tag = self.ast.nodes.items(.tag)[node];
    const main = self.ast.nodes.items(.main_token)[node];

    std.debug.assert(node_tag == .elementary_type);

    const token_tags = self.ast.tokens.items(.tag);

    try self.writer.writer().writeAll(token_tags[main].translateToken().?);
}
/// Translates the `mapping` type into a zig `AutoHashMap`
pub fn translateMappingType(self: Translator, node: Node.Index) TranslateErrors!void {
    const node_tag = self.ast.nodes.items(.tag)[node];

    std.debug.assert(node_tag == .mapping_decl);

    const data = self.ast.nodes.items(.data)[node];

    try self.writer.writer().writeAll("std.AutoHashMap(");

    try self.translateSolidityType(data.lhs);
    self.writer.setPunctuation(.comma_space);

    try self.translateSolidityType(data.rhs);
    self.writer.setPunctuation(.none);

    try self.writer.writer().writeByte(')');
}
/// Translates a constant variable declaration of solidity to zig.
pub fn translateConstantVariableDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .constant_variable_decl);

    const variable = self.ast.constantVariableDecl(node);

    try self.writer.writer().writeAll("const");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(variable.name));

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte(':');

    self.writer.setPunctuation(.space);
    try self.translateSolidityType(variable.ast.type_token);
    try self.writer.writer().writeByte('=');

    switch (nodes[variable.ast.expression_node]) {
        .number_literal,
        .string_literal,
        .identifier,
        => try self.renderLiteralNode(variable.ast.expression_node),
        else => return error.UnsupportedExpressionNode,
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte(';');
}
/// Translates a solidity variable declaration to a zig one.
pub fn translateVariableDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .variable_decl);

    const decl = self.ast.variableDecl(node);

    const name = decl.name orelse return error.ExpectedIdentifier;

    try self.writer.writer().writeAll(self.ast.tokenSlice(name));
    self.writer.setPunctuation(.none);

    try self.writer.writer().writeByte(':');

    self.writer.setPunctuation(.space);
    try self.translateSolidityType(decl.ast.type_expr);
}
/// Translates a solidity enum to a zig one.
pub fn translateEnum(self: Translator, node: Node.Index) TranslateErrors!void {
    switch (self.ast.nodes.items(.tag)[node]) {
        .enum_decl => return self.translateEnumDecl(node),
        .enum_decl_one => return self.translateEnumDeclOne(node),
        else => return error.InvalidNode,
    }
}
/// Translates a solidity enum with a single member to a zig one.
pub fn translateEnumDeclOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .enum_decl_one);

    var buffer: [1]Node.Index = undefined;
    const enum_decl = self.ast.enumDeclOne(&buffer, node);

    try self.writer.writer().writeAll("const");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(enum_decl.name));
    try self.writer.writer().writeByte('=');
    try self.writer.writer().writeAll("enum {\n");

    self.writer.pushIndentation();
    self.writer.setPunctuation(.none);
    for (enum_decl.fields) |field| {
        defer self.writer.setPunctuation(.comma_newline);
        try self.writer.writer().writeAll(self.ast.tokenSlice(field));
    }
    self.writer.popIndentation();

    try self.writer.reset();
    try self.writer.writer().writeAll("};");
}
/// Translates a solidity enum with multiple members to a zig one.
pub fn translateEnumDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .enum_decl);
    const enum_decl = self.ast.enumDecl(node);

    try self.writer.writer().writeAll("const");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(enum_decl.name));
    try self.writer.writer().writeByte('=');
    try self.writer.writer().writeAll("enum {\n");

    self.writer.pushIndentation();
    self.writer.setPunctuation(.none);

    for (enum_decl.fields) |field| {
        defer self.writer.setPunctuation(.comma_newline);
        try self.writer.writer().writeAll(self.ast.tokenSlice(field));
    }

    self.writer.popIndentation();

    try self.writer.reset();
    try self.writer.writer().writeAll("};");
}
/// Translates a solidity struct to a zig one.
pub fn translateStruct(self: Translator, node: Node.Index) TranslateErrors!void {
    switch (self.ast.nodes.items(.tag)[node]) {
        .struct_decl => return self.translateStructDecl(node),
        .struct_decl_one => return self.translateStructDeclOne(node),
        else => return error.InvalidNode,
    }
}
/// Translates a solidity struct with a single member to a zig one.
pub fn translateStructDeclOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .struct_decl_one);
    defer self.writer.setPunctuation(.none);

    var buffer: [1]Node.Index = undefined;
    const struct_decl = self.ast.structDeclOne(&buffer, node);

    try self.writer.writer().writeAll("const");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(struct_decl.name));
    try self.writer.writer().writeByte('=');
    try self.writer.writer().writeAll("struct {\n");

    self.writer.setPunctuation(.none);
    for (struct_decl.ast.fields) |field| {
        try self.translateStructField(field);
    }

    try self.writer.writer().writeAll("};");
}
/// Translates a solidity struct with multiple members to a zig one.
pub fn translateStructDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .struct_decl);
    const struct_decl = self.ast.structDecl(node);

    try self.writer.writer().writeAll("const");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(struct_decl.name));
    try self.writer.writer().writeByte('=');
    try self.writer.writer().writeAll("struct {\n");

    self.writer.setPunctuation(.none);
    for (struct_decl.ast.fields) |field| {
        try self.translateStructField(field);
        try self.writer.reset();
    }

    try self.writer.writer().writeAll("};");
}
/// Translates a solidity struct field to a zig one.
pub fn translateStructField(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .struct_field);

    self.writer.pushIndentation();
    const data = self.ast.nodes.items(.data)[node];

    try self.writer.writer().writeAll(self.ast.tokenSlice(data.rhs));
    self.writer.popIndentation();

    try self.writer.writer().writeByte(':');
    self.writer.setPunctuation(.space);

    try self.translateSolidityType(self.ast.nodes.items(.main_token)[node]);
    self.writer.setPunctuation(.comma_newline);
}
/// Translates a solidity function type independent of the node. Can fail
/// if the index leads to a unsupported type node.
pub fn translateFunctionType(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    switch (node_tag) {
        .function_type => return self.translateFullFunctionType(node),
        .function_type_one => return self.translateFunctionTypeOne(node),
        .function_type_simple => return self.translateFunctionTypeSimple(node),
        .function_type_multi => return self.translateFunctionTypeMulti(node),
        else => return error.InvalidFunctionType,
    }
}
/// Translates a solidity function type with multiple params and tuple of return params to a zig one.
pub fn translateFullFunctionType(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionTypeProto(&buffer, node);

    try self.writer.writer().writeAll("?*const fn(");

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    self.writer.setPunctuation(.space);

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.translateSolidityType(decl.ast.type_expr);

        return self.writer.setPunctuation(.none);
    }

    try self.writer.writer().writeAll("struct { ");

    self.writer.setPunctuation(.none);
    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);
        defer self.writer.setPunctuation(.comma_space);

        try self.translateSolidityType(decl.ast.type_expr);
    }

    self.writer.setPunctuation(.space);
    try self.writer.reset();
    try self.writer.writer().writeByte('}');
}
/// Translates a solidity function type with a single param and a tuple of return params to a zig one.
pub fn translateFunctionTypeOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_one);

    var buffer: [2]Node.Index = undefined;
    const function = self.ast.functionTypeProtoOne(&buffer, node);

    try self.writer.writer().writeAll("?*const fn(");

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.none);
        try self.translateVariableDecl(param);
    }

    try self.writer.writer().writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    self.writer.setPunctuation(.space);

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.translateSolidityType(decl.ast.type_expr);

        return self.writer.setPunctuation(.none);
    }

    try self.writer.writer().writeAll("struct{ ");

    self.writer.setPunctuation(.none);
    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);
        defer self.writer.setPunctuation(.comma_space);

        try self.translateSolidityType(decl.ast.type_expr);
    }

    self.writer.setPunctuation(.space);
    try self.writer.reset();
    try self.writer.writer().writeByte('}');
}
/// Translates a solidity function type with a single param and void returns to a zig one.
pub fn translateFunctionTypeSimple(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_simple);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionTypeProtoSimple(&buffer, node);

    try self.writer.writer().writeAll("?*const fn(");

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeAll(") void");
}
/// Translates a solidity function type with multiple params and void return to a zig one.
pub fn translateFunctionTypeMulti(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_multi);

    const function = self.ast.functionTypeMulti(node);

    try self.writer.writer().writeAll("?*const fn(");

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeAll(") void");
}
/// Translates a solidity function proto or declaration to a zig one.
pub fn translateFunction(self: Translator, node: Node.Index) TranslateErrors!void {
    switch (self.ast.nodes.items(.tag)[node]) {
        .function_proto_simple => return self.translateFunctionProtoSimple(node),
        .function_proto_multi => return self.translateFunctionProtoMulti(node),
        .function_proto_one => return self.translateFunctionProtoOne(node),
        .function_proto => return self.translateFunctionProto(node),
        .function_decl => return self.translateFunction(self.ast.nodes.items(.data)[node].lhs),
        else => return error.InvalidNode,
    }
}
/// Translates a solidity function proto with a multiple params and a tuple of return params to a zig one.
pub fn translateFunctionProto(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_proto);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionProto(&buffer, node);

    if (!self.isCallableFunction(function.ast.specifiers))
        return;

    const readable = self.isReadableFunction(function.ast.specifiers);

    try self.writer.writer().writeAll("pub fn");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(function.name));

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte('(');

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    if (!readable) {
        try self.writer.writer().writeAll("overrides: UnpreparedEnvelope");
        self.writer.setPunctuation(.none);
        try self.writer.writer().writeByte(')');

        self.writer.setPunctuation(.space_bang);
        return self.writer.writer().writeAll("Hash");
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    self.writer.setPunctuation(.space_bang);
    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);

        try self.writer.writer().writeAll("AbiDecoded(");
        try self.translateSolidityType(decl.ast.type_expr);

        self.writer.setPunctuation(.none);
        return self.writer.writer().writeByte(')');
    }

    try self.writer.writer().writeAll("AbiDecoded(struct{");

    self.writer.setPunctuation(.space);
    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);
        defer self.writer.setPunctuation(.comma_space);

        try self.translateSolidityType(decl.ast.type_expr);
    }

    self.writer.setPunctuation(.space);
    try self.writer.reset();
    try self.writer.writer().writeAll("})");
}
/// Translates a solidity function type with a single param and a tuple of return params to a zig one.
pub fn translateFunctionProtoOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_proto_one);

    var buffer: [2]Node.Index = undefined;
    const function = self.ast.functionProtoOne(&buffer, node);

    if (!self.isCallableFunction(function.ast.specifiers))
        return;

    const readable = self.isReadableFunction(function.ast.specifiers);

    try self.writer.writer().writeAll("pub fn");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(function.name));

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte('(');

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    if (!readable) {
        try self.writer.writer().writeAll("overrides: UnpreparedEnvelope");
        self.writer.setPunctuation(.none);
        try self.writer.writer().writeByte(')');

        self.writer.setPunctuation(.space_bang);
        return self.writer.writer().writeAll("Hash");
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    self.writer.setPunctuation(.space_bang);

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);

        try self.writer.writer().writeAll("AbiDecoded(");

        self.writer.setPunctuation(.none);
        try self.translateSolidityType(decl.ast.type_expr);

        return self.writer.writer().writeByte(')');
    }

    try self.writer.writer().writeAll("AbiDecoded(struct{");

    self.writer.setPunctuation(.space);
    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);
        defer self.writer.setPunctuation(.comma_space);

        try self.translateSolidityType(decl.ast.type_expr);
    }

    self.writer.setPunctuation(.space);
    try self.writer.reset();
    try self.writer.writer().writeAll("})");
}
/// Translates a solidity function proto with a single param and `Hash` returns to a zig one.
pub fn translateFunctionProtoSimple(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_proto_simple);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionProtoSimple(&buffer, node);

    if (!self.isCallableFunction(function.ast.specifiers))
        return;

    try self.writer.writer().writeAll("pub fn");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(function.name));

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte('(');

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeAll(") !Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateFunctionProtoMulti(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_proto_multi);

    const function = self.ast.functionMulti(node);

    if (!self.isCallableFunction(function.ast.specifiers))
        return;

    try self.writer.writer().writeAll("pub fn");

    self.writer.setPunctuation(.space);
    try self.writer.writer().writeAll(self.ast.tokenSlice(function.name));

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeByte('(');

    for (function.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    self.writer.setPunctuation(.none);
    try self.writer.writer().writeAll(") !Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateConstructorDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .construct_decl);
    defer self.writer.setPunctuation(.none);

    const constructor = self.ast.constructorDecl(node);

    try self.writer.writer().writeAll("pub fn deployContract(");

    for (constructor.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    try self.writer.writer().writeAll("bytecode: []const u8, overrides: UnpreparedEnvelope)");

    self.writer.setPunctuation(.space_bang);
    try self.writer.writer().writeAll("Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateConstructorDeclOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .construct_decl_one);
    defer self.writer.setPunctuation(.none);

    var buffer: [1]Node.Index = undefined;
    const constructor = self.ast.constructorDeclOne(&buffer, node);

    try self.writer.writer().writeAll("pub fn deployContract(");

    for (constructor.ast.params) |param| {
        defer self.writer.setPunctuation(.comma_space);
        try self.translateVariableDecl(param);
    }

    try self.writer.writer().writeAll("bytecode: []const u8, overrides: UnpreparedEnvelope)");

    self.writer.setPunctuation(.space_bang);
    try self.writer.writer().writeAll("Hash");
}
/// Checks if the `specifiers` node converts a function to a "readable" solidity function.
pub fn isReadableFunction(self: Translator, slice: []const Node.Index) bool {
    var seen_visibility = false;
    for (slice) |specifier| {
        switch (self.ast.tokens.items(.tag)[specifier]) {
            .keyword_view,
            .keyword_pure,
            => {
                seen_visibility = true;
                break;
            },
            else => continue,
        }
    }

    return seen_visibility;
}
/// Checks if the `specifiers` node converts a function to a "readable" solidity function.
pub fn isCallableFunction(self: Translator, slice: []const Node.Index) bool {
    var seen_visibility = false;
    for (slice) |specifier| {
        switch (self.ast.tokens.items(.tag)[specifier]) {
            .keyword_external,
            .keyword_public,
            => {
                seen_visibility = true;
                break;
            },
            else => continue,
        }
    }

    return seen_visibility;
}
/// Renders the main_token of a literal node or a identifier from the source code.
pub fn renderLiteralNode(self: Translator, node: Node.Index) Allocator.Error!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .number_literal or
        node_tag == .string_literal or
        node_tag == .identifier);

    const main_token = self.ast.nodes.items(.main_token)[node];

    try self.writer.writer().writeAll(self.ast.tokenSlice(main_token));
}

/// Auto indentation and Punctuation writer stream.
pub fn AutoPunctuationAndIndentStream(comptime BaseWriter: type) type {
    return struct {
        const Self = @This();

        pub const WriterError = BaseWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriterError, write);

        /// Supported punctuation to write.
        pub const Punctuation = enum {
            semicolon,
            comma,
            space,
            comma_space,
            comma_newline,
            none,
            space_bang,
        };

        /// The base writer for this wrapper
        base_writer: BaseWriter,
        /// Current amount of indentation to apply
        indentation_level: usize,
        /// Current amount of indentation to apply
        next_punctuation: Punctuation = .none,
        /// Current amount of indentation to apply
        indentation_count: usize = 0,

        /// Returns the writer with our writer function.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
        /// Write function that applies indentation and punctuation if necessary.
        pub fn write(self: *Self, bytes: []const u8) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyPunctuation();
            try self.applyIndentation();
            return self.writeSimple(bytes);
        }
        /// Applies the `next_punctuation` on the stream.
        pub fn applyPunctuation(self: *Self) WriterError!void {
            switch (self.next_punctuation) {
                .none => {},
                .comma => try self.base_writer.writeByte(','),
                .semicolon => try self.base_writer.writeByte(';'),
                .space => try self.base_writer.writeByte(' '),
                .comma_space => try self.base_writer.writeAll(", "),
                .comma_newline => try self.base_writer.writeAll(",\n"),
                .space_bang => try self.base_writer.writeAll(" !"),
            }
        }
        /// Applies indentation if the current level * count is higher than 0.
        pub fn applyIndentation(self: *Self) WriterError!void {
            if (self.getCurrentIndentation() > 0)
                try self.base_writer.writeByteNTimes(' ', self.indentation_level);
        }
        /// Gets the current indentation level to apply. `indentation_level` * `indentation_count`
        pub fn getCurrentIndentation(self: *Self) usize {
            var current: usize = 0;
            if (self.indentation_count > 0) {
                current = self.indentation_level * self.indentation_count;
            }

            return current;
        }
        /// Pushes one level of indentation.
        pub fn pushIndentation(self: *Self) void {
            self.indentation_count += 1;
        }
        /// Pops one level of indentation.
        pub fn popIndentation(self: *Self) void {
            std.debug.assert(self.indentation_count > 0);
            self.indentation_count -= 1;
        }
        /// Writes to the base stream with no indentation and punctuation
        pub fn writeSimple(self: *Self, bytes: []const u8) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.base_writer.writeAll(bytes);

            return bytes.len;
        }
        /// Sets the indentation_level.
        pub fn setIndentation(self: *Self, indent: usize) void {
            if (self.indentation_level == indent)
                return;

            self.indentation_level = indent;
        }
        /// Sets the next_punctuation to write.
        pub fn setPunctuation(self: *Self, punc: Punctuation) void {
            if (self.next_punctuation == punc)
                return;

            self.next_punctuation = punc;
        }
        /// Applies the punctuation and reset the next one.
        pub fn reset(self: *Self) WriterError!void {
            try self.applyPunctuation();
            self.next_punctuation = .none;
        }
    };
}
