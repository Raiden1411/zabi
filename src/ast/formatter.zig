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
        /// Current amount of indentation to apply
        indentation_level: usize,
        /// Current amount of indentation to apply
        indentation_count: usize,

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
        /// Writes a new line into the stream and updates the level.
        pub fn writeNewline(self: *Self) WriterError!void {
            return self.writeSimple("\n");
        }
        /// Applies indentation if the current level * count is higher than 0.
        pub fn applyIndentation(self: *Self) WriterError!void {
            if (self.getCurrentIndentation() > 0)
                try self.base_writer.writeByteNTimes(' ', self.indentation_level);
        }
        /// Gets the current indentation level to apply. `indentation_level` * `indentation_count`
        pub fn getCurrentIndentation(self: *Self) usize {
            var current: usize = 0;
            if (self.indentation_count > 0)
                current = self.indentation_level * self.indentation_count;

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
        pub fn writeSimple(
            self: *Self,
            bytes: []const u8,
        ) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            if (bytes[bytes.len - 1] == '\n')
                self.indentation_count = 0;

            try self.base_writer.writeAll(bytes);

            return bytes.len;
        }
        /// Sets the indentation_level.
        pub fn setIndentation(self: *Self, indent: usize) void {
            if (self.indentation_level == indent)
                return;

            self.indentation_level = indent;
        }
    };
}

/// Solidity languange formatter.
///
/// It's opinionated and for now supports minimal set of configurations.
pub fn SolidityFormatter(
    comptime OutWriter: type,
    comptime indent: comptime_int,
) type {
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

        // Asserts that the indent level cannot be 0;
        comptime {
            std.debug.assert(indent != 0);
        }

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
            inner_stream: OutWriter,
        ) Formatter {
            return .{
                .stream = .{
                    .base_writer = inner_stream,
                    .indentation_level = indent,
                    .indentation_count = 0,
                },
                .tree = tree,
            };
        }

        pub fn formatExpression(self: *Formatter, node: Ast.Node.Index, punctuation: Punctuation) Error!void {
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
                .less_than_or_equal,
                .greater_than,
                .greater_than_or_equal,
                .assign,
                .assign_add,
                .assign_sub,
                .assign_mul,
                .assing_mod,
                .assign_div,
                .assign_shl,
                .assign_sar,
                .assign_shr,
                .assing_bit_and,
                .assign_bit_xor,
                .assign_bit_or,
                .yul_assing,
                .add,
                .sub,
                .mod,
                .mul,
                .div,
                .shl,
                .shr,
                .sar,
                .exponent,
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
                try self.formatVariableDecl(node);

                if (i < nodes.len - 1)
                    try self.applyPunctuation(.comma_space);

                last_node = node;
            }

            return last_node;
        }
        /// Formats a single parameter variable declaration.
        pub fn formatVariableDecl(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            const var_decl = self.tree.variableDecl(node);

            try self.formatTypeExpression(var_decl.ast.type_expr);

            if (var_decl.memory) |memory| {
                try self.applyPunctuation(.space);
                try self.formatToken(memory, .none);
            }

            if (var_decl.calldata) |calldata| {
                try self.applyPunctuation(.space);
                try self.formatToken(calldata, .none);
            }

            if (var_decl.storage) |storage| {
                try self.applyPunctuation(.space);
                try self.formatToken(storage, .none);
            }

            if (var_decl.name) |name| {
                try self.applyPunctuation(.space);
                try self.formatToken(name, .none);
            }
        }
        /// Formats a solidity type expression.
        pub fn formatTypeExpression(
            self: *Formatter,
            node: Ast.Node.Index,
        ) Error!void {
            const tags: []const Ast.Node.Tag = self.tree.nodes.items(.tag);

            switch (tags[node]) {
                .elementary_type => return self.formatElementaryType(node),
                .mapping_decl => return self.formatMappingType(node),
                .function_type,
                .function_type_one,
                .function_type_simple,
                .function_type_multi,
                => return self.formatFullFunctionType(node),
                .identifier => {},
                .array_type => {},
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
            try self.formatTypeExpression(mapping.ast.left);

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
            try self.formatTypeExpression(mapping.ast.right);

            // r_paren
            const last_token = self.tree.lastToken(node);

            std.debug.assert(self.tree.tokens.items(.tag)[last_token] == .r_paren);
            try self.formatToken(last_token, .none);
        }
        /// Formats a single solidity elementary type.
        pub fn formatElementaryType(self: *Formatter, node: Ast.Node.Index) Error!void {
            std.debug.assert(self.tree.nodes.items(.tag)[node] == .elementary_type);

            return self.formatToken(self.tree.nodes.items(.main_token)[node], .none);
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
                .semicolon => self.stream.writer().writeAll(";"),
                .space => self.stream.writer().writeAll(" "),
                .none,
                .skip,
                => {},
            };
        }
    };
}
