const abi = @import("../abi/abi.zig");
const std = @import("std");
const meta = @import("../meta/meta.zig");
const testing = std.testing;
const types = @import("../meta/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AbiParameter = @import("../abi/abi_parameter.zig").AbiParameter;
const AbiParameterToPrimative = meta.AbiParameterToPrimative;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const Address = types.Address;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Constructor = abi.Constructor;
const Error = abi.Error;
const Function = abi.Function;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const ParamType = @import("../abi/param_type.zig").ParamType;

pub fn Decoded(comptime T: type) type {
    return struct { consumed: usize, data: T, bytes_read: u16 };
}

pub fn AbiDecoded(comptime params: []const AbiParameter) type {
    return struct {
        arena: *ArenaAllocator,
        values: AbiParametersToPrimative(params),

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();

            allocator.destroy(self.arena);
        }
    };
}

pub fn AbiDecodedRuntime(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .Struct and !info.Struct.is_tuple)
        @compileError("Expected tuple return type");

    return struct {
        arena: *ArenaAllocator,
        values: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();

            allocator.destroy(self.arena);
        }
    };
}

pub fn AbiSignatureDecoded(comptime params: []const AbiParameter) type {
    return struct {
        arena: *ArenaAllocator,
        name: []const u8,
        values: AbiParametersToPrimative(params),

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();

            allocator.destroy(self.arena);
        }
    };
}

pub fn AbiSignatureDecodedRuntime(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        name: []const u8,
        values: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();

            allocator.destroy(self.arena);
        }
    };
}

pub const DecodeOptions = struct {
    /// Max amount of bytes allowed to be read by the decoder.
    /// This avoid a DoS vulnerability discovered here:
    /// https://github.com/paulmillr/micro-eth-signer/discussions/20
    max_bytes: u16 = 1024,
    /// By default this is false.
    allow_junk_data: bool = false,
};

pub const DecodedErrors = error{ InvalidBits, InvalidEnumType, InvalidAbiParameter, InvalidSignedness, InvalidArraySize, JunkData, InvalidAbiSignature, BufferOverrun, InvalidLength, NoSpaceLeft, InvalidDecodeDataSize } || Allocator.Error || std.fmt.ParseIntError;

/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiFunctionRuntime(allocator: Allocator, comptime T: type, function: Function, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecodedRuntime(T) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try function.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
        return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and function.inputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParametersRuntime(allocator, T, function.inputs, data, opts);

    return .{ .arena = decoded.arena, .name = function.name, .values = decoded.values };
}
/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiFunctionOutputsRuntime(allocator: Allocator, comptime T: type, function: Function, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecodedRuntime(T) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try function.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
        return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and function.outputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParametersRuntime(allocator, T, function.outputs, data, opts);

    return .{ .arena = decoded.arena, .name = function.name, .values = decoded.values };
}
/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiErrorRuntime(allocator: Allocator, comptime T: type, err: Error, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecodedRuntime(T) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try err.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
        return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and err.inputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParametersRuntime(allocator, T, err.inputs, data, opts);

    return .{ .arena = decoded.arena, .name = err.name, .values = decoded.values };
}
/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiConstructorRuntime(allocator: Allocator, comptime T: type, constructor: Constructor, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecodedRuntime(T) {
    const decoded = try decodeAbiParametersRuntime(allocator, T, constructor.inputs, hex, opts);

    return .{ .arena = decoded.arena, .name = "", .values = decoded.values };
}
/// Main function that will be used to decode the hex values based on the abi paramters.
/// This will allocate and a ArenaAllocator will be used to manage the memory.
///
/// Caller owns the memory.
///
/// If the abi parameters are comptime know use `decodeAbiParameters`
pub fn decodeAbiParametersRuntime(allocator: Allocator, comptime T: type, params: []const AbiParameter, hex: []const u8, opts: DecodeOptions) !AbiDecodedRuntime(T) {
    var decoded: AbiDecodedRuntime(T) = .{ .arena = try allocator.create(ArenaAllocator), .values = undefined };
    errdefer allocator.destroy(decoded.arena);

    decoded.arena.* = ArenaAllocator.init(allocator);
    errdefer decoded.arena.deinit();

    const arena_allocator = decoded.arena.allocator();
    decoded.values = try decodeAbiParametersLeakyRuntime(arena_allocator, T, params, hex, opts);

    return decoded;
}
/// Subset function used for decoding. Its highly recommend to use an ArenaAllocator
/// or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
/// and with those all of the memory can be freed at once.
///
/// Caller owns the memory.
///
/// If the abi parameters are comptime know use `decodeAbiParametersLeaky`
pub fn decodeAbiParametersLeakyRuntime(allocator: Allocator, comptime T: type, params: []const AbiParameter, hex: []const u8, opts: DecodeOptions) !T {
    const info = @typeInfo(T);

    if (info != .Struct and !info.Struct.is_tuple)
        @compileError("Expected tuple return type");

    if (params.len == 0) {
        if (info.Struct.fields.len == 0)
            return .{};

        return error.InvalidLength;
    }

    std.debug.assert(hex.len > 63 and hex.len % 2 == 0);

    const hex_buffer = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;
    const buffer = try allocator.alloc(u8, @divExact(hex_buffer.len, 2));
    const bytes = try std.fmt.hexToBytes(buffer, hex_buffer);

    return try decodeItems(allocator, T, params, bytes, opts);
}
/// Reflects on the provided type and decodes based on it
/// and also based on the provided `[]const AbiParameter`
fn decodeItems(allocator: Allocator, comptime T: type, params: []const AbiParameter, hex: []u8, opts: DecodeOptions) !T {
    const info = @typeInfo(T).Struct.fields;
    var pos: usize = 0;
    var read: u16 = 0;

    var result: T = undefined;

    if (info.len != params.len)
        return error.InvalidLength;

    inline for (info, 0..) |field, i| {
        const decoded = try decodeItem(allocator, field.type, params[i], hex, pos, opts);
        pos += decoded.consumed;
        result[i] = decoded.data;
        read += decoded.bytes_read;

        if (pos > opts.max_bytes)
            return error.BufferOverrun;
    }

    if (!opts.allow_junk_data and hex.len > read)
        return error.JunkData;

    return result;
}
/// Reflects on the provided type and decodes based on it
/// and also based on the provided `[]const AbiParameter`
fn decodeItem(allocator: Allocator, comptime T: type, param: AbiParameter, hex: []u8, position: usize, opts: DecodeOptions) !Decoded(T) {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => {
            const decoded = switch (param.type) {
                .bool => try decodeBool(hex, position),
                else => return error.InvalidAbiParameter,
            };

            if (decoded.bytes_read > opts.max_bytes)
                return error.BufferOverrun;

            return decoded;
        },
        .Int => |int_info| {
            const decoded = switch (param.type) {
                .uint => |bits| if (int_info.signedness == .signed) return error.InvalidSignedness else if (int_info.bits != bits) return error.InvalidBits else try decodeNumber(T, hex, position),
                .int => |bits| if (int_info.signedness == .unsigned) return error.InvalidSignedness else if (int_info.bits != bits) return error.InvalidBits else try decodeNumber(T, hex, position),
                else => return error.InvalidAbiParameter,
            };

            if (decoded.bytes_read > opts.max_bytes)
                return error.BufferOverrun;

            return decoded;
        },
        .Optional => |opt_info| {
            return try decodeItem(allocator, opt_info.child, param, hex, position, opts);
        },
        .Enum => {
            const decoded = switch (param.type) {
                .string, .bytes => try decodeString(allocator, hex, position),
                else => return error.InvalidAbiParameter,
            };
            if (decoded.bytes_read > opts.max_bytes)
                return error.BufferOverrun;

            const str_enum = std.meta.stringToEnum(T, decoded.data) orelse return error.InvalidEnumType;
            return str_enum;
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                switch (param.type) {
                    .string, .bytes => {
                        const decoded = try decodeString(hex, position);
                        if (decoded.bytes_read > opts.max_bytes)
                            return error.BufferOverrun;

                        return .{ .consumed = decoded.consumed, .data = decoded.data[0..arr_info.len].*, .bytes_read = decoded.bytes_read };
                    },
                    .fixedBytes => |size| {
                        if (arr_info.len != size)
                            return error.InvalidAbiParameter;

                        const decoded = try decodeFixedBytes(size, hex, position);
                        if (decoded.bytes_read > opts.max_bytes)
                            return error.BufferOverrun;

                        return .{ .consumed = decoded.consumed, .data = decoded.data[0..arr_info.len].*, .bytes_read = decoded.bytes_read };
                    },
                    .address => {
                        if (arr_info.len != 20)
                            return error.InvalidAbiParameter;

                        const decoded = try decodeAddress(hex, position);
                        if (decoded.bytes_read > opts.max_bytes)
                            return error.BufferOverrun;

                        return decoded;
                    },
                    else => return error.InvalidAbiParameter,
                }
            }

            if (param.type != .fixedArray)
                return error.InvalidAbiParameter;

            if (param.type.fixedArray.size != arr_info.len)
                return error.InvalidArraySize;

            const abi_param: AbiParameter = .{ .type = param.type.fixedArray.child.*, .name = param.name, .internalType = param.internalType, .components = param.components };

            if (isDynamicType(abi_param)) {
                const offset = try decodeNumber(usize, hex, position);
                var pos: usize = 0;
                var read: u16 = 0;

                var result: T = undefined;
                const child = abi_param.type != .dynamicArray;

                for (0..arr_info.len) |i| {
                    const decoded = try decodeItem(allocator, arr_info.child, abi_param, hex[offset.data..], if (!child) pos else i * 32, opts);
                    pos += decoded.consumed;
                    result[i] = decoded.data;
                    read += decoded.bytes_read;

                    if (pos > opts.max_bytes)
                        return error.BufferOverrun;
                }

                return .{ .consumed = 32, .data = result, .bytes_read = read + 32 };
            }

            var pos: usize = 0;
            var read: u16 = 0;

            var result: T = undefined;
            for (0..arr_info.len) |i| {
                const decoded = try decodeItem(allocator, arr_info.child, abi_param, hex, pos + position, opts);
                pos += decoded.consumed;
                result[i] = decoded.data;
                read += decoded.bytes_read;

                if (pos > opts.max_bytes)
                    return error.BufferOverrun;
            }

            return .{ .consumed = 32, .data = result, .bytes_read = read };
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try decodeItem(allocator, ptr_info.child, hex, position, opts),
                .Slice => {
                    if (ptr_info.child == u8) {
                        const decoded = switch (param.type) {
                            .string, .bytes => try decodeString(hex, position),
                            else => return error.InvalidAbiParameter,
                        };
                        if (decoded.bytes_read > opts.max_bytes)
                            return error.BufferOverrun;

                        return decoded;
                    }

                    if (param.type != .dynamicArray)
                        return error.InvalidAbiParameter;

                    const abi_param = .{ .type = param.type.dynamicArray.*, .name = param.name, .internalType = param.internalType, .components = param.components };
                    const offset = try decodeNumber(usize, hex, position);
                    const length = try decodeNumber(usize, hex, offset.data);

                    var pos: usize = 0;
                    var read: u16 = 0;

                    var list = std.ArrayList(ptr_info.child).init(allocator);

                    for (0..length.data) |_| {
                        const decoded = try decodeItem(allocator, ptr_info.child, abi_param, hex[offset.data + 32 ..], pos, opts);
                        pos += decoded.consumed;
                        read += decoded.bytes_read;

                        if (pos > opts.max_bytes)
                            return error.BufferOverrun;

                        try list.append(decoded.data);
                    }

                    return .{ .consumed = 32, .data = try list.toOwnedSlice(), .bytes_read = read + 64 };
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(T)),
            }
        },
        .Struct => |struct_info| {
            if (struct_info.is_tuple)
                @compileError("Tuple types are not supported");

            var result: T = undefined;

            if (param.components) |components| {
                if (isDynamicType(param)) {
                    var pos: usize = 0;
                    var read: u16 = 0;
                    const offset = try decodeNumber(usize, hex, position);

                    inline for (struct_info.fields) |field| {
                        for (components) |component| {
                            if (std.mem.eql(u8, field.name, component.name)) {
                                const decoded = try decodeItem(allocator, field.type, component, hex[offset.data..], pos, opts);
                                pos += decoded.consumed;
                                read += decoded.bytes_read;

                                if (pos > opts.max_bytes)
                                    return error.BufferOverrun;

                                @field(result, field.name) = decoded.data;
                                break;
                            }
                        } else return error.UnknowField;
                    }

                    return .{ .consumed = 32, .data = result, .bytes_read = read + 32 };
                }

                var pos: usize = 0;
                var read: u16 = 0;
                inline for (struct_info.fields) |field| {
                    for (components) |component| {
                        if (std.mem.eql(u8, field.name, component.name)) {
                            const decoded = try decodeItem(allocator, field.type, component, hex, position + pos, opts);
                            pos += decoded.consumed;
                            read += decoded.bytes_read;

                            if (pos > opts.max_bytes)
                                return error.BufferOverrun;

                            @field(result, field.name) = decoded.data;
                            break;
                        }
                    } else return error.UnknowField;
                }

                return .{ .consumed = 32, .data = result, .bytes_read = read };
            } else return error.NullComponentType;
        },
        else => @compileError("Unsupported type" ++ @typeName(T)),
    }
}

// Comptime

/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiFunction(allocator: Allocator, comptime function: Function, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecoded(function.inputs) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try function.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
        return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and function.inputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParameters(allocator, function.inputs, data, opts);

    return .{ .arena = decoded.arena, .name = function.name, .values = decoded.values };
}

/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiFunctionOutputs(allocator: Allocator, comptime function: Function, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecoded(function.outputs) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try function.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8])) return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and function.outputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParameters(allocator, function.outputs, data, opts);

    return .{ .arena = decoded.arena, .name = function.name, .values = decoded.values };
}

/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiError(allocator: Allocator, comptime err: Error, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecoded(err.inputs) {
    std.debug.assert(hex.len > 7);

    const hashed_func_name = hex[0..8];
    const prepare = try err.allocPrepare(allocator);
    defer allocator.free(prepare);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(prepare, &hashed, .{});

    const hash_hex = std.fmt.bytesToHex(hashed, .lower);

    if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8])) return error.InvalidAbiSignature;

    const data = hex[8..];

    if (data.len == 0 and err.inputs.len > 0)
        return error.InvalidDecodeDataSize;

    const decoded = try decodeAbiParameters(allocator, err.inputs, data, opts);

    return .{ .arena = decoded.arena, .name = err.name, .values = decoded.values };
}

/// Decode the hex values based on the struct signature
/// Caller owns the memory.
pub fn decodeAbiConstructor(allocator: Allocator, comptime constructor: Constructor, hex: []const u8, opts: DecodeOptions) DecodedErrors!AbiSignatureDecoded(constructor.inputs) {
    const decoded = try decodeAbiParameters(allocator, constructor.inputs, hex, opts);

    return .{ .arena = decoded.arena, .name = "", .values = decoded.values };
}

/// Main function that will be used to decode the hex values based on the abi paramters.
/// This will allocate and a ArenaAllocator will be used to manage the memory.
///
/// Caller owns the memory.
pub fn decodeAbiParameters(allocator: Allocator, comptime params: []const AbiParameter, hex: []const u8, opts: DecodeOptions) !AbiDecoded(params) {
    var decoded: AbiDecoded(params) = .{ .arena = try allocator.create(ArenaAllocator), .values = undefined };
    errdefer allocator.destroy(decoded.arena);

    decoded.arena.* = ArenaAllocator.init(allocator);
    errdefer decoded.arena.deinit();

    const arena_allocator = decoded.arena.allocator();
    decoded.values = try decodeAbiParametersLeaky(arena_allocator, params, hex, opts);

    return decoded;
}

/// Subset function used for decoding. Its highly recommend to use an ArenaAllocator
/// or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
/// and with those all of the memory can be freed at once.
///
/// Caller owns the memory.
pub fn decodeAbiParametersLeaky(allocator: Allocator, comptime params: []const AbiParameter, hex: []const u8, opts: DecodeOptions) !AbiParametersToPrimative(params) {
    if (params.len == 0) return;
    std.debug.assert(hex.len > 63 and hex.len % 2 == 0);

    const hex_buffer = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;
    const buffer = try allocator.alloc(u8, @divExact(hex_buffer.len, 2));
    const bytes = try std.fmt.hexToBytes(buffer, hex_buffer);

    return decodeParameters(allocator, params, bytes, opts);
}

fn decodeParameters(allocator: Allocator, comptime params: []const AbiParameter, hex: []u8, opts: DecodeOptions) !AbiParametersToPrimative(params) {
    var pos: usize = 0;
    var read: u16 = 0;

    var result: AbiParametersToPrimative(params) = undefined;
    inline for (params, 0..) |param, i| {
        const decoded = try decodeParameter(allocator, param, hex, pos, opts);
        pos += decoded.consumed;
        result[i] = decoded.data;
        read += decoded.bytes_read;

        if (pos > opts.max_bytes)
            return error.BufferOverrun;
    }

    if (!opts.allow_junk_data and hex.len > read)
        return error.JunkData;

    return result;
}

fn decodeParameter(allocator: Allocator, comptime param: AbiParameter, hex: []u8, position: usize, opts: DecodeOptions) !Decoded(AbiParameterToPrimative(param)) {
    const decoded = outer: {
        break :outer switch (param.type) {
            .string, .bytes => try decodeString(hex, position),
            .address => try decodeAddress(hex, position),
            .fixedBytes => |val| {
                const decoded = try decodeFixedBytes(val, hex, position);

                break :outer .{ .consumed = decoded.consumed, .data = decoded.data[0..val].*, .bytes_read = decoded.bytes_read };
            },
            .int => |val| try decodeNumber(if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .signed, .bits = val } }), hex, position),
            .uint => |val| try decodeNumber(if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .unsigned, .bits = val } }), hex, position),
            .bool => try decodeBool(hex, position),
            .dynamicArray => |val| try decodeArray(allocator, .{ .type = val.*, .name = param.name, .internalType = param.internalType, .components = param.components }, hex, position, opts),
            .fixedArray => |val| try decodeFixedArray(allocator, .{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }, val.size, hex, position, opts),
            .tuple => try decodeTuple(allocator, param, hex, position, opts),
            inline else => @compileError("Not implemented " ++ @tagName(param.type)),
        };
    };

    if (decoded.bytes_read > opts.max_bytes)
        return error.BufferOverrun;

    return decoded;
}

fn decodeAddress(hex: []u8, position: usize) !Decoded(Address) {
    const slice = hex[position + 12 .. position + 32];

    return .{ .consumed = 32, .data = slice[0..20].*, .bytes_read = 32 };
}

fn decodeNumber(comptime T: type, hex: []u8, position: usize) !Decoded(T) {
    const info = @typeInfo(T);
    if (info != .Int)
        @compileError("Invalid type passed. Expected int type but found " ++ @typeName(T));

    const bytes = hex[position .. position + 32];

    const decoded = switch (info.Int.signedness) {
        .signed => std.mem.readInt(i256, @ptrCast(bytes), .big),
        .unsigned => std.mem.readInt(u256, @ptrCast(bytes), .big),
    };

    return .{ .consumed = 32, .data = @as(T, @truncate(decoded)), .bytes_read = 32 };
}

fn decodeBool(hex: []u8, position: usize) !Decoded(bool) {
    const bit = hex[position + 31];

    if (bit > 1)
        return error.InvalidBits;

    return .{ .consumed = 32, .data = bit != 0, .bytes_read = 32 };
}

fn decodeString(hex: []u8, position: usize) !Decoded([]const u8) {
    const offset = try decodeNumber(usize, hex, position);
    const length = try decodeNumber(usize, hex, offset.data);

    const slice = hex[offset.data + 32 .. offset.data + 32 + length.data];
    const remainder = length.data % 32;
    const len_padded = length.data + 32 - remainder;

    return .{ .consumed = 32, .data = slice, .bytes_read = @intCast(len_padded + 64) };
}

fn decodeFixedBytes(size: usize, hex: []u8, position: usize) !Decoded([]u8) {
    const slice = hex[position .. position + size];
    return .{ .consumed = 32, .data = slice, .bytes_read = 32 };
}

fn decodeArray(allocator: Allocator, comptime param: AbiParameter, hex: []u8, position: usize, opts: DecodeOptions) !Decoded([]const AbiParameterToPrimative(param)) {
    const offset = try decodeNumber(usize, hex, position);
    const length = try decodeNumber(usize, hex, offset.data);

    var pos: usize = 0;
    var read: u16 = 0;

    var list = std.ArrayList(AbiParameterToPrimative(param)).init(allocator);

    for (0..length.data) |_| {
        const decoded = try decodeParameter(allocator, param, hex[offset.data + 32 ..], pos, opts);
        pos += decoded.consumed;
        read += decoded.bytes_read;

        if (pos > opts.max_bytes)
            return error.BufferOverrun;

        try list.append(decoded.data);
    }

    return .{ .consumed = 32, .data = try list.toOwnedSlice(), .bytes_read = read + 64 };
}

fn decodeFixedArray(allocator: Allocator, comptime param: AbiParameter, comptime size: usize, hex: []u8, position: usize, opts: DecodeOptions) !Decoded([size]AbiParameterToPrimative(param)) {
    if (isDynamicType(param)) {
        const offset = try decodeNumber(usize, hex, position);
        var pos: usize = 0;
        var read: u16 = 0;

        var result: [size]AbiParameterToPrimative(param) = undefined;
        const child = blk: {
            switch (param.type) {
                .dynamicArray => |val| break :blk val.*,
                inline else => {},
            }
        };

        for (0..size) |i| {
            const decoded = try decodeParameter(allocator, param, hex[offset.data..], if (@TypeOf(child) != void) pos else i * 32, opts);
            pos += decoded.consumed;
            result[i] = decoded.data;
            read += decoded.bytes_read;

            if (pos > opts.max_bytes)
                return error.BufferOverrun;
        }

        return .{ .consumed = 32, .data = result, .bytes_read = read + 32 };
    }

    var pos: usize = 0;
    var read: u16 = 0;

    var result: [size]AbiParameterToPrimative(param) = undefined;
    for (0..size) |i| {
        const decoded = try decodeParameter(allocator, param, hex, pos + position, opts);
        pos += decoded.consumed;
        result[i] = decoded.data;
        read += decoded.bytes_read;

        if (pos > opts.max_bytes)
            return error.BufferOverrun;
    }

    return .{ .consumed = 32, .data = result, .bytes_read = read };
}

fn decodeTuple(allocator: Allocator, comptime param: AbiParameter, hex: []u8, position: usize, opts: DecodeOptions) !Decoded(AbiParameterToPrimative(param)) {
    var result: AbiParameterToPrimative(param) = undefined;

    if (param.components) |components| {
        if (isDynamicType(param)) {
            var pos: usize = 0;
            var read: u16 = 0;
            const offset = try decodeNumber(usize, hex, position);

            inline for (components) |component| {
                const decoded = try decodeParameter(allocator, component, hex[offset.data..], pos, opts);
                pos += decoded.consumed;
                read += decoded.bytes_read;

                if (pos > opts.max_bytes)
                    return error.BufferOverrun;

                @field(result, component.name) = decoded.data;
            }

            return .{ .consumed = 32, .data = result, .bytes_read = read + 32 };
        }

        var pos: usize = 0;
        var read: u16 = 0;
        inline for (components) |component| {
            const decoded = try decodeParameter(allocator, component, hex, position + pos, opts);
            pos += decoded.consumed;
            read += decoded.bytes_read;

            if (pos > opts.max_bytes)
                return error.BufferOverrun;

            @field(result, component.name) = decoded.data;
        }

        return .{ .consumed = 32, .data = result, .bytes_read = read };
    } else @compileError("Expected components to not be null");
}

fn isDynamicType(param: AbiParameter) bool {
    return switch (param.type) {
        .string,
        .bytes,
        .dynamicArray,
        => true,
        .tuple => {
            for (param.components.?) |component| {
                const dyn = isDynamicType(component);

                if (dyn) return dyn;
            }

            return false;
        },
        .fixedArray => |val| isDynamicType(.{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }),
        inline else => false,
    };
}

test "Bool" {
    {
        try testDecode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{true});
        try testDecode("0000000000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{false});

        const decoded = try decodeAbiConstructor(testing.allocator, .{ .type = .constructor, .stateMutability = .nonpayable, .inputs = &.{.{ .type = .{ .bool = {} }, .name = "foo" }} }, "0000000000000000000000000000000000000000000000000000000000000000", .{});
        defer decoded.deinit();

        try testInnerValues(.{false}, decoded.values);
    }
    {
        const ReturnType = std.meta.Tuple(&[_]type{bool});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000001", ReturnType, &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{true});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000000", ReturnType, &.{.{ .type = .{ .bool = {} }, .name = "foo" }}, .{false});

        const decoded = try decodeAbiConstructorRuntime(testing.allocator, ReturnType, .{ .type = .constructor, .stateMutability = .nonpayable, .inputs = &.{.{ .type = .{ .bool = {} }, .name = "foo" }} }, "0000000000000000000000000000000000000000000000000000000000000000", .{});
        defer decoded.deinit();

        try testInnerValues(.{false}, decoded.values);
    }
}

test "Uint/Int" {
    {
        try testDecode("0000000000000000000000000000000000000000000000000000000000000005", &.{.{ .type = .{ .uint = 8 }, .name = "foo" }}, .{5});
        try testDecode("0000000000000000000000000000000000000000000000000000000000010f2c", &.{.{ .type = .{ .uint = 256 }, .name = "foo" }}, .{69420});
        try testDecode("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb", &.{.{ .type = .{ .int = 256 }, .name = "foo" }}, .{-5});
        try testDecode("fffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a432eb", &.{.{ .type = .{ .int = 64 }, .name = "foo" }}, .{-123456789});

        const decoded = try decodeAbiError(testing.allocator, .{ .type = .@"error", .name = "Bar", .inputs = &.{.{ .type = .{ .int = 256 }, .name = "foo" }} }, "22217e1f0000000000000000000000000000000000000000000000000000000000010f2c", .{});
        defer decoded.deinit();

        try testInnerValues(.{69420}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
    {
        const R1 = std.meta.Tuple(&[_]type{u8});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000005", R1, &.{.{ .type = .{ .uint = 8 }, .name = "foo" }}, .{5});
        const R2 = std.meta.Tuple(&[_]type{u256});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000010f2c", R2, &.{.{ .type = .{ .uint = 256 }, .name = "foo" }}, .{69420});
        const R3 = std.meta.Tuple(&[_]type{i256});
        try testDecodeRuntime("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb", R3, &.{.{ .type = .{ .int = 256 }, .name = "foo" }}, .{-5});
        const R4 = std.meta.Tuple(&[_]type{i64});
        try testDecodeRuntime("fffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a432eb", R4, &.{.{ .type = .{ .int = 64 }, .name = "foo" }}, .{-123456789});

        const decoded = try decodeAbiErrorRuntime(testing.allocator, R3, .{ .type = .@"error", .name = "Bar", .inputs = &.{.{ .type = .{ .int = 256 }, .name = "foo" }} }, "22217e1f0000000000000000000000000000000000000000000000000000000000010f2c", .{});
        defer decoded.deinit();

        try testInnerValues(.{69420}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
}

test "Address" {
    {
        try testDecode("0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x4648451b5F87FF8F0F7D622bD40574bb97E25980")});
        try testDecode("000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x388C818CA8B9251b393131C08a736A67ccB19297")});

        const decoded = try decodeAbiFunctionOutputs(testing.allocator, .{ .type = .function, .name = "Bar", .inputs = &.{}, .stateMutability = .nonpayable, .outputs = &.{.{ .type = .{ .address = {} }, .name = "foo" }} }, "b0a378b0000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", .{});
        defer decoded.deinit();

        try testInnerValues(.{try utils.addressToBytes("0x388C818CA8B9251b393131C08a736A67ccB19297")}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
    {
        const R1 = std.meta.Tuple(&[_]type{Address});
        try testDecodeRuntime("0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", R1, &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x4648451b5F87FF8F0F7D622bD40574bb97E25980")});
        try testDecodeRuntime("000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", R1, &.{.{ .type = .{ .address = {} }, .name = "foo" }}, .{try utils.addressToBytes("0x388C818CA8B9251b393131C08a736A67ccB19297")});

        const decoded = try decodeAbiFunctionOutputsRuntime(testing.allocator, R1, .{ .type = .function, .name = "Bar", .inputs = &.{}, .stateMutability = .nonpayable, .outputs = &.{.{ .type = .{ .address = {} }, .name = "foo" }} }, "b0a378b0000000000000000000000000388c818ca8b9251b393131c08a736a67ccb19297", .{});
        defer decoded.deinit();

        try testInnerValues(.{try utils.addressToBytes("0x388C818CA8B9251b393131C08a736A67ccB19297")}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
}

test "Fixed Bytes" {
    {
        try testDecode("0123456789000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 5 }, .name = "foo" }}, .{[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 }});
        try testDecode("0123456789012345678900000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedBytes = 10 }, .name = "foo" }}, .{[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 } ** 2});

        const decoded = try decodeAbiError(testing.allocator, .{ .type = .@"error", .name = "Bar", .inputs = &.{} }, "b0a378b0", .{});
        defer decoded.deinit();

        try testing.expectEqualStrings("Bar", decoded.name);
    }
    {
        const R1 = std.meta.Tuple(&[_]type{[5]u8});
        const R2 = std.meta.Tuple(&[_]type{[10]u8});
        try testDecodeRuntime("0123456789000000000000000000000000000000000000000000000000000000", R1, &.{.{ .type = .{ .fixedBytes = 5 }, .name = "foo" }}, .{[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 }});
        try testDecodeRuntime("0123456789012345678900000000000000000000000000000000000000000000", R2, &.{.{ .type = .{ .fixedBytes = 10 }, .name = "foo" }}, .{[_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 } ** 2});

        const R3 = std.meta.Tuple(&[_]type{});
        const decoded = try decodeAbiErrorRuntime(testing.allocator, R3, .{ .type = .@"error", .name = "Bar", .inputs = &.{} }, "b0a378b0", .{});
        defer decoded.deinit();

        try testing.expectEqualStrings("Bar", decoded.name);
    }
}

test "Bytes/String" {
    {
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .{"foo"});
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .bytes = {} }, .name = "foo" }}, .{&[_]u8{ 0x66, 0x6f, 0x6f }});

        const decoded = try decodeAbiFunction(testing.allocator, .{ .type = .function, .name = "Bar", .inputs = &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .stateMutability = .nonpayable, .outputs = &.{} }, "4ec7c7ae00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", .{});
        defer decoded.deinit();

        try testInnerValues(.{"foo"}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
    {
        const R1 = std.meta.Tuple(&[_]type{[]const u8});

        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", R1, &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .{"foo"});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", R1, &.{.{ .type = .{ .bytes = {} }, .name = "foo" }}, .{&[_]u8{ 0x66, 0x6f, 0x6f }});

        const decoded = try decodeAbiFunctionRuntime(testing.allocator, R1, .{ .type = .function, .name = "Bar", .inputs = &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .stateMutability = .nonpayable, .outputs = &.{} }, "4ec7c7ae00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", .{});
        defer decoded.deinit();

        try testInnerValues(.{"foo"}, decoded.values);
        try testing.expectEqualStrings("Bar", decoded.name);
    }
}

test "Errors" {
    try testing.expectError(error.InvalidAbiSignature, decodeAbiFunction(testing.allocator, .{ .type = .function, .name = "Bar", .inputs = &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .stateMutability = .nonpayable, .outputs = &.{} }, "4ec7c7af00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", .{}));
    try testing.expectError(error.InvalidDecodeDataSize, decodeAbiFunction(testing.allocator, .{ .type = .function, .name = "Bar", .inputs = &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .stateMutability = .nonpayable, .outputs = &.{} }, "4ec7c7ae", .{}));
    try testing.expectError(error.BufferOverrun, decodeAbiParameters(testing.allocator, &.{.{ .type = .{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .dynamicArray = &.{ .uint = 256 } } } } } } } } } } }, .name = "" }}, "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020", .{}));
    try testing.expectError(error.JunkData, decodeAbiParameters(testing.allocator, &.{ .{ .type = .{ .uint = 256 }, .name = "foo" }, .{ .type = .{ .dynamicArray = &.{ .address = {} } }, .name = "bar" }, .{ .type = .{ .address = {} }, .name = "baz" }, .{ .type = .{ .uint = 256 }, .name = "fizz" } }, "0000000000000000000000000000000000000000000000164054d8356b4f5c2800000000000000000000000000000000000000000000000000000000000000800000000000000000000000006994ece772cc4abb5c9993c065a34c94544a40870000000000000000000000000000000000000000000000000000000062b348620000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000106d3c66d22d2dd0446df23d7f5960752994d6007a6572696f6e", .{}));
}

test "Arrays" {
    {
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &ParamType{ .int = 256 } }, .name = "foo" }}, .{&[_]i256{ 4, 2, 0 }});
        try testDecode("00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .int = 256 }, .size = 2 } }, .name = "foo" }}, .{[2]i256{ 4, 2 }});
        try testDecode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .name = "foo" }}, .{[2][]const u8{ "foo", "bar" }});
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }}, .{&[_][]const u8{ "foo", "bar" }});
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626172000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000362617a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .size = 3 } }, .name = "foo" }}, .{[3][2][]const u8{ .{ "foo", "bar" }, .{ "baz", "boo" }, .{ "fizz", "buzz" } }});
        try testDecode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000666697a7a7a7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000362757a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000662757a7a7a7a0000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .dynamicArray = &.{ .string = {} } }, .size = 2 } }, .name = "foo" }}, .{[2][]const []const u8{ &.{ "foo", "bar", "fizzzz", "buz" }, &.{ "fizz", "buzz", "buzzzz" } }});
    }
    {
        const R1 = std.meta.Tuple(&[_]type{[]const i256});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000", R1, &.{.{ .type = .{ .dynamicArray = &ParamType{ .int = 256 } }, .name = "foo" }}, .{&[_]i256{ 4, 2, 0 }});

        const R2 = std.meta.Tuple(&[_]type{[2]i256});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002", R2, &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .int = 256 }, .size = 2 } }, .name = "foo" }}, .{[2]i256{ 4, 2 }});

        const R3 = std.meta.Tuple(&[_]type{[2][]const u8});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", R3, &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .name = "foo" }}, .{[2][]const u8{ "foo", "bar" }});

        const R4 = std.meta.Tuple(&[_]type{[]const []const u8});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000", R4, &.{.{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }}, .{&[_][]const u8{ "foo", "bar" }});

        const R5 = std.meta.Tuple(&[_]type{[3][2][]const u8});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626172000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000362617a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", R5, &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .fixedArray = .{ .child = &.{ .string = {} }, .size = 2 } }, .size = 3 } }, .name = "foo" }}, .{[3][2][]const u8{ .{ "foo", "bar" }, .{ "baz", "boo" }, .{ "fizz", "buzz" } }});

        const R6 = std.meta.Tuple(&[_]type{[2][]const []const u8});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000666697a7a7a7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000362757a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000662757a7a7a7a0000000000000000000000000000000000000000000000000000", R6, &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .dynamicArray = &.{ .string = {} } }, .size = 2 } }, .name = "foo" }}, .{[2][]const []const u8{ &.{ "foo", "bar", "fizzzz", "buz" }, &.{ "fizz", "buzz", "buzzzz" } }});
    }
}
//
test "Tuples" {
    {
        try testDecode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }}, .{.{ .bar = true }});
        try testDecode("0000000000000000000000000000000000000000000000000000000000000001", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }}, .{.{ .bar = .{ .baz = true } }});
        try testDecode("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{.{ .bar = true, .baz = 69, .fizz = "buzz" }});
        try testDecode("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", &.{.{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{&.{.{ .bar = true, .baz = 69, .fizz = "buzz" }}});
    }
    {
        const R1 = std.meta.Tuple(&[_]type{struct { bar: bool }});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000001", R1, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }}, .{.{ .bar = true }});

        const R2 = std.meta.Tuple(&[_]type{struct { bar: struct { baz: bool } }});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000001", R2, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }}, .{.{ .bar = .{ .baz = true } }});

        const R3 = std.meta.Tuple(&[_]type{struct { bar: bool, baz: u256, fizz: []const u8 }});
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", R3, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{.{ .bar = true, .baz = 69, .fizz = "buzz" }});

        const R4 = std.meta.Tuple(&[_]type{[]const struct { bar: bool, baz: u256, fizz: []const u8 }});
        try testDecodeRuntime("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000", R4, &.{.{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "foo", .components = &.{ .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .uint = 256 }, .name = "baz" }, .{ .type = .{ .string = {} }, .name = "fizz" } } }}, .{&.{.{ .bar = true, .baz = 69, .fizz = "buzz" }}});
    }
}

test "Multiple" {
    {
        try testDecode("0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000001a40000000000000000000000000000000000000000000000000000000000010f2c", &.{ .{ .type = .{ .uint = 256 }, .name = "foo" }, .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .int = 120 } }, .name = "baz" } }, .{ 69, true, &[_]i120{ 69, 420, 69420 } });

        const params: []const AbiParameter = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }};
        //
        try testDecode("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000a45500000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001c666f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f00000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018424f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f00000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009", params, .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }});
    }
    {
        const R1 = std.meta.Tuple(&[_]type{ u256, bool, []const i120 });
        try testDecodeRuntime("0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000001a40000000000000000000000000000000000000000000000000000000000010f2c", R1, &.{ .{ .type = .{ .uint = 256 }, .name = "foo" }, .{ .type = .{ .bool = {} }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .int = 120 } }, .name = "baz" } }, .{ 69, true, &[_]i120{ 69, 420, 69420 } });

        const params: []const AbiParameter = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }};

        const R2 = std.meta.Tuple(&[_]type{struct { foo: []const []const u8, bar: u256, baz: []const struct { fizz: []const []const u8, buzz: bool, jazz: []const i256 } }});
        try testDecodeRuntime("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000a45500000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001c666f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f00000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018424f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f00000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009", R2, params, .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }});
    }
}

fn testDecode(hex: []const u8, comptime params: []const AbiParameter, comptime expected: anytype) !void {
    const decoded = try decodeAbiParameters(testing.allocator, params, hex, .{});
    defer decoded.deinit();

    try testing.expectEqual(decoded.values.len, expected.len);

    inline for (expected, 0..) |e, i| {
        try testInnerValues(e, decoded.values[i]);
    }
}

fn testDecodeRuntime(hex: []const u8, comptime T: type, params: []const AbiParameter, expected: anytype) !void {
    const decoded = try decodeAbiParametersRuntime(testing.allocator, T, params, hex, .{});
    defer decoded.deinit();

    try testing.expectEqual(decoded.values.len, expected.len);

    inline for (expected, 0..) |e, i| {
        try testInnerValues(e, decoded.values[i]);
    }
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
