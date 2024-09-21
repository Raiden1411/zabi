const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Allocator = std.mem.Allocator;
const Parser = @import("Parser.zig");
const Token = tokenizer.Token;

const Ast = @This();

/// Offset used in the parser.
pub const Offset = u32;

/// Index used for the parser.
pub const TokenIndex = u32;

/// Struct of arrays for the `Node` members.
pub const NodeList = std.MultiArrayList(Node);

/// Struct of arrays for the `Token.Tag` members.
pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: Offset,
});

/// Source code slice.
source: [:0]const u8,
/// Struct of arrays containing the token tags
/// and token starts.
tokens: TokenList.Slice,
/// Struct of arrays containing all node information.
nodes: NodeList.Slice,
/// Slice of extra data produces by the parser.
extra_data: []const Node.Index,
/// Slice of errors that appended in parsing.
errors: []const Error,

/// Clears any allocated memory from the `Ast`.
pub fn deinit(self: *Ast, allocator: Allocator) void {
    self.tokens.deinit(allocator);
    self.nodes.deinit(allocator);
    allocator.free(self.extra_data);
    allocator.free(self.errors);
}

/// Parses the source code and builds the ast.
pub fn parse(allocator: Allocator, source: [:0]const u8) Parser.ParserErrors!Ast {
    var tokens: Ast.TokenList = .{};
    defer tokens.deinit(allocator);

    var lexer = tokenizer.Tokenizer.init(source);

    while (true) {
        const token = lexer.next();

        try tokens.append(allocator, .{
            .tag = token.tag,
            .start = @intCast(token.location.start),
        });

        if (token.tag == .eof) break;
    }

    var parser: Parser = .{
        .source = source,
        .allocator = allocator,
        .token_index = 0,
        .token_tags = tokens.items(.tag),
        .token_starts = tokens.items(.start),
        .nodes = .{},
        .errors = .{},
        .scratch = .{},
        .extra_data = .{},
    };
    defer parser.deinit();

    try parser.parseSource();

    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra_data.toOwnedSlice(allocator),
        .errors = try parser.errors.toOwnedSlice(allocator),
    };
}

/// Ast Node representation.
///
/// `data` may contain indexes to extra_data to help build the syntax tree.
pub const Node = struct {
    /// Node tag of the parsed element.
    tag: Tag,
    /// Index into the main token of the node.
    main_token: TokenIndex,
    /// Left and right indexes into more information about the node.
    data: Data,

    /// Node index into the struct of arrays.
    pub const Index = u32;

    // Assert that out tag is always size 1.
    comptime {
        std.debug.assert(@sizeOf(Tag) == 1);
    }

    pub const Tag = enum {
        /// lhs is the first index to the first node
        /// rhs is the first index to the last node.
        root,
        /// lhs and rhs are undefined.
        /// main_token is the identifier token.
        identifier,
        /// `lhs.a`. `main_token` is the dot and rhs is the identifier token index.
        field_access,
        /// `lhs == rhs`.
        equal_equal,
        /// `lhs != rhs`.
        bang_equal,
        /// `lhs < rhs`
        less_than,
        /// `lhs <= rhs`
        less_or_equal,
        /// `lhs > rhs`
        greater_than,
        /// `lhs >= rhs`
        greater_or_equal,
        /// `lhs = rhs`
        assign,
        /// `lhs += rhs`
        assign_add,
        /// `lhs -= rhs`
        assign_sub,
        /// `lhs *= rhs`
        assign_mul,
        /// `lhs %= rhs`
        assign_mod,
        /// `lhs /= rhs`
        assign_div,
        /// `lhs <<= rhs`
        assign_shl,
        /// `lhs >>= rhs`
        assign_sar,
        /// `lhs >>>= rhs`
        assign_shr,
        /// `lhs &= rhs`
        assign_bit_and,
        /// `lhs |= rhs`
        assign_bit_or,
        /// `lhs ^= rhs`
        assign_bit_xor,
        /// `lhs + rhs`
        add,
        /// `lhs - rhs`
        sub,
        /// `lhs * rhs`
        mul,
        /// `lhs % rhs`
        mod,
        /// `lhs / rhs`
        div,
        /// `lhs << rhs`
        shl,
        /// `lhs >> rhs`
        sar,
        /// `lhs >>> rhs`
        shr,
        /// `lhs ** rhs`
        exponent,
        /// `lhs & rhs`
        bit_and,
        /// `lhs | rhs`
        bit_or,
        /// `lhs ^ rhs`
        bit_xor,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        bit_not,
        /// `lhs && rhs`
        conditional_and,
        /// `lhs || rhs`
        conditional_or,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        conditional_not,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        negation,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        increment,
        /// main_token is the operand.
        /// lhs is the expr and rhs is unused.
        decrement,
        /// main_token is the keyword.
        /// lhs is the expr and rhs is unused.
        delete,
        /// main token is the keyword.
        /// lhs is the node index to the type expression.
        /// rhs is unused.
        type_decl,
        /// main token is the keyword.
        /// lhs is the node index to the type expression.
        /// rhs is unused.
        new_decl,
        /// main token is `l_bracket`
        /// lhs is the expression
        /// rhs is `r_bracket`
        array_type,
        /// main token is `l_bracket`
        /// lhs is the index into extra data.
        /// rhs is unused.
        array_type_multi,
        /// `lhs[rhs]`
        array_access,
        /// main token is `l_bracket`
        /// lhs is the expression
        /// rhs is `r_bracket`
        array_init_one,
        /// main token is `l_bracket`
        /// lhs is the index into extra data.
        /// rhs is `r_bracket`
        array_init,
        /// main token is `l_paren`
        /// lhs is the expression
        /// rhs is `r_paren`
        tuple_init_one,
        /// main token is `l_paren`
        /// lhs is the index into extra data.
        /// rhs is `r_paren`
        tuple_init,
        /// main token is `l_brace`
        /// lhs is the expression
        /// rhs is `r_brace`
        struct_init_one,
        /// main token is `l_brace`
        /// lhs is the index into extra data.
        /// rhs is `r_brace`
        struct_init,
        /// main token is the keyword.
        /// lhs is the expression
        /// rhs is unused.
        payable_decl,
        /// main token is the keyword.
        /// both lhs and rhs are unused.
        string_literal,
        /// main token is the keyword.
        /// both lhs and rhs are unused.
        number_literal,
        /// main token is the keyword.
        /// lhs is the denomination keywords (gwei, wei, hours, etc)
        number_literal_sub_denomination,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the index into extra data.
        call,
        /// main token is `l_paren`
        /// lhs is the expression.
        /// rhs is the parameter.
        call_one,
        /// main token is keyword.
        /// lhs is the condition expression.
        /// rhs is then_expression.
        @"while",
        /// main token is keyword.
        /// lhs is the condition expression.
        /// rhs is while statement.
        do_while,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is then expression.
        @"for",
        /// main token is keyword.
        /// lhs is then expression.
        /// rhs is the index into extra data.
        @"if",
        /// main token is keyword.
        /// lhs is then expression.
        /// rhs is the then_expression.
        if_simple,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the index into extra data.
        @"try",
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the index into block expression.
        @"catch",
        /// main token is keyword.
        /// both rhs and lhs are unused.
        @"break",
        /// main token is keyword.
        /// lhs is the expression
        /// rhs is unused.
        @"return",
        /// main token is keyword.
        /// both rhs and lhs are unused.
        @"continue",
        /// main token is keyword.
        /// lhs is the expression to a call or call_one node.
        /// rhs is unused.
        emit,
        /// main token is keyword.
        /// lhs is the index into extra data.
        /// rhs is the block statement.
        function_decl,
        /// main token is keyword.
        /// lhs and rhs are indexes into statements.
        block_two,
        /// main token is keyword.
        /// lhs and rhs are indexes into statements that end with semicolon.
        block_two_semicolon,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements.
        block,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        block_semicolon,
        /// main token is keyword.
        /// lhs is the index to the block node.
        /// rhs is unused.
        unchecked_block,
        /// main token is keyword.
        /// lhs is the index to extra data.
        /// rhs is the identifier.
        using_directive,
        /// main token is keyword.
        /// lhs is the index to extra data.
        /// rhs is the identifier.
        using_directive_multi,
        /// main token is the operand.
        /// lhs is the identifier path.
        /// rhs is the as keyword.
        using_alias_operator,
        /// main token is `l_brace`.
        /// lhs and rhs are indexes into elements.
        contract_block_two,
        /// main token is `l_brace`.
        /// lhs and rhs are indexes into elements that end with semicolon.
        contract_block_two_semicolon,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        contract_block,
        /// main token is `l_brace`.
        /// lhs is the start of the statements.
        /// rhs is the end of the statements that end with semicolon.
        contract_block_semicolon,
        /// Throw away node used for unreserving nodes.
        unreachable_node,
        /// main token is the keyword or the index into `override_specifier`.
        /// lhs and rhs are unused.
        specifiers,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        override_specifier,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        abstract_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        abstract_decl_inheritance,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        contract_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        contract_decl_inheritance,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        interface_decl,
        /// main token is the keyword.
        /// lhs is the index into extra data.
        /// rhs is the `contract_block` node.
        interface_decl_inheritance,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the `contract_block` node.
        library_decl,
        /// `lhs` is undefined.
        /// `rhs` is the index to `path`.
        import_directive_path,
        /// `lhs` is the index into `path`
        /// `rhs` is the index into `identifier`
        import_directive_path_identifier,
        /// `lhs` is the index into extra data
        /// `rhs` is the `path`.
        import_directive_symbol,
        /// `lhs` is the index into extra data
        /// `rhs` is the `path`.
        import_directive_symbol_one,
        /// `lhs` is the  index into extra data.
        /// `rhs` is the index into `path`
        import_directive_asterisk,
        /// `lhs` is the start of the version range.
        /// `rhs` is the end of the version range.
        pragma_directive,
        /// main token is the keyword.
        /// `lhs` is the first child types.
        /// `rhs` is the second child types.
        ///
        /// Can have nested `mapping_decl` on rhs.
        mapping_decl,
        /// `lhs` and `rhs` are undefined.
        /// `main_token` is the type.
        elementary_type,
        /// `lhs` is the index to the storage modifier
        /// `rhs` is the index to the identifier
        variable_decl,
        /// `lhs` is the index to the identifier
        /// `rhs` is the index to the `elementary_type` node.
        user_defined_type,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the index into extra data.
        struct_decl,
        /// main token is the keyword.
        /// lhs is the identifier.
        /// rhs is the field.
        struct_decl_one,
        /// main token is the type
        /// lhs is unused.
        /// rhs is identifier.
        struct_field,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        event_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data.
        /// rhs is identifier.
        event_proto_simple,
        /// main token is the type
        /// lhs is the indexed keyword if exists or null node.
        /// rhs is identifier.
        event_variable_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        error_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is identifier.
        error_proto_simple,
        /// main token is the type
        /// lhs is identifier.
        /// rhs is unused.
        error_variable_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with param and with no return.
        /// rhs is identifier.
        function_proto_simple,
        /// main token is the keyword
        /// lhs is the index into extra data with params range with no return.
        /// rhs is identifier.
        function_proto_multi,
        /// main token is the keyword
        /// lhs is the index into extra data with param and with return params.
        /// rhs is identifier.
        function_proto_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range and returns params range.
        /// rhs is identifier.
        function_proto,
        /// main token is the keyword
        /// lhs is identifier.
        /// rhs is unused.
        enum_decl_one,
        /// main token is the keyword
        /// lhs is the index into extra data.
        /// rhs is unused.
        enum_decl,
        /// main token is the keyword
        /// lhs is the index into extra data with param and specifiers.
        /// rhs is the block statements.
        construct_decl_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range and specifiers.
        /// rhs is the block statements.
        construct_decl,
        /// main token is the keyword
        /// lhs is the index to the param
        /// rhs is the specifiers.
        modifier_proto_one,
        /// main token is the keyword
        /// lhs is the index into extra data with params range.
        /// rhs is the specifiers.
        modifier_proto,
        /// main token is the keyword
        /// lhs is the proto.
        /// rhs is the block statements.
        modifier_decl,
        /// main token is the index into extra data.
        /// lhs and rhs are unused.
        modifier_specifiers,
        /// main token is the state keyword or null_node
        /// lhs is the type index
        /// rhs is the expression or null_node.
        state_variable_decl,
    };

    /// Range used for params and others
    pub const Range = struct {
        start: Index,
        end: Index,
    };
    /// Node lhs and rhs index data.
    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };
    /// if expressions extra data.
    pub const If = struct {
        then_expression: Index,
        else_expression: Index,
    };

    /// For expression extra data.
    pub const For = struct {
        condition_one: Index,
        condition_two: Index,
        condition_three: Index,
    };

    /// Try expression extra data.
    pub const Try = struct {
        returns: Index,
        expression: Index,
        block_statement: Index,
    };

    /// Constructor definition extra data.
    /// Mostly used if the constructor has multiple params.
    pub const ConstructorProto = struct {
        params_start: Index,
        params_end: Index,
        specifiers: Index,
    };

    /// Constructor definition extra data.
    /// Mostly used if the constructor has a single param.
    pub const ConstructorProtoOne = struct {
        param: Index,
        specifiers: Index,
    };

    /// Function types definition extra data.
    /// Mostly used if the function has a single param.
    pub const FnProtoTypeOne = struct {
        param: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    /// Function types definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const FnProtoType = struct {
        params_start: Index,
        params_end: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a single param.
    pub const FnProtoOne = struct {
        param: Index,
        specifiers: Index,
        identifier: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const FnProto = struct {
        params_start: Index,
        params_end: Index,
        specifiers: Index,
        identifier: Index,
    };

    /// Contract, Interface inheritance definition extra data.
    /// Mostly used if its a single.
    pub const ContractInheritanceOne = struct {
        identifier: Index,
        inheritance: Index,
    };

    /// Contract, Interface inheritance definition extra data.
    /// Mostly used if its it has multiple ones.
    pub const ContractInheritance = struct {
        identifier: Index,
        inheritance_start: Index,
        inheritance_end: Index,
    };

    /// Event definition extra data.
    /// Mostly used if the function has a single param.
    pub const EventProtoOne = struct {
        params: Index,
        anonymous: Index,
    };

    /// Function definition extra data.
    /// Mostly used if the function has a multiple params.
    pub const EventProto = struct {
        params_start: Index,
        params_end: Index,
        anonymous: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with a asterisk
    pub const ImportAsterisk = struct {
        identifier: Index,
        from: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with an symbol.
    pub const ImportSymbolOne = struct {
        symbol: Index,
        from: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with multiple symbols.
    pub const ImportSymbol = struct {
        symbol_start: Index,
        symbol_end: Index,
        from: Index,
    };

    /// Extra data structure for nodes where
    /// the using directive as a single alias
    pub const UsingDirective = struct {
        aliases: Index,
        for_alias: Index,
        target_type: Index,
    };

    /// Extra data structure for nodes where
    /// the import directive starts with multiple alias.
    pub const UsingDirectiveMulti = struct {
        aliases_start: Index,
        aliases_end: Index,
        for_alias: Index,
        target_type: Index,
    };
};

/// Ast error structure used to keep track of parsing errors.
pub const Error = struct {
    tag: Tag,
    is_note: bool = false,
    /// True if `token` points to the token before the token causing an issue.
    token_is_prev: bool = false,
    token: TokenIndex,
    extra: union {
        none: void,
        expected_tag: Token.Tag,
    } = .{ .none = {} },

    pub const Tag = enum {
        same_line_doc_comment,
        expected_token,
        expected_semicolon,
        expected_pragma_version,
        expected_import_path_alias_asterisk,
        expected_comma_after,
        expected_r_brace,
        expected_elementary_or_identifier_path,
        expected_suffix,
        expected_variable_decl,
        expected_struct_field,
        expected_event_param,
        expected_error_param,
        expected_type_expr,
        expected_prefix_expr,
        trailing_comma,
        chained_comparison_operators,
        expected_expr,
        expected_statement,
        expected_function_call,
        expected_block_or_assignment_statement,
        expected_semicolon_or_lbrace,
        expected_else_or_semicolon,
        already_seen_specifier,
        expected_contract_element,
        expected_contract_block,
        unattached_doc_comment,
        expected_source_unit_expr,
        expected_operator,
    };
};
