const init = @import("signer.zig");

var has_inited = false;

pub fn ensureInit() !void {
    if (has_inited) return;

    try init.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
}
