const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Token = tokenizer.Token;

pub const Offset = u32;
pub const TokenIndex = u32;

/// Struct of arrays for the `Node` members.
pub const NodeList = std.MultiArrayList(Node);
/// Struct of arrays for the `Token.Tag` members.
pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: Offset,
});

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
        root,
        identifier,
        /// lhs is the index into extra data.
        /// rhs is the initialization expression, if any.
        /// `main_token` is the type.
        global_var_decl,
        /// `uint foo = rhs`
        /// lhs is the index into extra data.
        /// `main_token` is the type.
        simple_var_decl,
        /// `lhs.a`. `main_token` is the dot and rhs is the identifier token index.
        field_access,
        /// `lhs == rhs`.
        equal_equal,
        /// `lhs != rhs`.
        bang_equal,

        less_than,
        less_or_equal,

        greater_than,
        greater_or_equal,

        assign,
        assign_add,
        assign_sub,
        assign_mul,
        assign_mod,
        assign_div,
        assign_shl,
        assign_shr,
        assign_sar,
        assign_bit_and,
        assign_bit_or,
        assign_bit_xor,

        add,
        sub,
        mul,
        mod,
        div,
        shl,
        shr,
        sar,
        exponent,

        bit_and,
        bit_or,
        bit_xor,
        bit_not,

        conditional_and,
        conditional_or,
        conditional_not,

        negation,

        increment,
        decrement,

        delete,

        type_decl,
        new_decl,

        array_type,
        array_type_multi,

        array_access,
        array_init_one,
        array_init,

        tuple_init_one,
        tuple_init,

        struct_init_one,
        struct_init,

        payable_decl,

        string_literal,

        number_literal,
        number_literal_sub_denomination,

        call,
        call_one,

        @"while",
        do_while,
        @"for",
        @"if",
        if_simple,
        @"try",
        @"catch",
        @"break",
        @"return",
        @"continue",
        emit,
        function_decl,

        block_two,
        block_two_semicolon,
        block,
        block_semicolon,
        unchecked_block,

        using_directive,
        using_directive_multi,
        using_alias_operator,

        contract_block_two,
        contract_block_two_semicolon,
        contract_block,
        contract_block_semicolon,

        unreachable_node,

        specifiers,
        override_specifier,

        abstract_decl,
        abstract_decl_inheritance,
        contract_decl,
        contract_decl_inheritance,
        interface_decl,
        interface_decl_inheritance,
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

        struct_decl,
        struct_decl_one,
        struct_field,

        event_proto_multi,
        event_proto_simple,
        event_variable_decl,

        error_proto_multi,
        error_proto_simple,
        error_variable_decl,

        function_proto_simple,
        function_proto_multi,
        function_proto_one,
        function_proto,

        enum_decl_one,
        enum_decl,

        construct_decl_one,
        construct_decl,

        modifier_proto_one,
        modifier_proto,
        modifier_decl,
        modifier_specifiers,

        state_variable_decl,
    };

    pub const Range = struct {
        start: Index,
        end: Index,
    };

    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };

    pub const If = struct {
        then_expression: Index,
        else_expression: Index,
    };

    pub const For = struct {
        condition_one: Index,
        condition_two: Index,
        condition_three: Index,
    };

    pub const Try = struct {
        returns: Index,
        expression: Index,
        block_statement: Index,
    };

    pub const ConstructorProto = struct {
        params_start: Index,
        params_end: Index,
        specifiers: Index,
    };

    pub const ConstructorProtoOne = struct {
        param: Index,
        specifiers: Index,
    };

    pub const FnProtoTypeOne = struct {
        param: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    pub const ContractInheritanceOne = struct {
        identifier: Index,
        inheritance: Index,
    };

    pub const ContractInheritance = struct {
        identifier: Index,
        inheritance_start: Index,
        inheritance_end: Index,
    };

    pub const FnProtoType = struct {
        params_start: Index,
        params_end: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    pub const FnProtoOne = struct {
        param: Index,
        specifiers: Index,
        identifier: Index,
    };

    pub const FnProto = struct {
        params_start: Index,
        params_end: Index,
        /// Populated if (external|public|internal|private) is present.
        specifiers: Index,
        identifier: Index,
    };

    pub const EventProtoOne = struct {
        params: Index,
        anonymous: Index,
    };

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

    pub const UsingDirective = struct {
        aliases: Index,
        for_alias: Index,
        target_type: Index,
    };

    pub const UsingDirectiveMulti = struct {
        aliases_start: Index,
        aliases_end: Index,
        for_alias: Index,
        target_type: Index,
    };
};

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
