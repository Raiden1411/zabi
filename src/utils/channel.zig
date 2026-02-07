const std = @import("std");

/// Types
const Allocator = std.mem.Allocator;
const Condition = std.Io.Condition;
const Deque = std.Deque;
const Mutex = std.Io.Mutex;

/// Channel used to manages the messages between threads.
/// Main use case is for the websocket client.
pub fn Channel(comptime T: type) type {
    return struct {
        allocator: Allocator,
        fifo: Deque(T) = .empty,
        lock: Mutex = .init,
        readable: Condition = .init,
        writeable: Condition = .init,

        const Self = @This();

        /// Inits the channel.
        pub fn init(gpa: Allocator) Self {
            return .{
                .allocator = gpa,
            };
        }

        /// Frees the channel.
        /// If the list still has items with allocated
        /// memory this will not free them.
        pub fn deinit(self: *Self) void {
            self.fifo.deinit(self.allocator);
        }

        /// Puts an item in the channel.
        /// Blocks thread until it can add the item.
        pub fn put(
            self: *Self,
            io: std.Io,
            item: T,
        ) void {
            self.lock.lockUncancelable(io);
            defer {
                self.lock.unlock(io);
                self.readable.signal(io);
            }
            while (true) return self.fifo.pushBack(self.allocator, item) catch {
                self.writeable.waitUncancelable(io, &self.lock);
                continue;
            };
        }

        /// Tries to put in the channel. Will error if it can't.
        pub fn tryPut(
            self: *Self,
            io: std.Io,
            item: T,
        ) Allocator.Error!void {
            self.lock.lockUncancelable(io);
            defer self.lock.unlock(io);

            try self.fifo.pushBack(self.allocator, item);

            self.readable.signal(io);
        }

        /// Gets item from the channel. Blocks thread until it can get it.
        pub fn get(self: *Self, io: std.Io) T {
            self.lock.lockUncancelable(io);
            defer {
                self.lock.unlock(io);
                self.writeable.signal(io);
            }

            while (true) return self.fifo.popFront() orelse {
                self.readable.waitUncancelable(io, &self.lock);
                continue;
            };
        }

        /// Tries to get item from the channel.
        /// Returns null if there are no items.
        pub fn getOrNull(self: *Self, io: std.Io) ?T {
            self.lock.lockUncancelable(io);
            defer self.lock.unlock(io);

            if (self.fifo.popFront()) |item| return item;

            self.writeable.signal(io);

            return null;
        }
    };
}
