const analysis = @import("analysis.zig");
const enviroment = @import("enviroment.zig");
const std = @import("std");
const types = @import("zabi-types").ethereum;
const transaction = @import("zabi-types").transactions;

const Allocator = std.mem.Allocator;
const Address = types.Address;
const Bytecode = @import("bytecode.zig").Bytecode;
const EVMEnviroment = enviroment.EVMEnviroment;
const Hash = types.Hash;

/// EVM contract representation.
pub const Contract = struct {
    /// The bytecode associated with this contract.
    bytecode: Bytecode,
    /// Address that called this contract.
    caller: Address,
    /// Keccak hash of the bytecode.
    code_hash: ?Hash = null,
    /// The calldata input to use in this contract.
    input: []u8,
    /// The address of this contract.
    target_address: Address,
    /// Value in wei associated with this contract.
    value: u256,

    /// Creates a contract instance from the provided inputs.
    /// This will also prepare the provided bytecode in case it's given in a `raw` state.
    pub fn init(
        allocator: Allocator,
        data: []u8,
        bytecode: Bytecode,
        hash: ?Hash,
        value: u256,
        caller: Address,
        target_address: Address,
    ) Allocator.Error!Contract {
        const analyzed = try analysis.analyzeBytecode(allocator, bytecode);

        return .{
            .input = data,
            .bytecode = analyzed,
            .code_hash = hash,
            .value = value,
            .caller = caller,
            .target_address = target_address,
        };
    }

    /// Creates a contract instance from a given enviroment.
    /// This will also prepare the provided bytecode in case it's given in a `raw` state.
    pub fn initFromEnviroment(allocator: Allocator, env: EVMEnviroment, bytecode: Bytecode, hash: ?Hash) !Contract {
        const analyzed = try analysis.analyzeBytecode(allocator, bytecode);
        const contract_address = switch (env.tx.transact_to) {
            .call => |addr| addr,
            .create => [_]u8{0} ** 20,
        };

        return .{
            .input = env.tx.data,
            .bytecode = analyzed,
            .code_hash = hash,
            .value = env.tx.value,
            .caller = env.tx.caller,
            .target_address = contract_address,
        };
    }

    /// Clears the bytecode in case it's analyzed.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        self.bytecode.deinit(allocator);
    }

    /// Returns if the provided target result in a valid jump dest.
    pub fn isValidJump(self: Contract, target: usize) bool {
        const jump_table = self.bytecode.getJumpTable() orelse return false;

        return jump_table.isValid(target);
    }
};
