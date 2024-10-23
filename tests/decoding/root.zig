test "Decoding root" {
    _ = @import("decoder.test.zig");
    _ = @import("logs_decode.test.zig");
    _ = @import("rlp_decode.test.zig");
    _ = @import("parse_transaction.test.zig");
    _ = @import("ssz_decode.test.zig");
}
