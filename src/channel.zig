const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Channel(comptime T: type) type {
    return struct {
        lock: std.Thread.Mutex = .{},
        fifo: Fifo,
        writeable: std.Thread.Condition = .{},
        readable: std.Thread.Condition = .{},

        const Self = @This();
        const Fifo = std.fifo.LinearFifo(T, .Dynamic);

        pub fn init(alloc: Allocator) Self {
            return .{ .fifo = Fifo.init(alloc) };
        }

        pub fn deinit(self: *Self) void {
            self.fifo.deinit();
        }

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

        pub fn tryPut(self: *Self, item: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            try self.fifo.writeItem(item);

            self.readable.signal();
        }

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

        pub fn getOrNull(self: *Self) ?T {
            self.lock.lock();
            defer self.lock.unlock();

            if (self.fifo.readItem()) |item| return item;

            self.writeable.signal();
        }
    };
}
