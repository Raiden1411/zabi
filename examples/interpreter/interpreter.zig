const std = @import("std");
const zabi_evm = @import("zabi").evm;
const zabi_utils = @import("zabi").utils;

const Contract = zabi_evm.contract.Contract;
const Interpreter = zabi_evm.Interpreter;
const PlainHost = zabi_evm.host.PlainHost;

pub const CliOptions = struct {
    bytecode: []const u8,
    calldata: ?[]const u8 = null,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();

    const parsed = zabi_utils.args.parseArgs(CliOptions, allocator, &iter);
    const calldata_slice = parsed.calldata orelse "";

    const bytecode = try allocator.alloc(u8, @divExact(parsed.bytecode.len, 2));
    defer allocator.free(bytecode);

    const calldata = try allocator.alloc(u8, @divExact(calldata_slice.len, 2));
    defer allocator.free(calldata);

    _ = try std.fmt.hexToBytes(bytecode, parsed.bytecode);
    _ = try std.fmt.hexToBytes(calldata, calldata_slice);

    const contract_instance = try Contract.init(
        allocator,
        calldata,
        .{ .raw = bytecode },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(
        allocator,
        contract_instance,
        plain.host(),
        .{ .gas_limit = 300_000_000 },
    );

    const result = try interpreter.run();
    defer result.deinit(allocator);

    std.debug.print("Interpreter result: {any}", .{result});
}
