const std = @import("std");

const Allocator = std.mem.Allocator;
const Word = [32]u8;

pub const Memory = struct {
    allocator: Allocator,
    buffer: []u8,
    checkpoints: []u8,
    last_checkpoint: usize,
    memory_limit: u64,

    /// Create the interpreter's memory. This will not error.
    /// No initial capacity is set. It's essentially empty memory.
    pub fn initEmpty(allocator: Allocator, limit: ?u64) Memory {
        return .{
            .allocator = allocator,
            .buffer = &[_]u8{},
            .checkpoints = &[_]u8{},
            .last_checkpoint = 0,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
        };
    }
    /// Creates the memory with default 4096 capacity.
    pub fn initWithDefaultCapacity(allocator: Allocator, limit: ?u64) !Memory {
        return Memory.initWithCapacity(allocator, 4096, limit);
    }
    /// Creates the memory with `capacity`.
    pub fn initWithCapacity(allocator: Allocator, capacity: usize, limit: ?u64) !Memory {
        const buffer = try allocator.alloc(u8, capacity);
        const checkpoints = try allocator.alloc(u8, 32);

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .checkpoints = checkpoints,
            .last_checkpoint = 0,
            .memory_limit = limit orelse comptime std.math.maxInt(u64),
        };
    }
    /// Gets a byte from the list's buffer.
    pub fn getMemoryByte(self: Memory, offset: usize) u8 {
        const slice = self.getSlice();
        std.debug.assert(slice.len > offset); // Indexing out of bounds.

        return self.buffer[offset];
    }
    /// Gets a "Word" from memory of in other words it gets a slice
    /// of 32 bytes from the inner memory list.
    pub fn getMemoryWord(self: Memory, offset: usize) Word {
        const slice = self.getSlice();
        std.debug.assert(slice.len > offset + 32);

        return slice[offset .. offset + 32].*;
    }
    /// Gets a memory slice based on the last checkpoints until the end of the buffer.
    pub fn getSlice(self: Memory) []u8 {
        std.debug.assert(self.buffer.len > self.last_checkpoint);

        return self.buffer[self.last_checkpoint..self.buffer.len];
    }
    /// Resizes the underlaying memory buffer.
    /// Uses the allocator's `resize` method in case it's possible.
    /// If the new len is lower than the current buffer size data will be lost.
    pub fn resize(self: *Memory, new_len: usize) !void {
        if (self.last_checkpoint + new_len > self.memory_limit)
            return error.MaxMemoryReached;

        const resized = self.allocator.resize(self.buffer, new_len);

        if (resized)
            return;

        // Allocator refused to resize the memory so we do it ourselves.
        const new_buffer = try self.allocator.alloc(u8, new_len);

        {
            defer self.allocator.free(self.buffer);

            if (self.buffer.len > new_len) {
                @memcpy(new_buffer, self.buffer[0..new_len]);
            } else {
                @memcpy(new_buffer[0..self.buffer.len], self.buffer);
            }
        }

        self.buffer = new_buffer;
    }
    /// Converts a memory "Word" into a u256 number.
    pub fn wordToInt(self: Memory, offset: usize) u256 {
        const word = self.getMemoryWord(offset);

        return @as(u256, @bitCast(word.*));
    }
    /// Writes a single byte into this memory buffer.
    /// This can overwrite to existing memory.
    pub fn writeByte(self: Memory, offset: usize, byte: u8) !void {
        var byte_buffer: [1]u8 = [_]u8{byte};

        return self.write(offset, byte_buffer[0..]);
    }
    /// Writes a memory `Word` into the memory buffer.
    /// This can overwrite to existing memory.
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
    pub fn write(self: Memory, offset: usize, data: []u8) !void {
        const slice = self.getSlice();
        std.debug.assert(slice.len > offset + data.len);

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
        self.allocator.free(self.buffer);
        self.allocator.free(self.checkpoints);
    }
};
