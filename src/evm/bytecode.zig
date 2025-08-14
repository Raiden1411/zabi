const analysis = @import("analysis.zig");
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

/// State of the contract's bytecode.
pub const Bytecode = union(enum) {
    raw: []u8,
    analyzed: AnalyzedBytecode,

    /// Clears the analyzed jump table.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .raw => {},
            .analyzed => |analyzed| analyzed.deinit(allocator),
        }
    }
    /// Returns the jump_table is the bytecode state is `analyzed`
    /// otherwise it will return null.
    pub fn getJumpTable(self: @This()) ?JumpTable {
        switch (self) {
            .raw => return null,
            .analyzed => |analyzed| return analyzed.jump_table,
        }
    }
    /// Grabs the bytecode independent of the current state.
    pub fn getCodeBytes(self: @This()) []u8 {
        return switch (self) {
            .raw => |bytes| return bytes,
            .analyzed => |analyzed_bytes| return analyzed_bytes.bytecode,
        };
    }
};

/// Representation of the analyzed bytecode.
pub const AnalyzedBytecode = struct {
    bytecode: []u8,
    original_length: usize,
    jump_table: JumpTable,

    /// Creates an instance of `AnalyzedBytecode`.
    pub fn init(allocator: Allocator, raw: []u8) Allocator.Error!AnalyzedBytecode {
        var list = try std.array_list.Managed(u8).initCapacity(allocator, raw.len + 33);
        list.appendSliceAssumeCapacity(raw);
        list.appendSliceAssumeCapacity(&[_]u8{0} ** 33);

        const slice = try list.toOwnedSlice();
        const jump_table = try analysis.createJumpTable(allocator, slice);

        return .{
            .bytecode = slice,
            .original_length = raw.len,
            .jump_table = jump_table,
        };
    }
    /// Free's the underlaying allocated memory
    /// Assumes that the bytecode was already padded and memory was allocated.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.bytecode);
        self.jump_table.deinit(allocator);
    }
};

/// Essentially a `BitVec`
pub const JumpTable = struct {
    bytes: []u8,

    /// Creates the jump table. Provided size must follow the two's complement.
    pub fn init(
        allocator: Allocator,
        value: bool,
        size: usize,
    ) Allocator.Error!JumpTable {
        // Essentially `divCeil`
        const buffer = try allocator.alloc(u8, @divFloor(size - 1, 8) + 1);
        @memset(buffer, @intFromBool(value));

        return .{ .bytes = buffer };
    }

    /// Free's the underlaying buffer.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.bytes);
    }

    /// Sets or unset a bit at the given position.
    pub fn set(
        self: @This(),
        position: usize,
        value: bool,
    ) void {
        const byte_index = position >> 3;
        const bit_index: u3 = @intCast(position & 7);

        std.debug.assert(self.bytes.len > byte_index); // Index out of bouds;

        self.bytes[byte_index] &= ~(@as(u8, 1) << bit_index);
        self.bytes[byte_index] |= @as(u8, @intFromBool(value)) << bit_index;
    }
    /// Gets if a bit is set at a given position.
    pub fn peek(self: @This(), position: usize) u1 {
        const byte_index = position >> 3;
        const bit_index: u3 = @intCast(position & 7);

        std.debug.assert(self.bytes.len > byte_index); // Index out of bouds;

        return @intCast((self.bytes[byte_index] >> bit_index) & 1);
    }
    /// Check if the provided position results in a valid bit set.
    pub fn isValid(self: @This(), position: usize) bool {
        return position >> 3 < self.bytes.len and @as(bool, @bitCast(self.peek(position)));
    }
};
