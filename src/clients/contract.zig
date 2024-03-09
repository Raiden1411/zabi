const abitype = @import("../abi/abi.zig");
const block = @import("../meta/block.zig");
const decoder = @import("../decoding/decoder.zig");
const logs = @import("../meta/log.zig");
const meta = @import("../meta/meta.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../meta/transaction.zig");
const types = @import("../meta/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const Abi = abitype.Abi;
const Abitype = abitype.Abitype;
const AbiDecoded = decoder.AbiDecoded;
const AbiDecodedRuntime = decoder.AbiDecodedRuntime;
const AbiItem = abitype.AbiItem;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @import("../tests/Anvil.zig");
const BlockNumberRequest = block.BlockNumberRequest;
const ClientType = @import("wallet.zig").WalletClients;
const Constructor = abitype.Constructor;
const EthCall = transaction.EthCall;
const Function = abitype.Function;
const Gwei = types.Gwei;
const Hex = types.Hex;
const Hash = types.Hash;
const InitOptsHttp = @import("Client.zig").InitOptions;
const InitOptsWs = @import("WebSocket.zig").InitOptions;
const UnpreparedTransactionEnvelope = transaction.UnpreparedTransactionEnvelope;
const Wallet = @import("wallet.zig").Wallet;

fn ConstructorOpts(comptime constructor: Constructor) type {
    return struct {
        args: AbiParametersToPrimative(constructor.inputs),
        bytecode: Hex,
        overrides: UnpreparedTransactionEnvelope,
    };
}

fn FunctionOpts(comptime func: Function, comptime T: type) type {
    return struct {
        args: AbiParametersToPrimative(func.inputs),
        overrides: T,
    };
}
/// Wrapper on a wallet and comptime know Abi
pub fn ContractComptime(comptime client_type: ClientType) type {
    return struct {
        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
        };

        /// The contract settings depending on the client type.
        const ContractInitOpts = struct {
            private_key: Hex,
            wallet_opts: InitOpts,
        };

        /// The wallet instance that manages this contract instance
        wallet: *Wallet(client_type),
        /// Deinits the wallet instance.
        pub fn init(self: *ContractComptime(client_type), opts: ContractInitOpts) !void {
            const wallet = try opts.wallet_opts.allocator.create(Wallet(client_type));
            errdefer opts.wallet_opts.allocator.destroy(wallet);

            try wallet.init(opts.private_key, opts.wallet_opts);

            self.* = .{
                .wallet = wallet,
            };
        }
        /// Deinits the wallet instance.
        pub fn deinit(self: *ContractComptime(client_type)) void {
            const child_allocator = self.wallet.arena.child_allocator;

            self.wallet.deinit();
            child_allocator.destroy(self.wallet);

            self.* = undefined;
        }
        /// Creates a contract on the network.
        /// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
        pub fn deployContract(self: *ContractComptime(client_type), comptime constructor: Constructor, opts: ConstructorOpts(constructor)) !Hash {
            var copy = opts.overrides;
            const code = if (std.mem.startsWith(u8, opts.bytecode, "0x")) opts.bytecode[2..] else opts.bytecode;

            const encoded = try constructor.encode(self.wallet.allocator, opts.args);
            defer encoded.deinit();

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}{s}", .{ code, std.fmt.fmtSliceHexLower(encoded.data) });
            defer self.wallet.allocator.free(concated);

            if (copy.to != null)
                return error.CreatingContractToKnowAddress;

            const value = copy.value orelse 0;
            switch (constructor.abiConstructor.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableConstructor,
                .payable => {},
            }

            copy.data = concated;

            return try self.wallet.sendTransaction(copy);
        }
        /// Uses eth_call to query an contract information.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn readContractFunction(self: *ContractComptime(client_type), comptime func: Function, opts: FunctionOpts(func, EthCall)) !AbiDecoded(func.outputs) {
            var copy = opts.overrides;

            switch (func.stateMutability) {
                .view, .pure => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    tx.data = concated;
                },
            }

            const data = try self.wallet.pub_client.sendEthCall(copy, .{});
            const decoded = try decoder.decodeAbiParameters(self.wallet.allocator, func.outputs, data, .{});

            return decoded;
        }
        /// Encodes the function arguments based on the function abi item.
        /// Only abi items that are either `payable` or `nonpayable` will be allowed.
        /// It will send the transaction to the network and return the transaction hash.
        ///
        /// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
        pub fn writeContractFunction(self: *ContractComptime(client_type), comptime func: Function, opts: FunctionOpts(func, UnpreparedTransactionEnvelope)) !Hash {
            var copy = opts.overrides;

            switch (func.stateMutability) {
                .nonpayable, .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            const value = copy.value orelse 0;
            switch (func.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableFunction,
                .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            copy.data = concated;

            return try self.wallet.sendTransaction(copy);
        }
        /// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
        /// The transaction will not be added to the blockchain.
        /// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
        /// for a variety of reasons including EVM mechanics and node performance.
        ///
        /// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
        pub fn estimateGas(self: *ContractComptime(client_type), call_object: EthCall, opts: BlockNumberRequest) !Gwei {
            return try self.wallet.pub_client.estimateGas(call_object, opts);
        }
        /// Uses eth_call to simulate a contract interaction.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        /// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn simulateWriteCall(self: *ContractComptime(client_type), comptime func: Function, opts: FunctionOpts(func, UnpreparedTransactionEnvelope)) !Hex {
            var copy = opts.overrides;

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            copy.data = concated;

            const address = try self.wallet.getWalletAddress();
            const call: EthCall = switch (copy.type) {
                .cancun, .london => .{ .london = .{ .from = address, .to = copy.to, .data = copy.data, .value = copy.value, .maxFeePerGas = copy.maxFeePerGas, .maxPriorityFeePerGas = copy.maxPriorityFeePerGas, .gas = copy.gas } },
                .berlin, .legacy => .{ .legacy = .{ .from = address, .value = copy.value, .to = copy.to, .data = copy.data, .gas = copy.gas, .gasPrice = copy.gasPrice } },
                _ => .{ .legacy = .{ .from = address, .value = copy.value, .to = copy.to, .data = copy.data, .gas = copy.gas, .gasPrice = copy.gasPrice } },
            };

            return try self.wallet.pub_client.sendEthCall(call, .{});
        }
    };
}

/// Wrapper on a wallet and Abi
pub fn Contract(comptime client_type: ClientType) type {
    return struct {
        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
        };

        /// The contract settings depending on the client type.
        const ContractInitOpts = struct {
            abi: Abi,
            private_key: Hex,
            wallet_opts: InitOpts,
        };

        /// The wallet instance that manages this contract instance
        wallet: *Wallet(client_type),
        /// The abi that will be used to read or write from
        abi: Abi,

        pub fn init(self: *Contract(client_type), opts: ContractInitOpts) !void {
            const wallet = try opts.wallet_opts.allocator.create(Wallet(client_type));
            errdefer opts.wallet_opts.allocator.destroy(wallet);

            try wallet.init(opts.private_key, opts.wallet_opts);

            self.* = .{
                .abi = opts.abi,
                .wallet = wallet,
            };
        }
        /// Deinits the wallet instance.
        pub fn deinit(self: *Contract(client_type)) void {
            const child_allocator = self.wallet.arena.child_allocator;

            self.wallet.deinit();
            child_allocator.destroy(self.wallet);

            self.* = undefined;
        }
        /// Creates a contract on the network.
        /// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
        pub fn deployContract(self: *Contract(client_type), constructor_args: anytype, bytecode: []const u8, overrides: UnpreparedTransactionEnvelope) !Hash {
            var copy = overrides;
            const constructor = try getAbiItem(self.abi, .constructor, null);
            const code = if (std.mem.startsWith(u8, bytecode, "0x")) bytecode[2..] else bytecode;

            const encoded = try constructor.abiConstructor.encode(self.wallet.allocator, constructor_args);
            defer encoded.deinit();

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}{s}", .{ code, std.fmt.fmtSliceHexLower(encoded.data) });

            if (copy.to != null)
                return error.CreatingContractToKnowAddress;

            const value = copy.value orelse 0;
            switch (constructor.abiConstructor.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableConstructor,
                .payable => {},
            }

            copy.data = concated;

            return try self.wallet.sendTransaction(copy);
        }
        /// Uses eth_call to query an contract information.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn readContractFunction(self: *Contract(client_type), comptime T: type, function_name: []const u8, function_args: anytype, overrides: EthCall) !AbiDecodedRuntime(T) {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .view, .pure => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    tx.data = concated;
                },
            }

            const data = try self.wallet.pub_client.sendEthCall(copy, .{});
            const decoded = try decoder.decodeAbiParametersRuntime(self.wallet.allocator, T, function_item.abiFunction.outputs, data, .{});

            return decoded;
        }
        /// Encodes the function arguments based on the function abi item.
        /// Only abi items that are either `payable` or `nonpayable` will be allowed.
        /// It will send the transaction to the network and return the transaction hash.
        ///
        /// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
        pub fn writeContractFunction(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: UnpreparedTransactionEnvelope) !Hash {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .nonpayable, .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            const value = copy.value orelse 0;
            switch (function_item.abiFunction.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableFunction,
                .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            copy.data = concated;

            return try self.wallet.sendTransaction(copy);
        }
        /// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
        /// The transaction will not be added to the blockchain.
        /// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
        /// for a variety of reasons including EVM mechanics and node performance.
        ///
        /// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
        pub fn estimateGas(self: *Contract, call_object: EthCall, opts: BlockNumberRequest) !Gwei {
            return try self.wallet.pub_client.estimateGas(call_object, opts);
        }
        /// Uses eth_call to simulate a contract interaction.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        /// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn simulateWriteCall(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: UnpreparedTransactionEnvelope) !Hex {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(encoded)});
            defer self.wallet.allocator.free(concated);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            copy.data = concated;

            const address = try self.wallet.getWalletAddress();
            const call: EthCall = switch (copy.type) {
                .cancun, .london => .{ .london = .{ .from = address, .to = copy.to, .data = copy.data, .value = copy.value, .maxFeePerGas = copy.maxFeePerGas, .maxPriorityFeePerGas = copy.maxPriorityFeePerGas, .gas = copy.gas } },
                .berlin, .legacy => .{ .legacy = .{ .from = address, .value = copy.value, .to = copy.to, .data = copy.data, .gas = copy.gas, .gasPrice = copy.gasPrice } },
                _ => .{ .legacy = .{ .from = address, .value = copy.value, .to = copy.to, .data = copy.data, .gas = copy.gas, .gasPrice = copy.gasPrice } },
            };

            return try self.wallet.pub_client.sendEthCall(call, .{});
        }
    };
}

// TODO: Handle overrides abi items
/// Grabs the first match in the `Contract` abi
fn getAbiItem(abi: Abi, abi_type: Abitype, name: ?[]const u8) !AbiItem {
    switch (abi_type) {
        .constructor => {
            for (abi) |abi_item| {
                switch (abi_item) {
                    .abiConstructor => return abi_item,
                    inline else => continue,
                }
            }
        },
        .function => {
            for (abi) |abi_item| {
                switch (abi_item) {
                    .abiFunction => |function| {
                        if (std.mem.eql(u8, name.?, function.name))
                            return abi_item;

                        continue;
                    },
                    inline else => continue,
                }
            }
        },
        .event => {
            for (abi) |abi_item| {
                switch (abi_item) {
                    .abiEvent => |event| {
                        if (std.mem.eql(u8, name.?, event.name))
                            return abi_item;
                    },
                    inline else => continue,
                }
            }
        },
        .@"error" => {
            for (abi) |abi_item| {
                switch (abi_item) {
                    .abiError => |err| {
                        if (std.mem.eql(u8, name.?, err.name))
                            return abi_item;
                    },
                    inline else => continue,
                }
            }
        },
        inline else => return error.NotSupported,
    }

    return error.AbiItemNotFound;
}

test "DeployContract" {
    {
        const abi = &.{.{ .abiConstructor = .{ .type = .constructor, .inputs = &.{}, .stateMutability = .nonpayable } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.websocket) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        const hash = try contract.deployContract(.{}, "0x608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029", .{ .type = .london });

        try testing.expectEqual(hash.len, 32);
    }
    {
        const abi = &.{.{ .abiConstructor = .{ .type = .constructor, .inputs = &.{}, .stateMutability = .nonpayable } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        const hash = try contract.deployContract(.{}, "0x608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029", .{ .type = .london });

        try testing.expectEqual(hash.len, 32);
    }
}

test "ReadContract" {
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.websocket) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        const ReturnType = std.meta.Tuple(&[_]type{[20]u8});
        const result = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .london = .{ .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"), .from = try contract.wallet.getWalletAddress() } });
        try testing.expectEqual(result.values[0].len, 20);
    }
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        const ReturnType = std.meta.Tuple(&[_]type{[20]u8});
        const result = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .london = .{ .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"), .from = try contract.wallet.getWalletAddress() } });
        try testing.expectEqual(result.values[0].len, 20);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: ContractComptime(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        const result = try contract.readContractFunction(.{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" }, .{ .args = .{69}, .overrides = .{ .london = .{ .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"), .from = try contract.wallet.getWalletAddress() } } });

        try testing.expectEqual(result.values[0].len, 20);
    }
}

test "WriteContract" {
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.websocket) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.writeContractFunction("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expectEqual(result.len, 32);
    }
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.writeContractFunction("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expectEqual(result.len, 32);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: ContractComptime(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.writeContractFunction(.{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" }, .{ .args = .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"), true }, .overrides = .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") } });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expectEqual(result.len, 32);
    }
}

test "SimulateWriteCall" {
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expect(result.len > 0);
    }
    {
        const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: Contract(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expect(result.len > 0);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");

        var contract: ContractComptime(.http) = undefined;
        defer contract.deinit();

        try contract.init(.{ .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));

        const result = try contract.simulateWriteCall(.{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" }, .{ .args = .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"), true }, .overrides = .{ .type = .london, .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5") } });

        try anvil.stopImpersonatingAccount(try utils.addressToBytes("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18"));
        try testing.expect(result.len > 0);
    }
}
