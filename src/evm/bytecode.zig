const std = @import("std");

const Allocator = std.mem.Allocator;

/// State of the contract's bytecode.
pub const Bytecode = union(enum) {
    raw: []u8,
    analyzed: AnalyzedBytecode,

    /// Returns the jump_table is the bytecode state is `analyzed`
    /// otherwise it will return null.
    pub fn getJumpTable(self: @This()) ?JumpTable {
        switch (self) {
            .raw => return null,
            .analyzed => |analyzed| return analyzed.jump_table,
        }
    }
};

/// Representation of the analyzed bytecode.
pub const AnalyzedBytecode = struct {
    bytecode: []u8,
    original_length: usize,
    jump_table: JumpTable,
};

/// Essentially a `BitVec`
pub const JumpTable = struct {
    bytes: []u8,

    /// Creates the jump table. Provided size must follow the two's complement.
    pub fn init(allocator: Allocator, value: bool, size: usize) !JumpTable {
        const buffer = try allocator.alloc(u8, @divFloor(size, 8));
        @memset(buffer, @intFromBool(value));

        return .{ .bytes = buffer };
    }

    /// Free's the underlaying buffer.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        allocator.free(self.bytes);
    }

    /// Sets or unset a bit at the given position.
    pub fn set(self: @This(), position: usize, value: bool) void {
        const byte_index = position >> 3;
        const bit_index: u3 = @intCast(position & 7);

        std.debug.assert(self.bytes.len > byte_index);
        self.bytes[byte_index] &= ~(@as(u8, 1) << bit_index);
        self.bytes[byte_index] |= @as(u8, @intFromBool(value)) << bit_index;
    }
    /// Gets if a bit is set at a given position.
    pub fn peek(self: @This(), position: usize) u1 {
        const byte_index = (position - 1) >> 3;
        const bit_index: u3 = @intCast((position - 1) & 7);

        return @intCast((self.bytes[byte_index] >> bit_index) & 1);
    }
    /// Check if the provided position results in a valid bit set.
    pub fn isValid(self: @This(), position: usize) bool {
        return self.bytes.len < position and @as(bool, @bitCast(self.peek(position)));
    }
};
