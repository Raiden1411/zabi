const encoder = @import("../encoding/encoder.zig");
const encoder_logs = @import("../encoding/logs.zig");
const decoder = @import("../decoding/decoder.zig");
const decoder_logs = @import("../decoding/logs_decode.zig");
const meta = @import("../meta/root.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../types/ethereum.zig");

// Types
const AbiEncoded = encoder.AbiEncoded;
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiEventParameter = @import("abi_parameter.zig").AbiEventParameter;
const Allocator = std.mem.Allocator;
const Extract = meta.utils.Extract;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const StateMutability = @import("state_mutability.zig").StateMutability;
const Value = std.json.Value;

pub const Abitype = enum { function, @"error", event, constructor, fallback, receive };

/// Solidity Abi function representation.
/// Reference: ["function"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Function = struct {
    type: Extract(Abitype, "function"),
    /// Deprecated. Use either 'pure' or 'view'.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    constant: ?bool = null,
    /// Deprecated. Older vyper compiler versions used to provide gas estimates.
    ///
    /// https://github.com/vyperlang/vyper/issues/2151
    gas: ?i64 = null,
    inputs: []const AbiParameter,
    name: []const u8,
    outputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: StateMutability,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);

        for (self.outputs) |output| {
            output.deinit(allocator);
        }
        allocator.free(self.outputs);
    }

    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `EncodeAbiFunctionComptime` if the struct is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(self: @This(), allocator: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(allocator);
        defer allocator.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const encoded_params = try encoder.encodeAbiParameters(allocator, self.inputs, values);
        defer encoded_params.deinit();

        const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

        @memcpy(buffer[0..4], hashed[0..4]);
        @memcpy(buffer[4..], encoded_params.data[0..]);

        return buffer;
    }

    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `outputs` proprety.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `EncodeAbiFunctionComptime` if the struct is
    /// comptime know and you want better typesafety from the compiler
    pub fn encodeOutputs(self: @This(), allocator: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(allocator);
        defer allocator.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const encoded_params = try encoder.encodeAbiParameters(allocator, self.outputs, values);
        defer encoded_params.deinit();

        const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

        @memcpy(buffer[0..4], hashed[0..4]);
        @memcpy(buffer[4..], encoded_params.data[0..]);

        return buffer;
    }

    /// Decode a encoded function based on itself.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `inputs` proprety.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `decodeAbiFunction` if the struct is
    /// comptime know and you dont want to provided the return type.
    pub fn decode(self: @This(), allocator: Allocator, comptime T: type, encoded: []const u8, opts: decoder.DecodeOptions) !decoder.AbiSignatureDecodedRuntime(T) {
        std.debug.assert(encoded.len > 7);

        const hashed_func_name = encoded[0..8];
        const prepared = try self.allocPrepare(allocator);
        defer allocator.free(prepared);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prepare, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
            return error.InvalidAbiSignature;

        const data = encoded[8..];
        const func_name = try std.mem.concat(allocator, u8, &.{ "0x", hashed_func_name });
        errdefer allocator.free(func_name);

        if (data.len == 0 and self.inputs.len > 0)
            return error.InvalidDecodeDataSize;

        const decoded = try decoder.decodeAbiParametersRuntime(allocator, T, self.inputs, data, opts);

        return .{ .arena = decoded.arena, .name = func_name, .values = decoded.values };
    }

    /// Decode a encoded function based on itself.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `outputs` proprety.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `decodeAbiFunction` if the struct is
    /// comptime know and you dont want to provided the return type.
    pub fn decodeOutputs(self: @This(), allocator: Allocator, comptime T: type, encoded: []const u8, opts: decoder.DecodeOptions) !decoder.AbiSignatureDecodedRuntime(T) {
        std.debug.assert(encoded.len > 7);

        const hashed_func_name = encoded[0..8];
        const prepared = try self.allocPrepare(allocator);
        defer allocator.free(prepared);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prepare, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
            return error.InvalidAbiSignature;

        const data = encoded[8..];
        const func_name = try std.mem.concat(allocator, u8, &.{ "0x", hashed_func_name });
        errdefer allocator.free(func_name);

        if (data.len == 0 and self.outputs.len > 0)
            return error.InvalidDecodeDataSize;

        const decoded = try decoder.decodeAbiParametersRuntime(allocator, T, self.outputs, data, opts);

        return .{ .arena = decoded.arena, .name = func_name, .values = decoded.values };
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print(" {s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(", ", .{});
        }
        try writer.print(")", .{});

        if (self.stateMutability != .nonpayable) try writer.print(" {s}", .{@tagName(self.stateMutability)});

        if (self.outputs.len > 0) {
            try writer.print(" returns (", .{});
            for (self.outputs, 0..) |output, i| {
                try output.format(layout, opts, writer);
                if (i != self.outputs.len - 1) try writer.print(", ", .{});
            }
            try writer.print(")", .{});
        }
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    ///
    /// Caller owns the memory.
    pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try allocator.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(self: @This(), writer: anytype) !void {
        try writer.print("{s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.prepare(writer);
            if (i != self.inputs.len - 1) try writer.print(",", .{});
        }
        try writer.print(")", .{});
    }
};

/// Solidity Abi function representation.
/// Reference: ["event"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Event = struct {
    type: Extract(Abitype, "event"),
    name: []const u8,
    inputs: []const AbiEventParameter,
    anonymous: ?bool = null,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print(" {s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(",", .{});
        }
        try writer.print(")", .{});
    }

    /// Encode the struct signature based it's hash.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `EncodeAbiEventComptime` if the struct is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(self: @This(), allocator: Allocator) !Hash {
        const prep_signature = try self.allocPrepare(allocator);
        defer allocator.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        return hashed;
    }

    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    pub fn encodeLogTopics(self: @This(), allocator: Allocator, values: anytype) ![]const ?Hash {
        return try encoder_logs.encodeLogTopics(allocator, self, values);
    }

    /// Decode the encoded log topics based on the event signature and the provided type.
    ///
    /// Caller owns the memory.
    pub fn decodeLogTopics(self: @This(), allocator: Allocator, comptime T: type, encoded: []const ?Hash) !T {
        return try decoder_logs.decodeLogs(allocator, T, self, encoded);
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    ///
    /// Caller owns the memory.
    pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try allocator.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(self: @This(), writer: anytype) !void {
        try writer.print("{s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.prepare(writer);
            if (i != self.inputs.len - 1) try writer.print(",", .{});
        }
        try writer.print(")", .{});
    }
};

/// Solidity Abi function representation.
/// Reference: ["error"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Error = struct {
    type: Extract(Abitype, "error"),
    name: []const u8,
    inputs: []const AbiParameter,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print(" {s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(", ", .{});
        }
        try writer.print(")", .{});
    }

    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `EncodeAbiErrorComptime` if the struct is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(self: @This(), allocator: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(allocator);
        defer allocator.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const encoded_params = try encoder.encodeAbiParameters(allocator, self.inputs, values);
        defer encoded_params.deinit();

        const buffer = try allocator.alloc(u8, 4 + encoded_params.data.len);

        @memcpy(buffer[0..4], hashed[0..4]);
        @memcpy(buffer[4..], encoded_params.data[0..]);

        return buffer;
    }

    /// Decode a encoded error based on itself.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `inputs` proprety.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `decodeAbiError` if the struct is
    /// comptime know and you dont want to provided the return type.
    pub fn decode(self: @This(), allocator: Allocator, comptime T: type, encoded: []const u8, opts: decoder.DecodeOptions) !decoder.AbiSignatureDecodedRuntime(T) {
        std.debug.assert(encoded.len > 7);

        const hashed_func_name = encoded[0..8];
        const prepared = try self.allocPrepare(allocator);
        defer allocator.free(prepared);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prepare, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        if (!std.mem.eql(u8, hashed_func_name, hash_hex[0..8]))
            return error.InvalidAbiSignature;

        const data = encoded[8..];
        const func_name = try std.mem.concat(allocator, u8, &.{ "0x", hashed_func_name });
        errdefer allocator.free(func_name);

        if (data.len == 0 and self.inputs.len > 0)
            return error.InvalidDecodeDataSize;

        const decoded = try decoder.decodeAbiErrorRuntime(allocator, T, self.inputs, data, opts);

        return .{ .arena = decoded.arena, .name = func_name, .values = decoded.values };
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    ///
    /// Caller owns the memory.
    pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try allocator.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(self: @This(), writer: anytype) !void {
        try writer.print("{s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.prepare(writer);
            if (i != self.inputs.len - 1) try writer.print(",", .{});
        }
        try writer.print(")", .{});
    }
};

/// Solidity Abi function representation.
/// Reference: ["constructor"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Constructor = struct {
    type: Extract(Abitype, "constructor"),
    inputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: Extract(StateMutability, "payable,nonpayable"),

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.type)});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(", ", .{});
        }
        try writer.print(")", .{});

        if (self.stateMutability != .nonpayable) try writer.print(" {s}", .{@tagName(self.stateMutability)});
    }

    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `EncodeAbiConstructorComptime` if the struct is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(self: @This(), allocator: Allocator, values: anytype) !AbiEncoded {
        return encoder.encodeAbiParameters(allocator, self.inputs, values);
    }

    /// Decode a encoded constructor arguments based on itself.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `inputs` proprety.
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `decodeAbiConstructor` if the struct is
    /// comptime know and you dont want to provided the return type.
    pub fn decode(self: @This(), allocator: Allocator, comptime T: type, encoded: []const u8, opts: decoder.DecodeOptions) !decoder.AbiSignatureDecodedRuntime(T) {
        const decoded = try decoder.decodeAbiConstructorRuntime(allocator, T, self.inputs, encoded, opts);

        return .{ .arena = decoded.arena, .name = "", .values = decoded.values };
    }
};

/// Solidity Abi function representation.
/// Reference: ["fallback"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Fallback = struct {
    type: Extract(Abitype, "fallback"),
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: Extract(StateMutability, "payable,nonpayable"),

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        _ = opts;
        _ = layout;

        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print("()", .{});

        if (self.stateMutability != .nonpayable) try writer.print(" {s}", .{@tagName(self.stateMutability)});
    }
};

/// Solidity Abi function representation.
/// Reference: ["receive"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Receive = struct {
    type: Extract(Abitype, "receive"),
    stateMutability: Extract(StateMutability, "payable"),

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        _ = opts;
        _ = layout;

        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print("() external ", .{});

        try writer.print("{s}", .{@tagName(self.stateMutability)});
    }
};

/// Union representing all of the possible Abi members.
pub const AbiItem = union(enum) {
    abiFunction: Function,
    abiEvent: Event,
    abiError: Error,
    abiConstructor: Constructor,
    abiFallback: Fallback,
    abiReceive: Receive,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        const abitype = source.object.get("type") orelse return error.MissingField;

        if (abitype != .string)
            return error.UnexpectedToken;

        const abitype_enum = std.meta.stringToEnum(Abitype, abitype.string) orelse return error.UnexpectedToken;

        switch (abitype_enum) {
            .function => return @unionInit(@This(), "abiFunction", try std.json.parseFromValueLeaky(Function, allocator, source, options)),
            .event => return @unionInit(@This(), "abiEvent", try std.json.parseFromValueLeaky(Event, allocator, source, options)),
            .@"error" => return @unionInit(@This(), "abiError", try std.json.parseFromValueLeaky(Error, allocator, source, options)),
            .constructor => return @unionInit(@This(), "abiConstructor", try std.json.parseFromValueLeaky(Constructor, allocator, source, options)),
            .fallback => return @unionInit(@This(), "abiFallback", try std.json.parseFromValueLeaky(Fallback, allocator, source, options)),
            .receive => return @unionInit(@This(), "abiReceive", try std.json.parseFromValueLeaky(Receive, allocator, source, options)),
        }
    }

    pub fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            inline else => |item| if (@hasDecl(@TypeOf(item), "deinit")) item.deinit(allocator),
        }
    }

    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            inline else => |value| try value.format(layout, opts, writer),
        }
    }
};

pub const Abi = []const AbiItem;

test "Formatting" {
    try testing.expectFmt("error Foo(address bar)", "{s}", .{Error{ .type = .@"error", .name = "Foo", .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }} }});
    try testing.expectFmt("event Foo(address bar)", "{s}", .{Event{ .type = .event, .name = "Foo", .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar", .indexed = false }} }});
    try testing.expectFmt("constructor(address bar) payable", "{s}", .{Constructor{ .type = .constructor, .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }}, .stateMutability = .payable }});
    try testing.expectFmt("receive() external payable", "{s}", .{Receive{ .type = .receive, .stateMutability = .payable }});
    try testing.expectFmt("fallback()", "{s}", .{Fallback{ .type = .fallback, .stateMutability = .nonpayable }});
    try testing.expectFmt("fallback() payable", "{s}", .{Fallback{ .type = .fallback, .stateMutability = .payable }});
    try testing.expectFmt("function Foo(address bar)", "{s}", .{Function{ .type = .function, .name = "Foo", .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }}, .stateMutability = .nonpayable, .outputs = &.{} }});
    try testing.expectFmt("function Foo(address bar) view", "{s}", .{Function{ .type = .function, .name = "Foo", .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }}, .stateMutability = .view, .outputs = &.{} }});
    try testing.expectFmt("function Foo(address bar) pure returns (bool baz)", "{s}", .{Function{ .type = .function, .name = "Foo", .inputs = &.{.{ .type = .{ .address = {} }, .name = "bar" }}, .stateMutability = .pure, .outputs = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }});
    try testing.expectFmt("function Foo((string[] foo, uint256 bar, (bytes[] fizz, bool buzz, int256[] jazz)[] baz) fizzbuzz)", "{s}", .{Function{ .type = .function, .name = "Foo", .inputs = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }}, .stateMutability = .nonpayable, .outputs = &.{} }});
    try testing.expectFmt("function Foo((string[] foo, uint256 bar, (bytes[] fizz, bool buzz, int256[] jazz)[] baz) fizzbuzz)", "{s}", .{AbiItem{ .abiFunction = .{ .type = .function, .name = "Foo", .inputs = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }}, .stateMutability = .nonpayable, .outputs = &.{} } }});
}
