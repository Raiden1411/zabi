const bytecode = @import("bytecode.zig");
const constants = @import("constants.zig");
const std = @import("std");
const database = @import("database.zig");
const host = @import("host.zig");
const spec = @import("specification.zig");
const types = @import("zabi-types");

const Address = types.ethereum.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AutoHashMap = std.AutoHashMap;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const Bytecode = bytecode.Bytecode;
const Database = database.Database;
const Hash = types.ethereum.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Log = types.log.Log;
const SpecId = spec.SpecId;
const SelfDestructResult = host.SelfDestructResult;
const SStoreResult = host.SStoreResult;

pub const AccountStatus = packed struct(u6) {
    cold: u1 = 0,
    self_destructed: u1 = 0,
    touched: u1 = 0,
    created: u1 = 0,
    loaded: u1 = 0,
    non_existent: u1 = 0,
};

pub const StorageSlot = struct {
    original_value: u256,
    present_value: u256,
    is_cold: bool,
};

pub const AccountInfo = struct {
    balance: u256,
    nonce: u64,
    code_hash: Hash,
    code: ?Bytecode,
};

pub const JournalCheckpoint = struct {
    journal_checkpoint: usize,
    logs_checkpoint: usize,
};

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

pub fn StateLoaded(comptime T: type) type {
    return struct {
        data: T,
        cold: bool,
    };
}

pub const JournalEntry = union(enum) {
    account_warmed: struct { address: Address },
    account_destroyed: struct {
        address: Address,
        target: Address,
        was_destroyed: bool,
        had_balance: u256,
    },
    account_touched: struct { address: Address },
    balance_transfer: struct {
        from: Address,
        to: Address,
        balance: u256,
    },
    nonce_changed: struct {
        address: Address,
    },
    account_created: struct { address: Address },
    storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    },
    storage_warmed: struct {
        address: Address,
        key: u256,
    },
    transient_storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    },
    code_changed: struct { address: Address },
};

pub const JournaledState = struct {
    allocator: Allocator,
    database: Database,
    transient_storage: AutoHashMapUnmanaged(struct { Address, u256 }, u256),
    state: AutoHashMapUnmanaged(Address, Account),
    log_storage: ArrayListUnmanaged(Log),
    depth: usize,
    journal: ArrayListUnmanaged(ArrayListUnmanaged(JournalEntry)),
    spec: SpecId,
    warm_preloaded_address: AutoHashMapUnmanaged(Address, void),

    pub fn init(
        self: *JournaledState,
        allocator: Allocator,
        spec_id: SpecId,
        db: Database,
    ) void {
        self.* = .{
            .allocator = allocator,
            .database = db,
            .transient_storage = .empty,
            .state = .empty,
            .log_storage = .empty,
            .depth = 0,
            .journal = .empty,
            .spec = spec_id,
            .warm_preloaded_address = .empty,
        };
    }

    pub fn deinit(self: *JournaledState) void {
        for (0..self.journal.items.len) |index|
            (&self.journal.items[index]).deinit(self.allocator);

        var iter = self.state.valueIterator();
        while (iter.next()) |entry|
            entry.storage.deinit();

        self.journal.deinit(self.allocator);
        self.state.deinit(self.allocator);
        self.log_storage.deinit(self.allocator);
        self.transient_storage.deinit(self.allocator);
        self.warm_preloaded_address.deinit(self.allocator);

        self.* = undefined;
    }

    pub fn updateSpecId(
        self: *JournaledState,
        spec_id: SpecId,
    ) void {
        self.spec = spec_id;
    }

    pub fn touchAccount(
        self: *JournaledState,
        address: Address,
    ) !void {
        if (self.state.getPtr(address)) |account| {
            if (account.status.touched == 0) {
                var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
                try reference.append(self.allocator, .{ .account_touched = .{ .address = address } });

                account.status.touched = 1;
            }
        }
    }

    pub fn setCodeAndHash(
        self: *JournaledState,
        address: Address,
        code: Bytecode,
        hash: Hash,
    ) !void {
        var account = self.state.getPtr(address) orelse return error.NonExistentAccount;
        try self.touchAccount(address);

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .code_changed = .{ .address = address } });

        account.info.code = code;
        account.info.code_hash = hash;
    }

    pub fn setCode(
        self: *JournaledState,
        address: Address,
        code: Bytecode,
    ) !void {
        const bytes = code.getCodeBytes();

        var buffer: Hash = undefined;
        Keccak256.hash(bytes, &buffer, .{});

        return self.setCodeAndHash(address, code, buffer);
    }

    pub fn incrementAccountNonce(
        self: *JournaledState,
        address: Address,
    ) !?u64 {
        var account = self.state.getPtr(address) orelse return null;

        const add, const overflow = @addWithOverflow(account.info.nonce, 1);

        if (overflow != 0)
            return null;

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .nonce_changed = .{ .address = address } });

        account.info.nonce = add;

        return add;
    }

    pub fn checkpoint(self: *JournaledState) !JournalCheckpoint {
        const point: JournalCheckpoint = .{
            .journal_checkpoint = self.journal.items.len,
            .logs_checkpoint = self.log_storage.items.len,
        };

        self.depth += 1;
        try self.journal.append(self.allocator, .empty);

        return point;
    }

    pub fn commitCheckpoint(self: *JournaledState) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    pub fn transfer(
        self: *JournaledState,
        from: Address,
        to: Address,
        value: u256,
    ) !void {
        if (value == 0) {
            _ = try self.loadAccount(to);
            return self.touchAccount(to);
        }

        _ = try self.loadAccount(to);
        _ = try self.loadAccount(from);

        {
            var from_acc = self.state.getPtr(from) orelse return error.NonExistentAccount;
            try self.touchAccount(from);

            const sub, const overflow = @subWithOverflow(from_acc.info.balance, value);

            if (overflow != 0)
                return error.OutOfFunds;

            from_acc.info.balance = sub;
        }

        {
            var to_acc = self.state.getPtr(to) orelse return error.NonExistentAccount;
            try self.touchAccount(to);

            const add, const overflow = @addWithOverflow(to_acc.info.balance, value);

            if (overflow != 0)
                return error.OverflowPayment;

            to_acc.info.balance = add;
        }

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{
            .balance_transfer = .{
                .from = from,
                .to = to,
                .balance = value,
            },
        });
    }

    pub fn createAccountCheckpoint(
        self: *JournaledState,
        caller: Address,
        target_address: Address,
        balance: u256,
    ) !JournalCheckpoint {
        const point = try self.checkpoint();

        var caller_acc = self.state.getPtr(caller) orelse return error.NonExistentAccount;

        if (caller_acc.info.balance < balance) {
            try self.revertCheckpoint(point);
            return error.OutOfFunds;
        }

        var target_acc = self.state.getPtr(target_address) orelse return error.NonExistentAccount;

        if (@as(u256, @bitCast(target_acc.info.code_hash)) != @as(u256, @bitCast(constants.EMPTY_HASH)) or
            target_acc.info.nonce != 0)
        {
            try self.revertCheckpoint(point);
            return error.CreateCollision;
        }

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .account_created = .{ .address = target_address } });

        target_acc.status.created = 1;
        target_acc.info.code = null;

        if (self.spec.enabled(.SPURIOUS_DRAGON))
            target_acc.info.nonce = 1;

        try self.touchAccount(target_address);
        const add, const overflow = @addWithOverflow(target_acc.info.balance, balance);

        if (overflow != 0)
            return error.BalanceOverflow;

        target_acc.info.balance = add;
        caller_acc.info.balance -= balance;

        try reference.append(self.allocator, .{
            .balance_transfer = .{
                .from = caller,
                .to = target_address,
                .balance = balance,
            },
        });

        return point;
    }

    pub fn revertCheckpoint(
        self: *JournaledState,
        point: JournalCheckpoint,
    ) !void {
        self.commitCheckpoint();

        const length = self.journal.items.len - point.journal_checkpoint;

        for (0..length) |_| {
            var reference: ArrayListUnmanaged(JournalEntry) = self.journal.pop();
            defer reference.deinit(self.allocator);

            try self.revertJournal(&reference);
        }

        self.journal.shrinkAndFree(self.allocator, point.journal_checkpoint);
        self.log_storage.shrinkAndFree(self.allocator, point.logs_checkpoint);
    }

    pub fn revertJournal(
        self: *JournaledState,
        journal_entry: *ArrayListUnmanaged(JournalEntry),
    ) !void {
        while (journal_entry.popOrNull()) |entry| {
            switch (entry) {
                .account_warmed => |address| {
                    var account = self.state.getPtr(address.address) orelse return error.NonExistentAccount;
                    account.status.cold = 1;
                },
                .account_touched => |address| {
                    var account = self.state.getPtr(address.address) orelse return error.NonExistentAccount;
                    account.status.touched = 0;
                },
                .account_created => |address| {
                    var account = self.state.getPtr(address.address) orelse return error.NonExistentAccount;
                    account.status.created = 0;
                    account.info.nonce = 0;

                    var storage_iter = account.storage.valueIterator();

                    while (storage_iter.next()) |entry_value|
                        entry_value.is_cold = true;
                },
                .account_destroyed => |info| {
                    var account = self.state.getPtr(info.address) orelse return error.NonExistentAccount;

                    if (info.was_destroyed) {
                        account.status.self_destructed = 1;
                    } else {
                        account.status.self_destructed = 0;
                    }

                    account.info.balance += info.had_balance;

                    if (@as(u160, @bitCast(info.address)) != @as(u160, @bitCast(info.target))) {
                        var target_acc = self.state.getPtr(info.target) orelse return error.NonExistentAccount;

                        std.debug.assert(target_acc.info.balance >= info.had_balance);
                        target_acc.info.balance -= info.had_balance;
                    }
                },
                .balance_transfer => |info| {
                    var account_from = self.state.getPtr(info.from) orelse return error.NonExistentAccount;
                    var account_to = self.state.getPtr(info.to) orelse return error.NonExistentAccount;

                    account_from.info.balance += info.balance;

                    std.debug.assert(account_from.info.balance >= info.balance);
                    account_to.info.balance -= info.balance;
                },
                .code_changed => |address| {
                    var account = self.state.getPtr(address.address) orelse return error.NonExistentAccount;

                    account.info.code = null;
                    account.info.code_hash = constants.EMPTY_HASH;
                },
                .nonce_changed => |address| {
                    var account = self.state.getPtr(address.address) orelse return error.NonExistentAccount;

                    std.debug.assert(account.info.nonce > 0);
                    account.info.nonce -= 1;
                },
                .storage_warmed => |info| {
                    var account = self.state.getPtr(info.address) orelse return error.NonExistentAccount;
                    var storage = account.storage.getPtr(info.key) orelse return error.InvalidStorageKey;
                    storage.is_cold = true;
                },
                .storage_changed => |info| {
                    var account = self.state.getPtr(info.address) orelse return error.NonExistentAccount;
                    var storage = account.storage.get(info.key) orelse return error.InvalidStorageKey;
                    storage.present_value = info.had_value;
                },
                .transient_storage_changed => |info| {
                    if (info.had_value == 0) {
                        _ = self.transient_storage.remove(.{ info.address, info.key });
                    } else {
                        try self.transient_storage.put(self.allocator, .{ info.address, info.key }, info.had_value);
                    }
                },
            }
        }
    }

    pub fn loadAccount(
        self: *JournaledState,
        address: Address,
    ) !StateLoaded(Account) {
        const state = try self.load(address);

        if (state.cold) {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = .{ .address = address } });
        }

        return state;
    }

    pub fn loadCode(
        self: *JournaledState,
        address: Address,
    ) !StateLoaded(Account) {
        var state = try self.load(address);

        if (state.cold) {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = .{ .address = address } });
        }

        if (@as(u256, @bitCast(state.data.info.code_hash)) == @as(u256, @bitCast(constants.EMPTY_HASH))) {
            state.data.info.code = .{ .raw = @constCast("") };
        } else {
            const code = try self.database.codeByHash(state.data.info.code_hash);
            state.data.info.code = code;
        }

        return state;
    }

    fn load(
        self: *JournaledState,
        address: Address,
    ) !StateLoaded(Account) {
        const account = self.state.getPtr(address);

        if (account) |acc| {
            const cold = blk: {
                if (acc.status.cold != 0) {
                    acc.status.cold = 0;
                    break :blk true;
                }

                break :blk false;
            };

            return .{
                .cold = cold,
                .data = acc.*,
            };
        }

        const db_account: Account = account: {
            const account_info = try self.database.basic(address);

            if (account_info) |info|
                break :account .{
                    .info = info,
                    .storage = .init(self.allocator),
                    .status = .{ .loaded = 1 },
                };

            break :account .{
                .info = .{
                    .code_hash = constants.EMPTY_HASH,
                    .nonce = 0,
                    .code = .{ .raw = @constCast("") },
                    .balance = 0,
                },
                .storage = .init(self.allocator),
                .status = .{ .non_existent = 1 },
            };
        };

        const cold = !self.warm_preloaded_address.contains(address);
        try self.state.put(self.allocator, address, db_account);

        return .{
            .cold = cold,
            .data = db_account,
        };
    }

    pub fn selfDestruct(
        self: *JournaledState,
        address: Address,
        target: Address,
    ) !StateLoaded(SelfDestructResult) {
        const account = try self.loadAccount(address);
        const empty = account.data.isEmpty(self.spec);

        if (@as(u160, @bitCast(address)) != @as(u160, @bitCast(target))) {
            var target_account = self.state.getPtr(target) orelse return error.NonExistentAccount;

            try self.touchAccount(target);

            target_account.info.balance += account.data.info.balance;
        }

        var acc = self.state.getPtr(address) orelse return error.NonExistentAccount;
        const balance = acc.info.balance;
        const was_destroyed = acc.status.self_destructed;

        const entry: ?JournalEntry = entry: {
            if (acc.status.created != 0 and !self.spec.enabled(.CANCUN)) {
                acc.status.self_destructed = 1;
                acc.info.balance = 0;

                break :entry .{
                    .account_destroyed = .{
                        .target = target,
                        .address = address,
                        .had_balance = balance,
                        .was_destroyed = was_destroyed != 0,
                    },
                };
            }

            if (@as(u160, @bitCast(address)) != @as(u160, @bitCast(target))) {
                acc.info.balance = 0;

                break :entry .{
                    .balance_transfer = .{
                        .from = address,
                        .to = target,
                        .balance = balance,
                    },
                };
            }

            break :entry null;
        };

        if (entry) |journal_entry| {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, journal_entry);
        }

        return .{
            .cold = account.cold,
            .data = .{
                .had_value = balance != 0,
                .is_cold = account.cold,
                .target_exists = !empty,
                .previously_destroyed = was_destroyed != 0,
            },
        };
    }

    pub fn sload(
        self: *JournaledState,
        address: Address,
        key: u256,
    ) !StateLoaded(u256) {
        var account = self.state.getPtr(address) orelse return error.NonExistentAccount;

        const state: StateLoaded(u256) = state: {
            if (account.storage.getPtr(key)) |value| {
                const cold = blk: {
                    if (value.is_cold) {
                        value.is_cold = false;
                        break :blk true;
                    }

                    break :blk false;
                };

                break :state .{
                    .cold = cold,
                    .data = value.present_value,
                };
            }
            const value = if (account.status.created != 0) 0 else try self.database.storage(address, key);

            try account.storage.put(key, .{
                .is_cold = true,
                .present_value = value,
                .original_value = value,
            });

            break :state .{
                .cold = true,
                .data = value,
            };
        };

        if (state.cold) {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{
                .storage_warmed = .{
                    .address = address,
                    .key = key,
                },
            });
        }

        return state;
    }

    pub fn sstore(
        self: *JournaledState,
        address: Address,
        key: u256,
        new: u256,
    ) !StateLoaded(SStoreResult) {
        const present = try self.sload(address, key);

        var account = self.state.getPtr(address) orelse return error.NonExistentAccount;
        var slot = account.storage.getPtr(key) orelse return error.InvalidStorageKey;

        if (present.data == new) {
            return .{
                .data = .{
                    .original_value = slot.original_value,
                    .present_value = present.data,
                    .new_value = new,
                    .is_cold = present.cold,
                },
                .cold = present.cold,
            };
        }

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{
            .storage_changed = .{
                .address = address,
                .key = key,
                .had_value = present.data,
            },
        });

        slot.present_value = new;
        return .{
            .data = .{
                .original_value = slot.original_value,
                .present_value = present.data,
                .new_value = new,
                .is_cold = present.cold,
            },
            .cold = present.cold,
        };
    }

    pub fn tload(
        self: *JournaledState,
        address: Address,
        key: u256,
    ) u256 {
        return self.transient_storage.get(.{ address, key }) orelse 0;
    }

    pub fn tstore(
        self: *JournaledState,
        address: Address,
        key: u256,
        value: u256,
    ) !void {
        const had_value: ?u256 = blk: {
            if (value == 0) {
                const val = self.transient_storage.get(.{ address, key });

                if (val != null)
                    _ = self.transient_storage.remove(.{ address, key });

                break :blk val;
            } else {
                const previous = try self.transient_storage.fetchPut(self.allocator, .{ address, key }, value);

                if (previous) |previous_entry|
                    break :blk previous_entry.value;

                break :blk null;
            }
        };

        if (had_value) |val| {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{
                .transient_storage_changed = .{
                    .address = address,
                    .key = key,
                    .had_value = val,
                },
            });
        }
    }

    pub fn log(self: *JournaledState, event: Log) !void {
        return self.log_storage.append(self.allocator, event);
    }
};
