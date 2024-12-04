const std = @import("std");
const evm = @import("zabi-evm");
const wasm = @import("wasm.zig");

const Contract = evm.contract.Contract;
const Interpreter = evm.Interpreter;
const PlainHost = evm.host.PlainHost;

pub export fn runCode(
    calldata: [*]u8,
    calldata_len: usize,
    contract_code: [*]const u8,
    contract_len: usize,
) void {
    const alloced = wasm.allocator.alloc(u8, contract_len / 2) catch wasm.panic("Failed to allocate memory", null, null);
    defer wasm.allocator.free(alloced);

    _ = std.fmt.hexToBytes(alloced, contract_code[0..contract_len]) catch wasm.panic("Failed to decode contract_code", null, null);

    const contract_instance = Contract.init(
        wasm.allocator,
        calldata[0..calldata_len],
        .{ .raw = alloced },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    ) catch wasm.panic("Failed to start contract instance.", null, null);
    defer contract_instance.deinit(wasm.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(wasm.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    interpreter.init(wasm.allocator, contract_instance, plain.host(), .{}) catch wasm.panic("Failed to start interpreter", null, null);

    const result = interpreter.run() catch |err| {
        std.log.err("Run result from zig: {s}\n", .{@errorName(err)});
        @trap();
    };
    defer result.deinit(wasm.allocator);

    std.log.err("Run result from zig: {}\n", .{result});
}
