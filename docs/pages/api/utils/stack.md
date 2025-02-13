## Stack
Stack implemented using a `ArrayList` and
with thread safety features added on to it.

If memory is allocated on the stack items, `deinit`
will not clear all memory. You must clear them one by one.

### Signature

```zig
pub fn Stack(comptime T: type) type
```

## Error

Set of possible errors while performing stack operations.

```zig
Allocator.Error || error{ StackOverflow, StackUnderflow }
```

## Init
Starts the stack but doesn't set an initial capacity.
This is best to use when you would like a dymanic size stack.

### Signature

```zig
pub fn init(
    allocator: Allocator,
    max_size: ?usize,
) Self
```

## InitWithCapacity
Starts the stack and grows the capacity to the max size.
This is best to use when you would like a static size stack.

### Signature

```zig
pub fn initWithCapacity(
    allocator: Allocator,
    max_size: usize,
) !Self
```

## Deinit
Clears the stack.

### Signature

```zig
pub fn deinit(self: *Self) void
```

## DupUnsafe
Duplicates an item from the stack. Appends it to the top.
This is not thread safe.

### Signature

```zig
pub fn dupUnsafe(
    self: *Self,
    position: usize,
) Self.Error!void
```

## PushUnsafe
Appends an item to the stack.
This is not thread safe.

### Signature

```zig
pub fn pushUnsafe(
    self: *Self,
    item: T,
) (Allocator.Error || error{StackOverflow})!void
```

## PopUnsafe
Pops an item off the stack.
This is not thread safe.

### Signature

```zig
pub fn popUnsafe(self: *Self) ?T
```

## Push
Appends an item to the stack.
This is thread safe and blocks until it can
append the item.

### Signature

```zig
pub fn push(
    self: *Self,
    item: T,
) void
```

## Pop
Pops an item off the stack.
This is thread safe and blocks until it can
remove the item.

### Signature

```zig
pub fn pop(self: *Self) T
```

## PopOrNull
Pops an item off the stack. Returns null if the stack is empty.
This is thread safe,

### Signature

```zig
pub fn popOrNull(self: *Self) ?T
```

## SwapToTopUnsafe
Swaps the top value of the stack with the different position.
This is not thread safe.

### Signature

```zig
pub fn swapToTopUnsafe(
    self: *Self,
    position_swap: usize,
) error{StackUnderflow}!void
```

## SwapUnsafe
Swap an item from the stack depending on the provided positions.
This is not thread safe.

### Signature

```zig
pub fn swapUnsafe(
    self: *Self,
    position: usize,
    swap: usize,
) error{StackUnderflow}!void
```

## TryPopUnsafe
Pops item from the stack. Returns `StackUnderflow` if it cannot.
This is not thread safe,

### Signature

```zig
pub fn tryPopUnsafe(
    self: *Self,
) error{StackUnderflow}!T
```

## TryPop
Pops item from the stack. Returns `StackUnderflow` if it cannot.
This is thread safe,

### Signature

```zig
pub fn tryPop(
    self: *Self,
    item: T,
) error{StackUnderflow}!T
```

## TryPush
Pushes an item to the stack.
This is thread safe,

### Signature

```zig
pub fn tryPush(
    self: *Self,
    item: T,
) !void
```

## StackHeight
Returns the current stack size.

### Signature

```zig
pub fn stackHeight(self: *Self) usize
```

## AvailableSize
Returns number of items available in the stack

### Signature

```zig
pub fn availableSize(self: Self) usize
```

## BoundedStack
Stack implementation based on the `std.BoundedArray`.

### Signature

```zig
pub fn BoundedStack(comptime size: usize) type
```

## Error

Set of possible errors while performing stack operations.

```zig
error{ StackOverflow, StackUnderflow }
```

## SwapToTopUnsafe
Swaps the top value of the stack with the different position.
This is not thread safe.

### Signature

```zig
pub fn swapToTopUnsafe(
    self: *Self,
    position_swap: usize,
) error{StackUnderflow}!void
```

## DupUnsafe
Duplicates an item from the stack. Appends it to the top.

This is not thread safe.

### Signature

```zig
pub fn dupUnsafe(
    self: *Self,
    position: usize,
) Self.Error!void
```

## PushUnsafe
Pops item from the stack. Returns `StackUnderflow` if it cannot.

This is not thread safe,

### Signature

```zig
pub fn pushUnsafe(
    self: *Self,
    item: u256,
) error{StackOverflow}!void
```

## AppendAssumeCapacity
Appends item to the inner buffer. Increments the `len` of this array.

### Signature

```zig
pub fn appendAssumeCapacity(
    self: *Self,
    item: u256,
) void
```

## EnsureUnusedCapacity
Ensures that the stack has enough room to grow.
Otherwise it returns `StackOverflow`.

### Signature

```zig
pub fn ensureUnusedCapacity(
    self: Self,
    grow: usize,
) error{StackOverflow}!void
```

## PopUnsafe
Pops item from the stack. Returns `null` if it cannot.
This is not thread safe,

### Signature

```zig
pub fn popUnsafe(self: *Self) ?u256
```

## TryPopUnsafe
Pops item from the stack. Returns `StackUnderflow` if it cannot.
This is not thread safe,

### Signature

```zig
pub fn tryPopUnsafe(self: *Self) error{StackUnderflow}!u256
```

## PopOrNull
Pops item from the stack.
Returns null if the `len` is 0.

### Signature

```zig
pub fn popOrNull(self: *Self) ?u256
```

## Pop
Pops item from the stack.

### Signature

```zig
pub fn pop(self: *Self) u256
```

## Peek
Peek the last element of the stack and returns it's pointer.

Returns null if len is 0;

### Signature

```zig
pub fn peek(self: *Self) ?*u256
```

## TryPeek
Peek the last element of the stack and returns it's pointer.

Returns `StackUnderflow` if len is 0;

### Signature

```zig
pub fn tryPeek(self: *Self) error{StackUnderflow}!*u256
```

## StackHeight
Returns the current stack size.

### Signature

```zig
pub fn stackHeight(self: *Self) usize
```

## AvailableSize
Returns number of items available in the stack

### Signature

```zig
pub fn availableSize(self: Self) usize
```

