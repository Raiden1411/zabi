const std = @import("std");
const token = @import("tokens.zig");

const Allocator = std.mem.Allocator;
const TokenTag = token.Tag.SoliditySyntax;

const Ast = @This();

/// Index used for the parser.
pub const TokenIndex = u32;

/// Struct of arrays for the `Node` members.
pub const NodeList = std.MultiArrayList(Node);

/// Struct of arrays for the `Token.Tag` members.
pub const TokenList = std.ArrayListUnmanaged(TokenTag);

/// Source code slice.
source: [:0]const u8,
/// Struct of arrays containing the token tags
/// and token starts.
tokens: []const TokenTag,
/// Struct of arrays containing all node information.
nodes: NodeList.Slice,
/// Slice of extra data produces by the parser.
extra_data: []const Node.Index,

/// Clears any allocated memory from the `Ast`.
pub fn deinit(self: *Ast, allocator: Allocator) void {
    self.tokens.deinit(allocator);
    self.nodes.deinit(allocator);
    allocator.free(self.extra_data);
    allocator.free(self.errors);
}

pub const Node = struct {
    tag: Tag,
    data: Data,
    main_token: TokenIndex,

    pub const Index = u32;

    // Assert that out tag is always size 1.
    comptime {
        std.debug.assert(@sizeOf(Tag) == 1);
    }

    pub const Tag = enum {
        root,
        identifier,
        unreachable_node,

        constructor_proto_simple,
        constructor_proto_multi,

        event_proto_simple,
        event_proto_multi,

        error_proto_simple,
        error_proto_multi,

        function_proto,
        function_proto_one,
        function_proto_multi,
        function_proto_simple,

        array_type,
        elementary_type,
        tuple_type,
        tuple_type_one,

        specifiers,

        struct_decl,
        struct_decl_one,
        struct_field,

        var_decl,
        error_var_decl,
        event_var_decl,
    };

    pub const Data = struct {
        lhs: Index,
        rhs: Index,
    };

    pub const Range = struct {
        start: Index,
        end: Index,
    };

    pub const FunctionProto = struct {
        specifiers: Node.Index,
        identifier: TokenIndex,
        params_start: Node.Index,
        params_end: Node.Index,
    };

    pub const FunctionProtoOne = struct {
        specifiers: Node.Index,
        identifier: TokenIndex,
        param: Node.Index,
    };

    pub const FunctionProtoMulti = struct {
        identifier: TokenIndex,
        params_start: Node.Index,
        params_end: Node.Index,
    };

    pub const FunctionProtoSimple = struct {
        identifier: TokenIndex,
        param: Node.Index,
    };
};
