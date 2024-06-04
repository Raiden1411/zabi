const std = @import("std");
const meta = @import("../meta/json.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const RequestParser = meta.RequestParser;
const Value = std.json.Value;

/// The json response from a etherscan like explorer
pub fn ExplorerResponse(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        response: T,

        pub fn deinit(self: @This()) void {
            const child_allocator = self.arena.child_allocator;

            self.arena.deinit();

            child_allocator.destroy(self.arena);
        }

        pub fn fromJson(arena: *ArenaAllocator, value: T) @This() {
            return .{
                .arena = arena,
                .response = value,
            };
        }
    };
}

/// The json success response from a etherscan like explorer
pub fn ExplorerSuccessResponse(comptime T: type) type {
    return struct {
        status: u1 = 1,
        message: enum { OK } = .OK,
        result: T,

        pub usingnamespace RequestParser(@This());
    };
}

/// The json error response from a etherscan like explorer
pub const ExplorerErrorResponse = struct {
    status: u1 = 0,
    message: enum { NOK } = .NOK,
    result: []const u8,

    pub usingnamespace RequestParser(@This());
};

/// The response represented as a union of possible responses.
/// Returns the `@error` field from json parsing in case the message is `NOK`.
pub fn ExplorerRequestResponse(comptime T: type) type {
    return union(enum) {
        success: ExplorerSuccessResponse(T),
        @"error": ExplorerErrorResponse,

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            const json_value = try Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            if (source != .object)
                return error.UnexpectedToken;

            const message = source.object.get("message") orelse return error.UnexpectedToken;

            if (message != .string)
                return error.UnexpectedToken;

            const status = std.meta.stringToEnum(enum { OK, NOK }, message.string) orelse return error.UnexpectedToken;

            switch (status) {
                .NOK => return @unionInit(@This(), "error", try std.json.parseFromValueLeaky(ExplorerErrorResponse, allocator, source, options)),
                .OK => return @unionInit(@This(), "success", try std.json.parseFromValueLeaky(ExplorerSuccessResponse(T), allocator, source, options)),
            }
        }

        pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}

/// Set of predefined endpoints.
pub const EndPoints = union(enum) {
    /// Currently doesn't support tls v1.3 so it won't work until
    /// zig gets support for tls v1.2
    /// Assign it null if you would like to set the default endpoint value.
    ethereum: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    optimism: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    localhost: ?[]const u8,

    /// Gets the associated endpoint or the default one.
    pub fn getEndpoint(self: @This()) []const u8 {
        switch (self) {
            .ethereum => |path| return path orelse "https://api.etherscan.io/api",
            .optimism => |path| return path orelse "https://api-optimistic.etherscan.io/api",
            .localhost => |path| return path orelse "http://localhost:3000/",
        }
    }
};
