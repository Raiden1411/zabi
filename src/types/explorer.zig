const std = @import("std");
const meta = @import("../meta/json.zig");
const meta_utils = @import("../meta/utils.zig");
const types = @import("../types/ethereum.zig");
const block = @import("../types/block.zig");
const utils = @import("../utils/utils.zig");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const BlockTag = block.BlockTag;
const ConvertToEnum = meta_utils.ConvertToEnum;
const Hash = types.Hash;
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
    message: enum { NOK, NOTOK } = .NOK,
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

            const status = std.meta.stringToEnum(enum { OK, NOTOK, NOK }, message.string) orelse return error.UnexpectedToken;

            switch (status) {
                .NOTOK => return @unionInit(@This(), "error", try std.json.parseFromValueLeaky(ExplorerErrorResponse, allocator, source, options)),
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

/// Result from the api call of `getMultiAddressBalance`
pub const MultiAddressBalance = struct {
    /// The address of the account.
    account: Address,
    /// The balance of the account.
    balance: u256,

    pub usingnamespace RequestParser(@This());
};

/// Transaction represented by a `etherscan` like client.
pub const ExplorerTransaction = struct {
    /// The block number where the transaction was mined
    blockNumber: u64,
    /// The time when the transaction was commited.
    timeStamp: u64,
    /// The transaction hash
    hash: Hash,
    /// The transaction nonce
    nonce: u64,
    /// The block hash
    blockHash: Hash,
    /// Index of the transaction in the memory pool
    transactionIndex: usize,
    /// The sender of this transaction
    from: Address,
    /// The target address.
    to: ?Address,
    /// The value sent.
    value: u256,
    /// The gas limit of the transaction
    gas: u64,
    /// The gas price of the transaction.
    gasPrice: u64,
    /// If the transaction failed. Use `@bitCast` to convert to `bool`.
    isError: u1,
    /// The status of the receipt. Use `@bitCast` to convert to `bool`.
    txreceipt_status: u1,
    /// The transaction data.
    input: []u8,
    /// The gas used by the transaction.
    gasUsed: u64,
    /// The number of confirmations.
    confirmations: u64,
    /// The methodId of the contract if it interacted with any.
    methodId: ?[]u8,
    /// The contract method name if the transaction interacted with one.
    functionName: ?[]const u8,
    /// The contract address in case it exists.
    contractAddress: ?Address = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var seen: std.enums.EnumFieldStruct(ConvertToEnum(@This()), u32, 0) = .{};
        var result: @This() = undefined;

        if (source.object.get("to")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.to = utils.addressToBytes(value.string) catch null;
            @field(seen, "to") = 1;
        }

        if (source.object.get("from")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.from = utils.addressToBytes(value.string) catch return error.LengthMismatch;
            @field(seen, "from") = 1;
        }

        if (source.object.get("hash")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.hash = utils.hashToBytes(value.string) catch return error.LengthMismatch;
            @field(seen, "hash") = 1;
        }

        if (source.object.get("blockHash")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.blockHash = utils.hashToBytes(value.string) catch return error.LengthMismatch;
            @field(seen, "blockHash") = 1;
        }

        if (source.object.get("contractAddress")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.contractAddress = utils.addressToBytes(value.string) catch null;
            @field(seen, "contractAddress") = 1;
        }

        if (source.object.get("methodId")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.methodId = blk: {
                if (value.string.len != 0) {
                    const slice = if (std.mem.startsWith(u8, value.string, "0x")) value.string[2..] else value.string[0..];

                    if (slice.len == 0)
                        break :blk null;

                    const buffer = try allocator.alloc(u8, @divExact(slice.len, 2));
                    _ = std.fmt.hexToBytes(buffer, slice) catch return error.UnexpectedToken;

                    break :blk buffer;
                } else break :blk null;
            };
            @field(seen, "methodId") = 1;
        }

        if (source.object.get("functionName")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.functionName = if (value.string.len != 0) value.string else null;
            @field(seen, "functionName") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 1) {
                        // We parse but discard it. Parses as `[]const u8` because it would fail otherwise
                        // as some of our types are parsed in a non RFC compliance.
                        _ = try std.json.innerParseFromValue([]const u8, allocator, key_value.value_ptr.*, options);

                        break;
                    }

                    @field(seen, field.name) = 1;
                    @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                    break;
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value) |default_value| {
                    @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default_value))).*;
                } else return error.MissingField,
                1 => {},
                else => {
                    switch (options.duplicate_field_behavior) {
                        .@"error" => return error.DuplicateField,
                        else => {},
                    }
                },
            }
        }

        return result;
    }

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};

pub const TransactionListRequest = struct {
    /// The target address.
    address: Address,
    /// The start block from where you want to grab the list.
    startblock: usize,
    /// The end block from where you want to grab the list.
    endblock: usize,
};

pub const MultiAddressBalanceRequest = struct {
    /// The target addresses.
    address: []const Address,
    /// The block tag to use.
    tag: BlockTag,
};

pub const AddressBalanceRequest = struct {
    /// The target address.
    address: Address,
    /// The block tag to use.
    tag: BlockTag,
};
