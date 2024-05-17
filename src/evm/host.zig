const std = @import("std");
const log_types = @import("../types/log.zig");
const types = @import("../types/ethereum.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Hash = types.Hash;
const Log = log_types.Log;
const Storage = std.AutoHashMap(u256, u256);

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
        code: *const fn (self: *anyopaque, address: Address) ?struct { []u8, bool },
        /// Gets the code hash of an `address` and if that address is cold.
        codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool },
        /// Gets the host's `Enviroment`.
        getEnviroment: *const fn (self: *anyopaque) void,
        /// Loads an account.
        loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult,
        /// Emits a log owned by an address with the log data.
        log: *const fn (self: *anyopaque, log: Log) anyerror!void,
        /// Gets the storage value of an `address` at a given `index` and if that address is cold.
        sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!struct { u256, bool },
        /// Sets a storage value of an `address` at a given `index` and if that address is cold.
        sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!SStoreResult,
        /// Gets the transient storage value of an `address` at a given `index`.
        tload: *const fn (self: *anyopaque, address: Address, index: u256) ?u256,
        /// Sets the transient storage value of an `address` at a given `index`.
        tstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!void,
        /// Sets the address to be deleted and any funds it might have to `target` address.
        selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!SelfDestructResult,
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
    pub inline fn code(self: SelfHost, address: Address) ?struct { []u8, bool } {
        return self.vtable.code(self.ptr, address);
    }
    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn codeHash(self: SelfHost, address: Address) ?struct { Hash, bool } {
        return self.vtable.codeHash(self.ptr, address);
    }
    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn getEnviroment(self: SelfHost) void {
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
    /// Sets the address to be deleted and any funds it might have to `target` address.
    pub inline fn selfDestruct(self: SelfHost, address: Address, target: Address) anyerror!SelfDestructResult {
        return self.vtable.selfDestruct(self.ptr, address, target);
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

/// Mainly serves as a basic implementation of an evm host.
pub const PlainHost = struct {
    const Self = @This();

    /// The EVM enviroment
    env: void,
    /// The storage of this host.
    storage: Storage,
    /// The transient storage of this host.
    transient_storage: Storage,
    /// The logs of this host.
    log: ArrayList(Log),

    pub fn init(self: *Self, allocator: Allocator) void {
        const storage = Storage.init(allocator);
        const transient_storage = Storage.init(allocator);
        const logs = ArrayList(Log).init(allocator);

        self.* = .{
            .env = {},
            .storage = storage,
            .transient_storage = transient_storage,
            .log = logs,
        };
    }

    pub fn deinit(self: *Self) void {
        self.log.deinit();
        self.storage.deinit();
        self.transient_storage.deinit();
    }

    pub fn host(self: *Self) Host {
        return .{
            .ptr = self,
            .vtable = &.{
                .balance = balance,
                .blockHash = blockHash,
                .code = code,
                .codeHash = codeHash,
                .loadAccount = loadAccount,
                .sload = sload,
            },
        };
    }

    fn balance(ctx: *anyopaque, address: Address) ?struct { u256, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = address;

        return .{ 0, false };
    }

    fn blockHash(ctx: *anyopaque, block_number: u256) ?AccountResult {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = block_number;

        return [_]u8{0} ** 32;
    }

    fn code(ctx: *anyopaque, address: Address) ?struct { []u8, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = address;

        return .{ &[_]u8{}, false };
    }

    fn codeHash(ctx: *anyopaque, address: Address) ?struct { Hash, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = address;

        return .{ [_]u8{0} ** 32, false };
    }

    fn loadAccount(ctx: *anyopaque, address: Address) ?AccountResult {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = address;
        return AccountResult{ .is_new_account = false, .is_cold = false };
    }

    fn getEnviroment(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return self.env;
    }

    fn sload(ctx: *anyopaque, address: Address, index: u256) !struct { u256, bool } {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = address;

        const entry = self.storage.get(index);

        const result: struct { u256, bool } = blk: {
            if (entry) |value|
                break :blk .{ value, false };

            try self.storage.put(index, 0);
            break :blk .{ 0, true };
        };

        return result;
    }
};
