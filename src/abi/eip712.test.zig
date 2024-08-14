const eip712 = @import("eip712.zig");
const std = @import("std");
const testing = std.testing;

// Types
const TypedDataDomain = eip712.TypedDataDomain;

// Functions
const hashStruct = eip712.hashStruct;
const hashTypedData = eip712.hashTypedData;

test "With Message" {
    const fields = .{
        .Person = &.{
            .{ .name = "name", .type = "string" },
            .{ .name = "wallet", .type = "address" },
        },
        .Mail = &.{
            .{ .name = "from", .type = "Person" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
        },
    };

    const hash = try hashStruct(testing.allocator, fields, "Mail", .{
        .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" },
        .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" },
        .contents = "Hello, Bob!",
    });

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e", hex);
}

test "With Domain" {
    const domain: TypedDataDomain = .{
        .name = "Ether Mail",
        .version = "1",
        .chainId = 1,
        .verifyingContract = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    };
    const types = .{
        .EIP712Domain = &.{
            .{ .type = "string", .name = "name" },
            .{ .name = "version", .type = "string" },
            .{ .name = "chainId", .type = "uint256" },
            .{ .name = "verifyingContract", .type = "address" },
        },
        .Person = &.{
            .{ .name = "name", .type = "string" },
            .{ .name = "wallet", .type = "address" },
        },
        .Mail = &.{
            .{ .name = "from", .type = "Person" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
        },
    };

    const hash = try hashStruct(testing.allocator, types, "EIP712Domain", domain);

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xf2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f", hex);
}

test "EIP712 Minimal" {
    const hash = try hashTypedData(testing.allocator, .{ .EIP712Domain = .{} }, "EIP712Domain", .{}, .{});
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x8d4a3f4082945b7879e2b55f181c31a77c8c0a464b70669458abbaaf99de4c38", hex);
}

test "EIP712 Example" {
    const domain: TypedDataDomain = .{
        .name = "Ether Mail",
        .version = "1",
        .chainId = 1,
        .verifyingContract = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    };
    const types = .{
        .EIP712Domain = &.{
            .{ .type = "string", .name = "name" },
            .{ .name = "version", .type = "string" },
            .{ .name = "chainId", .type = "uint256" },
            .{ .name = "verifyingContract", .type = "address" },
        },
        .Person = &.{
            .{ .name = "name", .type = "string" },
            .{ .name = "wallet", .type = "address" },
        },
        .Mail = &.{
            .{ .name = "from", .type = "Person" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
        },
    };

    const hash = try hashTypedData(testing.allocator, types, "Mail", domain, .{
        .from = .{
            .name = "Cow",
            .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
        },
        .to = .{
            .name = "Bob",
            .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
        },
        .contents = "Hello, Bob!",
    });

    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2", hex);
}

test "EIP712 Complex" {
    const domain: TypedDataDomain = .{
        .name = "Ether Mail 🥵",
        .version = "1.1.1",
        .chainId = 1,
        .verifyingContract = "0x0000000000000000000000000000000000000000",
    };
    const types = .{
        .EIP712Domain = &.{
            .{ .type = "string", .name = "name" },
            .{ .type = "string", .name = "version" },
            .{ .type = "uint256", .name = "chainId" },
            .{ .type = "address", .name = "verifyingContract" },
        },
        .Name = &.{
            .{ .type = "string", .name = "first" },
            .{ .name = "last", .type = "string" },
        },
        .Person = &.{
            .{ .name = "name", .type = "Name" },
            .{ .name = "wallet", .type = "address" },
            .{ .type = "string[3]", .name = "favoriteColors" },
            .{ .name = "foo", .type = "uint256" },
            .{ .name = "age", .type = "uint8" },
            .{ .name = "isCool", .type = "bool" },
        },
        .Mail = &.{
            .{ .name = "timestamp", .type = "uint256" },
            .{ .type = "Person", .name = "from" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
            .{ .name = "hash", .type = "bytes" },
        },
    };

    const message = .{
        .timestamp = 1234567890,
        .contents = "Hello, Bob! 🖤",
        .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .from = .{
            .name = .{ .first = "Cow", .last = "Burns" },
            .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
            .foo = 123123123123123123,
            .age = 69,
            .favoriteColors = &.{ "red", "green", "blue" },
            .isCool = false,
        },
        .to = .{
            .name = .{ .first = "Bob", .last = "Builder" },
            .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
            .foo = 123123123123123123,
            .age = 70,
            .favoriteColors = &.{ "orange", "yellow", "green" },
            .isCool = true,
        },
    };

    const hash = try hashTypedData(testing.allocator, types, "Mail", domain, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x9a74cb859ad30835ffb2da406423233c212cf6dd78e6c2c98b0c9289568954ae", hex);
}

test "EIP712 Complex empty domain data" {
    const types = .{
        .EIP712Domain = &.{},
        .Name = &.{
            .{ .type = "string", .name = "first" },
            .{ .name = "last", .type = "string" },
        },
        .Person = &.{
            .{ .name = "name", .type = "Name" },
            .{ .name = "wallet", .type = "address" },
            .{ .type = "string[3]", .name = "favoriteColors" },
            .{ .name = "foo", .type = "uint256" },
            .{ .name = "age", .type = "uint8" },
            .{ .name = "isCool", .type = "bool" },
        },
        .Mail = &.{
            .{ .name = "timestamp", .type = "uint256" },
            .{ .type = "Person", .name = "from" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
            .{ .name = "hash", .type = "bytes" },
        },
    };

    const message = .{
        .timestamp = 1234567890,
        .contents = "Hello, Bob! 🖤",
        .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .from = .{
            .name = .{ .first = "Cow", .last = "Burns" },
            .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
            .foo = 123123123123123123,
            .age = 69,
            .favoriteColors = &.{ "red", "green", "blue" },
            .isCool = false,
        },
        .to = .{
            .name = .{ .first = "Bob", .last = "Builder" },
            .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
            .foo = 123123123123123123,
            .age = 70,
            .favoriteColors = &.{ "orange", "yellow", "green" },
            .isCool = true,
        },
    };

    const hash = try hashTypedData(testing.allocator, types, "Mail", .{}, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x14ed1dbbfecbe5de3919f7ea47daafdf3a29dfbb60dd88d85509f79773d503a5", hex);
}

test "EIP712 Complex null domain data" {
    const types = .{
        .EIP712Domain = &.{},
        .Name = &.{
            .{ .type = "string", .name = "first" },
            .{ .name = "last", .type = "string" },
        },
        .Person = &.{
            .{ .name = "name", .type = "Name" },
            .{ .name = "wallet", .type = "address" },
            .{ .type = "string[3]", .name = "favoriteColors" },
            .{ .name = "foo", .type = "uint256" },
            .{ .name = "age", .type = "uint8" },
            .{ .name = "isCool", .type = "bool" },
        },
        .Mail = &.{
            .{ .name = "timestamp", .type = "uint256" },
            .{ .type = "Person", .name = "from" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
            .{ .name = "hash", .type = "bytes" },
        },
    };

    const message = .{
        .timestamp = 1234567890,
        .contents = "Hello, Bob! 🖤",
        .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .from = .{
            .name = .{ .first = "Cow", .last = "Burns" },
            .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
            .foo = 123123123123123123,
            .age = 69,
            .favoriteColors = &.{ "red", "green", "blue" },
            .isCool = false,
        },
        .to = .{
            .name = .{ .first = "Bob", .last = "Builder" },
            .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
            .foo = 123123123123123123,
            .age = 70,
            .favoriteColors = &.{ "orange", "yellow", "green" },
            .isCool = true,
        },
    };

    const hash = try hashTypedData(testing.allocator, types, "Mail", null, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xad520b9936265259bb247eb16258d7b59c02dca1b278c7590f19d5ee03d362e8", hex);
}

test "EIP712 Complex empty domain name" {
    const types = .{
        .EIP712Domain = &.{
            .{ .type = "string", .name = "name" },
        },
        .Name = &.{
            .{ .type = "string", .name = "first" },
            .{ .name = "last", .type = "string" },
        },
        .Person = &.{
            .{ .name = "name", .type = "Name" },
            .{ .name = "wallet", .type = "address" },
            .{ .type = "string[3]", .name = "favoriteColors" },
            .{ .name = "foo", .type = "uint256" },
            .{ .name = "age", .type = "uint8" },
            .{ .name = "isCool", .type = "bool" },
        },
        .Mail = &.{
            .{ .name = "timestamp", .type = "uint256" },
            .{ .type = "Person", .name = "from" },
            .{ .name = "to", .type = "Person" },
            .{ .name = "contents", .type = "string" },
            .{ .name = "hash", .type = "bytes" },
        },
    };

    const message = .{
        .timestamp = 1234567890,
        .contents = "Hello, Bob! 🖤",
        .hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .from = .{
            .name = .{ .first = "Cow", .last = "Burns" },
            .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
            .foo = 123123123123123123,
            .age = 69,
            .favoriteColors = &.{ "red", "green", "blue" },
            .isCool = false,
        },
        .to = .{
            .name = .{ .first = "Bob", .last = "Builder" },
            .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
            .foo = 123123123123123123,
            .age = 70,
            .favoriteColors = &.{ "orange", "yellow", "green" },
            .isCool = true,
        },
    };

    const hash = try hashTypedData(testing.allocator, types, "Mail", .{ .name = "" }, message);
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0xc3f4f9ebd774352940f60aebbc83fcee20d0b17eb42bd1b20c91a748001ecb53", hex);
}
