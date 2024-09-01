const memory = @import("../../evm/memory.zig");
const std = @import("std");
const testing = std.testing;

const Memory = memory.Memory;
const availableWords = memory.availableWords;

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
        mem.writeInt(0, 69);
        try testing.expectEqual(69, mem.getMemoryByte(31));
    }
    {
        const int = mem.wordToInt(0);
        try testing.expectEqual(69, int);
    }
    {
        mem.writeWord(0, [_]u8{1} ** 32);
        const int = mem.wordToInt(0);
        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), int);
    }
    {
        mem.writeByte(0, 69);
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
