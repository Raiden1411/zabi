/// State mutability https://docs.soliditylang.org/en/latest/contracts.html#state-mutability
pub const AbiStateMutability = union(enum) { NonPayable, Payable, View, Pure };

/// Solidity Abi Parameter (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiParameter = struct {
    type: []const u8,
    name: ?[]const u8,
    internalType: ?[]const u8,
    components: ?[]const AbiParameter,
};

/// Solidity Abi Event Parameter (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiEventParameter = struct {
    type: []const u8,
    name: ?[]const u8,
    internalType: ?[]const u8,
    indexed: bool,
    components: ?[]const AbiParameter,
};

/// Solidity Abi Function (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiFunction = struct {
    type: []const u8,
    /// Solidity used to use this in the json abi. Deprecated in favor of view and pure
    constant: ?bool,
    /// Viper used to provide gas estimates. Currently deprecated.
    gas: ?i64,
    inputs: []AbiParameter,
    name: []const u8,
    outputs: []AbiParameter,
    /// Solidity used to use this in the json abi. Deprecated in favor of payable and nonpayable
    payable: ?bool,
    stateMutability: AbiStateMutability,
};

/// Solidity Abi Event (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiEvent = struct {
    type: []const u8,
    name: []const u8,
    inputs: []AbiEventParameter,
    anonymous: bool,
};

/// Solidity Abi Error (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiError = struct {
    type: []const u8,
    name: []const u8,
    inputs: []AbiParameter,
};

/// Solidity Abi Constructor (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiConstructor = struct {
    type: []const u8,
    inputs: []AbiParameter,
    /// Solidity used to use this in the json abi. Deprecated in favor of payable and nonpayable
    payable: ?bool,
    stateMutability: AbiStateMutability,
};

/// Solidity Abi Receive (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiReceive = struct {
    type: []const u8,
    stateMutability: .Payable,
};

/// Solidity Abi Fallback (https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const AbiFallback = struct {
    type: []const u8,
    stateMutability: union(enum) { Payable, NonPayable },
};

/// Union of all posible abi entries.
pub const AbiItem = union {
    AbiFunction: AbiFunction,
    AbiEvent: AbiEvent,
    AbiError: AbiError,
    AbiConstructor: AbiConstructor,
    AbiReceive: AbiReceive,
    AbiFallback: AbiFallback,
};

/// Abi spec
pub const Abi = []const AbiItem;
