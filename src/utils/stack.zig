const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Condition = std.Thread.Condition;
const Mutex = std.Thread.Mutex;

/// Stack implemented using a `ArrayList` and
/// with thread safety features added on to it.
///
/// If memory is allocated on the stack items, `deinit`
/// will not clear all memory. You must clear them one by one.
pub fn Stack(comptime T: type) type {
    return struct {
        const Self = Stack(T);

        /// Inner arraylist used to manage the stack
        inner: ArrayList(T),
        /// Max size that the stack grow to
        max_size: usize,
        mutex: Mutex = .{},
        writeable: Condition = .{},
        readable: Condition = .{},

        /// Starts the stack but doesn't set an initial capacity.
        /// This is best to use when you would like a dymanic size stack.
        pub fn init(allocator: Allocator, max_size: ?usize) Self {
            const list = ArrayList(T).init(allocator);

            return .{
                .inner = list,
                .max_size = max_size orelse std.math.maxInt(usize),
            };
        }
        /// Starts the stack and grows the capacity to the max size.
        /// This is best to use when you would like a static size stack.
        pub fn initWithCapacity(allocator: Allocator, max_size: usize) !Self {
            const list = try ArrayList(T).initCapacity(allocator, max_size);

            return .{
                .inner = list,
                .max_size = max_size,
            };
        }
        /// Clears the stack.
        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }
        /// Duplicates an item from the stack. Appends it to the top.
        /// This is not thread safe.
        pub fn dupUnsafe(self: *Self, position: usize) !void {
            if (self.inner.items.len < position)
                return error.StackUnderflow;

            const item = self.inner.items[self.inner.items.len - position];
            try self.pushUnsafe(item);
        }
        /// Appends an item to the stack.
        /// This is not thread safe.
        pub fn pushUnsafe(self: *Self, item: T) !void {
            if (self.inner.items.len > self.availableSize())
                return error.StackOverflow;

            try self.inner.ensureUnusedCapacity(1);
            self.inner.appendAssumeCapacity(item);
        }
        /// Pops an item off the stack.
        /// This is not thread safe.
        pub fn popUnsafe(self: *Self) ?T {
            return self.inner.popOrNull();
        }
        /// Appends an item to the stack.
        /// This is thread safe and blocks until it can
        /// append the item.
        pub fn push(self: *Self, item: T) void {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
                self.readable.signal();
            }

            while (true) return self.pushUnsafe(item) catch {
                self.writeable.wait(&self.mutex);
                continue;
            };
        }
        /// Pops an item off the stack.
        /// This is thread safe and blocks until it can
        /// remove the item.
        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
                self.writeable.signal();
            }

            while (true) return self.popUnsafe() orelse {
                self.readable.wait(&self.mutex);
                continue;
            };
        }
        /// Pops an item off the stack. Returns null if the stack is empty.
        /// This is thread safe,
        pub fn popOrNull(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.inner.popOrNull()) |item| return item;

            self.writeable.signal();

            return null;
        }
        /// Swaps the top value of the stack with the different position.
        /// This is not thread safe.
        pub fn swapToTopUnsafe(self: *Self, position_swap: usize) !void {
            if (self.inner.items.len < position_swap)
                return error.StackUnderflow;

            const top = self.inner.items[self.inner.items.len - 1];
            const second = self.inner.items[self.inner.items.len - position_swap];

            self.inner.items[self.inner.items.len - 1] = second;
            self.inner.items[self.inner.items.len - position_swap] = top;
        }
        /// Swap an item from the stack depending on the provided positions.
        /// This is not thread safe.
        pub fn swapUnsafe(self: *Self, position: usize, swap: usize) !void {
            std.debug.assert(swap > 0); // Overlapping swap;

            const second_position = position + swap;
            if (second_position >= self.inner.items.len)
                return error.StackUnderflow;

            const first = self.inner.items[position];
            const second = self.inner.items[second_position];

            self.inner.items[position] = second;
            self.inner.items[second_position] = first;
        }
        /// Pushes an item to the stack.
        /// This is thread safe,
        pub fn tryPush(self: *Self, item: T) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.pushUnsafe(item);

            self.readable.signal();
        }
        /// Returns the current stack size.
        pub fn stackHeight(self: *Self) usize {
            return self.inner.items.len;
        }
        /// Returns number of items available in the stack
        pub fn availableSize(self: Self) usize {
            return self.max_size - self.inner.items.len;
        }
    };
}
