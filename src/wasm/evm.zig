const std = @import("std");
const evm = @import("zabi").evm;
const wasm = @import("wasm.zig");

const Contract = evm.contract.Contract;
const Host = evm.host.Host;
const Interpreter = evm.Interpreter;
const PlainHost = evm.host.PlainHost;
const String = wasm.String;

pub export fn instanciateContract(
    calldata: [*]u8,
    calldata_len: usize,
    contract_code: [*]const u8,
    contract_len: usize,
) *Contract {
    const contract = wasm.allocator.create(Contract) catch wasm.panic("Failed to allocate memory", null, null);
    errdefer wasm.allocator.destroy(contract);

    if (contract_len % 2 != 0)
        wasm.panic("Contract length must follow two's complement", null, null);

    const alloced = wasm.allocator.alloc(u8, contract_len / 2) catch wasm.panic("Failed to allocate memory", null, null);
    defer wasm.allocator.free(alloced);

    _ = std.fmt.hexToBytes(alloced, contract_code[0..contract_len]) catch wasm.panic("Failed to decode contract_code", null, null);

    contract.* = Contract.init(
        wasm.allocator,
        calldata[0..calldata_len],
        .{ .raw = alloced },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    ) catch wasm.panic("Failed to start contract instance.", null, null);

    return contract;
}

pub export fn getPlainHost() *PlainHost {
    var plain = wasm.allocator.create(PlainHost) catch wasm.panic("Failed to allocate memory", null, null);
    errdefer plain.deinit();

    plain.init(wasm.allocator);

    return plain;
}

pub export fn generateHost(plain: *PlainHost) *Host {
    const host = wasm.allocator.create(Host) catch wasm.panic("Failed to allocate memory", null, null);
    host.* = plain.host();

    return host;
}

pub export fn runCode(
    contract: *Contract,
    host: *Host,
) String {
    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    interpreter.init(wasm.allocator, contract.*, host.*, .{}) catch
        wasm.panic("Failed to start interpreter", null, null);

    const result = interpreter.run() catch |err| {
        std.log.err("Failed to execute! Error name: {s}", .{@errorName(err)});
        @trap();
    };
    defer result.deinit(wasm.allocator);

    switch (result) {
        .no_action => return String.init(""),
        .call_action => |action| return String.init(wasm.allocator.dupe(u8, action.inputs) catch wasm.panic("Failed to allocate memory", null, null)),
        .create_action => |action| return String.init(wasm.allocator.dupe(u8, action.init_code) catch wasm.panic("Failed to allocate memory", null, null)),
        .return_action => |action| return String.init(wasm.allocator.dupe(u8, action.output) catch wasm.panic("Failed to allocate memory", null, null)),
    }
}
