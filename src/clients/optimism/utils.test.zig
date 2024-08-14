const op_utils = @import("utils.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const getL2HashFromL1DepositInfo = op_utils.getL2HashFromL1DepositInfo;
const getSourceHash = op_utils.getSourceHash;
const getWithdrawalHashStorageSlot = op_utils.getWithdrawalHashStorageSlot;

test "Source Hash" {
    const hash = getSourceHash(.user_deposit, 196, try utils.hashToBytes("0x9ba3933dc6ce43c145349770a39c30f9b647f17668f004bd2e05c80a2e7262f7"));

    try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0xd0868c8764d81f1749edb7dec4a550966963540d9fe50aefce8cdb38ea7b2213"));
}

test "L2HashFromL1DepositInfo" {
    {
        var buffer: [512]u8 = undefined;

        const opaque_bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045000000000000520800");
        const hash = try getL2HashFromL1DepositInfo(testing.allocator, .{
            .opaque_data = opaque_bytes,
            .from = try utils.addressToBytes("0x1a1E021A302C237453D3D45c7B82B19cEEB7E2e6"),
            .to = try utils.addressToBytes("0x1a1E021A302C237453D3D45c7B82B19cEEB7E2e6"),
            .l1_blockhash = try utils.hashToBytes("0x634c52556471c589f42db9131467e0c9484f5c73049e32d1a74e2a4ce0f91d57"),
            .log_index = 109,
            .domain = .user_deposit,
        });

        try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0x0a60b983815ed475c5919609025204a479654d93afc610feca7d99ae0befc329"));
    }
    {
        var buffer: [512]u8 = undefined;

        const opaque_bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000520800");
        const hash = try getL2HashFromL1DepositInfo(testing.allocator, .{
            .opaque_data = opaque_bytes,
            .from = try utils.addressToBytes("0x80B01fDEd19145FFB893123eC38eBba31b4043Ee"),
            .to = try utils.addressToBytes("0x80B01fDEd19145FFB893123eC38eBba31b4043Ee"),
            .l1_blockhash = try utils.hashToBytes("0x9375ba075993fcc3cd3f66ef1fc45687aeccc04edfc06da2bc7cdb8984046ed7"),
            .log_index = 36,
            .domain = .user_deposit,
        });

        try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0xb81d4b3fe43986c51d29bf29a8c68c9a301c074531d585298bc1e03df68c8459"));
    }
}

test "GetWithdrawalHashStorageSlot" {
    const slot = getWithdrawalHashStorageSlot(try utils.hashToBytes("0xB1C3824DEF40047847145E069BF467AA67E906611B9F5EF31515338DB0AABFA2"));

    try testing.expectEqualSlices(u8, &slot, &try utils.hashToBytes("0x4a932049252365b3eedbc5190e18949f2ec11f39d3bef2d259764799a1b27d99"));
}
