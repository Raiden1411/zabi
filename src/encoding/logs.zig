const abi = zabi_abi.abitypes;
const abi_parameter = zabi_abi.abi_parameter;
const encoder = @import("encoder.zig");
const meta = @import("zabi-meta").abi;
const std = @import("std");
const types = @import("zabi-types").ethereum;
const zabi_abi = @import("zabi-abi");

// Types
const AbiEvent = abi.Event;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const AbiEventParameterDataToPrimative = meta.AbiEventParameterDataToPrimative;
const AbiEventParametersDataToPrimative = meta.AbiEventParametersDataToPrimative;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Set of errors while performing logs abi encoding.
pub const EncodeLogsErrors = Allocator.Error || error{NoSpaceLeft};

pub fn encodeLogTopicsFromReflection(
    allocator: Allocator,
    event: AbiEvent,
    values: anytype,
) EncodeLogsErrors![]const ?Hash {
    var logs_encoder: AbiLogTopicsEncoderReflection = .empty;

    return logs_encoder.encodeLogTopicsWithSignature(allocator, event, values);
}

pub fn encodeLogTopics(
    comptime event: AbiEvent,
    allocator: Allocator,
    values: AbiEventParametersDataToPrimative(event.inputs),
) Allocator.Error![]const ?Hash {
    var logs_encoder: AbiLogTopicsEncoder(event) = .empty;

    return logs_encoder.encodeLogTopics(allocator, values);
}

pub const AbiLogTopicsEncoderReflection = struct {
    const Self = @This();

    pub const empty: Self = .{
        .topics = .empty,
    };

    topics: ArrayListUnmanaged(?Hash),

    pub fn encodeLogTopicsWithSignature(
        self: *Self,
        allocator: Allocator,
        event: AbiEvent,
        values: anytype,
    ) EncodeLogsErrors![]const ?Hash {
        const hash = try event.encode();

        const info = @typeInfo(@TypeOf(values));

        if (info != .@"struct" or !info.@"struct".is_tuple)
            @compileError("`values` must be a tuple struct!");

        try self.topics.ensureUnusedCapacity(allocator, values.len + 1);
        self.topics.appendAssumeCapacity(hash);

        if (event.inputs.len == 0)
            return self.topics.toOwnedSlice(allocator);

        inline for (values) |value| {
            self.encodeLogTopic(value);
        }

        return self.topics.toOwnedSlice(allocator);
    }

    pub fn encodeLogTopics(
        self: *Self,
        allocator: Allocator,
        values: anytype,
    ) Allocator.Error![]const ?Hash {
        const info = @typeInfo(@TypeOf(values));

        if (info != .@"struct" or !info.@"struct".is_tuple)
            @compileError("`values` must be a tuple struct!");

        try self.topics.ensureUnusedCapacity(allocator, values.len);

        inline for (values) |value| {
            self.encodeLogTopic(value);
        }

        return self.topics.toOwnedSlice(allocator);
    }

    pub fn encodeLogTopic(self: *Self, value: anytype) void {
        const info = @typeInfo(@TypeOf(value));

        switch (info) {
            .bool => self.topics.appendAssumeCapacity(encoder.encodeBoolean(value)),
            .int => |int_info| {
                const Int = switch (int_info.signedness) {
                    .unsigned => u256,
                    .signed => i256,
                };
                self.topics.appendAssumeCapacity(encoder.encodeNumber(Int, value));
            },
            .comptime_int => return self.encodeLogTopic(@as(std.math.IntFittingRange(value, value), value)),
            .null => self.topics.appendAssumeCapacity(null),
            .optional => if (value) |val| return self.encodeLogTopic(val) else self.topics.appendAssumeCapacity(null),
            .@"enum",
            .enum_literal,
            => {
                var buffer: [32]u8 = undefined;
                Keccak256.hash(@tagName(value), &buffer, .{});
                self.topics.appendAssumeCapacity(buffer);
            },
            .array => |arr_info| {
                if (arr_info.child != u8)
                    @compileError("Only `u8` arrays are supported!");

                if (arr_info.len > 32)
                    @compileError("Maximum size allowed is 32 bits.");

                self.topics.appendAssumeCapacity(encoder.encodeFixedBytes(arr_info.len, value));
            },
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .array => {
                            const Slice = []const std.meta.Elem(ptr_info.child);

                            return self.encodeLogTopic(@as(Slice, value));
                        },
                        else => return self.encodeLogTopic(value.*),
                    },
                    .Slice => {
                        if (ptr_info.child != u8)
                            @compileError("Only `u8` arrays are supported!");

                        var buffer: [32]u8 = undefined;
                        Keccak256.hash(value, &buffer, .{});
                        self.topics.appendAssumeCapacity(buffer);
                    },
                    else => @compileError("Unsupported pointer type '" ++ @tagName(ptr_info.child) ++ "'"),
                }
            },
            else => @compileError("Unsupported type '" ++ @typeName(@TypeOf(value)) ++ "'"),
        }
    }
};

pub fn AbiLogTopicsEncoder(comptime event: AbiEvent) type {
    return struct {
        const hash = event.encode() catch @compileError("Event signature higher than 256 bits!");
        const indexed_params = indexed: {
            var indexed: std.BoundedArray(AbiEventParameter, 32) = .{};

            for (event.inputs) |input| {
                if (input.indexed) {
                    indexed.append(input) catch @compileError("Append reached max size of 32");
                }
            }

            break :indexed indexed;
        };

        pub const empty: Self = .{
            .topics = .empty,
        };

        const Self = @This();

        topics: ArrayListUnmanaged(?Hash),

        pub fn encodeLogTopics(
            self: *Self,
            allocator: Allocator,
            values: AbiEventParametersDataToPrimative(event.inputs),
        ) Allocator.Error![]const ?Hash {
            try self.topics.ensureUnusedCapacity(allocator, indexed_params.len + 1);
            self.topics.appendAssumeCapacity(hash);

            if (indexed_params.len == 0)
                return self.topics.toOwnedSlice(allocator);

            const params_slice = comptime indexed_params.slice();

            inline for (params_slice, values) |param, value|
                self.encodeLogTopic(param, value);

            return self.topics.toOwnedSlice(allocator);
        }

        pub fn encodeLogTopic(
            self: *Self,
            comptime param: AbiEventParameter,
            value: AbiEventParameterDataToPrimative(param),
        ) void {
            switch (param.type) {
                .bool => self.topics.appendAssumeCapacity(encoder.encodeBoolean(value)),
                .int => self.topics.appendAssumeCapacity(encoder.encodeNumber(i256, value)),
                .uint => self.topics.appendAssumeCapacity(encoder.encodeNumber(u256, value)),
                .address => self.topics.appendAssumeCapacity(encoder.encodeAddress(value)),
                .fixedBytes => |bytes| self.topics.appendAssumeCapacity(encoder.encodeFixedBytes(bytes, value)),
                .bytes,
                .string,
                => {
                    var buffer: [32]u8 = undefined;
                    Keccak256.hash(value, &buffer, .{});
                    self.topics.appendAssumeCapacity(buffer);
                },
                else => @compileError("Unsupported abitype '" ++ @tagName(param.type) ++ "' for log topic encoding."),
            }
        }
    };
}
