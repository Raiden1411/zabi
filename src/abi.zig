const encoder = @import("encoder.zig");
const meta = @import("meta/meta.zig");
const std = @import("std");
const testing = std.testing;
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiEventParameter = @import("abi_parameter.zig").AbiEventParameter;
const Allocator = std.mem.Allocator;
const Extract = meta.Extract;
const StateMutability = @import("state_mutability.zig").StateMutability;
const UnionParser = meta.UnionParser;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

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

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(alloc);
        }
        alloc.free(self.inputs);

        for (self.outputs) |output| {
            output.deinit(alloc);
        }
        alloc.free(self.outputs);
    }

    pub fn encode(self: @This(), alloc: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(alloc);
        defer alloc.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        const encoded_params = try encoder.encodeAbiParameters(alloc, self.inputs, values);
        defer encoded_params.deinit();

        const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
        defer alloc.free(hexed);

        const buffer = try alloc.alloc(u8, 8 + hexed.len);

        @memcpy(buffer[0..8], hash_hex[0..8]);
        @memcpy(buffer[8..], hexed);

        return buffer;
    }

    pub fn encodeOutputs(self: @This(), alloc: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(alloc);
        defer alloc.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        const encoded_params = try encoder.encodeAbiParameters(alloc, self.outputs, values);
        defer encoded_params.deinit();

        const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
        defer alloc.free(hexed);

        const buffer = try alloc.alloc(u8, 8 + hexed.len);

        @memcpy(buffer[0..8], hash_hex[0..8]);
        @memcpy(buffer[8..], hexed);

        return buffer;
    }

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
                if (i != self.inputs.len - 1) try writer.print(", ", .{});
            }
            try writer.print(")", .{});
        }
    }

    pub fn allocPrepare(self: @This(), alloc: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try alloc.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

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

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(alloc);
        }
        alloc.free(self.inputs);
    }

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

    pub fn encode(self: @This(), alloc: Allocator) ![]u8 {
        const prep_signature = try self.allocPrepare(alloc);
        defer alloc.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        return try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.bytesToHex(hashed, .lower)});
    }

    pub fn allocPrepare(self: @This(), alloc: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try alloc.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

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

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(alloc);
        }
        alloc.free(self.inputs);
    }

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

    pub fn encode(self: @This(), alloc: Allocator, values: anytype) ![]u8 {
        const prep_signature = try self.allocPrepare(alloc);
        defer alloc.free(prep_signature);

        var hashed: [Keccak256.digest_length]u8 = undefined;
        Keccak256.hash(prep_signature, &hashed, .{});

        const hash_hex = std.fmt.bytesToHex(hashed, .lower);

        const encoded_params = try encoder.encodeAbiParameters(alloc, self.inputs, values);
        defer encoded_params.deinit();

        const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});
        defer alloc.free(hexed);

        const buffer = try alloc.alloc(u8, 8 + hexed.len);

        @memcpy(buffer[0..8], hash_hex[0..8]);
        @memcpy(buffer[8..], hexed);

        return buffer;
    }

    pub fn allocPrepare(self: @This(), alloc: Allocator) ![]u8 {
        var c_writter = std.io.countingWriter(std.io.null_writer);
        try self.prepare(c_writter.writer());

        const bytes = c_writter.bytes_written;
        const size = std.math.cast(usize, bytes) orelse return error.OutOfMemory;

        const buffer = try alloc.alloc(u8, size);

        var buf_writter = std.io.fixedBufferStream(buffer);
        try self.prepare(buf_writter.writer());

        return buf_writter.getWritten();
    }

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

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        for (self.inputs) |input| {
            input.deinit(alloc);
        }
        alloc.free(self.inputs);
    }

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

    pub fn encode(self: @This(), alloc: Allocator, values: anytype) ![]u8 {
        const encoded_params = try encoder.encodeAbiParameters(alloc, self.inputs, values);
        defer encoded_params.deinit();

        const hexed = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(encoded_params.data)});

        return hexed;
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

    pub usingnamespace UnionParser(@This());

    pub fn deinit(self: @This(), alloc: Allocator) void {
        switch (self) {
            inline else => |item| if (@hasDecl(@TypeOf(item), "deinit")) item.deinit(alloc),
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
}
