const constants = @import("zabi-utils").constants;
const env = @import("enviroment.zig");
const log_types = zabi_types.log;
const spec = @import("specification.zig");
const std = @import("std");
const types = zabi_types.ethereum;
const zabi_types = @import("zabi-types");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Bytecode = @import("bytecode.zig").Bytecode;
const EVMEnviroment = env.EVMEnviroment;
const Hash = types.Hash;
const Log = log_types.Log;
const Storage = std.AutoHashMap(u256, u256);
const SpecId = spec.SpecId;

/// The current status of an account.
pub const AccountStatus = packed struct(u6) {
    cold: u1 = 0,
    self_destructed: u1 = 0,
    touched: u1 = 0,
    created: u1 = 0,
    loaded: u1 = 0,
    non_existent: u1 = 0,
};

/// Representation of the storage of an evm account.
pub const StorageSlot = struct {
    original_value: u256,
    present_value: u256,
    is_cold: bool,
};

/// Information associated with an evm account.
pub const AccountInfo = struct {
    balance: u256,
    nonce: u64,
    code_hash: Hash,
    code: ?Bytecode,
};

/// Representation of an EVM account.
pub const Account = struct {
    info: AccountInfo,
    storage: AutoHashMap(u256, StorageSlot),
    status: AccountStatus,

    pub fn isEmpty(self: Account, spec_id: SpecId) bool {
        if (spec_id.enabled(.SPURIOUS_DRAGON)) {
            const empty_hash = @as(u256, @bitCast(self.info.code_hash)) != 0;
            const keccak_empty = @as(u256, @bitCast(constants.EMPTY_HASH)) != 0;

            return (empty_hash or keccak_empty) and self.info.balance == 0 and self.info.nonce == 0;
        }

        return self.status.non_existent != 0 and self.status.touched == 0;
    }
};

/// Result for loding and account from state.
pub const AccountResult = struct {
    is_cold: bool,
    is_new_account: bool,
};

/// Result of a sstore of code.
pub const SStoreResult = struct {
    original_value: u256,
    present_value: u256,
    new_value: u256,
    is_cold: bool,
};

/// Result of a self destruct opcode
pub const SelfDestructResult = struct {
    had_value: bool,
    target_exists: bool,
    is_cold: bool,
    previously_destroyed: bool,
};

/// Representation of an EVM context host.
pub const Host = struct {
    const SelfHost = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Gets the balance of an `address` and if that address is cold.
        balance: *const fn (self: *anyopaque, address: Address) ?struct { u256, bool },
        /// Gets the block hash from a given block number
        blockHash: *const fn (self: *anyopaque, block_number: u256) ?Hash,
        /// Gets the code of an `address` and if that address is cold.
        code: *const fn (self: *anyopaque, address: Address) ?struct { Bytecode, bool },
        /// Gets the code hash of an `address` and if that address is cold.
        codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool },
        /// Gets the host's `Enviroment`.
        getEnviroment: *const fn (self: *anyopaque) EVMEnviroment,
        /// Loads an account.
        loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult,
        /// Emits a log owned by an address with the log data.
        log: *const fn (self: *anyopaque, log: Log) anyerror!void,
        /// Sets the address to be deleted and any funds it might have to `target` address.
        selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!SelfDestructResult,
        /// Gets the storage value of an `address` at a given `index` and if that address is cold.
        sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!struct { u256, bool },
        /// Sets a storage value of an `address` at a given `index` and if that address is cold.
        sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!SStoreResult,
        /// Gets the transient storage value of an `address` at a given `index`.
        tload: *const fn (self: *anyopaque, address: Address, index: u256) ?u256,
        /// Sets the transient storage value of an `address` at a given `index`.
        tstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!void,
    };

    /// Gets the balance of an `address` and if that address is cold.
    pub inline fn balance(self: SelfHost, address: Address) ?struct { u256, bool } {
        return self.vtable.balance(self.ptr, address);
    }
    /// Gets the block hash from a given block number
    pub inline fn blockHash(self: SelfHost, block_number: u256) ?Hash {
        return self.vtable.blockHash(self.ptr, block_number);
    }
    /// Gets the code of an `address` and if that address is cold.
    pub inline fn code(self: SelfHost, address: Address) ?struct { Bytecode, bool } {
        return self.vtable.code(self.ptr, address);
    }
    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn codeHash(self: SelfHost, address: Address) ?struct { Hash, bool } {
        return self.vtable.codeHash(self.ptr, address);
    }
    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn getEnviroment(self: SelfHost) EVMEnviroment {
        return self.vtable.getEnviroment(self.ptr);
    }
    /// Loads an account.
    pub inline fn loadAccount(self: SelfHost, address: Address) ?AccountResult {
        return self.vtable.loadAccount(self.ptr, address);
    }
    /// Emits a log owned by an address with the log data.
    pub inline fn log(self: SelfHost, log_event: Log) anyerror!void {
        return self.vtable.log(self.ptr, log_event);
    }
    /// Sets the address to be deleted and any funds it might have to `target` address.
    pub inline fn selfDestruct(self: SelfHost, address: Address, target: Address) anyerror!SelfDestructResult {
        return self.vtable.selfDestruct(self.ptr, address, target);
    }
    /// Gets the storage value of an `address` at a given `index` and if that address is cold.
    pub inline fn sload(self: SelfHost, address: Address, index: u256) anyerror!struct { u256, bool } {
        return self.vtable.sload(self.ptr, address, index);
    }
    /// Sets a storage value of an `address` at a given `index` and if that address is cold.
    pub inline fn sstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!SStoreResult {
        return self.vtable.sstore(self.ptr, address, index, value);
    }
    /// Gets the transient storage value of an `address` at a given `index`.
    pub inline fn tload(self: SelfHost, address: Address, index: u256) ?u256 {
        return self.vtable.tload(self.ptr, address, index);
    }
    /// Emits a log owned by an address with the log data.
    pub inline fn tstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!void {
        return self.vtable.tstore(self.ptr, address, index, value);
    }
};

/// Mainly serves as a basic implementation of an evm host.
pub const PlainHost = struct {
    const Self = @This();

    /// The EVM enviroment
    env: EVMEnviroment,
    /// The storage of this host.
    storage: Storage,
    /// The transient storage of this host.
    transient_storage: Storage,
    /// The logs of this host.
    log_storage: ArrayList(Log),

    /// Creates instance of this `PlainHost`.
    pub fn init(self: *Self, allocator: Allocator) void {
        const storage = Storage.init(allocator);
        const transient_storage = Storage.init(allocator);
        const logs = ArrayList(Log).init(allocator);

        self.* = .{
            .env = EVMEnviroment.default(),
            .storage = storage,
            .transient_storage = transient_storage,
            .log_storage = logs,
        };
    }

    pub fn deinit(self: *Self) void {
        while (self.log_storage.popOrNull()) |log_event| {
            self.log_storage.allocator.free(log_event.topics);
        }

        self.log_storage.deinit();
        self.storage.deinit();
        self.transient_storage.deinit();
    }
    /// Returns the `Host` implementation for this instance.
    pub fn host(self: *Self) Host {
        return .{
            .ptr = self,
            .vtable = &.{
                .balance = balance,
                .blockHash = blockHash,
                .code = code,
                .codeHash = codeHash,
                .getEnviroment = getEnviroment,
                .loadAccount = loadAccount,
                .log = log,
                .selfDestruct = selfDestruct,
                .sload = sload,
                .sstore = sstore,
                .tload = tload,
                .tstore = tstore,
            },
        };
    }

    fn balance(_: *anyopaque, _: Address) ?struct { u256, bool } {
        return .{ 0, false };
    }

    fn blockHash(_: *anyopaque, _: u256) ?Hash {
        return [_]u8{0} ** 32;
    }

    fn code(_: *anyopaque, _: Address) ?struct { Bytecode, bool } {
        return .{ .{ .raw = &[_]u8{} }, false };
    }

    fn codeHash(_: *anyopaque, _: Address) ?struct { Hash, bool } {
        return .{ [_]u8{0} ** 32, false };
    }

    fn getEnviroment(ctx: *anyopaque) EVMEnviroment {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.env;
    }

    fn loadAccount(_: *anyopaque, _: Address) ?AccountResult {
        return AccountResult{ .is_new_account = false, .is_cold = false };
    }

    fn log(ctx: *anyopaque, log_event: Log) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        try self.log_storage.ensureUnusedCapacity(1);
        self.log_storage.appendAssumeCapacity(log_event);
    }

    fn selfDestruct(_: *anyopaque, _: Address, _: Address) !SelfDestructResult {
        @panic("selfDestruct is not implemented on this host");
    }

    fn sload(ctx: *anyopaque, _: Address, index: u256) Allocator.Error!struct { u256, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const entry = self.storage.get(index);

        const result: struct { u256, bool } = blk: {
            if (entry) |value|
                break :blk .{ value, false };

            try self.storage.put(index, 0);
            break :blk .{ 0, true };
        };

        return result;
    }

    fn sstore(ctx: *anyopaque, _: Address, index: u256, value: u256) Allocator.Error!SStoreResult {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const entry = self.storage.get(index);

        const result: SStoreResult = blk: {
            if (entry) |entry_value| {
                try self.storage.put(index, value);
                break :blk .{
                    .is_cold = false,
                    .new_value = value,
                    .present_value = entry_value,
                    .original_value = 0,
                };
            }

            try self.storage.put(index, value);
            break :blk .{
                .is_cold = true,
                .new_value = value,
                .present_value = 0,
                .original_value = 0,
            };
        };

        return result;
    }

    fn tload(ctx: *anyopaque, _: Address, index: u256) ?u256 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.transient_storage.get(index);
    }

    fn tstore(ctx: *anyopaque, _: Address, index: u256, value: u256) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.transient_storage.put(index, value);
    }
};
