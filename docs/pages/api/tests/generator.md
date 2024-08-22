## Generated
Similar to std.json.Parsed(T)

## Deinit

## GenerateOptions
Controls some of the behaviour for the generator.\
More options can be added in the future to alter
further this behaviour.

## GenerateRandomData
Generate pseudo random data for the provided type. Creates an
arena for all allocations. Similarly to how std.json works.\
This works on most zig types with a few expections of course.

## GenerateRandomDataLeaky
Generate pseudo random data for provided type. Nothing is freed
from the result so it's best to use something like an arena allocator or similar
to free the memory all at once.\
This is done because we might have
types where there will be deeply nested allocatations that can
be cumbersome to free.\
This works on most zig types with a few expections of course.

