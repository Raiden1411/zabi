const std = @import("std");
const testing = std.testing;

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

/// Similar to std.json.Parsed(T)
pub fn Generated(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        generated: T,

        pub fn deinit(self: @This()) void {
            const child_allocator = self.arena.child_allocator;

            self.arena.deinit();

            child_allocator.destroy(self.arena);
        }
    };
}

/// Controls some of the behaviour for the generator.
///
/// More options can be added in the future to alter
/// further this behaviour.
pub const GenerateOptions = struct {
    /// Control the size of the slice that you want to create.
    slice_size: ?usize = null,
    /// If the provided type is consider a potential "string"
    /// Tell the generator to use only ascii letter bytes and
    /// if you want lower or uppercase chars
    ascii: struct {
        use_on_arrays_and_slices: bool = false,
        format_bytes: enum { lowercase, uppercase } = .lowercase,
    } = .{},
    /// Tell the generator to use the types default values.
    use_default_values: bool = false,
};

/// Generate pseudo random data for the provided type. Creates an
/// arena for all allocations. Similarly to how std.json works.
///
/// This works on most zig types with a few expections of course.
pub fn generateRandomData(comptime T: type, allocator: Allocator, seed: u64, opts: GenerateOptions) Allocator.Error!Generated(T) {
    var generated: Generated(T) = .{ .arena = try allocator.create(ArenaAllocator), .generated = undefined };
    errdefer allocator.destroy(generated.arena);

    generated.arena.* = ArenaAllocator.init(allocator);
    errdefer generated.arena.deinit();

    generated.generated = try generateRandomDataLeaky(T, generated.arena.allocator(), seed, opts);

    return generated;
}
/// Generate pseudo random data for provided type. Nothing is freed
/// from the result so it's best to use something like an arena allocator or similar
/// to free the memory all at once.
///
/// This is done because we might have
/// types where there will be deeply nested allocatations that can
/// be cumbersome to free.
///
/// This works on most zig types with a few expections of course.
pub fn generateRandomDataLeaky(comptime T: type, allocator: Allocator, seed: u64, opts: GenerateOptions) Allocator.Error!T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            var rand = std.Random.DefaultPrng.init(seed);
            return rand.random().boolean();
        },
        .int => {
            var rand = std.Random.DefaultPrng.init(seed);
            const num = rand.random().int(T);

            return num;
        },
        .float => {
            var rand = std.Random.DefaultPrng.init(seed);
            const num = rand.random().float(T);

            return num;
        },
        .optional => |optional_child| {
            // Multiplies the seed based on the size of the child type.
            var rand = std.Random.DefaultPrng.init(seed * if (@sizeOf(optional_child.child) > 0) @sizeOf(optional_child.child) else 1);

            // Let the randomizer decide if we return null or not
            return if (rand.random().boolean()) null else try generateRandomDataLeaky(optional_child.child, allocator, seed, opts);
        },
        .@"enum" => {
            var rand = std.Random.DefaultPrng.init(seed);
            const value = rand.random().enumValue(T);

            return value;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null)
                @compileError("Unable to generate random data for untagged union'" ++ @typeName(T) ++ "'");

            comptime assert(union_info.fields.len > 0); // Cannot return from empty;

            // Gets a random index of the union fields and returns it as the active field.
            const field = comptime field: {
                if (union_info.fields.len == 1) break :field union_info.fields[0];

                var rand = std.Random.DefaultPrng.init(union_info.fields.len);
                const index = rand.random().uintLessThan(usize, union_info.fields.len);

                const active_field = union_info.fields[index];

                for (union_info.fields) |field| {
                    if (std.mem.eql(u8, field.name, active_field.name))
                        break :field active_field;
                } else @compileError("Invalid union type");
            };

            return @unionInit(T, field.name, try generateRandomDataLeaky(field.type, allocator, seed, opts));
        },
        .@"struct" => |struct_info| {
            comptime assert(struct_info.fields.len > 0); // Cannot return from empty;

            var result: T = undefined;
            var rand = std.Random.DefaultPrng.init(seed);

            inline for (struct_info.fields) |field| {
                const default = convertDefaultValueType(field);

                if (default) |default_value| {
                    if (opts.use_default_values) {
                        @field(result, field.name) = default_value;
                    } else {
                        // Gets a new seed foreach element.
                        @field(result, field.name) = try generateRandomDataLeaky(field.type, allocator, rand.random().int(u32), opts);
                    }
                } else {
                    // Gets a new seed foreach element.
                    @field(result, field.name) = try generateRandomDataLeaky(field.type, allocator, rand.random().int(u32), opts);
                }
            }

            return result;
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const pointer = try allocator.create(ptr_info.child);
                    errdefer allocator.destroy(pointer);

                    pointer.* = try generateRandomDataLeaky(ptr_info.child, allocator, seed, opts);

                    return pointer;
                },
                .Slice => {
                    var list = std.ArrayList(ptr_info.child).init(allocator);
                    errdefer list.deinit();

                    var rand = std.Random.DefaultPrng.init(seed);
                    const size = opts.slice_size orelse while (true) {
                        const rand_size = rand.random().int(u8);

                        if (rand_size == 0)
                            continue;

                        break rand_size;
                    };

                    assert(size > 0); // Cannot write to empty array.

                    if (ptr_info.child == u8) {
                        if (opts.ascii.use_on_arrays_and_slices) {
                            var writer = list.writer();

                            for (0..size) |i| {
                                rand.seed(size * (i + 1));

                                const char = switch (opts.ascii.format_bytes) {
                                    .lowercase => rand.random().intRangeAtMost(u8, 'a', 'z'),
                                    .uppercase => rand.random().intRangeAtMost(u8, 'A', 'Z'),
                                };

                                assert(std.ascii.isAlphabetic(char));

                                try writer.writeByte(char);
                            }

                            return list.toOwnedSlice();
                        }

                        // Expand the list to the size
                        // and use the items as the buffer
                        // to get the random bytes.
                        try list.ensureUnusedCapacity(size);
                        rand.random().bytes(list.items);

                        return list.toOwnedSlice();
                    }

                    for (0..size) |i| {
                        try list.ensureUnusedCapacity(1);
                        // Gets a new seed for each element.
                        list.appendAssumeCapacity(try generateRandomDataLeaky(ptr_info.child, allocator, size * (i + seed), opts));
                    }

                    return list.toOwnedSlice();
                },
                else => @compileError("Unsupported pointer type '" ++ @typeName(T) ++ "'"),
            }
        },
        .vector => |vec_info| {
            comptime assert(vec_info.len > 0); // Cannot return empty vec

            var result: T = undefined;
            var rand = std.Random.DefaultPrng.init(seed);

            for (0..vec_info.len) |i| {
                // Lets generate a new seed for each one.
                const new_seed = rand.random().int(u64);

                result[i] = try generateRandomDataLeaky(vec_info.child, allocator, new_seed, opts);
            }

            return result;
        },
        .array => |arr_info| {
            comptime assert(arr_info.len > 0); // Cannot return empty arr

            var result: T = undefined;
            var rand = std.Random.DefaultPrng.init(seed);

            if (arr_info.child == u8) {
                if (opts.ascii.use_on_arrays_and_slices) {
                    for (0..arr_info.len) |i| {
                        const char = switch (opts.ascii.format_bytes) {
                            .lowercase => rand.random().intRangeAtMost(u8, 'a', 'z'),
                            .uppercase => rand.random().intRangeAtMost(u8, 'A', 'Z'),
                        };

                        assert(std.ascii.isAlphabetic(char));

                        result[i] = char;
                    }

                    return result;
                }

                rand.random().bytes(result[0..]);

                return result;
            }

            for (0..arr_info.len) |i| {
                // Lets generate a new seed for each one.
                const new_seed = rand.random().int(u64);

                result[i] = try generateRandomDataLeaky(arr_info.child, allocator, new_seed, opts);
            }

            return result;
        },
        .void => return {},
        .null => return null,
        else => @compileError("Unsupported type '" ++ @typeName(T) ++ "'"),
    }
}

fn convertDefaultValueType(comptime field: std.builtin.Type.StructField) ?field.type {
    return if (field.default_value) |opaque_value|
        @as(*const field.type, @ptrCast(@alignCast(opaque_value))).*
    else
        null;
}
