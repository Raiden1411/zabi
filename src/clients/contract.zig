const abitype = @import("../abi/abi.zig");
const block = @import("../types/block.zig");
const decoder = @import("../decoding/decoder.zig");
const logs = @import("../types/log.zig");
const meta = @import("../meta/abi.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");

// Types
const Abi = abitype.Abi;
const AbiDecoded = decoder.AbiDecoded;
const Abitype = abitype.Abitype;
const AbiItem = abitype.AbiItem;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const BlockNumberRequest = block.BlockNumberRequest;
const ClientType = @import("wallet.zig").WalletClients;
const Constructor = abitype.Constructor;
const EthCall = transaction.EthCall;
const Function = abitype.Function;
const Gwei = types.Gwei;
const Hex = types.Hex;
const Hash = types.Hash;
const InitOptsHttp = @import("Client.zig").InitOptions;
const InitOptsIpc = @import("IPC.zig").InitOptions;
const InitOptsWs = @import("WebSocket.zig").InitOptions;
const TransactionReceipt = transaction.TransactionReceipt;
const RPCResponse = types.RPCResponse;
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
            .ipc => InitOptsIpc,
        };

        /// The contract settings depending on the client type.
        const ContractInitOpts = struct {
            private_key: ?Hash,
            wallet_opts: InitOpts,
        };

        /// The wallet instance that manages this contract instance
        wallet: *Wallet(client_type),
        /// Deinits the wallet instance.
        pub fn init(opts: ContractInitOpts) !*ContractComptime(client_type) {
            const self = try opts.wallet_opts.allocator.create(ContractComptime(client_type));
            errdefer opts.wallet_opts.allocator.destroy(self);

            self.* = .{
                .wallet = try Wallet(client_type).init(opts.private_key, opts.wallet_opts),
            };

            return self;
        }
        /// Deinits the wallet instance.
        pub fn deinit(self: *ContractComptime(client_type)) void {
            const allocator = self.wallet.allocator;
            self.wallet.deinit();
            allocator.destroy(self);
        }
        /// Creates a contract on the network.
        /// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
        pub fn deployContract(self: *ContractComptime(client_type), comptime constructor: Constructor, opts: ConstructorOpts(constructor)) !RPCResponse(Hash) {
            var copy = opts.overrides;

            const encoded = try constructor.encode(self.wallet.allocator, opts.args);
            defer encoded.deinit();

            const concated = try std.mem.concat(self.wallet.allocator, u8, &.{ opts.bytecode, encoded.data });
            defer self.wallet.allocator.free(concated);

            if (copy.to != null)
                return error.CreatingContractToKnowAddress;

            const value = copy.value orelse 0;
            switch (constructor.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableConstructor,
                .payable => {},
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
        pub fn estimateGas(self: *ContractComptime(client_type), call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
            return self.wallet.rpc_client.estimateGas(call_object, opts);
        }
        /// Uses eth_call to query an contract information.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn readContractFunction(
            self: *ContractComptime(client_type),
            comptime func: Function,
            opts: FunctionOpts(func, EthCall),
        ) !AbiDecoded(AbiParametersToPrimative(func.outputs)) {
            var copy = opts.overrides;

            switch (func.stateMutability) {
                .view, .pure => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    tx.data = encoded;
                },
            }

            const data = try self.wallet.rpc_client.sendEthCall(copy, .{});
            defer data.deinit();

            const decoded = try decoder.decodeAbiParameter(AbiParametersToPrimative(func.outputs), self.wallet.allocator, data.response, .{});

            return decoded;
        }
        /// Uses eth_call to simulate a contract interaction.
        /// It won't commit a transaction to the network.
        /// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn simulateWriteCall(self: *ContractComptime(client_type), comptime func: Function, opts: FunctionOpts(func, UnpreparedTransactionEnvelope)) !RPCResponse(Hex) {
            var copy = opts.overrides;

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            copy.data = encoded;

            const address = self.wallet.getWalletAddress();
            const call: EthCall = switch (copy.type) {
                .cancun, .london => .{ .london = .{
                    .from = address,
                    .to = copy.to,
                    .data = copy.data,
                    .value = copy.value,
                    .maxFeePerGas = copy.maxFeePerGas,
                    .maxPriorityFeePerGas = copy.maxPriorityFeePerGas,
                    .gas = copy.gas,
                } },
                .berlin, .legacy => .{ .legacy = .{
                    .from = address,
                    .value = copy.value,
                    .to = copy.to,
                    .data = copy.data,
                    .gas = copy.gas,
                    .gasPrice = copy.gasPrice,
                } },
                .deposit => return error.UnsupportedTransactionType,
                _ => return error.UnsupportedTransactionType,
            };

            return self.wallet.rpc_client.sendEthCall(call, .{});
        }
        /// Waits until a transaction gets mined and the receipt can be grabbed.
        /// This is retry based on either the amount of `confirmations` given.
        ///
        /// If 0 confirmations are given the transaction receipt can be null in case
        /// the transaction has not been mined yet. It's recommened to have atleast one confirmation
        /// because some nodes might be slower to sync.
        ///
        /// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
        pub fn waitForTransactionReceipt(self: *ContractComptime(client_type), tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
            return self.wallet.waitForTransactionReceipt(tx_hash, confirmations);
        }
        /// Encodes the function arguments based on the function abi item.
        /// Only abi items that are either `payable` or `nonpayable` will be allowed.
        /// It will send the transaction to the network and return the transaction hash.
        ///
        /// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
        pub fn writeContractFunction(self: *ContractComptime(client_type), comptime func: Function, opts: FunctionOpts(func, UnpreparedTransactionEnvelope)) !RPCResponse(Hash) {
            var copy = opts.overrides;

            switch (func.stateMutability) {
                .nonpayable, .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try func.encode(self.wallet.allocator, opts.args);
            defer self.wallet.allocator.free(encoded);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            const value = copy.value orelse 0;
            switch (func.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableFunction,
                .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            copy.data = encoded;

            return self.wallet.sendTransaction(copy);
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
            .ipc => InitOptsIpc,
        };

        /// The contract settings depending on the client type.
        const ContractInitOpts = struct {
            abi: Abi,
            private_key: ?Hash,
            wallet_opts: InitOpts,
        };

        /// The wallet instance that manages this contract instance
        wallet: *Wallet(client_type),
        /// The abi that will be used to read or write from
        abi: Abi,

        pub fn init(opts: ContractInitOpts) !*Contract(client_type) {
            const self = try opts.wallet_opts.allocator.create(Contract(client_type));
            errdefer opts.wallet_opts.allocator.destroy(self);

            self.* = .{
                .abi = opts.abi,
                .wallet = try Wallet(client_type).init(opts.private_key, opts.wallet_opts),
            };

            return self;
        }
        /// Deinits the wallet instance.
        pub fn deinit(self: *Contract(client_type)) void {
            const allocator = self.wallet.allocator;
            self.wallet.deinit();
            allocator.destroy(self);
        }
        /// Creates a contract on the network.
        /// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
        pub fn deployContract(self: *Contract(client_type), constructor_args: anytype, bytecode: Hex, overrides: UnpreparedTransactionEnvelope) !RPCResponse(Hash) {
            var copy = overrides;
            const constructor = try getAbiItem(self.abi, .constructor, null);

            const encoded = try constructor.abiConstructor.encode(self.wallet.allocator, constructor_args);
            defer encoded.deinit();

            const concated = try std.mem.concat(self.wallet.allocator, u8, &.{ bytecode, encoded.data });
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

            return self.wallet.sendTransaction(copy);
        }
        /// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
        /// The transaction will not be added to the blockchain.
        /// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
        /// for a variety of reasons including EVM mechanics and node performance.
        ///
        /// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
        pub fn estimateGas(self: *Contract(client_type), call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
            return self.wallet.rpc_client.estimateGas(call_object, opts);
        }
        /// Uses eth_call to query an contract information.
        /// Only abi items that are either `view` or `pure` will be allowed.
        /// It won't commit a transaction to the network.
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn readContractFunction(self: *Contract(client_type), comptime T: type, function_name: []const u8, function_args: anytype, overrides: EthCall) !AbiDecoded(T) {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .view, .pure => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer self.wallet.allocator.free(encoded);

            switch (copy) {
                inline else => |*tx| {
                    if (tx.to == null)
                        return error.InvalidRequestTarget;

                    tx.data = encoded;
                },
            }

            const data = try self.wallet.rpc_client.sendEthCall(copy, .{});
            defer data.deinit();

            const decoded = try decoder.decodeAbiParameter(T, self.wallet.allocator, data.response, .{});

            return decoded;
        }
        /// Uses eth_call to simulate a contract interaction.
        /// It won't commit a transaction to the network.
        /// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
        ///
        /// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
        pub fn simulateWriteCall(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: UnpreparedTransactionEnvelope) !RPCResponse(Hex) {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer if (encoded.len != 0) self.wallet.allocator.free(encoded);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            copy.data = encoded;

            const address = self.wallet.getWalletAddress();
            const call: EthCall = switch (copy.type) {
                .cancun, .london => .{ .london = .{
                    .from = address,
                    .to = copy.to,
                    .data = copy.data,
                    .value = copy.value,
                    .maxFeePerGas = copy.maxFeePerGas,
                    .maxPriorityFeePerGas = copy.maxPriorityFeePerGas,
                    .gas = copy.gas,
                } },
                .berlin, .legacy => .{ .legacy = .{
                    .from = address,
                    .value = copy.value,
                    .to = copy.to,
                    .data = copy.data,
                    .gas = copy.gas,
                    .gasPrice = copy.gasPrice,
                } },
                .deposit => return error.UnsupportedTransactionType,
                _ => return error.UnsupportedTransactionType,
            };

            return self.wallet.rpc_client.sendEthCall(call, .{});
        }
        /// Waits until a transaction gets mined and the receipt can be grabbed.
        /// This is retry based on either the amount of `confirmations` given.
        ///
        /// If 0 confirmations are given the transaction receipt can be null in case
        /// the transaction has not been mined yet. It's recommened to have atleast one confirmation
        /// because some nodes might be slower to sync.
        ///
        /// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
        pub fn waitForTransactionReceipt(self: *Contract(client_type), tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
            return self.wallet.waitForTransactionReceipt(tx_hash, confirmations);
        }
        /// Encodes the function arguments based on the function abi item.
        /// Only abi items that are either `payable` or `nonpayable` will be allowed.
        /// It will send the transaction to the network and return the transaction hash.
        ///
        /// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
        pub fn writeContractFunction(self: *Contract(client_type), function_name: []const u8, function_args: anytype, overrides: UnpreparedTransactionEnvelope) !RPCResponse(Hash) {
            const function_item = try getAbiItem(self.abi, .function, function_name);
            var copy = overrides;

            switch (function_item.abiFunction.stateMutability) {
                .nonpayable, .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            const encoded = try function_item.abiFunction.encode(self.wallet.allocator, function_args);
            defer self.wallet.allocator.free(encoded);

            if (copy.to == null)
                return error.InvalidRequestTarget;

            const value = copy.value orelse 0;
            switch (function_item.abiFunction.stateMutability) {
                .nonpayable => if (value != 0)
                    return error.ValueInNonPayableFunction,
                .payable => {},
                inline else => return error.InvalidFunctionMutability,
            }

            copy.data = encoded;

            return self.wallet.sendTransaction(copy);
        }
    };
}

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

                        continue;
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

                        continue;
                    },
                    inline else => continue,
                }
            }
        },
        inline else => return error.NotSupported,
    }

    return error.AbiItemNotFound;
}
