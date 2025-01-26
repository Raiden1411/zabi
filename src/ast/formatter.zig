const ast = Ast.ast;
const std = @import("std");

const Ast = @import("Ast.zig");

/// Auto indentation  writer stream.
pub fn IndentingStream(comptime BaseWriter: type) type {
    return struct {
        const Self = @This();

        pub const WriterError = BaseWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriterError, write);

        /// The base writer for this wrapper
        base_writer: BaseWriter,
        /// Current amount of indentation
        indentation: u8,
        /// Current amount of indentation to apply
        indentation_level: u8,
        /// If it should apply indentation to the rest of the stream
        apply_indentation: bool,

        /// Returns the writer with our writer function.
        pub fn writer(self: *Self) Writer {
            return .{
                .context = self,
            };
        }
        /// Write function that applies indentation and punctuation if necessary.
        pub fn write(
            self: *Self,
            bytes: []const u8,
        ) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyIndentation();
            return self.writeSimple(bytes);
        }
        /// Applies indentation if the current level * count is higher than 0.
        pub fn applyIndentation(self: *Self) WriterError!void {
            if (self.apply_indentation and self.getCurrentIndentation() > 0) {
                try self.base_writer.writeByteNTimes(' ', self.getCurrentIndentation());
                self.apply_indentation = false;
            }
        }
        /// Gets the current indentation level to apply. `indentation_level` * `indentation_count`
        pub fn getCurrentIndentation(self: *Self) usize {
            var current: usize = 0;
            if (self.indentation > 0)
                current = self.indentation * self.indentation_level;

            return current;
        }
        /// Pushes one level of indentation.
        pub fn pushIndentation(self: *Self) void {
            self.indentation_level += 1;
        }
        /// Pops one level of indentation.
        pub fn popIndentation(self: *Self) void {
            std.debug.assert(self.indentation_level > 0);
            self.indentation_level -= 1;
        }
        /// Writes to the base stream with no indentation and punctuation
        pub fn writeSimple(
            self: *Self,
            bytes: []const u8,
        ) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            if (bytes[bytes.len - 1] == '\n')
                self.apply_indentation = true;

            try self.base_writer.writeAll(bytes);

            return bytes.len;
        }
    };
}

/// Solidity languange formatter.
///
/// It's opinionated and for now supports minimal set of configurations.
pub fn SolidityFormatter(comptime OutWriter: type) type {
    return struct {
        /// Supported punctuation for this formatter.
        pub const Punctuation = enum {
            comma,
            comma_space,
            comma_newline,
            newline,
            none,
            semicolon,
            space,
            skip,
        };

        /// Set of errors when running the formatter.
        ///
        /// These error come from the formatter type that was provided.
        pub const Error = OutWriter.Error;

        const Formatter = @This();

        /// Auto indentation stream used to properly indent the code.
        stream: IndentingStream(OutWriter),
        /// Solidity Ast used as the base for formatting the source code.
        tree: Ast,

        /// Sets the initial state with the provided indentation
        pub fn init(
            tree: Ast,
            indentation: u8,
            inner_stream: OutWriter,
        ) Formatter {
            std.debug.assert(indentation != 0); // Cannot 0 indent

            return .{
                .stream = .{
                    .base_writer = inner_stream,
                    .indentation = indentation,
                    .indentation_level = 0,
                    .apply_indentation = true,
                },
                .tree = tree,
            };
        }

        /// Formats a single element of a solidity contract block
        pub fn formatContractBodyElement(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            const nodes = self.tree.nodes.items(.tag);

            switch (nodes[node]) {
                .function_proto_one,
                .function_proto,
                .function_proto_simple,
                .function_proto_multi,
                => @panic("TODO"),
                .error_proto_simple,
                => {
                    var buffer: [1]Ast.Node.Index = undefined;
                    const error_decl = self.tree.errorProtoSimple(&buffer, node);

                    try self.formatToken(error_decl.main_token, .space);
                    try self.formatToken(error_decl.name, .none);

                    // l_paren
                    try self.formatToken(error_decl.name + 1, .none);

                    for (error_decl.ast.params) |field|
                        try self.formatExpression(field, .none);

                    try self.formatToken(self.tree.lastToken(node), .newline);
                },
                .error_proto_multi,
                => {
                    const error_decl = self.tree.errorProtoMulti(node);

                    try self.formatToken(error_decl.main_token, .space);
                    try self.formatToken(error_decl.name, .none);

                    // l_paren
                    try self.formatToken(error_decl.name + 1, .none);

                    for (error_decl.ast.params, 0..) |field, i|
                        try self.formatExpression(
                            field,
                            if (i < error_decl.ast.params.len - 1)
                                .comma_space
                            else
                                .none,
                        );

                    try self.formatToken(self.tree.lastToken(node), .newline);
                },
                .event_proto_simple,
                .event_proto_multi,
                => @panic("TODO"),
                .constructor_decl,
                .constructor_decl_one,
                => @panic("TODO"),
                .struct_decl,
                .struct_decl_one,
                => @panic("TODO"),
                .modifier_proto,
                => @panic("TODO"),
                .function_decl,
                => @panic("TODO"),
                .modifier_decl,
                => @panic("TODO"),
                .user_defined_type,
                => @panic("TODO"),
                .using_directive,
                .using_directive_multi,
                => @panic("TODO"),
                .enum_decl,
                => {
                    const enum_decl = self.tree.enumDecl(node);

                    try self.formatToken(enum_decl.main_token, .space);
                    try self.formatToken(enum_decl.name, .space);

                    // l_brace
                    try self.formatToken(enum_decl.name + 1, .newline);

                    for (enum_decl.fields, 0..) |field, i|
                        try self.formatToken(
                            field,
                            if (i < enum_decl.fields.len - 1)
                                .comma_newline
                            else
                                .newline,
                        );

                    try self.formatToken(self.tree.lastToken(node), .newline);
                },
                .enum_decl_one,
                => {
                    var buffer: [1]Ast.Node.Index = undefined;
                    const enum_decl = self.tree.enumDeclOne(&buffer, node);

                    try self.formatToken(enum_decl.main_token, .space);
                    try self.formatToken(enum_decl.name, .space);

                    // l_brace
                    try self.formatToken(enum_decl.name + 1, .newline);

                    for (enum_decl.fields) |field|
                        try self.formatToken(field, .newline);

                    try self.formatToken(self.tree.lastToken(node), .newline);
                },
                else => @panic("TODO STATE VARIABLE"),
            }
        }
        /// Formats a solidity statement.
        pub fn formatStatement(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main_token = self.tree.nodes.items(.main_token);
            const data = self.tree.nodes.items(.data);
            const nodes = self.tree.nodes.items(.tag);

            switch (nodes[node]) {
                .@"if",
                => {
                    const if_node = self.tree.ifStatement(node);
                    // .keyword_if
                    try self.formatToken(if_node.main_token, .space);
                    // .l_paren
                    try self.formatToken(if_node.main_token + 1, .none);
                    // expression
                    try self.formatExpression(if_node.ast.condition, .none);

                    // .r_paren
                    const last = self.tree.lastToken(if_node.ast.condition);

                    if (self.tree.tokensOnSameLine(last, self.tree.firstToken(if_node.ast.then_expression))) {
                        // .r_paren
                        try self.formatToken(last + 1, .space);

                        // then_expression
                        try self.formatStatement(if_node.ast.then_expression, .space);
                    } else if (self.isBlockNode(if_node.ast.then_expression)) {
                        // .r_paren
                        try self.formatToken(last + 1, .space);
                        try self.formatStatement(if_node.ast.then_expression, .newline);
                    } else {
                        // .r_paren
                        try self.formatToken(last + 1, .newline);

                        self.stream.pushIndentation();
                        defer self.stream.popIndentation();

                        try self.formatStatement(if_node.ast.then_expression, .newline);
                    }

                    // .keyword_else
                    const first = self.tree.firstToken(if_node.ast.else_expression.?);
                    try self.formatToken(first - 1, .space);

                    // else_expression
                    return self.formatStatement(if_node.ast.else_expression.?, .newline);
                },
                .if_simple,
                => {
                    // .keyword_if
                    try self.formatToken(main_token[node], .space);
                    // .l_paren
                    try self.formatToken(main_token[node] + 1, .none);

                    // expression
                    try self.formatExpression(data[node].lhs, .none);

                    // .r_paren
                    const last = self.tree.lastToken(data[node].lhs);

                    if (self.tree.tokensOnSameLine(last, self.tree.firstToken(data[node].rhs))) {
                        try self.formatToken(last + 1, .space);
                        // then_expression
                        return self.formatStatement(data[node].rhs, .none);
                    }

                    if (self.isBlockNode(data[node].rhs)) {
                        try self.formatToken(last + 1, .space);
                        return self.formatStatement(data[node].rhs, .newline);
                    }

                    try self.formatToken(last + 1, .newline);

                    self.stream.pushIndentation();
                    defer self.stream.popIndentation();

                    return self.formatStatement(data[node].rhs, .newline);
                },
                // TODO: Change how this node works
                .@"try",
                => {
                    // .keyword_try
                    try self.formatToken(main_token[node], .none);

                    const expression = self.tree.extraData(data[node].lhs, Ast.Node.Try);
                    try self.formatExpression(expression.expression, .space);

                    if (expression.returns != 0) {
                        const first = self.tree.firstToken(expression.returns);
                        // .keyword_returns
                        try self.formatToken(first - 2, .space);
                        // .l_paren
                        try self.formatToken(first - 1, .none);

                        // expression
                        try self.formatExpression(expression.returns, .none);

                        // .r_paren
                        const last = self.tree.lastToken(expression.returns);
                        try self.formatToken(last + 1, .space);
                    }

                    try self.formatStatement(expression.block_statement, .newline);

                    const extra = self.tree.extraData(data[node].rhs, Ast.Node.Range);
                    const slice = self.tree.extra_data[extra.start..extra.end];

                    for (slice) |catch_statement| {
                        try self.formatToken(main_token[catch_statement], .space);

                        const possible_iden = main_token[catch_statement] + 1;

                        if (self.tree.tokens.items(.tag)[main_token[possible_iden]] == .identifier)
                            try self.formatToken(main_token[possible_iden], .space);

                        if (data[catch_statement].lhs != 0) {
                            const l_paren = self.tree.firstToken(data[catch_statement].lhs);
                            try self.formatToken(l_paren, .none);
                            try self.formatExpression(data[catch_statement].lhs, .none);

                            const r_paren = self.tree.lastToken(data[catch_statement].lhs);
                            try self.formatToken(r_paren, .none);
                        }

                        try self.formatStatement(data[catch_statement].rhs, .newline);
                    }
                },
                .@"break",
                .@"continue",
                => return self.formatToken(main_token[node], .semicolon),
                .@"return",
                => {
                    if (data[node].lhs != 0) {
                        try self.formatToken(main_token[node], .space);

                        return self.formatExpression(data[node].lhs, .semicolon);
                    }

                    return self.formatToken(main_token[node], .semicolon);
                },
                .emit,
                => {
                    try self.formatToken(main_token[node], .space);

                    return self.formatExpression(data[node].lhs, .semicolon);
                },
                .@"while",
                => {
                    const while_node = self.tree.whileStatement(node);
                    // .keyword_while
                    try self.formatToken(while_node.main_token, .space);
                    // .l_paren
                    try self.formatToken(while_node.main_token + 1, .none);
                    // expression
                    try self.formatExpression(while_node.ast.condition, .none);

                    // .r_paren
                    const last = self.tree.lastToken(while_node.ast.condition);

                    if (self.tree.tokensOnSameLine(last, self.tree.firstToken(while_node.ast.then_expression))) {
                        try self.formatToken(last + 1, .space);
                        // then_expression
                        return self.formatStatement(while_node.ast.then_expression, .newline);
                    }

                    if (self.isBlockNode(while_node.ast.then_expression)) {
                        try self.formatToken(last + 1, .space);

                        return self.formatStatement(while_node.ast.then_expression, .newline);
                    }

                    try self.formatToken(last + 1, .newline);

                    self.stream.pushIndentation();
                    defer self.stream.popIndentation();

                    return self.formatStatement(while_node.ast.then_expression, .newline);
                },
                .do_while,
                => {
                    const do_node = self.tree.doWhileStatement(node);

                    // .keyword_do
                    try self.formatToken(do_node.main_token, .space);
                    // expression
                    try self.formatStatement(do_node.ast.then_expression, .space);

                    const last = self.tree.lastToken(do_node.ast.then_expression);
                    // .keyword_while
                    try self.formatToken(last + 1, .space);
                    // .l_paren
                    try self.formatToken(last + 2, .none);
                    // while_expression
                    try self.formatExpression(do_node.ast.while_expression, .none);

                    // .r_paren
                    const r_paren = self.tree.lastToken(do_node.ast.while_expression);

                    return self.formatToken(r_paren + 1, .semicolon);
                },
                .@"for",
                => {
                    const for_node = self.tree.forStatement(node);

                    // .keyword_for
                    try self.formatToken(for_node.main_token, .space);
                    // .l_paren
                    try self.formatToken(for_node.main_token + 1, .none);

                    try self.formatExpression(for_node.ast.assign_expr, .none);
                    try self.formatToken(self.tree.lastToken(for_node.ast.assign_expr) + 1, .space);

                    try self.formatExpression(for_node.ast.condition, .none);
                    try self.formatToken(self.tree.lastToken(for_node.ast.condition) + 1, .space);

                    try self.formatExpression(for_node.ast.increment, .none);

                    const last = self.tree.lastToken(for_node.ast.increment);

                    if (self.tree.tokensOnSameLine(last, self.tree.firstToken(for_node.ast.then_expression))) {
                        try self.formatToken(last + 1, .space);
                        // then_expression
                        return self.formatStatement(for_node.ast.then_expression, .newline);
                    }

                    if (self.isBlockNode(for_node.ast.then_expression)) {
                        try self.formatToken(last + 1, .space);
                        // then_expression
                        return self.formatStatement(for_node.ast.then_expression, .newline);
                    }

                    try self.formatToken(last + 1, .newline);

                    self.stream.pushIndentation();
                    defer self.stream.popIndentation();

                    return self.formatStatement(for_node.ast.then_expression, .newline);
                },
                .assembly_decl,
                => @panic("TODO"),
                .unchecked_block,
                => {
                    // .keyword_unchecked
                    try self.formatToken(main_token[node], .space);

                    return self.formatStatement(data[node].lhs, .newline);
                },
                .block_two,
                .block_two_semicolon,
                => {
                    const statements: [2]Ast.Node.Index = .{
                        data[node].lhs,
                        data[node].rhs,
                    };

                    if (data[node].lhs == 0)
                        return self.formatBlockStatements(node, statements[0..0], punctuation)
                    else if (data[node].rhs == 0)
                        return self.formatBlockStatements(node, statements[0..1], punctuation)
                    else
                        return self.formatBlockStatements(node, statements[0..2], punctuation);
                },
                .block,
                .block_semicolon,
                => {
                    const statements = self.tree.extra_data[data[node].lhs..data[node].rhs];

                    return self.formatBlockStatements(node, statements, punctuation);
                },
                else => return self.formatExpression(node, .semicolon),
            }
        }
        /// Formats a solidity block of statements.
        pub fn formatBlockStatements(
            self: *Formatter,
            node: Ast.Node.Index,
            statements: []const Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main_token = self.tree.nodes.items(.main_token);

            try self.formatToken(main_token[node], .newline);

            self.stream.pushIndentation();

            for (statements) |statement|
                try self.formatStatement(statement, .none);

            self.stream.popIndentation();

            return self.formatToken(self.tree.lastToken(node), punctuation);
        }
        /// Formats a solidity expression.
        pub fn formatExpression(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main_token = self.tree.nodes.items(.main_token);
            const data = self.tree.nodes.items(.data);
            const nodes = self.tree.nodes.items(.tag);

            switch (nodes[node]) {
                .identifier,
                .number_literal,
                .string_literal,
                => return self.formatToken(main_token[node], punctuation),
                .field_access,
                => {
                    try self.formatExpression(data[node].lhs, .none);
                    try self.formatToken(main_token[node], .none);

                    return self.formatToken(data[node].rhs, punctuation);
                },
                .equal_equal,
                .bang_equal,
                .less_than,
                .less_or_equal,
                .greater_than,
                .greater_or_equal,
                .assign,
                .assign_add,
                .assign_sub,
                .assign_mul,
                .assign_mod,
                .assign_div,
                .assign_shl,
                .assign_sar,
                .assign_shr,
                .assign_bit_and,
                .assign_bit_xor,
                .assign_bit_or,
                .yul_assign,
                .add,
                .sub,
                .mod,
                .mul,
                .div,
                .shl,
                .shr,
                .sar,
                .bit_and,
                .bit_or,
                .bit_xor,
                .conditional_and,
                .conditional_or,
                => {
                    const operator = main_token[node];
                    const expressions = data[node];

                    try self.formatExpression(expressions.lhs, .space);
                    try self.formatToken(operator, .space);

                    return self.formatExpression(expressions.rhs, punctuation);
                },
                .exponent,
                => {
                    const operator = main_token[node];
                    const expressions = data[node];

                    try self.formatExpression(expressions.rhs, .space);
                    try self.formatToken(operator, .space);

                    return self.formatExpression(expressions.lhs, punctuation);
                },
                .bit_not,
                .conditional_not,
                // TODO: Update this for increment and decrement.
                .increment,
                .decrement,
                => {
                    const operator = main_token[node];
                    const expressions = data[node];

                    try self.formatToken(operator, .none);

                    return self.formatExpression(expressions.lhs, punctuation);
                },
                .new_decl,
                => {
                    const keyword = main_token[node];
                    const expressions = data[node];

                    try self.formatToken(keyword, .space);

                    return self.formatExpression(expressions.lhs, punctuation);
                },
                .type_decl,
                => {
                    const keyword = main_token[node];
                    const expressions = data[node];
                    const last = self.tree.lastToken(node);

                    try self.formatToken(keyword, .none);
                    try self.formatToken(keyword + 1, .none);

                    try self.formatExpression(expressions.lhs, punctuation);

                    return self.formatToken(last, .none);
                },
                .payable_decl,
                => {
                    const operator = main_token[node];
                    const expressions = data[node];
                    const last = self.tree.lastToken(node);

                    // .payable
                    try self.formatToken(operator, .none);

                    // .l_paren
                    try self.formatToken(operator + 1, .none);
                    try self.formatExpression(expressions.lhs, .none);

                    // .r_paren
                    return self.formatToken(last, punctuation);
                },
                .delete,
                => {
                    const operator = main_token[node];
                    const expressions = data[node];

                    try self.formatToken(operator, .space);

                    return self.formatExpression(expressions.lhs, punctuation);
                },
                .number_literal_sub_denomination,
                => {
                    const literal = main_token[node];
                    const denomination = data[node];

                    try self.formatToken(literal, .space);
                    try self.formatToken(denomination.lhs, punctuation);
                },
                .array_access,
                .tuple_init_one,
                .array_init_one,
                => {
                    const token = main_token[node];
                    const expression = data[node];

                    try self.formatToken(token, .none);

                    if (expression.lhs != 0)
                        try self.formatExpression(expression.lhs, .none);

                    return self.formatToken(expression.rhs, punctuation);
                },
                .struct_init_one,
                => {
                    const token = main_token[node];
                    const expression = data[node];
                    const last = self.tree.lastToken(node);

                    // .l_brace
                    try self.formatToken(token, .none);

                    if (expression.lhs != 0) {
                        const first = self.tree.firstToken(expression.lhs);

                        // .identifier
                        try self.formatToken(first - 2, .none);

                        // .colon
                        try self.formatToken(first - 1, .space);

                        try self.formatExpression(expression.lhs, .none);
                    }

                    // .r_brace
                    return self.formatToken(last, punctuation);
                },
                .call,
                => {
                    const token = main_token[node];
                    const expressions = data[node];

                    try self.formatExpression(expressions.lhs, .none);
                    try self.formatToken(token, .none);

                    const extra = self.tree.extraData(expressions.rhs, Ast.Node.Range);
                    const slice = self.tree.extra_data[extra.start..extra.end];
                    const last = self.tree.lastToken(node);

                    for (slice, 0..) |index, i|
                        try self.formatExpression(
                            index,
                            if (i < slice.len - 1) .comma_space else .none,
                        );

                    return self.formatToken(last, punctuation);
                },
                .call_one,
                => {
                    const token = main_token[node];
                    const expression = data[node];
                    const last = self.tree.lastToken(node);

                    try self.formatExpression(expression.lhs, .none);
                    try self.formatToken(token, .none);

                    if (expression.rhs != 0)
                        try self.formatExpression(expression.rhs, .none);

                    return self.formatToken(last, punctuation);
                },
                .variable_decl,
                => return self.formatVariableDecl(node, punctuation),
                .error_variable_decl,
                => return self.formatErrorVariableDecl(node, punctuation),
                .event_variable_decl,
                => return self.formatEventVariableDecl(node, punctuation),
                .struct_field,
                => return self.formatStructField(node, punctuation),
                .array_init,
                .tuple_init,
                => {
                    const token = main_token[node];
                    const expressions = data[node];

                    const extra = self.tree.extraData(expressions.lhs, Ast.Node.Range);
                    const slice = self.tree.extra_data[extra.start..extra.end];

                    try self.formatToken(token, .none);

                    for (slice, 0..) |index, i|
                        try self.formatExpression(
                            index,
                            if (i < slice.len - 1) .comma_space else .none,
                        );

                    return self.formatToken(expressions.rhs, punctuation);
                },
                .struct_init,
                => {
                    const token = main_token[node];
                    const expressions = data[node];
                    const last = self.tree.lastToken(node);

                    const extra = self.tree.extraData(expressions.lhs, Ast.Node.Range);
                    const slice = self.tree.extra_data[extra.start..extra.end];

                    try self.formatToken(token, .none);

                    for (slice, 0..) |index, i| {
                        const first = self.tree.firstToken(index);

                        // .identifier
                        try self.formatToken(first - 2, .none);

                        // .colon
                        try self.formatToken(first - 1, .space);

                        try self.formatExpression(
                            index,
                            if (i < slice.len - 1) .comma_space else .none,
                        );
                    }

                    return self.formatToken(last, punctuation);
                },
                else => unreachable, // invalid token
            }
        }
        /// Formats any `function_type*` node.
        pub fn formatFullFunctionType(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            switch (self.tree.nodes.items(.tag)[node]) {
                .function_type => return self.formatFunctionType(node),
                .function_type_one => return self.formatFunctionTypeOne(node),
                .function_type_simple => return self.formatFunctionTypeSimple(node),
                .function_type_multi => return self.formatFunctionTypeMulti(node),
                else => unreachable,
            }
        }
        /// Formats a `function_type` node.
        pub fn formatFunctionType(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            var buffer: [1]Ast.Node.Index = undefined;
            const fn_ast = self.tree.functionTypeProto(&buffer, node);

            try self.formatToken(fn_ast.main_token, .none);

            // .l_paren
            try self.formatToken(fn_ast.main_token + 1, .none);

            // type_expr -> modifier? -> identifier?
            const index = try self.formatFunctionTypeParams(fn_ast.ast.params);

            // .r_paren
            const r_paren = if (index != 0) self.tree.lastToken(index) + 1 else fn_ast.main_token + 2;
            try self.formatToken(r_paren, .space);

            // visibility tokens.
            if (fn_ast.visibility) |visibility|
                try self.formatToken(visibility, .space);

            // Mutability tokens.
            if (fn_ast.mutability) |mutability|
                try self.formatToken(mutability, .space);

            try self.stream.writer().writeAll("returns (");
            const r_index = try self.formatFunctionTypeParams(fn_ast.ast.returns.?);

            const rr_paren = self.tree.lastToken(r_index) + 1;
            try self.formatToken(rr_paren, .none);
        }
        /// Formats a `function_type_one` node.
        pub fn formatFunctionTypeOne(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            var buffer: [2]Ast.Node.Index = undefined;
            const fn_ast = self.tree.functionTypeProtoOne(&buffer, node);

            try self.formatToken(fn_ast.main_token, .none);

            // .l_paren
            try self.formatToken(fn_ast.main_token + 1, .none);

            // type_expr -> modifier? -> identifier?
            const index = try self.formatFunctionTypeParams(fn_ast.ast.params);

            // .r_paren
            const r_paren = if (index != 0) self.tree.lastToken(index) + 1 else fn_ast.main_token + 2;
            try self.formatToken(r_paren, .space);

            // visibility tokens.
            if (fn_ast.visibility) |visibility|
                try self.formatToken(visibility, .space);

            // Mutability tokens.
            if (fn_ast.mutability) |mutability|
                try self.formatToken(mutability, .space);

            try self.stream.writer().writeAll("returns (");
            const r_index = try self.formatFunctionTypeParams(fn_ast.ast.returns.?);

            const rr_paren = self.tree.lastToken(r_index) + 1;
            try self.formatToken(rr_paren, .none);
        }
        /// Formats a `function_type_multi` node.
        pub fn formatFunctionTypeMulti(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            const fn_ast = self.tree.functionTypeMulti(node);

            try self.formatToken(fn_ast.main_token, .none);

            // .l_paren
            try self.formatToken(fn_ast.main_token + 1, .none);

            // type_expr -> modifier? -> identifier?
            const index = try self.formatFunctionTypeParams(fn_ast.ast.params);

            // .r_paren
            const r_paren = if (index != 0) self.tree.lastToken(index) + 1 else fn_ast.main_token + 2;
            try self.formatToken(r_paren, .none);

            // visibility tokens.
            if (fn_ast.visibility) |visibility| {
                try self.applyPunctuation(.space);
                try self.formatToken(visibility, .none);
            }

            // Mutability tokens.
            if (fn_ast.mutability) |mutability| {
                try self.applyPunctuation(.space);
                try self.formatToken(mutability, .none);
            }
        }
        /// Formats a `function_type_simple` node.
        pub fn formatFunctionTypeSimple(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            var buffer: [1]Ast.Node.Index = undefined;
            const fn_ast = self.tree.functionTypeProtoSimple(&buffer, node);

            try self.formatToken(fn_ast.main_token, .none);

            // .l_paren
            try self.formatToken(fn_ast.main_token + 1, .none);

            // type_expr -> modifier? -> identifier?
            const index = try self.formatFunctionTypeParams(fn_ast.ast.params);

            // .r_paren
            const r_paren = if (index != 0) self.tree.lastToken(index) + 1 else fn_ast.main_token + 2;
            try self.formatToken(r_paren, .none);

            // visibility tokens.
            if (fn_ast.visibility) |visibility| {
                try self.applyPunctuation(.space);
                try self.formatToken(visibility, .none);
            }

            // Mutability tokens.
            if (fn_ast.mutability) |mutability| {
                try self.applyPunctuation(.space);
                try self.formatToken(mutability, .none);
            }
        }
        /// Formats the multiple function parameters
        ///
        /// This doesn't include the `l_paren` and `r_paren` tokens.
        pub fn formatFunctionTypeParams(
            self: *Formatter,
            nodes: []const Ast.Node.Index,
        ) Error!Ast.Node.Index {
            var last_node: Ast.Node.Index = 0;

            for (nodes, 0..) |node, i| {
                try self.formatVariableDecl(
                    node,
                    if (i < nodes.len - 1) .comma_space else .none,
                );

                last_node = node;
            }

            return last_node;
        }
        /// Formats a single parameter variable declaration.
        pub fn formatStructField(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main = self.tree.nodes.items(.main_token);
            const data = self.tree.nodes.items(.data);

            try self.formatTypeExpression(main[node], punctuation);

            if (data[node].rhs != 0)
                try self.formatToken(data[node].rhs, .semicolon);
        }
        /// Formats a single parameter variable declaration.
        pub fn formatEventVariableDecl(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main = self.tree.nodes.items(.main_token);
            const data = self.tree.nodes.items(.data);

            try self.formatTypeExpression(main[node], punctuation);

            if (data[node].lhs != 0)
                try self.formatToken(data[node].lhs, .space);

            if (data[node].rhs != 0)
                try self.formatToken(data[node].rhs, .space);
        }
        /// Formats a single parameter variable declaration.
        pub fn formatErrorVariableDecl(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const main = self.tree.nodes.items(.main_token);
            const data = self.tree.nodes.items(.data);

            try self.formatTypeExpression(main[node], punctuation);

            if (data[node].lhs != 0)
                try self.formatToken(data[node].lhs, punctuation);
        }
        /// Formats a single parameter variable declaration.
        pub fn formatVariableDecl(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const var_decl = self.tree.variableDecl(node);

            try self.formatTypeExpression(var_decl.ast.type_expr, punctuation);

            if (var_decl.memory) |memory|
                try self.formatToken(memory, .space);

            if (var_decl.calldata) |calldata|
                try self.formatToken(calldata, .space);

            if (var_decl.storage) |storage|
                try self.formatToken(storage, .space);

            if (var_decl.name) |name|
                try self.formatToken(name, punctuation);
        }
        /// Formats a solidity type expression.
        pub fn formatTypeExpression(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            const tags: []const Ast.Node.Tag = self.tree.nodes.items(.tag);
            const data = self.tree.nodes.items(.data);

            switch (tags[node]) {
                .elementary_type => return self.formatElementaryType(node, punctuation),
                .mapping_decl => return self.formatMappingType(node),
                .function_type,
                .function_type_one,
                .function_type_simple,
                .function_type_multi,
                => return self.formatFullFunctionType(node),
                .identifier => return self.formatExpression(node, punctuation),
                .array_type => {
                    const expression = data[node];

                    try self.formatTypeExpression(expression.lhs, punctuation);

                    try self.formatExpression(expression.rhs, .none);
                },
                else => unreachable,
            }
        }
        /// Formats a solidity mapping declaration
        pub fn formatMappingType(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            const tokens = self.tree.tokens.items(.tag);
            const mapping = self.tree.mappingDecl(node);

            try self.formatToken(mapping.main_token, .none);

            // l_paren
            try self.formatToken(mapping.main_token + 1, .none);
            // Initial type
            try self.formatTypeExpression(mapping.ast.left, .none);

            const maybe_ident = self.tree.lastToken(mapping.ast.left);
            switch (tokens[maybe_ident + 1]) {
                .identifier => {
                    // Applies space after the type expression.
                    try self.applyPunctuation(.space);
                    // .identifier
                    try self.formatToken(maybe_ident + 1, .space);
                    // .equal_bracket_right
                    try self.formatToken(maybe_ident + 2, .space);
                },
                .equal_bracket_right => {
                    // Applies space after the type expression.
                    try self.applyPunctuation(.space);
                    try self.formatToken(maybe_ident + 1, .space);
                },
                else => unreachable,
            }

            // Final type expression.
            try self.formatTypeExpression(mapping.ast.right, .none);

            // r_paren
            const last_token = self.tree.lastToken(node);

            std.debug.assert(self.tree.tokens.items(.tag)[last_token] == .r_paren);
            try self.formatToken(last_token, .none);
        }
        /// Formats a single solidity elementary type.
        pub fn formatElementaryType(
            self: *Formatter,
            node: Ast.Node.Index,
            punctuation: Punctuation,
        ) Error!void {
            std.debug.assert(self.tree.nodes.items(.tag)[node] == .elementary_type);

            return self.formatToken(self.tree.nodes.items(.main_token)[node], punctuation);
        }
        /// Formats a single token.
        ///
        /// If the token is a `doc_comment*` it will trim the whitespace on the right.
        pub fn formatToken(
            self: *Formatter,
            token_index: Ast.TokenIndex,
            punctuation: Punctuation,
        ) Error!void {
            const slice = self.tokenSlice(token_index);

            try self.stream.writer().writeAll(slice);
            return self.applyPunctuation(punctuation);
        }
        /// Grabs the associated source code from a `token`
        ///
        /// If the token is a `doc_comment*` it will trim the whitespace on the right.
        pub fn tokenSlice(
            self: *Formatter,
            token_index: Ast.TokenIndex,
        ) []const u8 {
            var slice = self.tree.tokenSlice(token_index);

            switch (self.tree.tokens.items(.tag)[token_index]) {
                .doc_comment,
                .doc_comment_container,
                => slice = std.mem.trimRight(u8, slice, &std.ascii.whitespace),
                else => {},
            }

            return slice;
        }
        /// Applies punctuation after a token.
        pub fn applyPunctuation(self: *Formatter, punctuation: Punctuation) Error!void {
            return switch (punctuation) {
                .comma => self.stream.writer().writeAll(","),
                .comma_space => self.stream.writer().writeAll(", "),
                .comma_newline => self.stream.writer().writeAll(",\n"),
                .newline => self.stream.writer().writeAll("\n"),
                .semicolon => self.stream.writer().writeAll(";\n"),
                .space => self.stream.writer().writeAll(" "),
                .none,
                .skip,
                => {},
            };
        }
        /// Checks if the node is a block node
        fn isBlockNode(self: Formatter, node: Ast.Node.Index) bool {
            return switch (self.tree.nodes.items(.tag)[node]) {
                .block_two,
                .block_two_semicolon,
                .block,
                .block_semicolon,
                => true,
                else => false,
            };
        }
    };
}
