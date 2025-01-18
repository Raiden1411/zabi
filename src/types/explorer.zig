const abi = @import("zabi-abi").abitypes;
const block = @import("block.zig");
const meta = @import("zabi-meta");
const std = @import("std");
const testing = std.testing;
const types = @import("ethereum.zig");
const utils = @import("zabi-utils").utils;

const Abi = abi.Abi;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const BlockTag = block.BlockTag;
const ConvertToEnum = meta.utils.ConvertToEnum;
const Hash = types.Hash;
const ParseOptions = std.json.ParseOptions;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const SemanticVersion = std.SemanticVersion;
const Value = std.json.Value;
const Uri = std.Uri;

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

        pub fn jsonParse(
            allocator: Allocator,
            source: anytype,
            options: ParseOptions,
        ) ParseError(@TypeOf(source.*))!@This() {
            return meta.json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(
            allocator: Allocator,
            source: Value,
            options: ParseOptions,
        ) ParseFromValueError!@This() {
            return meta.json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(
            self: @This(),
            writer_stream: anytype,
        ) @TypeOf(writer_stream.*).Error!void {
            return meta.json.jsonStringify(@This(), self, writer_stream);
        }
    };
}

/// The json error response from a etherscan like explorer
pub const ExplorerErrorResponse = struct {
    status: u1 = 0,
    message: []const u8,
    result: []const u8,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// The response represented as a union of possible responses.
/// Returns the `@error` field from json parsing in case the message is `NOK`.
pub fn ExplorerRequestResponse(comptime T: type) type {
    return union(enum) {
        success: ExplorerSuccessResponse(T),
        @"error": ExplorerErrorResponse,

        pub fn jsonParse(
            allocator: Allocator,
            source: anytype,
            options: ParseOptions,
        ) ParseError(@TypeOf(source.*))!@This() {
            const json_value = try Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(
            allocator: Allocator,
            source: Value,
            options: ParseOptions,
        ) ParseFromValueError!@This() {
            if (source != .object)
                return error.UnexpectedToken;

            const message = source.object.get("message") orelse return error.UnexpectedToken;

            if (message != .string)
                return error.UnexpectedToken;

            const status = std.meta.stringToEnum(enum { OK }, message.string);

            if (status != null)
                return @unionInit(@This(), "success", try std.json.parseFromValueLeaky(ExplorerSuccessResponse(T), allocator, source, options));

            return @unionInit(@This(), "error", try std.json.parseFromValueLeaky(ExplorerErrorResponse, allocator, source, options));
        }

        pub fn jsonStringify(
            self: @This(),
            stream: anytype,
        ) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}

/// Set of predefined block explorer endpoints.
/// For now these must have support for TLS v1.3
/// This only supports etherscan like block explorers.
pub const EndPoints = union(enum) {
    /// Assign it null if you would like to set the default endpoint value.
    arbitrum: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    arbitrum_sepolia: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    base: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    bsc: ?[]const u8,
    /// Currently doesn't support tls v1.3 so it won't work until
    /// zig gets support for tls v1.2
    /// Assign it null if you would like to set the default endpoint value.
    ethereum: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    fantom: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    localhost: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    moonbeam: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    optimism: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    polygon: ?[]const u8,
    /// Assign it null if you would like to set the default endpoint value.
    sepolia: ?[]const u8,

    /// Gets the associated endpoint or the default one.
    pub fn getEndpoint(self: @This()) []const u8 {
        switch (self) {
            .arbitrum => |path| return path orelse "https://api.arbiscan.io/api",
            .arbitrum_sepolia => |path| return path orelse "https://api-sepolia.arbiscan.io/api",
            .base => |path| return path orelse "https://api.basescan.org/api",
            .bsc => |path| return path orelse "https://api.bscscan.io/api",
            .ethereum => |path| return path orelse "https://api.etherscan.io/api",
            .fantom => |path| return path orelse "https://api.ftmscan.com/api",
            .localhost => |path| return path orelse "http://localhost:3000/",
            .moonbeam => |path| return path orelse "https://api-moonbeam.moonscan.io/api",
            .optimism => |path| return path orelse "https://api-optimistic.etherscan.io/api",
            .polygon => |path| return path orelse "https://api.polygonscan.io/api",
            .sepolia => |path| return path orelse "https://api-sepolia.etherscan.io/api",
        }
    }
};

/// Result from the api call of `getMultiAddressBalance`
pub const MultiAddressBalance = struct {
    /// The address of the account.
    account: Address,
    /// The balance of the account.
    balance: u256,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Token transaction represented by a `etherscan` like client.
pub const TokenExplorerTransaction = struct {
    /// The block number where the transaction was mined
    blockNumber: u64,
    /// The time when the transaction was commited.
    timeStamp: u64,
    /// The transaction hash
    hash: Hash,
    /// The transaction nonce.
    nonce: u64,
    /// The blockHash this transaction was mined.
    blockHash: Hash,
    /// The sender of this transaction
    from: Address,
    /// The contract address in case it exists.
    contractAddress: Address,
    /// The target address.
    to: Address,
    /// The value sent. Only used for erc20 tokens.
    value: ?u256 = null,
    /// The token Id. Only used for erc721 and erc1155 tokens.
    tokenId: ?u256 = null,
    /// The token name.
    tokenName: []const u8,
    /// The token symbol.
    tokenSymbol: []const u8,
    /// The token decimal. Only used for erc20 and erc721 tokens.
    tokenDecimal: ?u8 = null,
    /// The index of this transaction on the mempool
    transactionIndex: usize,
    /// The gas limit of the transaction
    gas: u64,
    /// The gas price of this transaction.
    gasPrice: u64,
    /// The gas used by the transaction.
    gasUsed: u64,
    /// The cumulative gas used by the transaction.
    cumulativeGasUsed: u64,
    /// Input field that has been deprecated.
    input: []const u8 = "deprecated",
    /// The total number of confirmations
    confirmations: usize,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var seen: std.enums.EnumFieldStruct(ConvertToEnum(@This()), u32, 0) = .{};
        var result: @This() = undefined;

        if (source.object.get("to")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.to = utils.addressToBytes(value.string) catch return error.LengthMismatch;
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

            result.contractAddress = utils.addressToBytes(value.string) catch return error.LengthMismatch;
            @field(seen, "contractAddress") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
};

/// Internal transaction represented by a `etherscan` like client.
pub const InternalExplorerTransaction = struct {
    /// The block number where the transaction was mined
    blockNumber: u64,
    /// The time when the transaction was commited.
    timeStamp: u64,
    /// The transaction hash
    hash: Hash,
    /// The sender of this transaction
    from: Address,
    /// The target address.
    to: ?Address,
    /// The value sent.
    value: u256,
    /// The contract address in case it exists.
    contractAddress: ?Address,
    /// The transaction data.
    input: ?[]u8,
    /// The transaction type.
    type: enum { call },
    /// The gas limit of the transaction
    gas: u64,
    /// The gas used by the transaction.
    gasUsed: u64,
    /// If the transaction failed. Use `@bitCast` to convert to `bool`.
    isError: u1,
    /// The status of the receipt. Use `@bitCast` to convert to `bool`.
    traceId: []const u8,
    /// The error code in case it exists.
    errCode: ?i64,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
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

        if (source.object.get("contractAddress")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.contractAddress = utils.addressToBytes(value.string) catch null;
            @field(seen, "contractAddress") = 1;
        }

        if (source.object.get("errCode")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            if (value.string.len == 0) {
                result.errCode = null;
                @field(seen, "errCode") = 1;
            }
        }

        if (source.object.get("input")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.input = blk: {
                if (value.string.len != 0) {
                    const slice = if (std.mem.startsWith(u8, value.string, "0x")) value.string[2..] else value.string[0..];

                    if (slice.len == 0)
                        break :blk null;

                    const buffer = try allocator.alloc(u8, @divExact(slice.len, 2));
                    _ = std.fmt.hexToBytes(buffer, slice) catch return error.UnexpectedToken;

                    break :blk buffer;
                } else break :blk null;
            };

            @field(seen, "input") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
    input: ?[]u8,
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

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
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

        if (source.object.get("input")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.input = blk: {
                if (value.string.len != 0) {
                    const slice = if (std.mem.startsWith(u8, value.string, "0x")) value.string[2..] else value.string[0..];

                    if (slice.len == 0)
                        break :blk null;

                    const buffer = try allocator.alloc(u8, @divExact(slice.len, 2));
                    _ = std.fmt.hexToBytes(buffer, slice) catch return error.UnexpectedToken;

                    break :blk buffer;
                } else break :blk null;
            };

            @field(seen, "input") = 1;
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
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
};

pub const GetSourceResult = struct {
    /// The contract's source code.
    SourceCode: []const u8,
    /// The contract's ABI.
    ABI: Abi,
    /// The contract name.
    ContractName: []const u8,
    /// The compiler version that was used.
    CompilerVersion: SemanticVersion,
    /// The number of optimizations used.
    OptimizationUsed: usize,
    /// The amount of runs of optimizations.
    Runs: usize,
    /// The constructor arguments if any were used.
    ConstructorArguments: ?[]const u8,
    /// The EVM version used.
    EVMVersion: enum { Default },
    /// The library used if any.
    Library: ?[]const u8,
    /// The license type used by the contract.
    LicenseType: []const u8,
    /// If it's a proxy contract or not. Can be `@bitCast` to bool
    Proxy: u1,
    /// The implementation if it exists.
    Implementation: ?[]const u8,
    /// The bzzr swarm source.
    SwarmSource: Uri,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var seen: std.enums.EnumFieldStruct(ConvertToEnum(@This()), u32, 0) = .{};
        var result: @This() = undefined;

        if (source.object.get("ConstructorArguments")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            if (value.string.len == 0) {
                result.ConstructorArguments = null;
                @field(seen, "ConstructorArguments") = 1;
            }
        }

        if (source.object.get("Library")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            if (value.string.len == 0) {
                result.Library = null;
                @field(seen, "Library") = 1;
            }
        }

        if (source.object.get("Implementation")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            if (value.string.len == 0) {
                result.Implementation = null;
                @field(seen, "Implementation") = 1;
            }
        }

        if (source.object.get("ABI")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.ABI = std.json.parseFromSliceLeaky(Abi, allocator, value.string, options) catch return error.UnexpectedToken;
            @field(seen, "ABI") = 1;
        }

        if (source.object.get("CompilerVersion")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            const slice = if (value.string[0] == 'v') value.string[1..] else value.string;
            result.CompilerVersion = SemanticVersion.parse(slice) catch return error.UnexpectedToken;
            @field(seen, "CompilerVersion") = 1;
        }

        if (source.object.get("SwarmSource")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.SwarmSource = std.Uri.parse(value.string) catch return error.UnexpectedToken;
            @field(seen, "SwarmSource") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
};

pub const Erc1155TokenEventRequest = struct {
    /// The target address.
    address: Address,
    /// The target contract address.
    contractaddress: Address,
    /// The start block from where you want to grab the list.
    startblock: usize,
    /// The end block from where you want to grab the list.
    endblock: BlockTag,
};
pub const TokenEventRequest = struct {
    /// The target address.
    address: Address,
    /// The target contract address.
    contractaddress: Address,
    /// The start block from where you want to grab the list.
    startblock: usize,
    /// The end block from where you want to grab the list.
    endblock: usize,
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

pub const RangeRequest = struct {
    /// The start block number range.
    startblock: u64,
    /// The end block number range.
    endblock: u64,
};

pub const ContractCreationResult = struct {
    /// The contract address
    contractAddress: Address,
    /// The contract creator
    contractCreator: Address,
    /// The creation transaction hash
    txHash: Hash,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        _ = allocator;
        _ = options;

        if (source != .object)
            return error.UnexpectedToken;

        var result: @This() = undefined;

        if (source.object.get("contractAddress")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.contractAddress = utils.addressToBytes(value.string) catch return error.UnexpectedToken;
        } else return error.UnexpectedToken;

        if (source.object.get("contractCreator")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.contractCreator = utils.addressToBytes(value.string) catch return error.UnexpectedToken;
        } else return error.UnexpectedToken;

        if (source.object.get("txHash")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.txHash = utils.hashToBytes(value.string) catch return error.UnexpectedToken;
        } else return error.UnexpectedToken;

        return result;
    }
};

pub const TransactionStatus = struct {
    /// If the transaction reverted.
    isError: ?u1,
    /// The error message in case it reverted.
    errDescription: ?[]const u8,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var result: @This() = undefined;

        if (source.object.get("isError")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.isError = try std.json.innerParseFromValue(u1, allocator, value, options);
        } else return error.UnexpectedToken;

        if (source.object.get("errDescription")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.isError = if (value.string.len != 0) try std.json.innerParseFromValue(u1, allocator, value, options) else null;
        } else return error.UnexpectedToken;

        return result;
    }
};

pub const ReceiptStatus = struct {
    /// The receipt status
    status: ?u1,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var result: @This() = undefined;

        if (source.object.get("status")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.status = if (value.string.len != 0) try std.json.innerParseFromValue(u1, allocator, value, options) else null;
        } else return error.UnexpectedToken;

        return result;
    }
};

/// The block reward endpoint response.
pub const BlockRewards = struct {
    /// The block number of the reward.
    blockNumber: u64,
    /// The timestamp of the reward.
    timeStamp: u64,
    /// The block miner.
    blockMiner: Address,
    /// The reward value.
    blockReward: u256,
    /// The uncles block rewards.
    uncles: []const BlockRewards,
    /// The reward value included in uncle blocks.
    uncleInclusionReward: u256,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var result: @This() = undefined;
        var seen: std.enums.EnumFieldStruct(ConvertToEnum(@This()), u32, 0) = .{};

        if (source.object.get("blockMiner")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            result.blockMiner = utils.addressToBytes(value.string) catch return error.UnexpectedToken;
            @field(seen, "blockMiner") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
};

/// `getLogs` request via a block explorer.
pub const LogRequest = struct {
    /// The address where you want to grab the logs.
    address: Address,
    /// The start block range where you want search from.
    fromBlock: u64,
    /// The en block range where you want search to.
    toBlock: u64,
};

/// Zig struct representation of the log explorer response.
pub const ExplorerLog = struct {
    /// The contract address
    address: Address,
    /// The emitted log topics from the contract call.
    topics: []const ?Hash,
    /// The data sent via the log
    data: []u8,
    /// The block number this log was emitted.
    blockNumber: ?u64,
    /// The block hash where this log was emitted.
    blockHash: ?Hash,
    /// The timestamp where this log was emitted.
    timeStamp: u64,
    /// The gas price of the transaction this log was emitted in.
    gasPrice: u64,
    /// The gas used by the transaction this log was emitted in.
    gasUsed: u64,
    /// The log index.
    logIndex: ?usize,
    /// The transaction hash that emitted this log.
    transactionHash: ?Hash,
    /// The transaction index in the memory pool location.
    transactionIndex: ?usize,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

pub const BlockCountdown = struct {
    /// The current block in the node.
    CurrentBlock: u64,
    /// The target block.
    CountdownBlock: u64,
    /// The number of blocks remaining between `CurrentBlock` and `CountdownBlock`.
    RemainingBlock: u64,
    /// The seconds until `CountdownBlock` is reached.
    EstimateTimeInSec: f64,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

pub const BlocktimeRequest = struct {
    /// Unix timestamp in seconds
    timestamp: u64,
    /// The tag to choose for finding the closest block based on the timestamp.
    closest: enum {
        before,
        after,
    },
};

pub const TokenBalanceRequest = struct {
    /// The target address.
    address: Address,
    /// The target contract address.
    contractaddress: Address,
    /// The block tag to use to query this information.
    tag: BlockTag,
};

pub const EtherPriceResponse = struct {
    /// The ETH-BTC price.
    ethbtc: f64,
    /// The ETH-BTC price timestamp.
    ethbtc_timestamp: u64,
    /// The ETH-USD price.
    ethusd: f64,
    /// The ETH-USD price timestamp.
    ethusd_timestamp: u64,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

pub const GasOracle = struct {
    /// The last block where the oracle recorded the information.
    LastBlock: u64,
    /// Safe gas price to used to get transaciton mined.
    SafeGasPrice: u64,
    /// Proposed gas price.
    ProposeGasPrice: u64,
    /// Fast gas price.
    FastGasPrice: u64,
    /// Suggest transacition base fee.
    suggestBaseFee: f64,
    /// Gas used ratio.
    gasUsedRatio: []const f64,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        var result: @This() = undefined;
        var seen: std.enums.EnumFieldStruct(ConvertToEnum(@This()), u32, 0) = .{};

        if (source.object.get("gasUsedRatio")) |value| {
            if (value != .string)
                return error.UnexpectedToken;

            var iter = std.mem.splitAny(u8, value.string, ",");
            var list = std.ArrayList(f64).init(allocator);
            errdefer list.deinit();

            while (iter.next()) |slice| {
                try list.append(try std.fmt.parseFloat(f64, slice));
            }
            result.gasUsedRatio = try list.toOwnedSlice();
            @field(seen, "gasUsedRatio") = 1;
        }

        var iter = source.object.iterator();

        while (iter.next()) |key_value| {
            const field_name = key_value.key_ptr.*;

            inline for (std.meta.fields(@This())) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    if (@field(seen, field.name) == 0) {
                        @field(seen, field.name) = 1;
                        @field(result, field.name) = try std.json.innerParseFromValue(field.type, allocator, key_value.value_ptr.*, options);
                        break;
                    }
                }
            }
        }

        inline for (std.meta.fields(@This())) |field| {
            switch (@field(seen, field.name)) {
                0 => if (field.default_value_ptr) |default_value| {
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
};
