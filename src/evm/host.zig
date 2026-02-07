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
        /// Gets the full account info for an `address`.
        accountInfo: *const fn (self: *anyopaque, address: Address) ?AccountInfo,
        /// Gets the balance of an `address` and if that address is cold.
        balance: *const fn (self: *anyopaque, address: Address) ?struct { u256, bool },
        /// Gets the block hash from a given block number
        blockHash: *const fn (self: *anyopaque, block_number: u64) ?Hash,
        /// Creates a new checkpoint for state rollback and increases call depth.
        checkpoint: *const fn (self: *anyopaque) JournalCheckpoint,
        /// Creates a new checkpoint for state rollback and increases call depth.
        createAccount: *const fn (self: *anyopaque, caller: Address, target_address: Address, value: u256) JournaledState.CreateAccountErrors!JournalCheckpoint,
        /// Gets the code of an `address` and if that address is cold.
        code: *const fn (self: *anyopaque, address: Address) ?struct { Bytecode, bool },
        /// Gets the code hash of an `address` and if that address is cold.
        codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool },
        /// Commits the current checkpoint, making state changes permanent.
        commitCheckpoint: *const fn (self: *anyopaque) void,
        /// Clears all transient storage values for transaction-boundary cleanup.
        clearTransientStorage: *const fn (self: *anyopaque) void,
        /// Clears transaction-scoped warm preload state.
        clearWarmPreloads: *const fn (self: *anyopaque) void,
        /// Gets the host's `Enviroment`.
        getEnviroment: *const fn (self: *anyopaque) EVMEnviroment,
        /// Increments the nonce value with associated address account.
        incrementNonce: *const fn (self: *anyopaque, address: Address) (Allocator.Error || error{Overflow})!u64,
        /// Loads an account.
        loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult,
        /// Marks an account as warm for transaction-scoped EIP-2929 tracking.
        preloadWarmAddress: *const fn (self: *anyopaque, address: Address) anyerror!void,
        /// Marks a storage key as warm for transaction-scoped EIP-2930 tracking.
        preloadWarmStorage: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!void,
        /// Emits a log owned by an address with the log data.
        log: *const fn (self: *anyopaque, log: Log) anyerror!void,
        /// Reverts state changes back to the given checkpoint.
        revertCheckpoint: *const fn (self: *anyopaque, checkpoint: JournalCheckpoint) anyerror!void,
        /// Sets the address to be deleted and any funds it might have to `target` address.
        selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult),
        /// Sets the provided bytecode in the account of the provided address.
        setCode: *const fn (self: *anyopaque, address: Address, bytecode: Bytecode) (Allocator.Error || error{NonExistentAccount})!void,
        /// Gets the storage value of an `address` at a given `index` and if that address is cold.
        sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!StateLoaded(u256),
        /// Sets a storage value of an `address` at a given `index` and if that address is cold.
        sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult),
        /// Gets the transient storage value of an `address` at a given `index`.
        tload: *const fn (self: *anyopaque, address: Address, index: u256) ?u256,
        /// Sets the transient storage value of an `address` at a given `index`.
        tstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!void,
        /// Transfers value from one address to another.
        transfer: *const fn (self: *anyopaque, from: Address, to: Address, value: u256) anyerror!void,
    };

    /// Gets the full account info for an `address`.
    pub inline fn accountInfo(self: SelfHost, address: Address) ?AccountInfo {
        return self.vtable.accountInfo(self.ptr, address);
    }

    /// Gets the balance of an `address` and if that address is cold.
    pub inline fn balance(self: SelfHost, address: Address) ?struct { u256, bool } {
        return self.vtable.balance(self.ptr, address);
    }

    /// Gets the block hash from a given block number
    pub inline fn blockHash(self: SelfHost, block_number: u64) ?Hash {
        return self.vtable.blockHash(self.ptr, block_number);
    }

    /// Creates a new checkpoint for state rollback and increases call depth.
    pub inline fn checkpoint(self: SelfHost) JournalCheckpoint {
        return self.vtable.checkpoint(self.ptr);
    }

    /// Creates a new checkpoint for state rollback and increases call depth.
    pub inline fn createAccount(self: SelfHost, caller: Address, target_address: Address, value: u256) JournaledState.CreateAccountErrors!JournalCheckpoint {
        return self.vtable.createAccount(self.ptr, caller, target_address, value);
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

    /// Clears all transient storage values for transaction-boundary cleanup.
    pub inline fn clearTransientStorage(self: SelfHost) void {
        return self.vtable.clearTransientStorage(self.ptr);
    }

    /// Clears transaction-scoped warm preload state.
    pub inline fn clearWarmPreloads(self: SelfHost) void {
        return self.vtable.clearWarmPreloads(self.ptr);
    }

    /// Transfers value from one address to another.
    pub inline fn incrementNonce(self: SelfHost, from: Address) (Allocator.Error || error{Overflow})!u64 {
        return self.vtable.incrementNonce(self.ptr, from);
    }

    /// Gets the host's `Enviroment`.
    pub inline fn getEnviroment(self: SelfHost) EVMEnviroment {
        return self.vtable.getEnviroment(self.ptr);
    }

    /// Loads an account.
    pub inline fn loadAccount(self: SelfHost, address: Address) ?AccountResult {
        return self.vtable.loadAccount(self.ptr, address);
    }

    /// Marks an account as warm for transaction-scoped EIP-2929 tracking.
    pub inline fn preloadWarmAddress(self: SelfHost, address: Address) anyerror!void {
        return self.vtable.preloadWarmAddress(self.ptr, address);
    }

    /// Marks a storage key as warm for transaction-scoped EIP-2930 tracking.
    pub inline fn preloadWarmStorage(self: SelfHost, address: Address, index: u256) anyerror!void {
        return self.vtable.preloadWarmStorage(self.ptr, address, index);
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

    /// Sets the provided bytecode in the account of the provided address.
    pub inline fn setCode(self: SelfHost, address: Address, bytecode: Bytecode) (Allocator.Error || error{NonExistentAccount})!void {
        return self.vtable.setCode(self.ptr, address, bytecode);
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

    /// Transfers value from one address to another.
    pub inline fn transfer(self: SelfHost, from: Address, to: Address, value: u256) anyerror!void {
        return self.vtable.transfer(self.ptr, from, to, value);
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
                .accountInfo = accountInfo,
                .balance = balance,
                .blockHash = blockHash,
                .checkpoint = checkpoint,
                .createAccount = createAccount,
                .code = code,
                .codeHash = codeHash,
                .commitCheckpoint = commitCheckpoint,
                .clearTransientStorage = clearTransientStorage,
                .clearWarmPreloads = clearWarmPreloads,
                .getEnviroment = getEnviroment,
                .incrementNonce = incrementNonce,
                .loadAccount = loadAccount,
                .preloadWarmAddress = preloadWarmAddress,
                .preloadWarmStorage = preloadWarmStorage,
                .log = log,
                .revertCheckpoint = revertCheckpoint,
                .setCode = setCode,
                .selfDestruct = selfDestruct,
                .sload = sload,
                .sstore = sstore,
                .tload = tload,
                .tstore = tstore,
                .transfer = transfer,
            },
        };
    }

    fn accountInfo(_: *anyopaque, _: Address) ?AccountInfo {
        return .{
            .balance = 0,
            .nonce = 0,
            .code_hash = [_]u8{0} ** 32,
            .code = null,
        };
    }

    fn balance(_: *anyopaque, _: Address) ?struct { u256, bool } {
        return .{ 0, false };
    }

    fn blockHash(_: *anyopaque, _: u64) ?Hash {
        return [_]u8{0} ** 32;
    }

    fn checkpoint(_: *anyopaque) JournalCheckpoint {
        return .{ .journal_checkpoint = 0, .logs_checkpoint = 0 };
    }

    fn createAccount(_: *anyopaque, _: Address, _: Address, _: u256) JournaledState.CreateAccountErrors!JournalCheckpoint {
        return .{ .journal_checkpoint = 0, .logs_checkpoint = 0 };
    }

    fn code(_: *anyopaque, _: Address) ?struct { Bytecode, bool } {
        return .{ .{ .raw = &[_]u8{} }, false };
    }

    fn codeHash(_: *anyopaque, _: Address) ?struct { Hash, bool } {
        return .{ [_]u8{0} ** 32, false };
    }

    fn commitCheckpoint(_: *anyopaque) void {}

    fn clearTransientStorage(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.transient_storage.clearRetainingCapacity();
    }

    fn clearWarmPreloads(_: *anyopaque) void {}

    fn getEnviroment(ctx: *anyopaque) EVMEnviroment {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.env;
    }

    fn incrementNonce(_: *anyopaque, _: Address) (Allocator.Error || error{Overflow})!u64 {
        return 0;
    }

    fn loadAccount(_: *anyopaque, _: Address) ?AccountResult {
        return AccountResult{ .is_new_account = false, .is_cold = false };
    }

    fn preloadWarmAddress(_: *anyopaque, _: Address) error{}!void {}

    fn preloadWarmStorage(_: *anyopaque, _: Address, _: u256) error{}!void {}

    fn log(ctx: *anyopaque, log_event: Log) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        try self.log_storage.ensureUnusedCapacity(1);
        self.log_storage.appendAssumeCapacity(log_event);
    }

    fn revertCheckpoint(_: *anyopaque, _: JournalCheckpoint) error{}!void {}

    fn selfDestruct(_: *anyopaque, _: Address, _: Address) error{}!StateLoaded(SelfDestructResult) {
        @panic("selfDestruct is not implemented on this host");
    }

    fn setCode(_: *anyopaque, _: Address, _: Bytecode) (Allocator.Error || error{NonExistentAccount})!void {}

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

    fn transfer(_: *anyopaque, _: Address, _: Address, _: u256) error{}!void {}
};

/// EVM Journaled context.
pub const JournaledHost = struct {
    const Self = @This();

    /// Inner evm state.
    journal: JournaledState,
    /// EVM enviroment context.
    env: EVMEnviroment,

    /// Sets the initial state the journaled host.
    pub fn init(enviroment: EVMEnviroment, journal_db: JournaledState) Self {
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
                .accountInfo = accountInfo,
                .balance = balance,
                .blockHash = blockHash,
                .checkpoint = checkpoint,
                .createAccount = createAccount,
                .code = code,
                .codeHash = codeHash,
                .commitCheckpoint = commitCheckpoint,
                .clearTransientStorage = clearTransientStorage,
                .clearWarmPreloads = clearWarmPreloads,
                .getEnviroment = getEnviroment,
                .incrementNonce = incrementNonce,
                .loadAccount = loadAccount,
                .preloadWarmAddress = preloadWarmAddress,
                .preloadWarmStorage = preloadWarmStorage,
                .log = log,
                .revertCheckpoint = revertCheckpoint,
                .selfDestruct = selfDestruct,
                .setCode = setCode,
                .sload = sload,
                .sstore = sstore,
                .tload = tload,
                .tstore = tstore,
                .transfer = transfer,
            },
        };
    }

    // Implementation of the interface.
    fn accountInfo(ctx: *anyopaque, address: Address) ?AccountInfo {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const account = self.journal.loadAccount(address) catch return null;

        return account.data.info;
    }

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

    fn checkpoint(ctx: *anyopaque) JournalCheckpoint {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.checkpoint();
    }

    fn createAccount(ctx: *anyopaque, caller: Address, target_address: Address, value: u256) JournaledState.CreateAccountErrors!JournalCheckpoint {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.createAccountCheckpoint(caller, target_address, value);
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

    fn clearTransientStorage(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.journal.clearTransientStorage();
    }

    fn clearWarmPreloads(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.journal.clearWarmPreloads();
    }

    fn getEnviroment(ctx: *anyopaque) EVMEnviroment {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.env;
    }

    fn incrementNonce(ctx: *anyopaque, from: Address) (Allocator.Error || error{Overflow})!u64 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const current = try self.journal.incrementAccountNonce(from) orelse return error.Overflow;

        return current - 1;
    }

    fn loadAccount(ctx: *anyopaque, address: Address) ?AccountResult {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const account = self.journal.loadAccount(address) catch return null;

        return .{
            .is_new_account = account.data.status.created != 0,
            .is_cold = account.cold,
        };
    }

    fn preloadWarmAddress(ctx: *anyopaque, address: Address) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.preloadWarmAddress(address);
    }

    fn preloadWarmStorage(ctx: *anyopaque, address: Address, index: u256) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.preloadWarmStorage(address, index);
    }

    fn log(ctx: *anyopaque, log_event: Log) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        try self.journal.log_storage.ensureUnusedCapacity(self.journal.allocator, 1);
        self.journal.log_storage.appendAssumeCapacity(log_event);
    }

    fn revertCheckpoint(ctx: *anyopaque, point: JournalCheckpoint) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.journal.revertCheckpoint(point);
    }

    fn setCode(ctx: *anyopaque, address: Address, bytecode: Bytecode) (Allocator.Error || error{NonExistentAccount})!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.setCode(address, bytecode);
    }

    fn selfDestruct(ctx: *anyopaque, from: Address, target: Address) !StateLoaded(SelfDestructResult) {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.selfDestruct(from, target);
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

    fn transfer(ctx: *anyopaque, from: Address, to: Address, value: u256) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.journal.transfer(from, to, value);
    }
};
