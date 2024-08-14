const decoder = @import("../decoding/decoder.zig");
const encoder = @import("../encoding/encoder.zig");
const std = @import("std");
const testing = std.testing;

// Types
const AbiDecoded = decoder.AbiDecoded;
const Allocator = std.mem.Allocator;
const DecodeOptions = decoder.DecodeOptions;
const ParamType = @import("param_type.zig").ParamType;

/// Struct to represent solidity Abi Paramters
pub const AbiParameter = struct {
    name: []const u8,
    type: ParamType,
    internalType: ?[]const u8 = null,
    components: ?[]const AbiParameter = null,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.components) |components| {
            for (components) |component| {
                component.deinit(alloc);
            }
            alloc.free(components);
        }
    }

    /// Encode the paramters based on the values provided and `self`.
    /// Runtime reflection based on the provided values will occur to determine
    /// what is the correct method to use to encode the values
    ///
    /// Caller owns the memory.
    ///
    /// Consider using `encodeAbiParametersComptime` if the parameter is
    /// comptime know and you want better typesafety from the compiler
    pub fn encode(self: @This(), allocator: Allocator, values: anytype) ![]u8 {
        const encoded = try encoder.encodeAbiParameters(allocator, &.{self}, values);
        defer encoded.deinit();

        const hexed = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded.data)});

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
    pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) !AbiDecoded(T) {
        return decoder.decodeAbiParameter(allocator, T, &.{self}, encoded, options);
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.format(layout, opts, writer);
                if (i != components.len - 1) try writer.print(", ", .{});
            }
            try writer.print(")", .{});
        }

        try self.type.typeToString(writer);
        if (self.name.len != 0) try writer.print(" {s}", .{self.name});
    }

    /// Format the struct into a human readable string.
    /// Intended to use for hashing purposes.
    pub fn prepare(self: @This(), writer: anytype) !void {
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

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.components) |components| {
            for (components) |component| {
                component.deinit(alloc);
            }
            alloc.free(components);
        }
    }

    /// Format the struct into a human readable string.
    pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.components) |components| {
            try writer.print("(", .{});
            for (components, 0..) |component, i| {
                try component.format(layout, opts, writer);
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
    pub fn prepare(self: @This(), writer: anytype) !void {
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

test "Json parse simple paramter" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "address"
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internalType);
    try testing.expect(null == parsed.value.components);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.type);
    try testing.expectEqualStrings("foo", parsed.value.name);
}

test "Json parse simple event paramter" {
    const sliceIndexed =
        \\ {
        \\  "name": "foo",
        \\  "type": "address",
        \\  "indexed": true
        \\ }
    ;

    const parsedEvent = try std.json.parseFromSlice(AbiEventParameter, testing.allocator, sliceIndexed, .{});
    defer parsedEvent.deinit();

    try testing.expect(null == parsedEvent.value.internalType);
    try testing.expect(null == parsedEvent.value.components);
    try testing.expect(parsedEvent.value.indexed);
    try testing.expectEqual(ParamType{ .address = {} }, parsedEvent.value.type);
    try testing.expectEqualStrings("foo", parsedEvent.value.name);
}

test "Json parse with components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internalType);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
}

test "Json parse with multiple components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      },
        \\      {
        \\          "type": "int",
        \\          "name": "baz"
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internalType);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqual(ParamType{ .int = 256 }, parsed.value.components.?[1].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
    try testing.expectEqualStrings("baz", parsed.value.components.?[1].name);
}

test "Json parse with nested components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      },
        \\      {
        \\      "name": "foo",
        \\      "type": "tuple",
        \\      "components": [
        \\              {
        \\                  "type": "address",
        \\                  "name": "bar"
        \\              }
        \\          ]
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internalType);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.components.?[1].type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[1].components.?[0].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
    try testing.expectEqualStrings("foo", parsed.value.components.?[1].name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[1].components.?[0].name);
}

test "Json parse error" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "adress"
        \\ }
    ;

    try testing.expectError(error.InvalidEnumTag, std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{}));

    const sslice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple[]",
        \\  "components": [
        \\       {
        \\          "type": "address",
        \\          "name": "bar",
        \\          "indexed": false
        \\       }
        \\   ]
        \\ }
    ;

    try testing.expectError(error.UnknownField, std.json.parseFromSlice(AbiParameter, testing.allocator, sslice, .{}));
}

test "Prepare" {
    {
        const param: AbiParameter = .{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .address = {} }, .name = "bar" }} };

        var c_writter = std.io.countingWriter(std.io.null_writer);
        try param.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try testing.allocator.alloc(u8, size);
        defer testing.allocator.free(buffer);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try param.prepare(buf_writter.writer());

        const slice = buf_writter.getWritten();

        try testing.expectEqualStrings(slice, "(address)");
    }
    {
        const param: AbiEventParameter = .{ .type = .{ .tuple = {} }, .name = "foo", .indexed = false, .components = &.{.{ .type = .{ .address = {} }, .name = "bar" }} };

        var c_writter = std.io.countingWriter(std.io.null_writer);
        try param.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try testing.allocator.alloc(u8, size);
        defer testing.allocator.free(buffer);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try param.prepare(buf_writter.writer());

        const slice = buf_writter.getWritten();

        try testing.expectEqualStrings(slice, "(address)");
    }
}

test "Format" {
    {
        const param: AbiEventParameter = .{ .type = .{ .tuple = {} }, .name = "foo", .indexed = false, .components = &.{.{ .type = .{ .address = {} }, .name = "bar" }} };
        try testing.expectFmt("(address bar) foo", "{s}", .{param});
    }
    {
        const param: AbiParameter = .{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .address = {} }, .name = "bar" }} };
        try testing.expectFmt("(address bar) foo", "{s}", .{param});
    }
}
