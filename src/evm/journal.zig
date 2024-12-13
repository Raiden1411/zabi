const std = @import("std");
const bytecode = @import("bytecode.zig");
const types = @import("zabi-types");
const spec = @import("specification.zig");

const Address = types.ethereum.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AutoHashMap = std.AutoHashMap;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const Bytecode = bytecode.Bytecode;
const EvmState = AutoHashMapUnmanaged(Address, Account);
const Hash = types.ethereum.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Log = types.log.Log;
const SpecId = spec.SpecId;
const TransientStorage = AutoHashMapUnmanaged(struct { Address, u256 }, u256);

pub const AccountStatus = packed struct(u6) {
    cold: u1,
    self_destructed: u1,
    touched: u1,
    created: u1,
    loaded: u1,
    non_existent: u1,
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
    storage: AutoHashMap(Address, StorageSlot),
    status: AccountStatus,
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
    database: void,
    transient_storage: TransientStorage,
    state: EvmState,
    /// The logs of this host.
    log_storage: ArrayListUnmanaged(Log),
    depth: usize,
    journal: ArrayListUnmanaged(ArrayListUnmanaged(JournalEntry)),
    spec: SpecId,
    warm_preloaded_address: AutoHashMap(Address, void),

    pub fn init(self: *JournaledState, allocator: Allocator, spec_id: SpecId) void {
        self.* = .{
            .allocator = allocator,
            .database = {},
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
        while (self.journal.popOrNull()) |*entries| {
            entries.deinit(self.allocator);
        }

        self.journal.deinit(self.allocator);
        self.state.deinit(self.allocator);
        self.log_storage.deinit(self.allocator);
        self.transient_storage.deinit(self.allocator);
        self.warm_preloaded_address.deinit(self.allocator);

        self.* = undefined;
    }

    pub fn updateSpecId(self: *JournaledState, spec_id: SpecId) void {
        self.spec = spec_id;
    }

    pub fn touchAccount(self: *JournaledState, address: Address) error{EmptyJournal}!void {
        if (self.state.get(address)) |*account| {
            if (account.status.touched == 0) {
                var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];

                account.status.touched = 1;
                try reference.append(self.allocator, .{ .account_touched = account });
            }
        }
    }

    pub fn setCodeAndHash(self: *JournaledState, address: Address, code: Bytecode, hash: Hash) !void {
        var account = self.state.get(address) orelse return error.NonExistentAccount;
        try self.touchAccount(address);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .code_changed = address });

        account.info.code = code;
        account.info.code_hash = hash;
    }

    pub fn setCode(self: *JournaledState, address: Address, code: Bytecode) !void {
        const bytes = code.getCodeBytes();

        var buffer: Hash = undefined;
        Keccak256.hash(bytes, &buffer, .{});

        return self.setCodeAndHash(address, code, buffer);
    }

    pub fn incrementAccountNonce(self: *JournaledState, address: Address) ?u64 {
        var account = self.state.get(address) orelse return null;

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .nonce_changed = address });

        account.info.nonce += 1;

        return account.info.nonce;
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

    pub fn transfer(self: *JournaledState, from: Address, to: Address, value: u256) !void {
        if (value == 0) {
            _ = self.loadAccount(to);
            return self.touchAccount(to);
        }

        _ = self.loadAccount(to);
        _ = self.loadAccount(from);

        {
            var from_acc = self.state.get(from).?;
            try self.touchAccount(from);

            const sub, const overflow = @subWithOverflow(from_acc.info.balance, value);

            if (overflow != 0)
                return error.OutOfFunds;

            from_acc.data.info.balance = sub;
        }

        {
            var to_acc = self.state.get(to).?;
            try self.touchAccount(to);

            const add, const overflow = @addWithOverflow(to_acc.info.balance, value);

            if (overflow != 0)
                return error.OverflowPayment;

            to_acc.info.balance = add;
        }

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

        var caller_acc = self.state.get(caller).?;

        if (caller_acc.info.balance < balance) {
            try self.revertCheckpoint(point);
            return error.OutOfFunds;
        }

        var target_acc = self.state.get(target_address).?;

        if (@as(u256, @bitCast(target_acc.info.code_hash)) != 0 or target_acc.info.nonce != 0) {
            try self.revertCheckpoint(point);
            return error.CreateCollision;
        }

        target_acc.status.created = 1;
        target_acc.info.code = null;

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .account_created = target_address });

        if (self.spec.enabled(.SPURIOUS_DRAGON)) {
            target_acc.info.nonce = 1;
        }

        try self.touchAccount(target_address);
        const add, const overflow = @addWithOverflow(target_acc.info.balance, balance);

        if (overflow != 0)
            return error.OverflowPayment;

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

    pub fn revertCheckpoint(self: *JournaledState, point: JournalCheckpoint) !void {
        self.commitCheckpoint();

        const length = self.journal.items.len - point.journal_checkpoint;
        for (0..length) |_| {
            var reference: ArrayListUnmanaged(JournalEntry) = self.journal.pop();
            defer reference.deinit(self.allocator);

            try self.revertJournal(&reference);
        }

        self.journal.shrinkAndFree(self.allocator, length);
        self.log_storage.shrinkAndFree(self.allocator, self.log_storage.items.len - point.logs_checkpoint);
    }

    pub fn revertJournal(self: *JournaledState, journal_entry: *ArrayListUnmanaged(JournalEntry)) !void {
        while (journal_entry.popOrNull()) |entry| {
            switch (entry) {
                .account_warmed => |address| {
                    var account = self.state.get(address).?;
                    account.status.cold = 0;
                },
                .account_touched => |address| {
                    var account = self.state.get(address).?;
                    account.status.touched = 0;
                },
                .account_destroyed => |info| {
                    var account = self.state.get(info.address).?;

                    if (info.was_destroyed) {
                        account.status.self_destructed = 1;
                    } else {
                        account.status.self_destructed = 0;
                    }

                    account.info.balance += info.had_balance;

                    if (info.address != info.target) {
                        var target_acc = self.state.get(info.target).?;
                        target_acc.info.balance -= info.had_balance;
                    }
                },
                .balance_transfer => |info| {
                    var account_from = self.state.get(info.from).?;
                    var account_to = self.state.get(info.to).?;

                    account_from.info.balance += info.balance;
                    account_to.info.balance -= info.balance;
                },
                .code_changed => |address| {
                    var account = self.state.get(address).?;
                    account.info.code = null;
                    account.info.code_hash = [_]u8{0} ** 32;
                },
                .nonce_changed => |address| {
                    var account = self.state.get(address).?;
                    account.info.nonce -= 1;
                },
                .storage_warmed => |info| {
                    var account = self.state.get(info.address).?;
                    var storage = account.storage.get(info.key).?;
                    storage.is_cold = true;
                },
                .storage_changed => |info| {
                    var account = self.state.get(info.address).?;
                    var storage = account.storage.get(info.key).?;
                    storage.present_value = info.had_value;
                },
                .transient_storage_changed => |info| {
                    if (info.had_value == 0) {
                        _ = self.transient_storage.remove(info.key);
                    } else {
                        try self.transient_storage.put(self.allocator, info.key, info.had_value);
                    }
                },
            }
        }
    }

    pub fn loadAccount(self: *JournaledState, address: Address) StateLoaded(Account) {
        const state = self.load(address);

        if (state.cold) {
            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = address });
        }

        return state;
    }

    pub fn loadCode(self: *JournaledState, address: Address) StateLoaded(Account) {
        var state = self.load(address);

        if (state.cold) {
            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = address });
        }

        if (state.data.info.code_hash == [_]u8{0} ** 32) {
            state.data.info.code = null;
        } else {
            const code = self.database.getCodeByHash(state.data.info.code_hash);
            state.data.info.code = code;
        }

        return state;
    }

    fn load(self: *JournaledState, address: Address) StateLoaded(Account) {
        const account = self.state.get(address);

        if (account) |*acc| {
            const cold = blk: {
                if (acc.status.cold != 0) {
                    acc.status.cold = 0;
                    break :blk true;
                }

                break :blk false;
            };

            return StateLoaded(Account){
                .cold = cold,
                .data = acc.*,
            };
        }

        const db_account: Account = self.database.basic(address) orelse undefined;
        const cold = !self.warm_preloaded_address.contains(address);

        return StateLoaded(Account){
            .cold = cold,
            .data = db_account,
        };
    }
};
