const encoder = zabi_encoding.abi_encoding;
const encoder_logs = zabi_encoding.logs_encoding;
const decoder = zabi_decoding.abi_decoder;
const decoder_logs = zabi_decoding.logs_decoder;
const meta = @import("zabi-meta");
const std = @import("std");
const types = @import("zabi-types").ethereum;
const abi = @import("root.zig");
const zabi_encoding = @import("zabi-encoding");
const zabi_decoding = @import("zabi-decoding");

// Types
const AbiDecoded = decoder.AbiDecoded;
const AbiEncoder = encoder.AbiEncoder;
const AbiEventParameter = abi.abi_parameter.AbiEventParameter;
const AbiParameter = abi.abi_parameter.AbiParameter;
const AbiParametersToPrimative = meta.abi.AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const DecodeOptions = decoder.DecodeOptions;
const DecodeErrors = decoder.DecoderErrors;
const EncodeErrors = encoder.EncodeErrors;
const EncodeLogsErrors = encoder_logs.EncodeLogsErrors;
const Extract = meta.utils.Extract;
const Hash = types.Hash;
const LogDecoderOptions = decoder_logs.LogDecoderOptions;
const LogsDecoderErrors = decoder_logs.LogsDecoderErrors;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const StateMutability = abi.state_mutability.StateMutability;
const Value = std.json.Value;

/// Set of possible abi values according to the abi spec.
pub const Abitype = enum {
    function,
    @"error",
    event,
    constructor,
    fallback,
    receive,
};

/// Set of possible errors when running `allocPrepare`
pub const PrepareErrors = Allocator.Error || error{NoSpaceLeft};

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

    /// Abi Encode the struct signature based on the values provided.
    ///
    /// Compile time reflection is used to encode based on type of the values provided.
    pub fn encodeFromReflection(
        self: @This(),
        allocator: Allocator,
        values: anytype,
    ) EncodeErrors![]u8 {
        var buffer: [256]u8 = undefined;

        var stream = std.io.fixedBufferStream(&buffer);
        try self.prepare(stream.writer());

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(stream.getWritten(), &hashed, .{});

        var abi_encoder: AbiEncoder = .empty;

        try abi_encoder.preEncodeValuesFromReflection(allocator, values);
        try abi_encoder.heads.appendSlice(allocator, hashed[0..4]);

        return abi_encoder.encodePointers(allocator);
    }
    /// Abi Encode the struct signature based on the values provided.
    ///
    /// This is only available if `self` is know at comptime. With this we will know the exact type
    /// of what the `values` should be.
    pub fn encode(
        comptime self: @This(),
        allocator: Allocator,
        values: AbiParametersToPrimative(self.inputs),
    ) EncodeErrors![]u8 {
        return encoder.encodeAbiFunction(self, allocator, values);
    }
    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values.
    /// This methods will run the values against the `outputs` proprety.
    ///
    /// Caller owns the memory.
    pub fn encodeOutputs(
        comptime self: @This(),
        allocator: Allocator,
        values: AbiParametersToPrimative(self.outputs),
    ) Allocator.Error![]u8 {
        return encoder.encodeAbiFunctionOutputs(self, allocator, values);
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
    pub fn decode(
        self: @This(),
        comptime T: type,
        allocator: Allocator,
        encoded: []const u8,
        options: DecodeOptions,
    ) DecodeErrors!AbiDecoded(T) {
        _ = self;
        return decoder.decodeAbiFunction(T, allocator, encoded, options);
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
    pub fn decodeOutputs(
        self: @This(),
        comptime T: type,
        allocator: Allocator,
        encoded: []const u8,
        options: DecodeOptions,
    ) DecodeErrors!AbiDecoded(T) {
        _ = self;
        return decoder.decodeAbiFunctionOutputs(T, allocator, encoded, options);
    }
    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
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
    pub fn allocPrepare(self: @This(), allocator: Allocator) PrepareErrors![]u8 {
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
    pub fn prepare(self: @This(), writer: anytype) PrepareErrors!void {
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
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print(" {s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(",", .{});
        }
        try writer.print(")", .{});
    }
    /// Generates the hash of the struct signatures.
    pub fn encode(self: @This()) PrepareErrors!Hash {
        var buffer: [256]u8 = undefined;

        var stream = std.io.fixedBufferStream(&buffer);
        try self.prepare(stream.writer());

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(stream.getWritten(), &hashed, .{});

        return hashed;
    }
    /// Encode the struct signature based on the values provided.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    pub fn encodeLogTopics(self: @This(), allocator: Allocator, values: anytype) EncodeLogsErrors![]const ?Hash {
        return try encoder_logs.encodeLogTopics(allocator, self, values);
    }
    /// Decode the encoded log topics based on the event signature and the provided type.
    ///
    /// Caller owns the memory.
    pub fn decodeLogTopics(self: @This(), comptime T: type, encoded: []const ?Hash, options: LogDecoderOptions) LogsDecoderErrors!T {
        _ = self;
        return try decoder_logs.decodeLogs(T, encoded, options);
    }
    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    ///
    /// Caller owns the memory.
    pub fn allocPrepare(self: @This(), allocator: Allocator) PrepareErrors![]u8 {
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
    pub fn prepare(self: @This(), writer: anytype) PrepareErrors!void {
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

    pub fn deinit(self: @This(), allocator: Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("{s}", .{@tagName(self.type)});
        try writer.print(" {s}", .{self.name});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(", ", .{});
        }
        try writer.print(")", .{});
    }

    /// Abi Encode the struct signature based on the values provided.
    ///
    /// This is only available if `self` is know at comptime. With this we will know the exact type
    /// of what the `values` should be.
    pub fn encode(comptime self: @This(), allocator: Allocator, values: AbiParametersToPrimative(self.inputs)) EncodeErrors![]u8 {
        return encoder.encodeAbiError(self, allocator, values);
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
    pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) DecodeErrors!AbiDecoded(T) {
        _ = self;
        return decoder.decodeAbiError(T, allocator, encoded, options);
    }
    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    ///
    /// Caller owns the memory.
    pub fn allocPrepare(self: @This(), allocator: Allocator) PrepareErrors![]u8 {
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
    pub fn prepare(self: @This(), writer: anytype) PrepareErrors!void {
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

    pub fn deinit(self: @This(), allocator: Allocator) void {
        for (self.inputs) |input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        try writer.print("{s}", .{@tagName(self.type)});

        try writer.print("(", .{});
        for (self.inputs, 0..) |input, i| {
            try input.format(layout, opts, writer);
            if (i != self.inputs.len - 1) try writer.print(", ", .{});
        }
        try writer.print(")", .{});

        if (self.stateMutability != .nonpayable) try writer.print(" {s}", .{@tagName(self.stateMutability)});
    }
    /// Abi Encode the struct signature based on the values provided.
    ///
    /// Compile time reflection is used to encode based on type of the values provided.
    pub fn encodeFromReflection(
        self: @This(),
        allocator: Allocator,
        values: anytype,
    ) EncodeErrors![]u8 {
        _ = self;

        return encoder.encodeAbiParametersFromReflection(allocator, values);
    }
    /// Abi Encode the struct signature based on the values provided.
    ///
    /// This is only available if `self` is know at comptime. With this we will know the exact type
    /// of what the `values` should be.
    pub fn encode(
        comptime self: @This(),
        allocator: Allocator,
        values: AbiParametersToPrimative(self.inputs),
    ) EncodeErrors![]u8 {
        return encoder.encodeAbiParameters(self.inputs, allocator, values);
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
    pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) DecodeErrors!AbiDecoded(T) {
        _ = self;
        return decoder.decodeAbiConstructor(T, allocator, encoded, options);
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
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
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
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
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

    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            inline else => |value| try value.format(layout, opts, writer),
        }
    }
};

/// Abi representation in ZIG.
pub const Abi = []const AbiItem;
