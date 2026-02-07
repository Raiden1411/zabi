const std = @import("std");
const zabi_evm = @import("zabi").evm;
const zabi_utils = @import("zabi").utils;

const EVM = zabi_evm.EVM;
const EVMEnviroment = zabi_evm.enviroment.EVMEnviroment;
const JournaledHost = zabi_evm.host.JournaledHost;
const JournaledState = zabi_evm.journal.JournaledState;
const MemoryDatabase = zabi_evm.database.MemoryDatabase;
const AccountInfo = zabi_evm.host.AccountInfo;

pub const CliOptions = struct {
    bytecode: []const u8,
    calldata: ?[]const u8 = null,
};

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.smp_allocator;

    var iter = init.args.iterate();
    const parsed = zabi_utils.args.parseArgs(CliOptions, allocator, &iter);

    const calldata_slice = parsed.calldata orelse "";

    const bytecode = try allocator.alloc(u8, @divExact(parsed.bytecode.len, 2));
    defer allocator.free(bytecode);

    const calldata = try allocator.alloc(u8, @divExact(calldata_slice.len, 2));
    defer allocator.free(calldata);

    _ = try std.fmt.hexToBytes(bytecode, parsed.bytecode);
    _ = try std.fmt.hexToBytes(calldata, calldata_slice);

    var evm: EVM = undefined;
    defer evm.deinit();

    const caller: [20]u8 = [_]u8{1} ** 20;
    const target: [20]u8 = [_]u8{2} ** 20;

    const env: EVMEnviroment = .{
        .config = .{ .spec_id = .LATEST, .disable_balance_check = true },
        .block = .{ .gas_limit = 300_000_000 },
        .tx = .{
            .caller = caller,
            .transact_to = .{ .call = target },
            .gas_limit = 300_000_000,
            .gas_price = 1,
            .value = 0,
            .data = calldata,
        },
    };

    var database: MemoryDatabase = undefined;
    defer database.deinit();

    try database.init(allocator);

    var caller_info: AccountInfo = .{
        .balance = 0,
        .nonce = 0,
        .code_hash = zabi_utils.constants.EMPTY_HASH,
        .code = null,
    };

    var target_info: AccountInfo = .{
        .balance = 0,
        .nonce = 0,
        .code_hash = [_]u8{2} ** 32,
        .code = .{ .raw = bytecode },
    };

    try database.addAccountInfo(caller, &caller_info);
    try database.addAccountInfo(target, &target_info);

    var journal: JournaledState = undefined;
    defer journal.deinit();

    journal.init(allocator, env.config.spec_id, database.database());

    var host = JournaledHost.init(env, journal);

    evm.init(allocator, host.host());

    var result = try evm.executeTransaction();
    defer result.deinit(allocator);

    std.debug.print("EVM result: {any}", .{result});
}
