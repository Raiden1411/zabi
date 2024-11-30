const std = @import("std");

/// Types
const Allocator = std.mem.Allocator;
const Condition = std.Thread.Condition;
const LinearFifo = std.fifo.LinearFifo;
const Mutex = std.Thread.Mutex;

/// Channel used to manages the messages between threads.
/// Main use case is for the websocket client.
pub fn Channel(comptime T: type) type {
    return struct {
        lock: Mutex = .{},
        fifo: Fifo,
        writeable: Condition = .{},
        readable: Condition = .{},

        const Self = @This();
        const Fifo = LinearFifo(T, .Dynamic);

        /// Inits the channel.
        pub fn init(alloc: Allocator) Self {
            return .{ .fifo = Fifo.init(alloc) };
        }
        /// Frees the channel.
        /// If the list still has items with allocated
        /// memory this will not free them.
        pub fn deinit(self: *Self) void {
            self.fifo.deinit();
        }
        /// Puts an item in the channel.
        /// Blocks thread until it can add the item.
        pub fn put(self: *Self, item: T) void {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.readable.signal();
            }
            while (true) return self.fifo.writeItem(item) catch {
                self.writeable.wait(&self.lock);
                continue;
            };
        }
        /// Tries to put in the channel. Will error if it can't.
        pub fn tryPut(self: *Self, item: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            try self.fifo.writeItem(item);

            self.readable.signal();
        }
        /// Gets item from the channel. Blocks thread until it can get it.
        pub fn get(self: *Self) T {
            self.lock.lock();
            defer {
                self.lock.unlock();
                self.writeable.signal();
            }

            while (true) return self.fifo.readItem() orelse {
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

            while (true) return self.fifo.readItem() orelse {
                try self.readable.timedWait(&self.lock, 5 * std.time.ns_per_s);
                continue;
            };
        }
        /// Tries to get item from the channel.
        /// Returns null if there are no items.
        pub fn getOrNull(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.fifo.readItem()) |item| return item;

            self.writeable.signal();

            return null;
        }
    };
}
