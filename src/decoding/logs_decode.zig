const std = @import("std");
const abi = @import("../abi/abi.zig");
const abi_parameter = @import("../abi/abi_parameter.zig");
const human = @import("../human-readable/abi_parsing.zig");
const meta = @import("../meta/abi.zig");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiEventParametersToPrimativeType = meta.AbiEventParametersToPrimativeType;
const AbiEventParameterToPrimativeType = meta.AbiEventParameterToPrimativeType;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

// Functions
const encodeLogs = @import("../encoding/logs.zig").encodeLogTopics;

pub const LogDecoderOptions = struct {
    allocator: ?Allocator = null,
    endianess: std.builtin.Endian = .big,
};

pub fn decodeLog(comptime T: type, encoded: Hash, options: LogDecoderOptions) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => {
            const value = std.mem.readInt(u256, encoded, .big);

            return @as(u1, @truncate(value)) != 0;
        },
        .Int => |int_value| {
            const IntType = switch (int_value.signedness) {
                .signed => i256,
                .unsigned => u256,
            };

            const value = std.mem.readInt(IntType, encoded, .big);

            return @as(T, @truncate(value));
        },
        .Optional => |opt_info| return decodeLog(opt_info.child, encoded, options),
        .Array => |arr_info| {
            if (arr_info.child != u8)
                @compileError("Only u8 arrays are supported. Found: " ++ @typeName(T));

            if (arr_info.len > 32)
                @compileError("Only [32]u8 arrays and lower are supported. Found: " ++ @typeName(T));

            const value = std.mem.readInt(u256, encoded, options.endianess);

            return @bitCast(value);
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => {
                    const allocator = options.allocator orelse return error.ExpectedAllocator;

                    const pointer = try allocator.create(T);
                    errdefer allocator.destroy(pointer);

                    pointer.* = try decodeLog(ptr_info.child, encoded, options);

                    return pointer;
                },
                else => @compileError("Unsupported pointer type '" ++ @typeName(T) ++ "'"),
            }
        },
    }
}
