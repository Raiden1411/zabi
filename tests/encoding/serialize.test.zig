const serialize = @import("zabi-encoding").serialize;
const std = @import("std");
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

// Types
const Hash = types.Hash;
const Signature = @import("zabi-crypto").signature.Signature;
const Signer = @import("zabi-crypto").Signer;

const serializeTransaction = serialize.serializeTransaction;
const serializeCancunTransaction = serialize.serializeCancunTransaction;
const serializeTransactionLegacy = serialize.serializeTransactionLegacy;
const serializeTransactionEIP1559 = serialize.serializeTransactionEIP1559;
const serializeTransactionEIP2930 = serialize.serializeTransactionEIP2930;

test "Base eip 4844" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeCancunTransaction(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .maxFeePerGas = try utils.parseGwei(2),
        .gas = 0,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{},
        .maxFeePerBlobGas = 0,
        .blobVersionedHashes = &.{[_]u8{0} ** 32},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("03f8500145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c080e1a00000000000000000000000000000000000000000000000000000000000000000", hex);
}

test "Base eip 1559" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");

    const base = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .maxFeePerGas = try utils.parseGwei(2),
        .gas = 0,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip 1559" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const zero = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 0,
        .maxPriorityFeePerGas = 0,
        .maxFeePerGas = 0,
        .gas = 0,
        .to = to,
        .value = 0,
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02dd018080808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 1559" {
    const min = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 0,
        .maxPriorityFeePerGas = 0,
        .maxFeePerGas = 0,
        .gas = 0,
        .to = null,
        .value = 0,
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02c90180808080808080c0", hex);
}

test "Base eip1559 with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .maxFeePerGas = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ef01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip1559 with accessList" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .maxFeePerGas = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{
            .{ .address = [_]u8{0} ** 20, .storageKeys = &.{ [_]u8{0} ** 31 ++ [1]u8{1}, [_]u8{0} ** 31 ++ [1]u8{2} } },
        },
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f88b01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip1559 with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .maxFeePerGas = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = @constCast(&[_]u8{ 0x12, 0x34 }),
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f101458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip 2930" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP2930(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 0,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip eip2930" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const zero = try serializeTransactionEIP2930(testing.allocator, .{
        .chainId = 1,
        .nonce = 0,
        .gasPrice = 0,
        .gas = 0,
        .to = to,
        .value = 0,
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01dc0180808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 2930" {
    const min = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01c801808080808080c0", hex);
}

test "Base eip2930 with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP2930(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{},
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ea0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip2930 with accessList" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP2930(testing.allocator, .{
        .chainId = 1,
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
        .accessList = &.{
            .{ .address = [_]u8{0} ** 20, .storageKeys = &.{ [_]u8{0} ** 31 ++ [1]u8{1}, [_]u8{0} ** 31 ++ [1]u8{2} } },
        },
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01f8860145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip2930 with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = @constCast(&[_]u8{ 0x12, 0x34 }), .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ec0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip legacy" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionLegacy(testing.allocator, .{
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 0,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Zero eip legacy" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const zero = try serializeTransactionLegacy(testing.allocator, .{
        .nonce = 0,
        .gasPrice = 0,
        .gas = 0,
        .to = to,
        .value = 0,
        .data = null,
    }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da80808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080", hex);
}

test "Minimal eip legacy" {
    const min = try serializeTransactionLegacy(testing.allocator, .{
        .nonce = 0,
        .gasPrice = 0,
        .gas = 0,
        .to = null,
        .value = 0,
        .data = null,
    }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("c6808080808080", hex);
}

test "Base legacy with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionLegacy(testing.allocator, .{
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e845847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Base legacy with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base = try serializeTransactionLegacy(testing.allocator, .{
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 21001,
        .to = to,
        .value = try utils.parseEth(1),
        .data = @constCast(&[_]u8{ 0x12, 0x34 }),
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("ea45847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234", hex);
}

test "Serialize Transaction Base" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const base_legacy = try serializeTransaction(testing.allocator, .{
        .legacy = .{
            .nonce = 69,
            .gasPrice = try utils.parseGwei(2),
            .gas = 0,
            .to = to,
            .value = try utils.parseEth(1),
            .data = null,
        },
    }, null);
    defer testing.allocator.free(base_legacy);

    const hex_legacy = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_legacy)});
    defer testing.allocator.free(hex_legacy);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex_legacy);

    const base_2930 = try serializeTransaction(testing.allocator, .{
        .berlin = .{
            .chainId = 1,
            .nonce = 69,
            .gasPrice = try utils.parseGwei(2),
            .gas = 0,
            .to = to,
            .value = try utils.parseEth(1),
            .data = null,
            .accessList = &.{},
        },
    }, null);
    defer testing.allocator.free(base_2930);

    const hex_2930 = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_2930)});
    defer testing.allocator.free(hex_2930);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex_2930);

    const base = try serializeTransaction(testing.allocator, .{
        .london = .{
            .chainId = 1,
            .nonce = 69,
            .maxPriorityFeePerGas = try utils.parseGwei(2),
            .maxFeePerGas = try utils.parseGwei(2),
            .gas = 0,
            .to = to,
            .value = try utils.parseEth(1),
            .data = null,
            .accessList = &.{},
        },
    }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Serialize eip1559 with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");

    const encoded = try serializeTransactionEIP1559(testing.allocator, .{
        .chainId = 31337,
        .nonce = 0,
        .maxFeePerGas = try utils.parseGwei(2),
        .data = null,
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .gas = 21001,
        .value = try utils.parseEth(1),
        .accessList = &.{},
        .to = to,
    }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f874827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a0d4d68c02302962fa53289fda5616c9e19a9d63b3956d63d177097143b2093e3ea025e1dd76721b4fc48eb5e2f91bf9132699036deccd45b3fa9d77b1d9b7628fb2", hex);
}

test "Serialize eip2930 with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("01ec827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");

    const encoded = try serializeTransactionEIP2930(testing.allocator, .{
        .chainId = 31337,
        .nonce = 0,
        .gasPrice = try utils.parseGwei(2),
        .data = null,
        .gas = 21001,
        .value = try utils.parseEth(1),
        .accessList = &.{},
        .to = to,
    }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01f86f827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a0855b7b9d7f752dd108609930a5dd9ced9c131936d84d5c302a6a4edd0c50101aa075fc0c4af1cf18d5bf15a9960b1988d2fbf9ae6351a957dd572e95adbbf8c26f", hex);
}

test "Serialize legacy with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("ed8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080827a698080");

    const encoded = try serializeTransactionLegacy(testing.allocator, .{
        .chainId = 31337,
        .nonce = 0,
        .gasPrice = try utils.parseGwei(2),
        .data = null,
        .gas = 21001,
        .value = try utils.parseEth(1),
        .to = to,
    }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("f86d8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a76400008082f4f5a0a918ad4845f590df2667eceacdb621dcedf9c3efefd7f783d5f45840131c338da059a2e246acdab8cfdc51b764ec20e4a59ca1998d8a101dba01cd1cb34c1179a0", hex);
}

fn generateSignature(message: []const u8) !Signature {
    var buffer_hex: Hash = undefined;
    _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    const wallet = try Signer.init(buffer_hex);
    const buffer = try testing.allocator.alloc(u8, message.len / 2);
    defer testing.allocator.free(buffer);

    _ = try std.fmt.hexToBytes(buffer, message);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(buffer, &hash, .{});
    return try wallet.sign(hash);
}
