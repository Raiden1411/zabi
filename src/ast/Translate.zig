const std = @import("std");

const Allocator = std.mem.Allocator;
const SolidityAst = @import("Ast.zig");
const Node = SolidityAst.Node;
const ArrayList = std.ArrayList(u8);

const Translator = @This();

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
/// Writer used to write the translation too.
writer: ArrayList.Writer,

/// Sets the initial state of the `Translator`.
pub fn init(solidity_ast: SolidityAst, writer: ArrayList.Writer) Translator {
    return .{
        .ast = solidity_ast,
        .writer = writer,
    };
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
        else => return error.InvalidNode,
    }
}
/// Translates the elementary types of solidity to zig ones.
pub fn translateElementaryType(self: Translator, node: Node.Index) Allocator.Error!void {
    const node_tag = self.ast.nodes.items(.tag)[node];
    const main = self.ast.nodes.items(.main_token)[node];

    std.debug.assert(node_tag == .elementary_type);

    const token_tags = self.ast.tokens.items(.tag);

    try self.writer.writeAll(token_tags[main].translateToken().?);
}
/// Translates the `mapping` type into a zig `AutoHashMap`
pub fn translateMappingType(self: Translator, node: Node.Index) TranslateErrors!void {
    const node_tag = self.ast.nodes.items(.tag)[node];

    std.debug.assert(node_tag == .mapping_decl);

    const data = self.ast.nodes.items(.data)[node];

    try self.writer.writeAll("std.AutoHashMap(");

    try self.translateSolidityType(data.lhs);
    try self.writer.writeByte(',');
    try self.translateSolidityType(data.rhs);
    try self.writer.writeByte(')');
}
/// Translates a constant variable declaration of solidity to zig.
pub fn translateConstantVariableDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .constant_variable_decl);

    const variable = self.ast.constantVariableDecl(node);

    try self.writer.print("const {s}: ", .{self.ast.tokenSlice(variable.name)});
    try self.translateSolidityType(variable.ast.type_token);

    try self.writer.writeAll(" = ");
    switch (nodes[variable.ast.expression_node]) {
        .number_literal,
        .string_literal,
        => try self.renderLiteralNode(variable.ast.expression_node),
        else => return error.UnsupportedExpressionNode,
    }

    try self.writer.writeByte(';');
}
/// Translates a solidity variable declaration to a zig one.
pub fn translateVariableDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .variable_decl);

    const decl = self.ast.variableDecl(node);

    if (decl.name) |name| {
        try self.writer.print("{s}: ", .{self.ast.tokenSlice(name)});
    } else return error.ExpectedIdentifier;

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

    try self.writer.print("const {s} = ", .{self.ast.tokenSlice(enum_decl.name)});
    try self.writer.writeAll("enum {");

    for (enum_decl.fields) |field| {
        try self.writer.writeAll(self.ast.tokenSlice(field));
        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("};");
}
/// Translates a solidity enum with multiple members to a zig one.
pub fn translateEnumDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .enum_decl);
    const enum_decl = self.ast.enumDecl(node);

    try self.writer.print("const {s} = ", .{self.ast.tokenSlice(enum_decl.name)});
    try self.writer.writeAll("enum {");

    for (enum_decl.fields) |field| {
        try self.writer.writeAll(self.ast.tokenSlice(field));
        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("};");
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

    var buffer: [1]Node.Index = undefined;
    const struct_decl = self.ast.structDeclOne(&buffer, node);

    try self.writer.print("const {s} = ", .{self.ast.tokenSlice(struct_decl.name)});
    try self.writer.writeAll("struct {");

    for (struct_decl.ast.fields) |field| {
        try self.translateStructField(field);
        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("};");
}
/// Translates a solidity struct with multiple members to a zig one.
pub fn translateStructDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .struct_decl);
    const struct_decl = self.ast.structDecl(node);

    try self.writer.print("const {s} = ", .{self.ast.tokenSlice(struct_decl.name)});
    try self.writer.writeAll("struct {");

    for (struct_decl.ast.fields) |field| {
        try self.translateStructField(field);
        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("};");
}
/// Translates a solidity struct field to a zig one.
pub fn translateStructField(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .struct_field);

    const data = self.ast.nodes.items(.data)[node];

    try self.writer.print("{s}: ", .{self.ast.tokenSlice(data.rhs)});

    try self.translateSolidityType(self.ast.nodes.items(.main_token)[node]);
}
/// Translates a solidity function type with multiple params and tuple of return params to a zig one.
pub fn translateFunctionType(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionTypeProto(&buffer, node);

    try self.writer.writeAll("?*const fn(");

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.writer.writeByte(' ');
        return self.translateSolidityType(decl.ast.type_expr);
    }

    try self.writer.writeAll(" struct { ");

    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);

        try self.translateSolidityType(decl.ast.type_expr);

        try self.writer.writeByte(',');
    }

    try self.writer.writeByte('}');
}
/// Translates a solidity function type with a single param and a tuple of return params to a zig one.
pub fn translateFunctionTypeOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_one);

    var buffer: [2]Node.Index = undefined;
    const function = self.ast.functionTypeProtoOne(&buffer, node);

    try self.writer.writeAll("?*const fn(");

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.writer.writeByte(' ');
        return self.translateSolidityType(decl.ast.type_expr);
    }

    try self.writer.writeAll(" struct{ ");

    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);

        try self.translateSolidityType(decl.ast.type_expr);

        try self.writer.writeByte(',');
    }

    try self.writer.writeByte('}');
}
/// Translates a solidity function type with a single param and void returns to a zig one.
pub fn translateFunctionTypeSimple(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_simple);

    var buffer: [1]Node.Index = undefined;
    const function = self.ast.functionTypeProtoSimple(&buffer, node);

    try self.writer.writeAll("?*const fn(");

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll(") void");
}
/// Translates a solidity function type with multiple params and void return to a zig one.
pub fn translateFunctionTypeMulti(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_type_multi);

    const function = self.ast.functionTypeMulti(node);

    try self.writer.writeAll("?*const fn(");

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll(") void");
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

    try self.writer.print("pub fn {s}(", .{self.ast.tokenSlice(function.name)});

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    if (!readable) {
        try self.writer.writeAll(" overrides: UnpreparedEnvelope");
        try self.writer.writeByte(')');
        return self.writer.writeAll(" !Hash");
    }

    try self.writer.writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.writer.writeAll(" !AbiDecoded(");
        try self.translateSolidityType(decl.ast.type_expr);

        return try self.writer.writeByte(')');
    }

    try self.writer.writeAll(" !AbiDecoded(struct{");

    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);

        try self.translateSolidityType(decl.ast.type_expr);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("})");
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

    try self.writer.print("pub fn {s}(", .{self.ast.tokenSlice(function.name)});

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    if (!readable) {
        try self.writer.writeAll(" overrides: UnpreparedEnvelope");
        try self.writer.writeByte(')');
        return self.writer.writeAll(" !Hash");
    }

    try self.writer.writeByte(')');

    const returns_slice = function.ast.returns orelse return error.InvalidFunctionType;

    if (returns_slice.len == 1) {
        const decl = self.ast.variableDecl(returns_slice[0]);
        try self.writer.writeAll(" !AbiDecoded(");
        try self.translateSolidityType(decl.ast.type_expr);

        return try self.writer.writeByte(')');
    }

    try self.writer.writeAll(" !AbiDecoded(struct{");

    for (returns_slice) |param| {
        const decl = self.ast.variableDecl(param);

        try self.translateSolidityType(decl.ast.type_expr);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll("})");
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

    try self.writer.print("pub fn {s}(", .{self.ast.tokenSlice(function.name)});

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll(") !Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateFunctionProtoMulti(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .function_proto_multi);

    const function = self.ast.functionMulti(node);

    if (!self.isCallableFunction(function.ast.specifiers))
        return;

    try self.writer.print("pub fn {s}(", .{self.ast.tokenSlice(function.name)});

    for (function.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }
    try self.writer.writeByte(')');

    try self.writer.writeAll(") !Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateConstructorDecl(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .construct_decl);

    const constructor = self.ast.constructorDecl(node);

    try self.writer.writeAll("pub fn deployContract(");

    for (constructor.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll(" bytecode: []const u8, overrides: UnpreparedEnvelope)");

    try self.writer.writeAll(" !Hash");
}
/// Translates a solidity function proto with a multiple params and `Hash` returns to a zig one.
pub fn translateConstructorDeclOne(self: Translator, node: Node.Index) TranslateErrors!void {
    const nodes = self.ast.nodes.items(.tag);
    const node_tag = nodes[node];

    std.debug.assert(node_tag == .construct_decl_one);

    var buffer: [1]Node.Index = undefined;
    const constructor = self.ast.constructorDeclOne(&buffer, node);

    try self.writer.writeAll("pub fn deployContract(");

    for (constructor.ast.params) |param| {
        try self.translateVariableDecl(param);

        try self.writer.writeByte(',');
    }

    try self.writer.writeAll(" bytecode: []const u8, overrides: UnpreparedEnvelope)");

    try self.writer.writeAll(" !Hash");
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

    try self.writer.writeAll(self.ast.tokenSlice(main_token));
}
