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
        const Self = @This();

        /// Set of possible errors while performing stack operations.
        pub const Error = Allocator.Error || error{ StackOverflow, StackUnderflow };

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
        pub fn dupUnsafe(self: *Self, position: usize) Self.Error!void {
            if (self.inner.items.len < position)
                return error.StackUnderflow;

            const item = self.inner.items[self.inner.items.len - position];
            try self.pushUnsafe(item);
        }
        /// Appends an item to the stack.
        /// This is not thread safe.
        pub fn pushUnsafe(self: *Self, item: T) (Allocator.Error || error{StackOverflow})!void {
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

            if (self.popUnsafe()) |item| return item;

            self.writeable.signal();

            return null;
        }
        /// Swaps the top value of the stack with the different position.
        /// This is not thread safe.
        pub fn swapToTopUnsafe(self: *Self, position_swap: usize) error{StackUnderflow}!void {
            if (self.inner.items.len < position_swap)
                return error.StackUnderflow;

            const top = self.inner.items.len - 1;
            const second = top - position_swap;

            self.inner.items[top] ^= self.inner.items[second];
            self.inner.items[second] ^= self.inner.items[top];
            self.inner.items[top] ^= self.inner.items[second];
        }
        /// Swap an item from the stack depending on the provided positions.
        /// This is not thread safe.
        pub fn swapUnsafe(self: *Self, position: usize, swap: usize) error{StackUnderflow}!void {
            std.debug.assert(swap > 0); // Overlapping swap;

            const second_position = position + swap;
            if (second_position >= self.inner.items.len)
                return error.StackUnderflow;

            const first = self.inner.items[position];
            const second = self.inner.items[second_position];

            self.inner.items[position] = second;
            self.inner.items[second_position] = first;
        }
        /// Pops item from the stack. Returns `StackUnderflow` if it cannot.
        /// This is not thread safe,
        pub fn tryPopUnsafe(self: *Self) error{StackUnderflow}!T {
            return self.popUnsafe() orelse error.StackUnderflow;
        }
        /// Pops item from the stack. Returns `StackUnderflow` if it cannot.
        /// This is thread safe,
        pub fn tryPop(self: *Self, item: T) error{StackUnderflow}!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.popUnsafe(item) orelse error.StackUnderflow;

            self.writeable.signal();
        }
        /// Pushes an item to the stack.
        /// This is thread safe,
        pub fn tryPush(self: *Self, item: T) !void {
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

/// Stack implementation based on the `std.BoundedArray`.
pub fn BoundedStack(comptime size: usize) type {
    return struct {
        const Self = @This();

        /// Set of possible errors while performing stack operations.
        pub const Error = error{ StackOverflow, StackUnderflow };

        /// Inner buffer that will hold the stack items.
        inner: [size]u256 = undefined,
        /// Stack size.
        len: usize,

        /// Swaps the top value of the stack with the different position.
        /// This is not thread safe.
        pub fn swapToTopUnsafe(self: *Self, position_swap: usize) error{StackUnderflow}!void {
            if (self.inner.len < position_swap) {
                @branchHint(.unlikely);
                return error.StackUnderflow;
            }

            const top = self.len - 1;
            const second = top - position_swap;

            self.inner[top] ^= self.inner[second];
            self.inner[second] ^= self.inner[top];
            self.inner[top] ^= self.inner[second];
        }
        /// Duplicates an item from the stack. Appends it to the top.
        /// This is not thread safe.
        pub fn dupUnsafe(self: *Self, position: usize) Self.Error!void {
            if (self.inner.len < position)
                return error.StackUnderflow;

            const item = self.inner[self.len - position];
            try self.pushUnsafe(item);
        }
        /// Pops item from the stack. Returns `StackUnderflow` if it cannot.
        /// This is not thread safe,
        pub fn pushUnsafe(self: *Self, item: u256) error{StackOverflow}!void {
            try self.ensureUnusedCapacity(1);
            self.appendAssumeCapacity(item);
        }
        /// Appends item to the inner buffer. Increments the `len` of this array.
        pub fn appendAssumeCapacity(self: *Self, item: u256) void {
            std.debug.assert(self.len < size);

            self.len += 1;
            self.inner[self.len - 1] = item;
        }
        /// Ensures that the stack has enough room to grow.
        /// Otherwise it returns `StackOverflow`.
        pub fn ensureUnusedCapacity(self: Self, grow: usize) error{StackOverflow}!void {
            if (self.len + grow > size) {
                @branchHint(.unlikely);
                return error.StackOverflow;
            }
        }
        /// Pops item from the stack. Returns `null` if it cannot.
        /// This is not thread safe,
        pub fn popUnsafe(self: *Self) ?u256 {
            return self.popOrNull();
        }
        /// Pops item from the stack. Returns `StackUnderflow` if it cannot.
        /// This is not thread safe,
        pub fn tryPopUnsafe(self: *Self) error{StackUnderflow}!u256 {
            return self.popOrNull() orelse error.StackUnderflow;
        }
        /// Pops item from the stack.
        /// Returns null if the `len` is 0.
        pub fn popOrNull(self: *Self) ?u256 {
            return if (self.len == 0) null else self.pop();
        }
        /// Pops item from the stack.
        pub fn pop(self: *Self) u256 {
            const item = self.inner[self.len - 1];
            self.len -= 1;

            return item;
        }
        /// Peek the last element of the stack and returns it's pointer.
        /// Returns null if len is 0;
        pub fn peek(self: *Self) ?*u256 {
            if (self.len == 0)
                return null;

            return &self.inner[self.len - 1];
        }
        /// Peek the last element of the stack and returns it's pointer.
        /// Returns `StackUnderflow` if len is 0;
        pub fn tryPeek(self: *Self) error{StackUnderflow}!*u256 {
            return self.peek() orelse error.StackUnderflow;
        }
        /// Returns the current stack size.
        pub fn stackHeight(self: *Self) usize {
            return self.len;
        }
        /// Returns number of items available in the stack
        pub fn availableSize(self: Self) usize {
            return self.inner.len - self.len;
        }
    };
}
