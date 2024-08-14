/// The custom abi decoder.
pub const abi_decoder = @import("decoder.zig");
/// The custom abi decoder dedicated for log topics.
pub const logs_decoder = @import("logs_decode.zig");
/// Parses serialized transactions.
pub const parse_transacition = @import("parse_transaction.zig");
/// The RLP decoder.
pub const rlp = @import("rlp_decode.zig");
/// The SSZ decoder.
pub const ssz = @import("ssz_decode.zig");

test "Decoding Root" {
    _ = @import("decoder.test.zig");
    _ = @import("logs_decode.test.zig");
    _ = @import("parse_transaction.test.zig");
    _ = @import("rlp_decode.test.zig");
    _ = @import("ssz_decode.test.zig");
}
