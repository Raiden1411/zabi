const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Word = [32]u8;

/// A extendable memory used by the evm interpreter.
pub const Memory = struct {
    /// The inner allocator used to grow the memory
    allocator: Allocator,
    /// The underlaying memory buffer.
    buffer: []u8,
    /// Set of memory checkpoints
    checkpoints: ArrayList(usize),
    /// The last memory checkpoint
    last_checkpoint: usize,
    /// The max memory size
    memory_limit: u64,
    total_capacity: usize,

    /// Create the interpreter's memory. This will not error.
    /// No initial capacity is set. It's essentially empty memory.
    pub fn initEmpty(allocator: Allocator, limit: ?u64) Memory {
        return .{
            .allocator = allocator,
            .buffer = &[_]u8{},
            .checkpoints = ArrayList(usize).init(allocator),
            .last_checkpoint = 0,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
            .total_capacity = 0,
        };
    }
    /// Creates the memory with default 4096 capacity.
    pub fn initWithDefaultCapacity(allocator: Allocator, limit: ?u64) !Memory {
        return Memory.initWithCapacity(allocator, 4096, limit);
    }
    /// Creates the memory with `capacity`.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize, limit: ?u64) !Memory {
        const buffer = try allocator.alloc(u8, capacity);
        const checkpoints = try ArrayList(usize).initCapacity(allocator, 32);

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .checkpoints = checkpoints,
            .last_checkpoint = 0,
            .total_capacity = capacity,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
        };
    }
    /// Prepares the memory for returning to the previous context.
    pub fn freeContext(self: *Memory) void {
        const checkpoint = self.checkpoints.pop();
        self.buffer.len = checkpoint;
        self.last_checkpoint = self.checkpoints.getLastOrNull() orelse 0;
    }
    /// Gets the current size of the `Memory` range.
    pub fn getCurrentMemorySize(self: Memory) u64 {
        return @truncate(self.buffer.len - self.last_checkpoint);
    }
    /// Gets a byte from the list's buffer.
    pub fn getMemoryByte(self: Memory, offset: usize) u8 {
        const slice = self.getSlice();
        std.debug.assert(slice.len > offset); // Indexing out of bounds.

        return self.buffer[offset];
    }
    /// Gets a `Word` from memory of in other words it gets a slice
    /// of 32 bytes from the inner memory buffer.
    pub fn getMemoryWord(self: Memory, offset: usize) Word {
        const slice = self.getSlice();
        std.debug.assert(slice.len >= offset + 32);

        var buffer: [32]u8 = undefined;
        @memcpy(buffer[0..], slice[offset .. offset + 32]);

        return buffer;
    }
    /// Gets a memory slice based on the last checkpoints until the end of the buffer.
    pub fn getSlice(self: Memory) []u8 {
        std.debug.assert(self.buffer.len > self.last_checkpoint);

        return self.buffer[self.last_checkpoint..self.buffer.len];
    }
    /// Copies elements from one part of the buffer to another part of itself.
    /// Asserts that the provided indexes are not out of bound.
    pub fn memoryCopy(self: *Memory, destination: u64, source: u64, length: u64) void {
        const slice = self.getSlice();

        std.debug.assert(slice.len >= destination + length); // Indexing out of bound.
        std.debug.assert(slice.len >= source + length); // Indexing out of bound.

        @memcpy(slice[destination .. destination + length], slice[source .. source + length]);
    }
    /// Prepares the memory for a new context.
    pub fn newContext(self: *Memory) !void {
        const new_checkpoint = self.buffer.len;
        try self.checkpoints.append(new_checkpoint);
        self.last_checkpoint = new_checkpoint;
    }
    /// Resizes the underlaying memory buffer.
    /// Uses the allocator's `resize` method in case it's possible.
    /// If the new len is lower than the current buffer size data will be lost.
    pub fn resize(self: *Memory, new_len: usize) !void {
        const new_capacity = self.last_checkpoint + new_len;
        if (new_capacity > self.memory_limit)
            return error.MaxMemoryReached;

        // Extends to new len within capacity.
        if (self.total_capacity >= new_capacity) {
            self.buffer.len = new_capacity;
            return;
        }

        if (self.allocator.resize(self.buffer, new_capacity))
            return;

        // Allocator refused to resize the memory so we do it ourselves.
        const new_buffer = try self.allocator.alloc(u8, new_capacity);

        if (self.buffer.len > new_capacity)
            @memcpy(new_buffer, self.buffer[0..new_capacity])
        else
            @memcpy(new_buffer[0..self.buffer.len], self.buffer);

        self.allocator.free(self.buffer);
        self.buffer = new_buffer;
        self.total_capacity = new_capacity;
    }
    /// Converts a memory "Word" into a u256 number.
    /// This reads the word as `Big` endian.
    pub fn wordToInt(self: Memory, offset: usize) u256 {
        const word = self.getMemoryWord(offset);

        return std.mem.readInt(u256, &word, .big);
    }
    /// Writes a single byte into this memory buffer.
    /// This can overwrite to existing memory.
    pub fn writeByte(self: Memory, offset: usize, byte: u8) !void {
        var byte_buffer: [1]u8 = [_]u8{byte};

        return self.write(offset, byte_buffer[0..]);
    }
    /// Writes a memory `Word` into the memory buffer.
    /// This can overwrite existing memory.
    pub fn writeWord(self: Memory, offset: usize, word: [32]u8) !void {
        return self.write(offset, word[0..]);
    }
    /// Writes a `u256` number into the memory buffer.
    /// This can overwrite to existing memory.
    pub fn writeInt(self: Memory, offset: usize, data: u256) !void {
        var buffer: [32]u8 = undefined;

        std.mem.writeInt(u256, &buffer, data, .big);

        return self.write(offset, buffer[0..]);
    }
    /// Writes a slice to the memory buffer based on a offset.
    /// This can overwrite to existing memory.
    pub fn write(self: Memory, offset: usize, data: []const u8) !void {
        const slice = self.getSlice();
        std.debug.assert(slice.len >= offset + data.len);

        @memcpy(slice[offset .. offset + data.len], data);
    }
    /// Writes a slice to a given offset in memory + the provided data's offset.
    /// This can overwrite existing memory.
    pub fn writeData(self: Memory, offset: usize, data_offset: usize, len: usize, data: []u8) !void {
        if (data_offset >= data.len) {
            const slice = self.getSlice();
            @memset(slice[offset .. offset + len], 0);

            return;
        }

        const end = @min(data_offset + len, data.len);
        const data_len = end - data_offset;

        std.debug.assert(data_offset < data.len and end <= data.len);

        // Copy the data to the buffer.
        const slice = data[data_offset..data_len];
        const memory_slice = self.getSlice();
        @memcpy(memory_slice[offset..data_len], slice);

        // Zero out the remainder of the memory.
        @memset(memory_slice[offset + data_len .. len - data_len], 0);
    }
    /// Frees the underlaying memory buffers.
    pub fn deinit(self: Memory) void {
        self.allocator.free(self.buffer.ptr[0..self.total_capacity]);
        self.checkpoints.deinit();
    }
};

/// Returns number of words what would fit to provided number of bytes,
/// It rounds up the number bytes to number of words.
pub inline fn availableWords(size: u64) u64 {
    const result, const overflow = @addWithOverflow(size, 31);

    if (@bitCast(overflow))
        return std.math.maxInt(u64) / 2;

    return @divFloor(result, 32);
}

test "Available words" {
    try testing.expectEqual(availableWords(0), 0);
    try testing.expectEqual(availableWords(1), 1);
    try testing.expectEqual(availableWords(31), 1);
    try testing.expectEqual(availableWords(32), 1);
    try testing.expectEqual(availableWords(33), 2);
    try testing.expectEqual(availableWords(63), 2);
    try testing.expectEqual(availableWords(64), 2);
    try testing.expectEqual(availableWords(65), 3);
    try testing.expectEqual(availableWords(std.math.maxInt(u64)), std.math.maxInt(u64) / 2);
}

test "Memory" {
    var mem = try Memory.initWithDefaultCapacity(testing.allocator, null);
    defer mem.deinit();

    {
        try mem.writeInt(0, 69);
        try testing.expectEqual(69, mem.getMemoryByte(31));
    }
    {
        const int = mem.wordToInt(0);
        try testing.expectEqual(69, int);
    }
    {
        try mem.writeWord(0, [_]u8{1} ** 32);
        const int = mem.wordToInt(0);
        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), int);
    }
    {
        try mem.writeByte(0, 69);
        const int = mem.getMemoryByte(0);
        try testing.expectEqual(69, int);
    }
}

test "Context" {
    var mem = Memory.initEmpty(testing.allocator, null);
    defer mem.deinit();

    try mem.resize(32);
    try testing.expectEqual(mem.getCurrentMemorySize(), 32);
    try testing.expectEqual(mem.buffer.len, 32);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
    try testing.expectEqual(mem.total_capacity, 32);

    try mem.newContext();
    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 128);
    try testing.expectEqual(mem.checkpoints.items.len, 1);
    try testing.expectEqual(mem.last_checkpoint, 32);
    try testing.expectEqual(mem.total_capacity, 128);

    try mem.newContext();
    try mem.resize(128);
    try testing.expectEqual(mem.getCurrentMemorySize(), 128);
    try testing.expectEqual(mem.buffer.len, 256);
    try testing.expectEqual(mem.checkpoints.items.len, 2);
    try testing.expectEqual(mem.last_checkpoint, 128);
    try testing.expectEqual(mem.total_capacity, 256);

    mem.freeContext();
    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 128);
    try testing.expectEqual(mem.checkpoints.items.len, 1);
    try testing.expectEqual(mem.last_checkpoint, 32);
    try testing.expectEqual(mem.total_capacity, 256);

    mem.freeContext();
    try mem.resize(64);
    try testing.expectEqual(mem.getCurrentMemorySize(), 64);
    try testing.expectEqual(mem.buffer.len, 64);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
    try testing.expectEqual(mem.total_capacity, 256);
}

test "No Context" {
    var mem = Memory.initEmpty(testing.allocator, null);
    defer mem.deinit();

    try mem.resize(32);
    try testing.expectEqual(mem.getCurrentMemorySize(), 32);
    try testing.expectEqual(mem.buffer.len, 32);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);

    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 96);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);

    try mem.resize(64);
    try testing.expectEqual(mem.getCurrentMemorySize(), 64);
    try testing.expectEqual(mem.buffer.len, 64);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
}
