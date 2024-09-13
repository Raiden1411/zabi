const std = @import("std");
const tokenizer = @import("tokenizer.zig");

const Token = tokenizer.Token;

pub const Offset = u32;
pub const TokenIndex = u32;

pub const NodeList = std.MultiArrayList(Node);

pub const Node = struct {
    tag: Tag,
    main_token: TokenIndex,
    data: Data,

    pub const Index = u32;

    comptime {
        std.debug.assert(@sizeOf(Tag) == 1);
    }

    pub const Tag = enum {
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
        bit_and,
        bit_or,
        bit_xor,
        bit_not,
        conditional_and,
        conditional_or,
        conditional_not,
        negation,
        array_type,
        array_access,
        string_literal,
        call,
        call_one,
        @"while",
        @"for",
        @"if",
        @"try",
        @"catch",
        @"break",
        @"return",
        function_proto_simple,
        function_proto_multi,
        function_proto_one,
        function_proto,
        function_decl,
        container_decl,
        container_field,
        block,
        block_semicolon,
        event_proto_multi,
        event_proto_simple,
        event_proto_one,
        event_proto,
        event_decl,
        error_proto_multi,
        error_proto_simple,
        error_proto_one,
        error_proto,
        error_decl,
        contract_decl,
        interface_decl,
        library_decl,
        import_directive_path,
        import_directive_symbol,
        import_directive_asterisk,
        pragma_directive,
    };

    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };

    pub const If = struct {
        then_expression: Index,
        else_expression: Index,
    };

    pub const While = struct {
        condition_expression: Index,
        then_expression: Index,
    };

    pub const For = struct {
        condition_expression: Index,
        then_expression: Index,
    };

    pub const FnProtoOne = struct {
        param: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    pub const FnProto = struct {
        params_start: Index,
        params_end: Index,
        /// Populated if (external|public|internal|private) is present.
        visibility: Index,
        /// Populated if (payable|view|pure) is present
        mutability: Index,
    };

    pub const ImportAsterisk = struct {
        identifier: Index,
        from: Index,
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
        expected_token,
        expected_pragma_version,
        expected_import_path_alias_asterisk,
        expected_comma_after,
        expected_r_brace,
    };
};
