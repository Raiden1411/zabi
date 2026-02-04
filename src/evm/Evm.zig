const actions = @import("actions.zig");
const analysis = @import("analysis.zig");
const bytecode = @import("bytecode.zig");
const contract_type = @import("contract.zig");
const encoding = @import("zabi-encoding");
const enviroment = @import("enviroment.zig");
const gas_tracker = @import("gas_tracker.zig");
const host_type = @import("host.zig");
const interpreter_type = @import("Interpreter.zig");
const journal = @import("journal.zig");
const mem = @import("memory.zig");
const specification = @import("specification.zig");
const std = @import("std");
const zabi_utils = @import("zabi-utils");

const Address = @import("zabi-types").ethereum.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Bytecode = bytecode.Bytecode;
const CallAction = actions.CallAction;
const CallScheme = actions.CallScheme;
const Contract = contract_type.Contract;
const CreateAction = actions.CreateAction;
const CreateScheme = actions.CreateScheme;

const GasTracker = gas_tracker.GasTracker;
const Host = host_type.Host;
const Interpreter = interpreter_type;
const InterpreterActions = interpreter_type.InterpreterActions;
const InterpreterStatus = interpreter_type.InterpreterStatus;
const JournalCheckpoint = journal.JournalCheckpoint;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Memory = mem.Memory;
const ReturnAction = actions.ReturnAction;
const RlpEncoder = encoding.RlpEncoder;
const SpecId = specification.SpecId;

/// The EVM driver that orchestrates contract execution.
///
/// The EVM manages the call stack, handles CALL/CREATE recursion,
/// forwards gas between frames, and wires return data back to callers.
/// It treats the Interpreter as a pure execution engine that yields
/// actions, while the EVM applies semantic effects.
const EVM = @This();

/// Maximum call stack depth as defined by Ethereum specification.
/// Prevents stack overflow attacks via deep recursion.
pub const MAX_CALL_STACK_DEPTH: usize = 1024;

/// Represents a single call frame in the EVM execution stack.
///
/// Each call or create operation pushes a new frame onto the stack.
/// The frame contains the interpreter state, contract context, and
/// metadata needed to resume the parent frame after completion.
pub const CallFrame = struct {
    /// The contract being executed in this frame.
    contract: Contract,
    /// The interpreter executing the contract bytecode.
    interpreter: Interpreter,
    /// Memory range in parent frame where return data should be written.
    /// Format: (offset, length). Only used for CALL-like operations.
    return_memory_offset: struct { usize, usize },
    /// True if this frame is executing a CREATE/CREATE2 operation.
    is_create: bool,
    /// Checkpoint for state rollback on revert. Used by JournaledHost to
    /// restore state when a subcall fails. Null for top-level frames when
    /// no checkpoint was created (e.g., PlainHost returns dummy checkpoints).
    checkpoint: JournalCheckpoint,

    /// Releases all resources associated with this call frame.
    pub fn deinit(self: *CallFrame, allocator: Allocator) void {
        self.interpreter.deinit();
        self.contract.deinit(allocator);
    }
};

/// Result of a completed EVM execution.
pub const ExecutionResult = struct {
    /// Final status of execution (stopped, returned, reverted, etc.).
    status: InterpreterStatus,
    /// Output data from the execution (return data or revert reason).
    output: []u8,
    /// Total gas consumed during execution.
    gas_used: u64,
    /// Gas to be refunded (e.g., from SSTORE clearing).
    gas_refunded: i64,

    /// Releases the output buffer.
    pub fn deinit(self: *ExecutionResult, allocator: Allocator) void {
        allocator.free(self.output);
    }
};

/// Errors that can occur during EVM execution.
pub const ExecutionError = error{
    /// Target address has no associated bytecode.
    NoAssociatedBytecode,
    /// Call stack depth exceeded MAX_CALL_STACK_DEPTH.
    DepthLimitReached,
    /// Execution ran out of gas.
    OutOfGas,
    /// CREATE target address already has code or non-zero nonce.
    CreateCollision,
    /// Bytecode failed validation.
    InvalidBytecode,
    /// Deployed contract exceeds maximum code size (EIP-170).
    ContractSizeLimit,
} || Interpreter.InterpreterRunErrors || RlpEncoder.Error;

allocator: Allocator,
/// Host interface for state access (storage, accounts, logs).
/// The Host owns the environment configuration (block, tx, config).
host: Host,
/// Stack of active call frames. The last element is the current frame.
call_stack: ArrayListUnmanaged(CallFrame),
/// Return data from the most recent completed call (for RETURNDATASIZE/COPY).
return_data: []u8,

/// Initializes the EVM with the given configuration.
///
/// The Host owns the environment (block, tx, config). Access it via `host.getEnviroment()`.
/// The EVM must be deinitialized with `deinit` after use to free resources.
pub fn init(
    self: *EVM,
    allocator: Allocator,
    evm_host: Host,
) void {
    self.* = .{
        .allocator = allocator,
        .host = evm_host,
        .call_stack = .empty,
        .return_data = &[_]u8{},
    };
}

/// Releases all resources held by the EVM.
pub fn deinit(self: *EVM) void {
    for (self.call_stack.items) |*frame|
        frame.deinit(self.allocator);

    self.call_stack.deinit(self.allocator);
    self.allocator.free(self.return_data);
}

/// Executes a transaction against the EVM.
///
/// Dispatches to either `executeBytecode` for calls or `executeCreate`
/// for contract deployments based on the transaction target.
pub fn executeTransaction(self: *EVM) ExecutionError!ExecutionResult {
    const env = self.host.getEnviroment();

    switch (env.tx.transact_to) {
        .call => |target| {
            const code, _ = self.host.code(target) orelse
                return error.NoAssociatedBytecode;

            return self.executeBytecode(code);
        },
        .create => return self.executeCreate(),
    }
}

/// Executes bytecode in a call context.
///
/// Prepares the contract from the transaction environment and
/// starts the execution loop.
pub fn executeBytecode(self: *EVM, code: Bytecode) ExecutionError!ExecutionResult {
    const env = self.host.getEnviroment();
    const contract: Contract = try .initFromEnviroment(self.allocator, env, code, null);

    return self.executeWithContract(contract, false, .{ 0, 0 });
}

/// Executes a contract creation transaction.
///
/// Derives the create address from sender and nonce, then executes
/// the init code.
pub fn executeCreate(self: *EVM) ExecutionError!ExecutionResult {
    const env = self.host.getEnviroment();
    const create_address = try deriveCreateAddress(self.allocator, .{ env.tx.caller, env.tx.nonce });
    return self.executeCreateWithAddress(create_address);
}

/// Pushes a new call frame and begins execution.
///
/// Enforces the call depth limit before creating the frame.
fn executeWithContract(
    self: *EVM,
    contract: Contract,
    is_create: bool,
    return_memory_offset: struct { usize, usize },
) ExecutionError!ExecutionResult {
    if (self.call_stack.items.len >= MAX_CALL_STACK_DEPTH)
        return error.DepthLimitReached;

    const env = self.host.getEnviroment();

    const checkpoint = self.host.checkpoint() catch return error.OutOfGas;

    var interpreter: Interpreter = undefined;
    try interpreter.init(self.allocator, &contract, self.host, .{
        .gas_limit = env.tx.gas_limit,
        .spec_id = env.config.spec_id,
    });

    const frame: CallFrame = .{
        .contract = contract,
        .interpreter = interpreter,
        .return_memory_offset = return_memory_offset,
        .is_create = is_create,
        .checkpoint = checkpoint,
    };

    self.call_stack.append(self.allocator, frame) catch |err| {
        // If we fail to append, clean up and revert the checkpoint
        self.host.revertCheckpoint(checkpoint) catch {};
        interpreter.deinit();
        return err;
    };

    return self.runExecutionLoop();
}

/// Main execution loop that processes frames until completion.
///
/// Runs the current frame's interpreter until it yields an action,
/// then handles that action (return, call, or create). Continues
/// until the call stack is empty.
fn runExecutionLoop(self: *EVM) ExecutionError!ExecutionResult {
    while (self.call_stack.items.len > 0) {
        const current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        const action = current_frame.interpreter.run() catch |err| {
            // On interpreter error, revert checkpoint and clean up frame
            var frame = self.call_stack.pop().?;
            defer self.host.revertCheckpoint(frame.checkpoint) catch {};

            frame.contract.deinit(self.allocator);
            frame.interpreter.deinit();
            return err;
        };

        switch (action) {
            .return_action => |ret| {
                // SAFETY:
                // This is safe to do since we are inside the loop and will
                // always at least have one element in the call_stack.
                var frame = self.call_stack.pop().?;
                defer {
                    frame.contract.deinit(self.allocator);
                    frame.interpreter.deinit();
                }

                switch (ret.result) {
                    .stopped,
                    .retured,
                    => self.host.commitCheckpoint(),
                    else => self.host.revertCheckpoint(frame.checkpoint) catch {},
                }

                if (self.call_stack.items.len == 0) {
                    const env = self.host.getEnviroment();
                    const gas_used = frame.interpreter.gas_tracker.usedAmount();
                    const gas_refunded: i64 = if (env.config.disable_gas_refund) 0 else ret.gas.refund_amount;

                    return .{
                        .status = ret.result,
                        .output = ret.output,
                        .gas_used = gas_used,
                        .gas_refunded = gas_refunded,
                    };
                }

                const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];
                try self.handleReturnFromCall(parent_frame, &frame, ret);
            },
            .call_action => |call| try self.executeCallAction(call),
            .create_action => |create| try self.executeCreateAction(create),
            .no_action => {
                // SAFETY:
                // This is safe to do since we are inside the loop and will
                // always at least have one element in the call_stack.
                var frame = self.call_stack.pop().?;
                defer {
                    frame.contract.deinit(self.allocator);
                    frame.interpreter.deinit();
                }

                self.host.commitCheckpoint();

                if (self.call_stack.items.len == 0)
                    return .{
                        .status = .stopped,
                        .output = &[0]u8{},
                        .gas_used = frame.interpreter.gas_tracker.usedAmount(),
                        .gas_refunded = 0,
                    };
            },
        }
    }

    return .{
        .status = .stopped,
        .output = &[0]u8{},
        .gas_used = 0,
        .gas_refunded = 0,
    };
}

/// Handles return from a completed subcall.
///
/// Returns unused gas to the parent frame, updates return data buffer,
/// writes output to parent memory (for successful calls), and pushes
/// success indicator onto the parent stack.
fn handleReturnFromCall(
    self: *EVM,
    parent_frame: *CallFrame,
    child_frame: *const CallFrame,
    ret: ReturnAction,
) ExecutionError!void {
    const success = ret.result == .stopped or ret.result == .returned;
    parent_frame.interpreter.gas_tracker.available += ret.gas.availableGas();

    self.allocator.free(self.return_data);
    self.return_data = try self.allocator.dupe(u8, ret.output);

    // Restore parent memory context before writing return data.
    // This must happen for both success and failure cases.
    if (!child_frame.is_create)
        parent_frame.interpreter.memory.freeContext();

    if (success and !child_frame.is_create) {
        const offset, const len = child_frame.return_memory_offset;
        if (len > 0) {
            const copy_len = @min(len, ret.output.len);
            if (copy_len > 0) {
                const new_size = offset +| copy_len;
                try parent_frame.interpreter.resize(new_size);
                parent_frame.interpreter.memory.write(offset, ret.output[0..copy_len]);
            }
        }
    }

    parent_frame.interpreter.stack.appendAssumeCapacity(@intFromBool(success));
    parent_frame.interpreter.status = .running;
}

/// Executes a CALL/CALLCODE/DELEGATECALL/STATICCALL action.
///
/// Loads target bytecode, sets up the call context based on the scheme,
/// creates a new call frame, and prepares parent memory for subcall.
fn executeCallAction(self: *EVM, call: CallAction) ExecutionError!void {
    if (self.call_stack.items.len >= MAX_CALL_STACK_DEPTH) {
        const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];

        parent_frame.interpreter.stack.appendAssumeCapacity(0);
        parent_frame.interpreter.status = .running;

        return;
    }

    const code, _ = self.host.code(call.bytecode_address) orelse {
        const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];

        parent_frame.interpreter.stack.appendAssumeCapacity(1);
        parent_frame.interpreter.status = .running;

        return;
    };

    const env = self.host.getEnviroment();

    const prepared_code = switch (env.config.perform_analysis) {
        .analyse => try analysis.analyzeBytecode(self.allocator, code),
        .raw => code,
    };

    const caller = switch (call.scheme) {
        .delegate => call.caller,
        else => call.target_address,
    };

    const target_address = switch (call.scheme) {
        .callcode => self.call_stack.items[self.call_stack.items.len - 1].contract.target_address,
        else => call.target_address,
    };

    const value = switch (call.value) {
        inline else => |value| value,
    };

    const contract: Contract = .{
        .bytecode = prepared_code,
        .caller = caller,
        .code_hash = null,
        .input = call.inputs,
        .target_address = target_address,
        .value = value,
    };

    const checkpoint = self.host.checkpoint() catch {
        const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        parent_frame.interpreter.stack.appendAssumeCapacity(0);
        parent_frame.interpreter.status = .running;
        return;
    };

    var interpreter: Interpreter = undefined;
    try interpreter.init(self.allocator, &contract, self.host, .{
        .gas_limit = call.gas_limit,
        .spec_id = env.config.spec_id,
        .is_static = call.is_static,
    });

    try self.call_stack.items[self.call_stack.items.len - 1].interpreter.memory.newContext();

    const frame: CallFrame = .{
        .contract = contract,
        .interpreter = interpreter,
        .return_memory_offset = call.return_memory_offset,
        .is_create = false,
        .checkpoint = checkpoint,
    };

    try self.call_stack.append(self.allocator, frame);
}

/// Executes a CREATE or CREATE2 action.
///
/// Derives the target address and pushes a new create frame onto the stack.
fn executeCreateAction(self: *EVM, create: CreateAction) ExecutionError!void {
    if (self.call_stack.items.len >= MAX_CALL_STACK_DEPTH) {
        const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        parent_frame.interpreter.stack.appendAssumeCapacity(0);
        parent_frame.interpreter.status = .running;
        return;
    }

    const env = self.host.getEnviroment();

    const create_address = switch (create.scheme) {
        .create => try deriveCreateAddress(self.allocator, .{ create.caller, 0 }),
        .create2 => |salt| deriveCreate2Address(create.caller, salt, create.init_code),
    };

    const prepared_code: Bytecode = switch (env.config.perform_analysis) {
        .analyse => try analysis.analyzeBytecode(self.allocator, .{ .raw = create.init_code }),
        .raw => .{ .raw = create.init_code },
    };

    const contract: Contract = .{
        .bytecode = prepared_code,
        .caller = create.caller,
        .code_hash = null,
        .input = &[_]u8{},
        .target_address = create_address,
        .value = create.value,
    };

    const checkpoint = self.host.checkpoint() catch {
        const parent_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        parent_frame.interpreter.stack.appendAssumeCapacity(0);
        parent_frame.interpreter.status = .running;
        return;
    };

    var interpreter: Interpreter = undefined;
    try interpreter.init(self.allocator, &contract, self.host, .{
        .gas_limit = create.gas_limit,
        .spec_id = env.config.spec_id,
    });

    const frame: CallFrame = .{
        .contract = contract,
        .interpreter = interpreter,
        .return_memory_offset = .{ 0, 0 },
        .is_create = true,
        .checkpoint = checkpoint,
    };

    try self.call_stack.append(self.allocator, frame);
}

/// Creates a contract at the specified address for top-level create transactions.
fn executeCreateWithAddress(
    self: *EVM,
) ExecutionError!ExecutionResult {
    const env = self.host.getEnviroment();

    const prepared_code: Bytecode = switch (env.config.perform_analysis) {
        .analyse => try analysis.analyzeBytecode(self.allocator, .{ .raw = env.tx.data }),
        .raw => .{ .raw = env.tx.data },
    };

    const contract: Contract = .{
        .bytecode = prepared_code,
        .caller = env.tx.caller,
        .code_hash = null,
        .input = &[_]u8{},
        .target_address = env.tx.transact_to,
        .value = env.tx.value,
    };

    return self.executeWithContract(contract, true, .{ 0, 0 });
}

/// Derives a CREATE address from sender and nonce using RLP encoding.
///
/// Address = keccak256(rlp([sender, nonce]))[12:32]
pub fn deriveCreateAddress(allocator: Allocator, payload: struct { Address, u64 }) RlpEncoder.Error!Address {
    const encoded = try RlpEncoder.encodeRlp(allocator, payload);
    defer allocator.free(encoded);

    var hash: [32]u8 = undefined;
    Keccak256.hash(encoded, &hash, .{});

    return hash[12..32].*;
}

/// Derives a CREATE2 address from sender, salt, and init code hash.
///
/// Address = keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:32]
pub fn deriveCreate2Address(sender: Address, salt: u256, init_code: []const u8) Address {
    var hash: [32]u8 = undefined;
    var code_hash: [32]u8 = undefined;
    var hasher = Keccak256.init(.{});

    Keccak256.hash(init_code, &code_hash, .{});

    hasher.update(&[_]u8{0xff});
    hasher.update(&sender);
    hasher.update(&std.mem.toBytes(std.mem.nativeToBig(u256, salt)));
    hasher.update(&code_hash);
    hasher.final(&hash);

    return hash[12..32].*;
}
