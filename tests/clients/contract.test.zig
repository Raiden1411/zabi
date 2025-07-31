const abitypes = @import("zabi").abi.abitypes;
const Wallet = @import("zabi").clients.Wallet;
const std = @import("std");
const testing = std.testing;
const types = @import("zabi").types.ethereum;
const utils = @import("zabi").utils.utils;

const Hash = types.Hash;
const HttpProvider = @import("zabi").clients.Provider.HttpProvider;
const WebsocketProvider = @import("zabi").clients.Provider.WebsocketProvider;
const IpcProvider = @import("zabi").clients.Provider.IpcProvider;

test "DeployContract" {
    {
        const abi: abitypes.Constructor = .{
            .type = .constructor,
            .inputs = &.{},
            .stateMutability = .nonpayable,
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, true);
        defer wallet.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try wallet.deployContract(abi, .{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
    {
        const abi: abitypes.Constructor = .{
            .type = .constructor,
            .inputs = &.{},
            .stateMutability = .nonpayable,
        };

        var client = try IpcProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .path = "/tmp/anvil.ipc" },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, true);
        defer wallet.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try wallet.deployContract(abi, .{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
    {
        const abi: abitypes.Constructor = .{
            .type = .constructor,
            .inputs = &.{},
            .stateMutability = .nonpayable,
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, true);
        defer wallet.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try wallet.deployContract(abi, .{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
}

test "WriteContract" {
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.writeContractFunction(abi, .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"),
            true,
        }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.writeContractFunction(abi, .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"),
            true,
        }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        var client = try IpcProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .path = "/tmp/anvil.ipc" },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.writeContractFunction(abi, .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"),
            true,
        }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };
        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.writeContractFunctionComptime(abi, .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
}

test "SimulateWriteCall" {
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try HttpProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.simulateWriteCall(abi, .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.simulateWriteCall(abi, .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        var client = try IpcProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .path = "/tmp/anvil.ipc" },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.simulateWriteCall(abi, .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi: abitypes.Function = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        };

        const uri = try std.Uri.parse("http://localhost:6969/");
        var client = try WebsocketProvider.init(.{
            .allocator = testing.allocator,
            .network_config = .{
                .endpoint = .{ .uri = uri },
            },
        });
        defer client.deinit();
        try client.readLoopSeperateThread();

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var wallet = try Wallet.init(buffer_hex, testing.allocator, &client.provider, false);
        defer wallet.deinit();

        const result = try wallet.simulateWriteCallComptime(abi, .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
}
