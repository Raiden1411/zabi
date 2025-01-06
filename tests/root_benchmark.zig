//! Runs the tests as a benchmark without the client tests since those are network bound.
test {
    // _ = @import("abi/root.zig");
    // _ = @import("ast/tokenizer.test.zig");
    _ = @import("ast/parser.test.zig");
    // _ = @import("clients/url.test.zig");
    // _ = @import("clients/ens_utils.test.zig");
    // _ = @import("clients/parse_deposit.test.zig");
    // _ = @import("clients/serialize_deposit.test.zig");
    // _ = @import("clients/utils.test.zig");
    // _ = @import("crypto/root.zig");
    // _ = @import("decoding/root.zig");
    // _ = @import("encoding/root.zig");
    // _ = @import("evm/root.zig");
    // _ = @import("human-readable/root.zig");
    // _ = @import("meta/root.zig");
    // _ = @import("utils/root.zig");
}
