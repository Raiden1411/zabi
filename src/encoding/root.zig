/// The custom abi encoder.
pub const abi_encoding = @import("encoder.zig");
/// The custom abi encoder dedicated for log topics.
pub const logs_encoding = @import("logs.zig");
/// RLP Encoding. Most zig types are supported.
pub const rlp = @import("rlp.zig");
/// Transaction serializer.
pub const serialize = @import("serialize.zig");
/// SSZ encoding. Most zig types are supported.
pub const ssz = @import("ssz.zig");

test "Encoding Root" {
    _ = @import("encoder.test.zig");
    _ = @import("logs.test.zig");
    _ = @import("rlp.test.zig");
    _ = @import("serialize.test.zig");
    _ = @import("ssz.test.zig");
}
