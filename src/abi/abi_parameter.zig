const decoder = @import("zabi-decoding").abi_decoder;
const encoder = @import("zabi-encoding").abi_encoding;
const std = @import("std");
const testing = std.testing;

// Types
const AbiDecoded = decoder.AbiDecoded;
const Allocator = std.mem.Allocator;
const DecoderErrors = decoder.DecoderErrors;
const DecodeOptions = decoder.DecodeOptions;
const EncodeErrors = encoder.EncodeErrors;
const ParamType = @import("param_type.zig").ParamType;
const Writer = std.Io.Writer;

/// Set of possible errors when running `allocPrepare`
pub const PrepareErrors = Allocator.Error || error{NoSpaceLeft} || Writer.Error;

/// Struct to represent solidity Abi Paramters
pub const AbiParameter = struct {
    name: []const u8,
    type: ParamType,
    internalType: ?[]const u8 = null,
    components: ?[]const AbiParameter = null,

    /// Encode the paramters based on the values provided and `self`.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `encodeAbiParametersComptime` if the parameter is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(
        self: @This(),
        allocator: Allocator,
        values: anytype,
    ) EncodeErrors![]u8 {
        const encoded = try encoder.encodeAbiParameters(allocator, &.{self}, values);
        defer encoded.deinit();

        const hexed = try std.fmt.allocPrint(allocator, "{x}", .{encoded});

        return hexed;
    }

    /// Decode the paramters based on self.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory only if the param type is a dynamic array
    ///
    /// Consider using `decodeAbiParameters` if the parameter is
    /// comptime know and you want better typesafety from the compiler
    pub fn decode(
        self: @This(),
        comptime T: type,
        allocator: Allocator,
        encoded: []const u8,
        options: DecodeOptions,
    ) DecoderErrors!AbiDecoded(T) {
        return decoder.decodeAbiParameter(allocator, T, &.{self}, encoded, options);
    }

    /// Format the struct into a human readable string.
    pub fn format(
        self: @This(),
        writer: anytype,
    ) std.Io.Writer.Error!void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.format(writer);
                if (i != components.len - 1) try writer.print(", ", .{});
            }
            try writer.print(")", .{});
        }

        try self.type.typeToString(writer);
        if (self.name.len != 0) try writer.print(" {s}", .{self.name});
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(
        self: @This(),
        writer: *Writer,
    ) PrepareErrors!void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.prepare(writer);
                if (i != components.len - 1) try writer.print(",", .{});
            }
            try writer.print(")", .{});
        }

        try self.type.typeToString(writer);
    }
};

/// Struct to represent solidity Abi Event Paramters
pub const AbiEventParameter = struct {
    name: []const u8,
    type: ParamType,
    internalType: ?[]const u8 = null,
    indexed: bool,
    components: ?[]const AbiParameter = null,

    /// Format the struct into a human readable string.
    pub fn format(
        self: @This(),
        writer: anytype,
    ) std.Io.Writer.Error!void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.format(writer);
                if (i != components.len - 1) try writer.print(", ", .{});
            }
            try writer.print(")", .{});
        }

        try self.type.typeToString(writer);
        if (self.indexed) try writer.print(" indexed", .{});
        if (self.name.len != 0) try writer.print(" {s}", .{self.name});
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(
        self: @This(),
        writer: *Writer,
    ) PrepareErrors!void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.prepare(writer);
                if (i != components.len - 1) try writer.print(",", .{});
            }
            try writer.print(")", .{});
        }

        try self.type.typeToString(writer);
    }
};
