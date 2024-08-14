const std = @import("std");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

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
/// of an `ArrayList`.
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
pub fn decodeAbiParameter(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) !AbiDecoded(T) {
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
        .Bool => {
            const bit = encoded[position + 31];

            if (bit > 1)
                return error.InvalidBitFound;

            return .{
                .consumed = 32,
                .data = bit != 0,
                .bytes_read = 32,
            };
        },
        .Int => |int_info| {
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
        .Optional => |opt_info| return decodeParameter(opt_info.child, allocator, encoded, position, options),
        .Enum => {
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
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                if (arr_info.len > 32)
                    @compileError("Invalid u8 array length. Expected lower than or equal to 32");

                const AsInt = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = arr_info.len * 8 } });

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
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
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
                .Slice => {
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

                    var list = std.ArrayList(ptr_info.child).init(allocator);
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
        .Struct => |struct_info| {
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

test "Bool" {
    try testDecodeRuntime(bool, "0000000000000000000000000000000000000000000000000000000000000001", true, .{});
    try testDecodeRuntime(bool, "0000000000000000000000000000000000000000000000000000000000000000", false, .{});
}

test "Uint/Int" {
    try testDecodeRuntime(u8, "0000000000000000000000000000000000000000000000000000000000000005", 5, .{});
    try testDecodeRuntime(u256, "0000000000000000000000000000000000000000000000000000000000010f2c", 69420, .{});
    try testDecodeRuntime(i256, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb", -5, .{});
    try testDecodeRuntime(i64, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a432eb", -123456789, .{});
}

test "Array bytes" {
    try testDecodeRuntime([20]u8, "0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", try utils.addressToBytes("0x4648451b5F87FF8F0F7D622bD40574bb97E25980"), .{});
    try testDecodeRuntime([5]u8, "0123456789000000000000000000000000000000000000000000000000000000", [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 }, .{ .bytes_endian = .little });
    try testDecodeRuntime([10]u8, "0123456789012345678900000000000000000000000000000000000000000000", [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 } ** 2, .{ .bytes_endian = .little });
}

test "Strings/Bytes" {
    try testDecodeRuntime([]const u8, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", "foo", .{});
    try testDecodeRuntime([]u8, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", @constCast(&[_]u8{ 0x66, 0x6f, 0x6f }), .{});
}

test "Errors" {
    var buffer: [4096]u8 = undefined;
    const bytes = try std.fmt.hexToBytes(&buffer, "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020");
    try testing.expectError(error.BufferOverrun, decodeAbiParameter([]const []const []const []const []const []const []const []const []const []const u256, testing.allocator, bytes, .{}));
}

test "Arrays" {
    try testDecodeRuntime(
        []const i256,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000",
        &[_]i256{ 4, 2, 0 },
        .{},
    );
    try testDecodeRuntime(
        [2]i256,
        "00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002",
        [2]i256{ 4, 2 },
        .{},
    );
    try testDecodeRuntime(
        [2][]const u8,
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000",
        [2][]const u8{ "foo", "bar" },
        .{},
    );
    try testDecodeRuntime(
        []const []const u8,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000",
        &[_][]const u8{ "foo", "bar" },
        .{},
    );
    try testDecodeRuntime(
        [3][2][]const u8,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626172000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000362617a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        [3][2][]const u8{ .{ "foo", "bar" }, .{ "baz", "boo" }, .{ "fizz", "buzz" } },
        .{},
    );
    try testDecodeRuntime(
        [2][]const []const u8,
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000666697a7a7a7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000362757a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000662757a7a7a7a0000000000000000000000000000000000000000000000000000",
        [2][]const []const u8{ &.{ "foo", "bar", "fizzzz", "buz" }, &.{ "fizz", "buzz", "buzzzz" } },
        .{},
    );
}

test "Structs" {
    try testDecodeRuntime(
        struct { bar: bool },
        "0000000000000000000000000000000000000000000000000000000000000001",
        .{ .bar = true },
        .{},
    );
    try testDecodeRuntime(
        struct { bar: struct { baz: bool } },
        "0000000000000000000000000000000000000000000000000000000000000001",
        .{ .bar = .{ .baz = true } },
        .{},
    );
    try testDecodeRuntime(
        struct { bar: bool, baz: u256, fizz: []const u8 },
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        .{ .bar = true, .baz = 69, .fizz = "buzz" },
        .{},
    );
    try testDecodeRuntime(
        []const struct { bar: bool, baz: u256, fizz: []const u8 },
        "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        &.{.{ .bar = true, .baz = 69, .fizz = "buzz" }},
        .{},
    );
}

test "Tuples" {
    try testDecodeRuntime(
        struct { u256, bool, []const i120 },
        "0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000001a40000000000000000000000000000000000000000000000000000000000010f2c",
        .{ 69, true, &[_]i120{ 69, 420, 69420 } },
        .{},
    );
    try testDecodeRuntime(
        struct { struct { foo: []const []const u8, bar: u256, baz: []const struct { fizz: []const []const u8, buzz: bool, jazz: []const i256 } } },
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000a45500000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001c666f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f00000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018424f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f00000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009",
        .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }},
        .{},
    );
}

// Testing functions.
fn testDecodeRuntime(comptime T: type, hex: []const u8, expected: T, options: DecodeOptions) !void {
    var buffer: [2048]u8 = undefined;

    const bytes = try std.fmt.hexToBytes(&buffer, hex);
    const decoded = try decodeAbiParameter(T, testing.allocator, bytes, options);
    defer decoded.deinit();

    try testInnerValues(expected, decoded.result);
}

fn testInnerValues(expected: anytype, actual: anytype) !void {
    if (@TypeOf(actual) == []const u8) {
        return try testing.expectEqualStrings(expected, actual);
    }

    const info = @typeInfo(@TypeOf(expected));
    if (info == .Pointer) {
        if (@typeInfo(info.Pointer.child) == .Struct) return try testInnerValues(expected[0], actual[0]);

        for (expected, actual) |e, a| {
            try testInnerValues(e, a);
        }
        return;
    }
    if (info == .Array) {
        for (expected, actual) |e, a| {
            try testInnerValues(e, a);
        }
        return;
    }

    if (info == .Struct) {
        inline for (info.Struct.fields) |field| {
            try testInnerValues(@field(expected, field.name), @field(actual, field.name));
        }
        return;
    }
    return try testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}
