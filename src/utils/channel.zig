const std = @import("std");

/// Types
const Allocator = std.mem.Allocator;
const Condition = std.Thread.Condition;
const Deque = std.Deque;
const Mutex = std.Thread.Mutex;

/// Channel used to manages the messages between threads.
/// Main use case is for the websocket client.
pub fn Channel(comptime T: type) type {
    return struct {
        allocator: Allocator,
        fifo: Deque(T) = .empty,
        lock: Mutex = .{},
        readable: Condition = .{},
        writeable: Condition = .{},

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
            item: T,
        ) void {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.readable.signal();
            }
            while (true) return self.fifo.pushBack(self.allocator, item) catch {
                self.writeable.wait(&self.lock);
                continue;
            };
        }

        /// Tries to put in the channel. Will error if it can't.
        pub fn tryPut(
            self: *Self,
            item: T,
        ) Allocator.Error!void {
            self.lock.lock();
            defer self.lock.unlock();

            try self.fifo.pushBack(self.allocator, item);

            self.readable.signal();
        }

        /// Gets item from the channel. Blocks thread until it can get it.
        pub fn get(self: *Self) T {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.writeable.signal();
            }

            while (true) return self.fifo.popFront() orelse {
                self.readable.wait(&self.lock);
                continue;
            };
        }

        /// Gets item from the channel.
        ///
        /// Wait with a maximum of 1ms to get a message.
        /// If it cannot get the it fails.
        pub fn tryGet(self: *Self) error{Timeout}!T {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.writeable.signal();
            }

            while (true) return self.fifo.popFront() orelse {
                try self.readable.timedWait(&self.lock, 5 * std.time.ns_per_s);
                continue;
            };
        }

        /// Tries to get item from the channel.
        /// Returns null if there are no items.
        pub fn getOrNull(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.fifo.popFront()) |item| return item;

            self.writeable.signal();

            return null;
        }
    };
}
