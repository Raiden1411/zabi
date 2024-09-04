const contract_client = @import("../../clients/contract.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

const Contract = contract_client.Contract;
const ContractComptime = contract_client.ContractComptime;
const Hash = types.Hash;

test "DeployContract" {
    {
        const abi = &.{
            .{
                .abiConstructor = .{
                    .type = .constructor,
                    .inputs = &.{},
                    .stateMutability = .nonpayable,
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.websocket).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = true,
        });
        defer contract.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try contract.deployContract(.{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
    {
        const abi = &.{
            .{
                .abiConstructor = .{
                    .type = .constructor,
                    .inputs = &.{},
                    .stateMutability = .nonpayable,
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.http).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try contract.deployContract(.{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
    {
        const abi = &.{
            .{
                .abiConstructor = .{
                    .type = .constructor,
                    .inputs = &.{},
                    .stateMutability = .nonpayable,
                },
            },
        };

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.ipc).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .path = "/tmp/anvil.ipc" },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, "608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029");
        const hash = try contract.deployContract(.{}, bytes, .{ .type = .london });
        defer hash.deinit();
    }
}

test "WriteContract" {
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.websocket).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.writeContractFunction("setApprovalForAll", .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"),
            true,
        }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.websocket).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },

            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.writeContractFunction("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.ipc).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .path = "/tmp/anvil.ipc" },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.writeContractFunction("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try ContractComptime(.http).init(.{
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = true,
        });
        defer contract.deinit();

        const result = try contract.writeContractFunction(.{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        }, .{
            .args = .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"), true },
            .overrides = .{
                .type = .london,
                .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
            },
        });
        defer result.deinit();
    }
}

test "SimulateWriteCall" {
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.websocket).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.http).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });
        defer result.deinit();
    }
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.http).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
            .type = .berlin,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        });
        defer result.deinit();
    }
    {
        const abi = &.{
            .{
                .abiFunction = .{
                    .type = .function,
                    .inputs = &.{
                        .{ .type = .{ .address = {} }, .name = "operator" },
                        .{ .type = .{ .bool = {} }, .name = "approved" },
                    },
                    .stateMutability = .nonpayable,
                    .outputs = &.{},
                    .name = "setApprovalForAll",
                },
            },
        };

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try Contract(.ipc).init(.{
            .abi = abi,
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .path = "/tmp/anvil.ipc" },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });
        defer result.deinit();
    }
    {
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try ContractComptime(.http).init(.{
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = false,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall(.{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        }, .{ .args = .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"),
            true,
        }, .overrides = .{
            .type = .london,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        } });
        defer result.deinit();
    }
    {
        const uri = try std.Uri.parse("http://localhost:6969/");

        var buffer_hex: Hash = undefined;
        _ = try std.fmt.hexToBytes(&buffer_hex, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        var contract = try ContractComptime(.http).init(.{
            .private_key = buffer_hex,
            .wallet_opts = .{
                .allocator = testing.allocator,
                .network_config = .{
                    .endpoint = .{ .uri = uri },
                },
            },
            .nonce_manager = true,
        });
        defer contract.deinit();

        const result = try contract.simulateWriteCall(.{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        }, .{ .args = .{
            try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"),
            true,
        }, .overrides = .{
            .type = .berlin,
            .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
        } });
        defer result.deinit();
    }
}
