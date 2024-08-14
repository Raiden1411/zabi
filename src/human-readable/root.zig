/// Custom Solidity lexer.
const lexer = @import("lexer.zig");
/// Custom solidity tokens.
const tokens = @import("tokens.zig");

/// The abi parser.
pub const parsing = @import("abi_parsing.zig");

/// Custom solidity lexer. Not a fully compatable lexer.
pub const Lexer = lexer.Lexer;
/// Custom solidity parser. Not a fully compatable parser.
pub const Parser = @import("Parser.zig");
/// Solidity tags.
pub const TokensTag = tokens.Tag;

test "Human Readable Root" {
    _ = @import("abi_parsing.test.zig");
    _ = @import("lexer.test.zig");
}
