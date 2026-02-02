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

    if (contract_len % 2 != 0 or calldata_len % 2 != 0)
        wasm.panic("Contract length and calldata length must follow two's complement", null, null);

    const bytecode = wasm.allocator.alloc(u8, contract_len / 2) catch wasm.panic("Failed to allocate memory", null, null);
    errdefer wasm.allocator.free(bytecode);

    _ = std.fmt.hexToBytes(bytecode, contract_code[0..contract_len]) catch wasm.panic("Failed to decode contract_code", null, null);

    const input = wasm.allocator.alloc(u8, calldata_len / 2) catch wasm.panic("Failed to allocate memory", null, null);
    errdefer wasm.allocator.free(input);

    _ = std.fmt.hexToBytes(input, calldata[0..calldata_len]) catch wasm.panic("Failed to decode calldata", null, null);

    contract.* = Contract.init(
        wasm.allocator,
        input,
        .{ .raw = bytecode },
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
    contract: *const Contract,
    host: *Host,
) String {
    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    interpreter.init(wasm.allocator, contract, host.*, .{ .gas_limit = 300_000_000 }) catch
        wasm.panic("Failed to start interpreter", null, null);

    const result = interpreter.run() catch |err| {
        std.log.err("Failed to execute! Error name: {s}", .{@errorName(err)});
        @trap();
    };
    defer result.deinit(wasm.allocator);

    switch (result) {
        .no_action => return .{ .ptr = 0, .len = 0 },
        .call_action => |action| return dupeToString(action.inputs),
        .create_action => |action| return dupeToString(action.init_code),
        .return_action => |action| return dupeToString(action.output),
    }
}

fn dupeToString(data: []const u8) String {
    if (data.len == 0) {
        return .{ .ptr = 0, .len = 0 };
    }
    const duped = wasm.allocator.dupe(u8, data) catch wasm.panic("Failed to allocate memory", null, null);
    return String.init(duped);
}
