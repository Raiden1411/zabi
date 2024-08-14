/// Set of Abi items used for the clients
const abi_items = @import("abi.zig");
/// A public client to interacting on L1.
const l1_public_client = @import("clients/L1PubClient.zig");
/// A wallet client to interacting on L1.
const l1_wallet_client = @import("clients/L1WalletClient.zig");
/// A public client to interacting on L2s.
const l2_public_client = @import("clients/L2PubClient.zig");
/// A wallet client to interacting on L2s.
const l2_wallet_client = @import("clients/L2WalletClient.zig");
/// Parse a serialized deposit.
const parse = @import("parse_deposit.zig");
/// Serialize a deposit.
const serialize = @import("serialize_deposit.zig");
/// Set of contracts used in by the superchain.
const superchain_contracts = @import("contracts.zig");
/// Superchain transaction types.
const transaction_types = @import("types/transaction.zig");
/// Types specific for the superchain.
const types = @import("types/types.zig");
/// Set of nice to have utils specific for interacting with the
/// super chain contracts.
const utils = @import("utils.zig");
/// Specfic types for withdrawal events.
const withdrawal_types = @import("types/withdrawl.zig");

test "Superchain Root" {
    _ = @import("utils.test.zig");
    _ = @import("parse_deposit.test.zig");
    _ = @import("serialize_deposit.test.zig");
    _ = @import("clients/l1_public_client.test.zig");
    _ = @import("clients/l2_public_client.test.zig");
}
