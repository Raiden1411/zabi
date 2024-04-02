/// A generic client for interacting with EVM contracts.
pub const contract = @import("contract.zig");
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
