const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Word = [32]u8;

/// A extendable memory used by the evm interpreter.
pub const Memory = struct {
    /// Sets the initial capacity to be aligned with the cpu cache size.
    const init_capacity = @as(comptime_int, @max(1, std.atomic.cache_line / @sizeOf(u256)));

    /// Set of errors when resizing errors.
    pub const Error = error{MaxMemoryReached};

    /// The inner allocator used to grow the memory
    allocator: Allocator,
    /// The underlaying memory buffer.
    buffer: []u8,
    /// Set of memory checkpoints
    checkpoints: ArrayListUnmanaged(usize),
    /// The last memory checkpoint
    last_checkpoint: usize,
    /// The max memory size
    memory_limit: u64,
    /// The total allocated capacity of this memory.
    total_capacity: usize,

    /// Create the interpreter's memory. This will not error.
    /// No initial capacity is set. It's essentially empty memory.
    pub fn initEmpty(
        allocator: Allocator,
        limit: ?u64,
    ) Memory {
        return .{
            .allocator = allocator,
            .buffer = &[_]u8{},
            .checkpoints = .empty,
            .last_checkpoint = 0,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
            .total_capacity = 0,
        };
    }

    /// Creates the memory with default 4096 capacity.
    pub fn initWithDefaultCapacity(
        allocator: Allocator,
        limit: ?u64,
    ) Allocator.Error!Memory {
        return Memory.initWithCapacity(allocator, 4096, limit);
    }

    /// Creates the memory with `capacity`.
    pub fn initWithCapacity(
        allocator: Allocator,
        capacity: usize,
        limit: ?u64,
    ) Allocator.Error!Memory {
        var buffer = try allocator.alloc(u8, capacity);
        const checkpoints = try ArrayListUnmanaged(usize).initCapacity(allocator, 32);

        buffer.len = 0;

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .checkpoints = checkpoints,
            .last_checkpoint = 0,
            .total_capacity = capacity,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
        };
    }

    /// Frees the underlaying memory buffers.
    pub fn deinit(self: *Memory) void {
        self.allocator.free(self.buffer.ptr[0..self.total_capacity]);
        self.checkpoints.deinit(self.allocator);
    }

    /// Prepares the memory for returning to the previous context.
    pub fn freeContext(self: *Memory) void {
        const checkpoint = self.checkpoints.pop();
        self.buffer.len = checkpoint orelse 0;
        self.last_checkpoint = self.checkpoints.getLastOrNull() orelse 0;
    }

    /// Gets the current size of the `Memory` range.
    pub fn getCurrentMemorySize(self: Memory) u64 {
        std.debug.assert(self.buffer.len >= self.last_checkpoint);
        return self.buffer.len - self.last_checkpoint;
    }

    /// Gets a byte from the list's buffer.
    pub fn getMemoryByte(
        self: Memory,
        offset: usize,
    ) u8 {
        const slice = self.getSlice();
        std.debug.assert(slice.len > offset); // Indexing out of bounds.

        return self.buffer[offset];
    }

    /// Gets a `Word` from memory of in other words it gets a slice
    /// of 32 bytes from the inner memory buffer.
    pub fn getMemoryWord(
        self: Memory,
        offset: usize,
    ) Word {
        const slice = self.getSlice();
        std.debug.assert(slice.len >= offset + 32);

        return slice[offset .. offset + 32][0..32].*;
    }

    /// Gets a memory slice based on the last checkpoints until the end of the buffer.
    pub fn getSlice(self: Memory) []u8 {
        std.debug.assert(self.buffer.len > self.last_checkpoint);

        return self.buffer[self.last_checkpoint..];
    }

    /// Copies elements from one part of the buffer to another part of itself.
    /// Asserts that the provided indexes are not out of bound.
    pub fn memoryCopy(
        self: *Memory,
        destination: usize,
        source: usize,
        length: usize,
    ) void {
        const slice = self.getSlice();

        std.debug.assert(slice.len >= destination + length); // Indexing out of bound.
        std.debug.assert(slice.len >= source + length); // Indexing out of bound.

        @memcpy(slice[destination .. destination + length], slice[source .. source + length]);
    }

    /// Prepares the memory for a new context.
    pub fn newContext(self: *Memory) Allocator.Error!void {
        const new_checkpoint = self.buffer.len;

        try self.checkpoints.append(self.allocator, new_checkpoint);
        self.last_checkpoint = new_checkpoint;
    }

    /// Resizes the underlaying memory buffer.
    /// Uses the allocator's `resize` method in case it's possible.
    /// If the new len is lower than the current buffer size data will be lost.
    pub fn resize(
        self: *Memory,
        new_len: usize,
    ) (Allocator.Error || Memory.Error)!void {
        const new_capacity = self.last_checkpoint + new_len;

        if (new_capacity > self.memory_limit) {
            @branchHint(.cold);
            return error.MaxMemoryReached;
        }

        // Extends to new len within capacity.
        if (self.total_capacity >= new_capacity) {
            self.buffer.len = new_capacity;

            return;
        }

        const better = growCapacity(self.total_capacity, new_capacity);

        const new_buffer = try self.allocator.alloc(u8, better);
        const old_memory = self.buffer.ptr[0..self.total_capacity];

        @memcpy(new_buffer[0..self.buffer.len], self.buffer);
        self.allocator.free(old_memory);
        self.buffer.ptr = new_buffer.ptr;
        self.buffer.len = new_capacity;
        self.total_capacity = better;
    }

    /// Converts a memory "Word" into a u256 number.
    /// This reads the word as `Big` endian.
    pub fn wordToInt(
        self: Memory,
        offset: usize,
    ) u256 {
        const word = self.getMemoryWord(offset);

        return std.mem.readInt(u256, &word, .big);
    }

    /// Writes a single byte into this memory buffer.
    /// This can overwrite to existing memory.
    pub fn writeByte(
        self: Memory,
        offset: usize,
        byte: u8,
    ) void {
        var byte_buffer: [1]u8 = [_]u8{byte};

        return self.write(offset, byte_buffer[0..]);
    }

    /// Writes a memory `Word` into the memory buffer.
    /// This can overwrite existing memory.
    pub fn writeWord(
        self: Memory,
        offset: usize,
        word: [32]u8,
    ) void {
        return self.write(offset, word[0..]);
    }

    /// Writes a `u256` number into the memory buffer.
    /// This can overwrite to existing memory.
    pub fn writeInt(
        self: Memory,
        offset: usize,
        data: u256,
    ) void {
        var buffer: [32]u8 = undefined;

        std.mem.writeInt(u256, &buffer, data, .big);

        return self.write(offset, buffer[0..]);
    }

    /// Writes a slice to the memory buffer based on a offset.
    /// This can overwrite to existing memory.
    pub fn write(
        self: Memory,
        offset: usize,
        data: []const u8,
    ) void {
        const slice = self.getSlice();
        std.debug.assert(slice.len >= offset + data.len);

        @memcpy(slice[offset .. offset + data.len], data);
    }

    /// Writes a slice to a given offset in memory + the provided data's offset.
    /// This can overwrite existing memory.
    pub fn writeData(
        self: Memory,
        offset: usize,
        data_offset: usize,
        len: usize,
        data: []u8,
    ) void {
        if (data_offset >= data.len) {
            const slice = self.getSlice();
            @memset(slice[offset .. offset + len], 0);

            return;
        }

        const end = @min(data_offset + len, data.len);
        const data_len = end - data_offset;

        std.debug.assert(data_offset < data.len and end <= data.len);

        const slice = data[data_offset..data_len];
        const memory_slice = self.getSlice();
        // Copy the data to the buffer.
        @memcpy(memory_slice[offset..data_len], slice);

        const range_start = offset + data_len;
        const range_end = range_start + (len - data_len);
        // Zero out the remainder of the memory.
        @memset(memory_slice[range_start..range_end], 0);
    }

    /// Adapted from `ArrayList` growCapacity function.
    fn growCapacity(
        current: usize,
        minimum: usize,
    ) usize {
        var new = current;
        while (true) {
            new +|= new + init_capacity;
            if (new > minimum) {
                @branchHint(.likely);
                return new;
            }
        }
    }
};

/// Returns number of words what would fit to provided number of bytes,
/// It rounds up the number bytes to number of words.
pub inline fn availableWords(size: u64) usize {
    const new_size: u64 = size +| 31;

    return @intCast(@divFloor(new_size, 32));
}
