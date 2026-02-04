const constants = @import("zabi-utils").constants;
const env = @import("enviroment.zig");
const journal = @import("journal.zig");
const log_types = zabi_types.log;
const spec = @import("specification.zig");
const std = @import("std");
const types = zabi_types.ethereum;
const zabi_types = @import("zabi-types");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;
const Bytecode = @import("bytecode.zig").Bytecode;
const EVMEnviroment = env.EVMEnviroment;
const Hash = types.Hash;
const JournaledState = journal.JournaledState;
const JournalCheckpoint = journal.JournalCheckpoint;
const Log = log_types.Log;
const StateLoaded = journal.StateLoaded;
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
        blockHash: *const fn (self: *anyopaque, block_number: u64) ?Hash,
        /// Creates a new checkpoint for state rollback and increases call depth.
        checkpoint: *const fn (self: *anyopaque) anyerror!JournalCheckpoint,
        /// Gets the code of an `address` and if that address is cold.
        code: *const fn (self: *anyopaque, address: Address) ?struct { Bytecode, bool },
        /// Gets the code hash of an `address` and if that address is cold.
        codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool },
        /// Commits the current checkpoint, making state changes permanent.
        commitCheckpoint: *const fn (self: *anyopaque) void,
        /// Gets the host's `Enviroment`.
        getEnviroment: *const fn (self: *anyopaque) EVMEnviroment,
        /// Loads an account.
        loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult,
        /// Emits a log owned by an address with the log data.
        log: *const fn (self: *anyopaque, log: Log) anyerror!void,
        /// Reverts state changes back to the given checkpoint.
        revertCheckpoint: *const fn (self: *anyopaque, checkpoint: JournalCheckpoint) anyerror!void,
        /// Sets the address to be deleted and any funds it might have to `target` address.
        selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult),
        /// Gets the storage value of an `address` at a given `index` and if that address is cold.
        sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!StateLoaded(u256),
        /// Sets a storage value of an `address` at a given `index` and if that address is cold.
        sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult),
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
    pub inline fn blockHash(self: SelfHost, block_number: u64) ?Hash {
        return self.vtable.blockHash(self.ptr, block_number);
    }
    /// Creates a new checkpoint for state rollback and increases call depth.
    pub inline fn checkpoint(self: SelfHost) anyerror!JournalCheckpoint {
        return self.vtable.checkpoint(self.ptr);
    }
    /// Gets the code of an `address` and if that address is cold.
    pub inline fn code(self: SelfHost, address: Address) ?struct { Bytecode, bool } {
        return self.vtable.code(self.ptr, address);
    }
    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn codeHash(self: SelfHost, address: Address) ?struct { Hash, bool } {
        return self.vtable.codeHash(self.ptr, address);
    }
    /// Commits the current checkpoint, making state changes permanent.
    pub inline fn commitCheckpoint(self: SelfHost) void {
        return self.vtable.commitCheckpoint(self.ptr);
    }
    /// Gets the host's `Enviroment`.
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
    /// Reverts state changes back to the given checkpoint.
    pub inline fn revertCheckpoint(self: SelfHost, point: JournalCheckpoint) anyerror!void {
        return self.vtable.revertCheckpoint(self.ptr, point);
    }
    /// Sets the address to be deleted and any funds it might have to `target` address.
    pub inline fn selfDestruct(self: SelfHost, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult) {
        return self.vtable.selfDestruct(self.ptr, address, target);
    }
    /// Gets the storage value of an `address` at a given `index` and if that address is cold.
    pub inline fn sload(self: SelfHost, address: Address, index: u256) anyerror!StateLoaded(u256) {
        return self.vtable.sload(self.ptr, address, index);
    }
    /// Sets a storage value of an `address` at a given `index` and if that address is cold.
    pub inline fn sstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult) {
        return self.vtable.sstore(self.ptr, address, index, value);
    }
    /// Gets the transient storage value of an `address` at a given `index`.
    pub inline fn tload(self: SelfHost, address: Address, index: u256) ?u256 {
        return self.vtable.tload(self.ptr, address, index);
    }
    /// Sets the transient storage value of an `address` at a given `index`.
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
            .env = .{},
            .storage = storage,
            .transient_storage = transient_storage,
            .log_storage = logs,
        };
    }

    pub fn deinit(self: *Self) void {
        while (self.log_storage.pop()) |log_event| {
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
                .checkpoint = checkpoint,
                .code = code,
                .codeHash = codeHash,
                .commitCheckpoint = commitCheckpoint,
                .getEnviroment = getEnviroment,
                .loadAccount = loadAccount,
                .log = log,
                .revertCheckpoint = revertCheckpoint,
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

    fn blockHash(_: *anyopaque, _: u64) ?Hash {
        return [_]u8{0} ** 32;
    }

    fn checkpoint(_: *anyopaque) error{}!JournalCheckpoint {
        return .{ .journal_checkpoint = 0, .logs_checkpoint = 0 };
    }

    fn code(_: *anyopaque, _: Address) ?struct { Bytecode, bool } {
        return .{ .{ .raw = &[_]u8{} }, false };
    }

    fn codeHash(_: *anyopaque, _: Address) ?struct { Hash, bool } {
        return .{ [_]u8{0} ** 32, false };
    }

    fn commitCheckpoint(_: *anyopaque) void {}

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

    fn revertCheckpoint(_: *anyopaque, _: JournalCheckpoint) error{}!void {}

    fn selfDestruct(_: *anyopaque, _: Address, _: Address) error{}!StateLoaded(SelfDestructResult) {
        @panic("selfDestruct is not implemented on this host");
    }

    fn sload(ctx: *anyopaque, _: Address, index: u256) Allocator.Error!StateLoaded(u256) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const entry = self.storage.get(index);

        const result: StateLoaded(u256) = blk: {
            if (entry) |value|
                break :blk .{ .data = value, .cold = false };

            try self.storage.put(index, 0);
            break :blk .{ .data = 0, .cold = true };
        };

        return result;
    }

    fn sstore(ctx: *anyopaque, _: Address, index: u256, value: u256) Allocator.Error!StateLoaded(SStoreResult) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const entry = self.storage.get(index);

        const result: StateLoaded(SStoreResult) = blk: {
            if (entry) |entry_value| {
                try self.storage.put(index, value);
                break :blk .{
                    .data = .{
                        .is_cold = false,
                        .new_value = value,
                        .present_value = entry_value,
                        .original_value = 0,
                    },
                    .cold = false,
                };
            }

            try self.storage.put(index, value);
            break :blk .{
                .data = .{
                    .is_cold = true,
                    .new_value = value,
                    .present_value = 0,
                    .original_value = 0,
                },
                .cold = true,
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

/// EVM Journaled context.
pub const JournaledHost = struct {
    const Self = @This();

    /// Inner evm state.
    journal: JournaledState,
    /// EVM enviroment context.
    env: EVMEnviroment,

    /// Sets the initial state the journaled host.
    pub fn init(enviroment: EVMEnviroment, journal_db: JournaledState) !void {
        return .{
            .env = enviroment,
            .journal = journal_db,
        };
    }

    /// Returns the `Host` implementation for this instance.
    pub fn host(self: *Self) Host {
        return .{
            .ptr = self,
            .vtable = &.{
                .balance = balance,
                .blockHash = blockHash,
                .checkpoint = checkpoint,
                .code = code,
                .codeHash = codeHash,
                .commitCheckpoint = commitCheckpoint,
                .getEnviroment = getEnviroment,
                .loadAccount = loadAccount,
                .log = log,
                .revertCheckpoint = revertCheckpoint,
                .selfDestruct = selfDestruct,
                .sload = sload,
                .sstore = sstore,
                .tload = tload,
                .tstore = tstore,
            },
        };
    }

    // Implementation of the interface.
    fn balance(ctx: *anyopaque, address: Address) ?struct { u256, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const account = self.journal.loadAccount(address) catch return null;

        return .{
            account.data.info.balance,
            account.cold,
        };
    }

    fn blockHash(ctx: *anyopaque, number: u64) ?Hash {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const diff, const overflow = @subWithOverflow(self.env.block.number, number);

        if (overflow != 0)
            return [_]u8{0} ** 32;

        switch (diff) {
            0,
            => return [_]u8{0} ** 32,
            1...256,
            => return self.journal.database.blockHash(number) catch null,
            else => return [_]u8{0} ** 32,
        }
    }

    fn checkpoint(ctx: *anyopaque) anyerror!JournalCheckpoint {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.checkpoint();
    }

    fn code(ctx: *anyopaque, address: Address) ?struct { Bytecode, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const account = self.journal.loadCode(address) catch return null;

        return .{
            account.data.info.code orelse .{ .raw = @constCast("") },
            account.cold,
        };
    }

    fn codeHash(ctx: *anyopaque, address: Address) ?struct { Hash, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const account = self.journal.loadCode(address) catch return null;

        return .{
            account.data.info.code_hash,
            account.cold,
        };
    }

    fn commitCheckpoint(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.journal.commitCheckpoint();
    }

    fn getEnviroment(ctx: *anyopaque) EVMEnviroment {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.env;
    }

    fn loadAccount(ctx: *anyopaque, address: Address) ?AccountResult {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const account = self.journal.loadAccount(address) catch return null;

        return .{
            .is_new_account = account.data.status.created != 0,
            .is_cold = account.cold,
        };
    }

    fn log(ctx: *anyopaque, log_event: Log) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        try self.journal.log_storage.ensureUnusedCapacity(1);
        self.journal.log_storage.appendAssumeCapacity(log_event);
    }

    fn revertCheckpoint(ctx: *anyopaque, point: JournalCheckpoint) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.revertCheckpoint(point);
    }

    fn selfDestruct(ctx: *anyopaque, from: Address, target: Address) !StateLoaded(SelfDestructResult) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = try self.journal.selfDestruct(from, target);

        return result.data;
    }

    fn sload(ctx: *anyopaque, address: Address, index: u256) !StateLoaded(u256) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.sload(address, index);
    }

    fn sstore(ctx: *anyopaque, address: Address, index: u256, value: u256) !StateLoaded(SStoreResult) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.sstore(address, index, value);
    }

    fn tload(ctx: *anyopaque, address: Address, index: u256) ?u256 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.tload(address, index);
    }

    fn tstore(ctx: *anyopaque, address: Address, index: u256, value: u256) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.tstore(address, index, value);
    }
};
