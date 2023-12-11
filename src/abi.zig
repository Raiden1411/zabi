const std = @import("std");
const testing = std.testing;
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiEventParameter = @import("abi_parameter.zig").AbiEventParameter;
const Alloc = std.mem.Allocator;
const FromAbitypeToEnum = @import("types.zig").FromAbitypeToEnum;
const ParserOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const StateMutability = @import("state_mutability.zig").StateMutability;
const Token = std.json.Token;
const UnionParser = @import("types.zig").UnionParser;

pub const Abitype = enum { function, @"error", event, constructor, fallback, receive };

/// Solidity Abi function representation.
/// Reference: ["function"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Function = struct {
    type: FromAbitypeToEnum(.function),
    /// Deprecated. Use either 'pure' or 'view'.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    constant: ?bool = null,
    /// Deprecated. Older vyper compiler versions used to provide gas estimates.
    ///
    /// https://github.com/vyperlang/vyper/issues/2151
    gas: ?i64 = null,
    inputs: []const AbiParameter,
    name: []const u8,
    outputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: StateMutability,
};

/// Solidity Abi function representation.
/// Reference: ["event"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Event = struct {
    type: FromAbitypeToEnum(.event),
    name: []const u8,
    inputs: []const AbiEventParameter,
    anonymous: ?bool = null,
};

/// Solidity Abi function representation.
/// Reference: ["error"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Error = struct {
    type: FromAbitypeToEnum(.@"error"),
    name: []const u8,
    inputs: []const AbiParameter,
};

/// Solidity Abi function representation.
/// Reference: ["constructor"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Constructor = struct {
    type: FromAbitypeToEnum(.constructor),
    inputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: StateMutability,
};

/// Solidity Abi function representation.
/// Reference: ["fallback"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Fallback = struct {
    type: FromAbitypeToEnum(.fallback),
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: StateMutability,
};

/// Solidity Abi function representation.
/// Reference: ["receive"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
const Receive = struct {
    type: FromAbitypeToEnum(.receive),
    stateMutability: enum { payable },
};

pub const AbiItem = union(enum) {
    abiFunction: Function,
    abiEvent: Event,
    abiError: Error,
    abiConstructor: Constructor,
    abiFallback: Fallback,
    abiReceive: Receive,

    pub usingnamespace UnionParser(@This());
};

pub const Abi = []const AbiItem;
test "Json parse simple" {
    const slice =
        \\ [{
        \\  "type": "receive",
        \\  "stateMutability": "payable"
        \\ }]
    ;

    const parsed = try std.json.parseFromSlice(Abi, testing.allocator, slice, .{});
    defer parsed.deinit();
}
