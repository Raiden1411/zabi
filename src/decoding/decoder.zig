const std = @import("std");
const testing = std.testing;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Endian = std.builtin.Endian;

/// Set of possible errors when the decoder runs.
pub const DecoderErrors = error{ NoJunkDataAllowed, BufferOverrun, InvalidBitFound } || Allocator.Error;

/// Set of options to control the abi decoder behaviour.
pub const DecodeOptions = struct {
    /// Max amount of bytes allowed to be read by the decoder.
    /// This avoid a DoS vulnerability discovered here:
    /// https://github.com/paulmillr/micro-eth-signer/discussions/20
    max_bytes: u16 = 1024,
    /// By default this is false.
    allow_junk_data: bool = false,
    /// Tell the decoder if an allocation should be made.
    /// Allocations are always made if dealing with a type that will require a list i.e `[]const u64`.
    allocate_when: enum { alloc_always, alloc_if_needed } = .alloc_if_needed,
    /// Tells the endianess of the bytes that you want to decode
    /// Addresses are encoded in big endian and bytes1..32 are encoded in little endian.
    /// There might be some cases where you will need to decode a bytes20 and address at the same time.
    /// Since they can represent the same type it's advised to decode the address as `u160` and change this value to `little`.
    /// since it already decodes as big-endian and then `std.mem.writeInt` the value to the expected endianess.
    bytes_endian: Endian = .big,
};

/// Result type of decoded objects.
pub fn Decoded(comptime T: type) type {
    return struct {
        /// Bytes consumed on the slice.
        consumed: usize,
        /// Decoded data
        data: T,
        /// Total amount of bytes read from the slice.
        bytes_read: u16,
    };
}
/// Result type of a abi decoded slice. Allocations are managed via an arena.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn AbiDecoded(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        result: T,

        pub fn deinit(self: @This()) void {
            const child_allocator = self.arena.child_allocator;
            self.arena.deinit();

            child_allocator.destroy(self.arena);
        }
    };
}
/// Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.
/// Assumes that the encoded slice contains the function signature and removes it from the
/// encoded slice.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
/// const decoded =  try decodeAbiFunction([]const i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn decodeAbiFunction(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T) {
    return decodeAbiError(T, allocator, encoded, options);
}
/// Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.
/// Assumes that the encoded slice contracts the error signature and removes it from the
/// encoded slice.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
/// const decoded =  try decodeAbiError([]const i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn decodeAbiError(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T) {
    const slice = encoded[4..];

    return decodeAbiParameter(T, allocator, slice, options);
}
/// Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.
/// Since abi encoded function output values don't have signature in the encoded slice this is essentially a wrapper for `decodeAbiParameter`.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
/// const decoded =  try decodeAbiFunctionOutputs([]const i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn decodeAbiFunctionOutputs(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T) {
    return decodeAbiParameter(T, allocator, encoded, options);
}
/// Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.
/// Since abi encoded constructor values don't have signature in the encoded slice this is essentially a wrapper for `decodeAbiParameter`.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
/// const decoded =  try decodeAbiConstructor([]const i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn decodeAbiConstructor(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T) {
    return decodeAbiParameter(T, allocator, encoded, options);
}
/// Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.
/// This is usefull when you have to grab ownership of the memory from the slice or the type you need requires the creation
/// of an `array_list.Managed`.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
/// const decoded =  try decodeParameter([]const i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
///
/// If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.
pub fn decodeAbiParameter(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T) {
    const arena = try allocator.create(ArenaAllocator);
    errdefer allocator.destroy(arena);

    var res: AbiDecoded(T) = .{ .arena = arena, .result = undefined };

    res.arena.* = ArenaAllocator.init(allocator);
    errdefer res.arena.deinit();

    const decoded = try decodeAbiParameterLeaky(T, res.arena.allocator(), encoded, options);

    res.result = decoded;

    return res;
}
/// Decodes the abi encoded slice. This doesn't clean any allocated memory.
/// Usefull if the type that you want do decode to doesn't create any allocations or you already
/// own the memory that this will decode from. Otherwise you will be better off using `decodeAbiParameter`.
///
/// Allocations:
///     `Bool`, `Int`, `Enum`, `Array` => **false**.
///     `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.
///     `Optional` => Depends on the child.
///     `Struct` => Depends on the child.
///     Other types are not supported.
///
///
/// **Example:**
/// ```zig
/// var buffer: [1024]u8 = undefined;
/// const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002");
/// const decoded =  try decodeParameter([2]i256, testing.allocator, bytes, .{});
/// defer decoded.deinit();
/// ```
pub fn decodeAbiParameterLeaky(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!T {
    std.debug.assert(encoded.len > 31 and encoded.len & 1 == 0); // Not a hex string.

    const decoded = try decodeParameter(T, allocator, encoded, 0, options);

    if (decoded.consumed >= options.max_bytes)
        return error.BufferOverrun;

    if (!options.allow_junk_data and encoded.len > decoded.bytes_read)
        return error.NoJunkDataAllowed;

    return decoded.data;
}
/// Internal function that is used to parse encoded abi values.
fn decodeParameter(comptime T: type, allocator: Allocator, encoded: []u8, position: usize, options: DecodeOptions) DecoderErrors!Decoded(T) {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            const bit = encoded[position + 31];

            if (bit > 1)
                return error.InvalidBitFound;

            return .{
                .consumed = 32,
                .data = bit != 0,
                .bytes_read = 32,
            };
        },
        .int => |int_info| {
            const bytes = encoded[position .. position + 32];

            const number = switch (int_info.signedness) {
                .signed => std.mem.readInt(i256, @ptrCast(bytes), .big),
                .unsigned => std.mem.readInt(u256, @ptrCast(bytes), .big),
            };

            return .{
                .consumed = 32,
                .data = if (number > std.math.maxInt(T)) std.math.maxInt(T) else @truncate(number),
                .bytes_read = 32,
            };
        },
        .optional => |opt_info| return decodeParameter(opt_info.child, allocator, encoded, position, options),
        .@"enum" => {
            const offset: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[position .. position + 32]), .big));
            const length: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[offset .. offset + 32]), .big));

            const slice = encoded[offset + 32 .. offset + 32 + length];
            const remainder = length % 32;
            const padded = length + 32 - remainder;

            return .{
                .consumed = 32,
                .data = std.meta.stringToEnum(T, slice),
                .bytes_read = @intCast(padded + 64),
            };
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                if (arr_info.len > 32)
                    @compileError("Invalid u8 array length. Expected lower than or equal to 32");

                const AsInt = @Type(.{ .int = .{ .signedness = .unsigned, .bits = arr_info.len * 8 } });

                const slice = encoded[position .. position + 32];
                var result: T = undefined;

                const as_number = std.mem.readInt(u256, @ptrCast(slice), options.bytes_endian);
                std.mem.writeInt(AsInt, &result, @truncate(as_number), options.bytes_endian);

                return .{
                    .consumed = 32,
                    .data = result,
                    .bytes_read = 32,
                };
            }

            if (utils.isDynamicType(T)) {
                const offset: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[position .. position + 32]), .big));

                var pos: usize = 0;
                var read: u16 = 0;

                var result: T = undefined;

                for (0..arr_info.len) |i| {
                    const decoded = try decodeParameter(arr_info.child, allocator, encoded[offset..], pos, options);

                    pos += decoded.consumed;
                    result[i] = decoded.data;
                    read += decoded.bytes_read;

                    if (pos >= options.max_bytes)
                        return error.BufferOverrun;
                }

                return .{
                    .consumed = 32,
                    .data = result,
                    .bytes_read = read + 32,
                };
            }

            var pos: usize = 0;
            var read: u16 = 0;

            var result: T = undefined;
            for (0..arr_info.len) |i| {
                const decoded = try decodeParameter(arr_info.child, allocator, encoded, pos + position, options);

                pos += decoded.consumed;
                result[i] = decoded.data;
                read += decoded.bytes_read;

                if (pos > options.max_bytes)
                    return error.BufferOverrun;
            }

            return .{
                .consumed = 32,
                .data = result,
                .bytes_read = read,
            };
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
                    const value = try allocator.create(ptr_info.child);
                    errdefer allocator.destroy(value);

                    const decoded = try decodeParameter(ptr_info.child, allocator, encoded, position, options);
                    value.* = decoded.data;

                    return .{
                        .consumed = decoded.consumed,
                        .data = value,
                        .bytes_read = decoded.bytes_read,
                    };
                },
                .slice => {
                    if (ptr_info.child == u8) {
                        const offset: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[position .. position + 32]), .big));
                        const length: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[offset .. offset + 32]), .big));

                        const slice = encoded[offset + 32 .. offset + 32 + length];
                        const remainder = length % 32;
                        const padded = length + 32 - remainder;

                        const data = if (options.allocate_when == .alloc_always) try allocator.dupe(u8, slice) else slice;

                        return .{
                            .consumed = 32,
                            .data = data,
                            .bytes_read = @intCast(padded + 64),
                        };
                    }

                    const offset: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[position .. position + 32]), .big));
                    const length: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[offset .. offset + 32]), .big));

                    var pos: usize = 0;
                    var read: u16 = 0;

                    var list = std.array_list.Managed(ptr_info.child).init(allocator);
                    errdefer list.deinit();

                    for (0..length) |_| {
                        const decoded = try decodeParameter(ptr_info.child, allocator, encoded[offset + 32 ..], pos, options);

                        pos += decoded.consumed;
                        read += decoded.bytes_read;

                        if (pos >= options.max_bytes)
                            return error.BufferOverrun;

                        try list.append(decoded.data);
                    }

                    return .{
                        .consumed = 32,
                        .data = try list.toOwnedSlice(),
                        .bytes_read = read + 64,
                    };
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(T)),
            }
        },
        .@"struct" => |struct_info| {
            var result: T = undefined;

            var pos: usize = 0;
            var read: u16 = 0;

            if (struct_info.is_tuple) {
                inline for (struct_info.fields) |field| {
                    const decoded = try decodeParameter(field.type, allocator, encoded, pos + position, options);

                    pos += decoded.consumed;
                    read += decoded.bytes_read;

                    if (pos >= options.max_bytes)
                        return error.BufferOverrun;

                    @field(result, field.name) = decoded.data;
                }

                return .{
                    .consumed = 32,
                    .data = result,
                    .bytes_read = read,
                };
            }

            if (utils.isDynamicType(T)) {
                const offset: usize = @truncate(std.mem.readInt(u256, @ptrCast(encoded[position .. position + 32]), .big));

                inline for (struct_info.fields) |field| {
                    const decoded = try decodeParameter(field.type, allocator, encoded[offset..], pos, options);

                    pos += decoded.consumed;
                    read += decoded.bytes_read;

                    if (pos >= options.max_bytes)
                        return error.BufferOverrun;

                    @field(result, field.name) = decoded.data;
                }

                return .{
                    .consumed = 32,
                    .data = result,
                    .bytes_read = read + 32,
                };
            }

            inline for (struct_info.fields) |field| {
                const decoded = try decodeParameter(field.type, allocator, encoded, pos + position, options);

                pos += decoded.consumed;
                read += decoded.bytes_read;

                if (pos >= options.max_bytes)
                    return error.BufferOverrun;

                @field(result, field.name) = decoded.data;
            }

            return .{
                .consumed = 32,
                .data = result,
                .bytes_read = read,
            };
        },

        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}
