/// async enabled implementation of some of zabi's rpc clients.
pub const @"async" = @import("async/root.zig");

/// A generic client for interactintes
pub const contract = @import("contract.zig");

/// KZG commitments. Related to EIP4844. Uses the c library
/// to enable support for zabi to use.
pub const kzg4844 = @import("c_kzg_4844");

/// Multicall contract wrapper that exposes contract functions.
pub const multicall = @import("multicall.zig");

/// Network config for different type of chains and associated contracts.
pub const network = @import("network.zig");

/// Dedicated `searchUrlParams` for zabi expected types.
/// This also includes the `QueryWriter` which details the supported types
pub const url = @import("url.zig");

/// A generic wallet implementation to send transactions
/// and sign messages with.
pub const wallet = @import("wallet.zig");

/// The HTTP/S rpc client to interact with EVM based chains.
/// Supports most RPC methods. Converts errors responses
/// into zig errors. Handles error 429 but not the rest.
pub const PubClient = @import("Client.zig");

/// The WS/S rpc client to interact with EVM based chains.
/// Supports most RPC methods. Converts errors responses
/// into zig errors. Handles error 429 but not the rest.
pub const WebSocket = @import("WebSocket.zig");

/// Zabi's custom websocket client RFC implementation.
/// RFC: https://www.rfc-editor.org/rfc/rfc6455
pub const WebSocketClient = @import("WebSocketClient.zig");

/// The ipc rpc client to interact with EVM based chains.
/// Supports most RPC methods. Converts errors responses
/// into zig errors. Handles error 429 but not the rest.
pub const IpcClient = @import("IPC.zig");

/// The Block explorer client. Used for calling the api endpoints
/// of endpoints like etherscan and alike. It has it's own dedicated
/// `searchUrlParams` writer. It only supports the free api methods,
/// but you should have all the tool available in the library if you want to target
/// the PRO methods.
pub const BlockExplorer = @import("BlockExplorer.zig");

/// Custom wrapper for interacting with the Anvil testchain
pub const Anvil = @import("Anvil.zig");

/// Custom wrapper for interacting with the Hardhat testchain
pub const Hardhat = @import("Hardhat.zig");
