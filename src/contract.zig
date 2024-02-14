const abitype = @import("abi/abi.zig");
const block = @import("meta/block.zig");
const decoder = @import("decoding/decoder.zig");
const logs = @import("meta/log.zig");
const meta = @import("meta/meta.zig");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const std = @import("std");
const Anvil = @import("tests/Anvil.zig");
const Allocator = std.mem.Allocator;
const ClientType = @import("wallet.zig").WalletClients;
const Wallet = @import("wallet.zig").Wallet;

const Abi = abitype.Abi;
const Abitype = abitype.Abitype;
const AbiDecoded = decoder.AbiDecoded;
const AbiDecodedRuntime = decoder.AbiDecodedRuntime;
const AbiItem = abitype.AbiItem;
const BlockNumberRequest = block.BlockNumberRequest;
const Constructor = abitype.Constructor;
const EthCall = transaction.EthCall;
const Function = abitype.Function;
const Gwei = types.Gwei;
const Hex = types.Hex;
const PrepareEnvelope = transaction.PrepareEnvelope;

pub fn Contract(comptime client_type: ClientType) type {
    return struct {
        /// The wallet instance that manages this contract instance
        wallet: *Wallet(client_type),
        /// The abi that will be used to read or write from
        abi: Abi,

        /// Deinits the wallet instance.
        pub fn deinit(self: *Contract(client_type)) void {
            self.wallet.deinit();
        }
        /// Creates a contract on the network.
        /// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
        pub fn deployContract(self: *Contract(client_type), constructor_args: anytype, bytecode: []const u8, overrides: PrepareEnvelope) !Hex {
            var copy = overrides;
            const constructor = try self.getAbiItem(.constructor, null);
            const code = if (std.mem.startsWith(u8, bytecode, "0x")) bytecode[2..] else bytecode;

            const encoded = try constructor.abiConstructor.encode(self.wallet.allocator, constructor_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}{s}", .{ code, std.fmt.fmtSliceHexLower(encoded) });
            defer self.wallet.allocator.free(concated);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to != null)
                        return error.CreatingContractToKnowAddress;

                    const value = tx.value orelse 0;
                    switch (constructor.abiConstructor.stateMutability) {
                        .nonpayable => if (value != 0)
                            return error.ValueInNonPayableConstructor,
                        .payable => {},
                    }

                    tx.data = concated;
                },
            }

            return try self.wallet.sendTransaction(copy);
        }
        /// Uses eth_call to query an contract information.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn readContractFunction(self: *Contract(client_type), comptime T: type, function_name: []const u8, function_args: anytype, overrides: EthCall) !AbiDecodedRuntime(T) {
            const function_item = try self.getAbiItem(.function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .view, .pure => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{encoded});
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
        pub fn writeContractFunction(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: PrepareEnvelope) !Hex {
            const function_item = try self.getAbiItem(.function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .nonpayable, .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{encoded});
            defer self.wallet.allocator.free(concated);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    const value = tx.value orelse 0;
                    switch (function_item.abiFunction.stateMutability) {
                        .nonpayable => if (value != 0)
                            return error.ValueInNonPayableFunction,
                        .payable => {},
                        inline else => return error.InvalidFunctionMutability,
                    }

                    tx.data = concated;
                },
            }

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
        pub fn simulateWriteCall(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: PrepareEnvelope) !Hex {
            const function_item = try self.getAbiItem(.function, function_name);
            var copy = overrides;

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            const concated = try std.fmt.allocPrint(self.wallet.allocator, "0x{s}", .{encoded});
            defer self.wallet.allocator.free(concated);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    tx.data = concated;
                },
            }

            const address = try self.wallet.getWalletAddress();
            const call: EthCall = switch (copy) {
                .eip1559 => |tx| .{ .eip1559 = .{ .from = address, .to = tx.to, .data = tx.data, .value = tx.value, .maxFeePerGas = tx.maxFeePerGas, .maxPriorityFeePerGas = tx.maxPriorityFeePerGas, .gas = tx.gas } },
                inline else => |tx| .{ .legacy = .{ .from = address, .value = tx.value, .to = tx.to, .data = tx.data, .gas = tx.gas, .gasPrice = tx.gasPrice } },
            };

            return try self.wallet.pub_client.sendEthCall(call, .{});
        }
        // TODO: Handle overrides abi items
        /// Grabs the first match in the `Contract` abi
        fn getAbiItem(self: Contract(client_type), abi_type: Abitype, name: ?[]const u8) !AbiItem {
            switch (abi_type) {
                .constructor => {
                    for (self.abi) |abi_item| {
                        switch (abi_item) {
                            .abiConstructor => return abi_item,
                            inline else => continue,
                        }
                    }
                },
                .function => {
                    for (self.abi) |abi_item| {
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
                    for (self.abi) |abi_item| {
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
                    for (self.abi) |abi_item| {
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
    };
}
/// Init values needed depending on the abi constructor arguments.
fn AbiConstructorArgs(comptime constructor: Constructor, comptime client_type: ClientType) type {
    return struct { args: meta.AbiParametersToPrimative(constructor.inputs), bytecode: []const u8, wallet: *Wallet(client_type), overrides: PrepareEnvelope };
}
/// Creates a contract on the network.
/// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
/// The arguments here are comptime so that the compiler can effectively enforce the correct expected types.
pub fn deployContract(comptime constructor: Constructor, comptime client_type: ClientType, opts: AbiConstructorArgs(constructor, client_type)) !Hex {
    const code = if (std.mem.startsWith(u8, opts.bytecode, "0x")) opts.bytecode[2..] else opts.bytecode;
    var copy = opts.overrides;

    const encoded = try constructor.encode(opts.wallet.allocator, opts.args);
    defer if (encoded.len != 0) opts.wallet.allocator.free(encoded);

    const concated = try std.fmt.allocPrint(opts.wallet.allocator, "0x{s}{s}", .{ code, std.fmt.fmtSliceHexLower(encoded) });
    defer opts.wallet.allocator.free(concated);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to != null)
                return error.CreatingContractToKnowAddress;

            const value = tx.value orelse 0;
            switch (constructor.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableConstructor,
                .payable => {},
            }

            tx.data = concated;
        },
    }

    return try opts.wallet.sendTransaction(copy);
}
/// Init values needed depending on the abi function arguments.
fn AbiFunctionArgs(comptime function: Function, comptime Overrides: type, client_type: ClientType) type {
    return struct { args: meta.AbiParametersToPrimative(function.inputs), wallet: *Wallet(client_type), overrides: Overrides };
}
/// Uses eth_call to query an contract information.
/// Only abi items that are either `view` or `pure` will be allowed.
/// It won't commit a transaction to the network.
/// The arguments here are comptime so that the compiler can effectively enforce the correct expected types.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn readContractFunction(comptime function: Function, comptime client_type: ClientType, opts: AbiFunctionArgs(function, EthCall, client_type)) !AbiDecoded(function.outputs) {
    switch (function.stateMutability) {
        .view, .pure => {},
        inline else => return error.InvalidFunctionMutability,
    }
    var copy = opts.overrides;

    const encoded = try function.encode(opts.wallet.allocator, opts.args);
    defer if (encoded.len != 0) opts.wallet.allocator.free(encoded);

    const concated = try std.fmt.allocPrint(opts.wallet.allocator, "0x{s}", .{encoded});
    defer opts.wallet.allocator.free(concated);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to == null)
                return error.InvalidRequestTarget;

            tx.data = concated;
        },
    }

    const data = try opts.wallet.pub_client.sendEthCall(copy, .{});
    const decoded = try decoder.decodeAbiParameters(opts.wallet.allocator, function.outputs, data, .{});

    return decoded;
}
/// Encodes the function arguments based on the function abi item.
/// Only abi items that are either `payable` or `nonpayable` will be allowed.
/// It will send the transaction to the network and return the transaction hash.
/// The arguments here are comptime so that the compiler can effectively enforce the correct expected types.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn writeContractFunction(comptime function: Function, comptime client_type: ClientType, opts: AbiFunctionArgs(function, PrepareEnvelope, client_type)) !Hex {
    switch (function.stateMutability) {
        .payable, .nonpayable => {},
        inline else => return error.InvalidFunctionMutability,
    }
    var copy = opts.overrides;

    const encoded = try function.encode(opts.wallet.allocator, opts.args);
    defer if (encoded.len != 0) opts.wallet.allocator.free(encoded);

    const concated = try std.fmt.allocPrint(opts.wallet.allocator, "0x{s}", .{encoded});
    defer opts.wallet.allocator.free(concated);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to == null)
                return error.InvalidRequestTarget;

            const value = tx.value orelse 0;
            switch (function.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableFunction,
                .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            tx.data = concated;
        },
    }

    return try opts.wallet.sendTransaction(copy);
}
/// Uses eth_call to simulate a contract interaction.
/// Only abi items that are either `view` or `pure` will be allowed.
/// It won't commit a transaction to the network.
/// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
/// The arguments here are comptime so that the compiler can effectively enforce the correct expected types.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn simulateWriteCall(comptime function: Function, comptime client_type: ClientType, opts: AbiFunctionArgs(function, PrepareEnvelope, client_type)) !Hex {
    var copy = opts.overrides;

    const encoded = try function.encode(opts.wallet.allocator, opts.args);
    defer if (encoded.len != 0) opts.wallet.allocator.free(encoded);

    const concated = try std.fmt.allocPrint(opts.wallet.allocator, "0x{s}", .{encoded});
    defer opts.wallet.allocator.free(concated);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to == null)
                return error.InvalidRequestTarget;

            tx.data = concated;
        },
    }

    const address = try opts.wallet.getWalletAddress();
    const call: transaction.EthCall = switch (copy) {
        .eip1559 => |tx| .{ .eip1559 = .{ .from = address, .to = tx.to, .data = tx.data, .value = tx.value, .maxFeePerGas = tx.maxFeePerGas, .maxPriorityFeePerGas = tx.maxPriorityFeePerGas, .gas = tx.gas } },
        inline else => |tx| .{ .legacy = .{ .from = address, .value = tx.value, .to = tx.to, .data = tx.data, .gas = tx.gas, .gasPrice = tx.gasPrice } },
    };

    return try opts.wallet.pub_client.sendEthCall(call, .{});
}

test "DeployContract" {
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.websocket) = .{ .abi = &.{.{ .abiConstructor = .{ .type = .constructor, .inputs = &.{}, .stateMutability = .nonpayable } }}, .wallet = try Wallet(.websocket).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();

        const hash = try contract.deployContract(.{}, "0x608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029", .{ .eip1559 = .{} });

        try testing.expectEqual(hash.len, 66);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.http) = .{ .abi = &.{.{ .abiConstructor = .{ .type = .constructor, .inputs = &.{}, .stateMutability = .nonpayable } }}, .wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();

        const hash = try contract.deployContract(.{}, "0x608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029", .{ .eip1559 = .{} });

        try testing.expectEqual(hash.len, 66);
    }
}

test "ReadContract" {
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.websocket) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" } }}, .wallet = try Wallet(.websocket).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        const ReturnType = std.meta.Tuple(&[_]type{[]const u8});
        const result = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5", .from = try contract.wallet.getWalletAddress() } });
        try testing.expectEqual(result.values[0].len, 42);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.http) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" } }}, .wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        const ReturnType = std.meta.Tuple(&[_]type{[]const u8});
        const result = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5", .from = try contract.wallet.getWalletAddress() } });
        try testing.expectEqual(result.values[0].len, 42);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
        defer wallet.deinit();

        const result = try readContractFunction(.{ .type = .function, .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "tokenId" }}, .stateMutability = .view, .outputs = &.{.{ .type = .{ .address = {} }, .name = "" }}, .name = "ownerOf" }, .http, .{ .wallet = wallet, .args = .{69}, .overrides = .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5", .from = try wallet.getWalletAddress() } } });

        try testing.expectEqual(result.values[0].len, 42);
    }
}

test "WriteContract" {
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.websocket) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }}, .wallet = try Wallet(.websocket).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try contract.writeContractFunction("setApprovalForAll", .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6546", true }, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expectEqual(result.len, 66);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.http) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }}, .wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try contract.writeContractFunction("setApprovalForAll", .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6546", true }, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expectEqual(result.len, 66);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
        var anvil: Anvil = undefined;
        defer wallet.deinit();
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try writeContractFunction(.{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" }, .http, .{ .args = .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6547", true }, .overrides = .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } }, .wallet = wallet });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expectEqual(result.len, 66);
    }
}

test "SimulateWriteCall" {
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.websocket) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }}, .wallet = try Wallet(.websocket).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6546", true }, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expect(result.len > 0);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var contract: Contract(.http) = .{ .abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }}, .wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri }) };
        defer contract.deinit();
        var anvil: Anvil = undefined;
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try contract.simulateWriteCall("setApprovalForAll", .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6546", true }, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expect(result.len > 0);
    }
    {
        const uri = try std.Uri.parse("http://localhost:8545/");
        var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
        var anvil: Anvil = undefined;
        defer wallet.deinit();
        defer anvil.deinit();

        try anvil.initClient(.{ .fork_url = "", .alloc = testing.allocator });
        try anvil.impersonateAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");

        const result = try simulateWriteCall(.{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" }, .http, .{ .args = .{ "0x19bb64b80CbF61E61965B0E5c2560CC7364c6547", true }, .overrides = .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5" } }, .wallet = wallet });

        try anvil.stopImpersonatingAccount("0xA207CDAf9b660960F819466BA69c28E7Cc8aEd18");
        try testing.expect(result.len > 0);
    }
}
