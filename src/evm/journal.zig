const bytecode = @import("bytecode.zig");
const constants = @import("zabi-utils").constants;
const std = @import("std");
const database = @import("database.zig");
const host = @import("host.zig");
const spec = @import("specification.zig");
const types = @import("zabi-types");

const Account = host.Account;
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

/// A journal of state changes internal to the EVM.
///
/// On each additional call, the depth of the journaled state is increased and a new journal is added.
/// The journal contains every state change that happens within that call, making it possible to revert changes made in a specific call.
pub const JournaledState = struct {
    /// Set of basic error when interacting with this journal.
    pub const BasicErrors = Allocator.Error || error{UnexpectedError};

    /// Set of errors when performing revert actions.
    pub const RevertCheckpointError = Allocator.Error || error{ NonExistentAccount, InvalidStorageKey };

    /// Set of errors when performing load or storage store.
    pub const LoadErrors = RevertCheckpointError || error{UnexpectedError};

    /// Set of errors when performing a value transfer.
    pub const TransferErrors = BasicErrors || error{ NonExistentAccount, OutOfFunds, OverflowPayment };

    /// Set of possible basic database errors.
    pub const CreateAccountErrors = TransferErrors || LoadErrors || error{
        CreateCollision,
        BalanceOverflow,
    };

    /// The allocator used by the journal.
    allocator: Allocator,
    /// The database used to grab information in case the journal doesn't have it.
    database: Database,
    /// EIP-1153 transient storage
    transient_storage: AutoHashMapUnmanaged(struct { Address, u256 }, u256),
    /// The current journal state.
    state: AutoHashMapUnmanaged(Address, Account),
    /// List of emitted logs
    log_storage: ArrayListUnmanaged(Log),
    /// The current call stack depth.
    depth: usize,
    /// The journal of state changes. One for each call.
    journal: ArrayListUnmanaged(ArrayListUnmanaged(JournalEntry)),
    /// The spec id for the journal. Changes the behaviour depending on the current spec.
    spec: SpecId,
    /// Warm loaded addresses are used to check if loaded address
    /// should be considered cold or warm loaded when the account
    /// is first accessed.
    warm_preloaded_address: AutoHashMapUnmanaged(Address, void),

    /// Sets up the initial state for this journal.
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

    /// Clears any allocated memory.
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

    /// Creates a new checkpoint and increase the call depth.
    pub fn checkpoint(self: *JournaledState) Allocator.Error!JournalCheckpoint {
        const point: JournalCheckpoint = .{
            .journal_checkpoint = self.journal.items.len,
            .logs_checkpoint = self.log_storage.items.len,
        };

        self.depth += 1;
        try self.journal.append(self.allocator, .empty);

        return point;
    }

    /// Commits the checkpoint
    pub fn commitCheckpoint(self: *JournaledState) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    /// Creates an account with a checkpoint so that in case the account already exists
    /// or the account is out of funds it's able to revert any journal entries.
    ///
    /// A `account_created` entry is created along with a `balance_transfer` and `account_touched`.
    pub fn createAccountCheckpoint(
        self: *JournaledState,
        caller: Address,
        target_address: Address,
        balance: u256,
    ) CreateAccountErrors!JournalCheckpoint {
        const point = try self.checkpoint();

        var caller_acc = self.state.getPtr(caller) orelse return error.NonExistentAccount;

        if (caller_acc.info.balance < balance) {
            try self.revertCheckpoint(point);
            return error.OutOfFunds;
        }

        var target_acc = self.state.getPtr(target_address) orelse return error.NonExistentAccount;

        if (@as(u256, @bitCast(target_acc.info.code_hash)) != @as(u256, @bitCast(constants.EMPTY_HASH)) or target_acc.info.nonce != 0) {
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

    /// Increments the nonce of an account.
    ///
    /// A `nonce_changed` entry will be emitted.
    pub fn incrementAccountNonce(
        self: *JournaledState,
        address: Address,
    ) Allocator.Error!?u64 {
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

    /// Loads an account from the state.
    ///
    /// A `account_warmed` entry is added to the journal if the load was cold.
    pub fn loadAccount(
        self: *JournaledState,
        address: Address,
    ) BasicErrors!StateLoaded(Account) {
        const state = try self.load(address);

        if (state.cold) {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = .{ .address = address } });
        }

        return state;
    }

    /// Loads the bytecode from an account
    ///
    /// Returns empty bytecode if the code hash is equal to the Keccak256 hash of an empty string.
    /// A `account_warmed` entry is added to the journal if the load was cold.
    pub fn loadCode(
        self: *JournaledState,
        address: Address,
    ) BasicErrors!StateLoaded(Account) {
        var state = try self.load(address);

        if (state.cold) {
            std.debug.assert(self.journal.items.len > 0);

            var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
            try reference.append(self.allocator, .{ .account_warmed = .{ .address = address } });
        }

        if (@as(u256, @bitCast(state.data.info.code_hash)) == @as(u256, @bitCast(constants.EMPTY_HASH))) {
            state.data.info.code = .{ .raw = @constCast("") };
        } else {
            const code = self.database.codeByHash(state.data.info.code_hash) catch return error.UnexpectedError;
            state.data.info.code = code;
        }

        return state;
    }

    /// Appends the log to the log event list.
    pub fn log(self: *JournaledState, event: Log) Allocator.Error!void {
        return self.log_storage.append(self.allocator, event);
    }

    /// Reverts a checkpoint and uncommit's all of the journal entries.
    pub fn revertCheckpoint(
        self: *JournaledState,
        point: JournalCheckpoint,
    ) RevertCheckpointError!void {
        self.commitCheckpoint();

        const length = self.journal.items.len - point.journal_checkpoint;

        for (0..length) |_| {
            var reference: ArrayListUnmanaged(JournalEntry) = self.journal.pop() orelse unreachable;
            defer reference.deinit(self.allocator);

            try self.revertJournal(&reference);
        }

        self.journal.shrinkAndFree(self.allocator, point.journal_checkpoint);
        self.log_storage.shrinkAndFree(self.allocator, point.logs_checkpoint);
    }

    /// Reverts a list of journal entries. Depending on the type of entry different actions will be taken.
    pub fn revertJournal(
        self: *JournaledState,
        journal_entry: *ArrayListUnmanaged(JournalEntry),
    ) RevertCheckpointError!void {
        while (journal_entry.pop()) |entry| {
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

    /// Performs the self destruct action
    ///
    /// Transfer the balance to the target address.
    ///
    /// Balance will be lost if address and target are the same BUT when current spec enables Cancun,
    /// this happens only when the account associated to address is created in the same transaction.
    pub fn selfDestruct(
        self: *JournaledState,
        address: Address,
        target: Address,
    ) LoadErrors!StateLoaded(SelfDestructResult) {
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

    /// Sets the bytecode for an account and generates the associated Keccak256 hash for that bytecode.
    ///
    /// A `code_changed` entry will be emitted.
    pub fn setCode(
        self: *JournaledState,
        address: Address,
        code: Bytecode,
    ) (Allocator.Error || error{NonExistentAccount})!void {
        const bytes = code.getCodeBytes();

        var buffer: Hash = undefined;
        Keccak256.hash(bytes, &buffer, .{});

        return self.setCodeAndHash(address, code, buffer);
    }

    /// Sets the bytecode and the Keccak256 hash for an associated account.
    ///
    /// A `code_changed` entry will be emitted.
    pub fn setCodeAndHash(
        self: *JournaledState,
        address: Address,
        code: Bytecode,
        hash: Hash,
    ) (Allocator.Error || error{NonExistentAccount})!void {
        var account = self.state.getPtr(address) orelse return error.NonExistentAccount;
        try self.touchAccount(address);

        std.debug.assert(self.journal.items.len > 0);

        var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
        try reference.append(self.allocator, .{ .code_changed = .{ .address = address } });

        account.info.code = code;
        account.info.code_hash = hash;
    }

    /// Loads a value from the account storage based on the provided key.
    ///
    /// Returns if the load was cold or not.
    pub fn sload(
        self: *JournaledState,
        address: Address,
        key: u256,
    ) LoadErrors!StateLoaded(u256) {
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
            const value = if (account.status.created != 0)
                0
            else
                self.database.storage(address, key) catch return error.UnexpectedError;

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

    /// Stores a value to the account's storage based on the provided index.
    ///
    /// Returns if store was cold or not.
    pub fn sstore(
        self: *JournaledState,
        address: Address,
        key: u256,
        new: u256,
    ) LoadErrors!StateLoaded(SStoreResult) {
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

    /// Read transient storage tied to the account.
    ///
    /// EIP-1153: Transient storage opcodes
    pub fn tload(
        self: *JournaledState,
        address: Address,
        key: u256,
    ) u256 {
        return self.transient_storage.get(.{ address, key }) orelse 0;
    }

    /// Sets an account as touched.
    pub fn touchAccount(
        self: *JournaledState,
        address: Address,
    ) Allocator.Error!void {
        if (self.state.getPtr(address)) |account| {
            if (account.status.touched == 0) {
                var reference: *ArrayListUnmanaged(JournalEntry) = &self.journal.items[self.journal.items.len - 1];
                try reference.append(self.allocator, .{ .account_touched = .{ .address = address } });

                account.status.touched = 1;
            }
        }
    }
    /// Transfers the value from one account to other another account.
    ///
    /// A `balance_transfer` entry is created.
    pub fn transfer(
        self: *JournaledState,
        from: Address,
        to: Address,
        value: u256,
    ) TransferErrors!void {
        if (value == 0) {
            _ = try self.loadAccount(to);
            return self.touchAccount(to);
        }

        _ = try self.loadAccount(to);
        _ = try self.loadAccount(from);

        // Substract value from account
        var from_acc = self.state.getPtr(from) orelse return error.NonExistentAccount;
        try self.touchAccount(from);

        const sub, const overflow_sub = @subWithOverflow(from_acc.info.balance, value);

        if (overflow_sub != 0)
            return error.OutOfFunds;

        from_acc.info.balance = sub;

        // Add value to the account
        var to_acc = self.state.getPtr(to) orelse return error.NonExistentAccount;
        try self.touchAccount(to);

        const add, const overflow_add = @addWithOverflow(to_acc.info.balance, value);

        if (overflow_add != 0)
            return error.OverflowPayment;

        to_acc.info.balance = add;

        // Append journal_entry to the list.
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

    /// Store transient storage tied to the account.
    ///
    /// If values is different add entry to the journal
    /// so that old state can be reverted if that action is needed.
    ///
    /// EIP-1153: Transient storage opcodes
    pub fn tstore(
        self: *JournaledState,
        address: Address,
        key: u256,
        value: u256,
    ) Allocator.Error!void {
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

    /// Updates the spec id for this journal.
    pub fn updateSpecId(
        self: *JournaledState,
        spec_id: SpecId,
    ) void {
        self.spec = spec_id;
    }

    /// Performs a load from the state and represent if the account is cold or not
    ///
    /// Loads directly from the database if the account doesn't exists in the state.
    fn load(
        self: *JournaledState,
        address: Address,
    ) BasicErrors!StateLoaded(Account) {
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
            const account_info = self.database.basic(address) catch return error.UnexpectedError;

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
};

/// Journaling checkpoint in case the journal needs to revert.
pub const JournalCheckpoint = struct {
    journal_checkpoint: usize,
    logs_checkpoint: usize,
};

/// Representation of an journal entry.
pub const JournalEntry = union(enum) {
    /// Entry used to mark an account that is warm inside EVM in regards to EIP-2929 AccessList.
    account_warmed: struct {
        address: Address,
    },
    /// Entry for marking an account to be destroyed and journal balance to be reverted
    account_destroyed: struct {
        address: Address,
        target: Address,
        was_destroyed: bool,
        had_balance: u256,
    },
    /// Loading account does not mean that account will need to be added to MerkleTree (touched).
    /// Only when account is called (to execute contract or transfer balance) only then account is made touched.
    account_touched: struct {
        address: Address,
    },
    /// Entry for transfering balance between two accounts
    balance_transfer: struct {
        from: Address,
        to: Address,
        balance: u256,
    },
    /// Entry for increment the nonce of an account
    nonce_changed: struct {
        address: Address,
    },
    /// Entry for creating an account
    account_created: struct {
        address: Address,
    },
    /// Entry used to track storage changes
    storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    },
    /// Entry used to track storage warming introduced by EIP-2929.
    storage_warmed: struct {
        address: Address,
        key: u256,
    },
    /// Entry used to track an EIP-1153 transient storage change.
    transient_storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    },
    /// Entry used to change the bytecode associated with an account.
    code_changed: struct {
        address: Address,
    },
};

/// Data structure returned when performing loads.
pub fn StateLoaded(comptime T: type) type {
    return struct {
        data: T,
        cold: bool,
    };
}
