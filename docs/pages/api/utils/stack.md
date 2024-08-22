## Stack
Stack implemented using a `ArrayList` and
with thread safety features added on to it.\
If memory is allocated on the stack items, `deinit`
will not clear all memory. You must clear them one by one.

## Init
Starts the stack but doesn't set an initial capacity.\
This is best to use when you would like a dymanic size stack.

## InitWithCapacity
Starts the stack and grows the capacity to the max size.\
This is best to use when you would like a static size stack.

## Deinit
Clears the stack.

## DupUnsafe
Duplicates an item from the stack. Appends it to the top.\
This is not thread safe.

## PushUnsafe
Appends an item to the stack.\
This is not thread safe.

## PopUnsafe
Pops an item off the stack.\
This is not thread safe.

## Push
Appends an item to the stack.\
This is thread safe and blocks until it can
append the item.

## Pop
Pops an item off the stack.\
This is thread safe and blocks until it can
remove the item.

## PopOrNull
Pops an item off the stack. Returns null if the stack is empty.\
This is thread safe,

## SwapToTopUnsafe
Swaps the top value of the stack with the different position.\
This is not thread safe.

## SwapUnsafe
Swap an item from the stack depending on the provided positions.\
This is not thread safe.

## TryPopUnsafe
Pops item from the stack. Returns `StackUnderflow` if it cannot.\
This is not thread safe,

## TryPop
Pops item from the stack. Returns `StackUnderflow` if it cannot.\
This is thread safe,

## TryPush
Pushes an item to the stack.\
This is thread safe,

## StackHeight
Returns the current stack size.

## AvailableSize
Returns number of items available in the stack

