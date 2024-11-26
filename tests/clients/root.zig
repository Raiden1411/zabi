test "Clients Root" {
    // Block explorer tests
    // _ = @import("block_explorer.test.zig");
    // _ = @import("url.test.zig");
    //
    // // Pub clients tests
    // _ = @import("public_client.test.zig");
    // _ = @import("ipc.test.zig");
    _ = @import("websocket.test.zig");

    // Wallet tests
    // _ = @import("wallet.test.zig");
    // _ = @import("contract.test.zig");
    //
    // // Ens tests
    // _ = @import("ens.test.zig");
    // _ = @import("ens_utils.test.zig");
    //
    // // Op-stack tests
    // _ = @import("parse_deposit.test.zig");
    // _ = @import("serialize_deposit.test.zig");
    // _ = @import("utils.test.zig");
    //
    // _ = @import("l1_wallet_client.test.zig");
    // _ = @import("l1_public_client.test.zig");
    // _ = @import("l2_public_client.test.zig");

    // Test only available to OP_MAINNET
    // _ = @import("l2_wallet_client.test.zig");
}
