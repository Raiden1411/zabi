const std = @import("std");
const meta_utils = @import("../meta/utils.zig");
const tx_types = @import("transaction.zig");
const types = @import("ethereum.zig");

const Address = types.Address;
const AddressHashMap = std.AutoArrayHashMap(Address, PoolTransactionByNonce);
const Allocator = std.mem.Allocator;
const ConvertToEnum = meta_utils.ConvertToEnum;
const PoolPendingTransactionHashMap = std.AutoArrayHashMap(u64, Transaction);
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Transaction = tx_types.Transaction;
const Value = std.json.Value;

/// Result tx pool status.
pub const TxPoolStatus = struct {
    pending: u64,
    queued: u64,
};
/// Result tx pool content.
pub const TxPoolContent = struct {
    pending: Subpool,
    queued: Subpool,
};
/// Geth mempool subpool type
const Subpool = struct {
    address: AddressHashMap,

    /// Parses as a dynamic value and then uses that value to json parse
    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!Subpool {
        var result = AddressHashMap.init(allocator);

        const parsed = try Value.jsonParse(allocator, source, options);

        var iter = parsed.object.iterator();

        while (iter.next()) |field| {
            const key = field.key_ptr.*;
            var addr: [20]u8 = undefined;
            _ = std.fmt.hexToBytes(addr[0..], key[2..]) catch return error.InvalidCharacter;

            const tx_parse = try std.json.parseFromValueLeaky(PoolTransactionByNonce, allocator, field.value_ptr.*, options);

            try result.put(addr, tx_parse);
        }

        return .{ .address = result };
    }
    /// Address are checksumed on stringify.
    pub fn jsonStringify(value: @This(), source: anytype) !void {
        try source.beginObject();
        var iter = value.address.iterator();

        while (iter.next()) |field| {
            const key = field.key_ptr.*;
            var buffer: [42]u8 = undefined;
            var hash_buffer: [std.crypto.hash.sha3.Keccak256.digest_length]u8 = undefined;

            const hexed = std.fmt.bytesToHex(key, .lower);
            std.crypto.hash.sha3.Keccak256.hash(&hexed, &hash_buffer, .{});

            // Checksum the address
            for (buffer[2..], 0..) |*c, i| {
                const char = hexed[i];
                switch (char) {
                    'a'...'f' => {
                        const mask: u8 = if (i % 2 == 0) 0x80 else 0x08;
                        if ((hash_buffer[i / 2] & mask) > 7) {
                            c.* = char & 0b11011111;
                        } else c.* = char;
                    },
                    else => {
                        c.* = char;
                    },
                }
            }
            @memcpy(buffer[0..2], "0x");

            try source.objectField(buffer[0..]);
            try source.write(field.value_ptr.*);
        }

        try source.endObject();
    }
};
/// Geth transaction object dump from mempool by nonce.
const PoolTransactionByNonce = struct {
    nonce: PoolPendingTransactionHashMap,

    /// Parses as a dynamic value and then uses that value to json parse
    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!PoolTransactionByNonce {
        var result = PoolPendingTransactionHashMap.init(allocator);

        const parsed = try Value.jsonParse(allocator, source, options);

        var iter = parsed.object.iterator();

        while (iter.next()) |field| {
            const key = field.key_ptr.*;
            const key_num = try std.fmt.parseInt(u64, key, 10);

            const tx_parse = try std.json.parseFromValueLeaky(Transaction, allocator, field.value_ptr.*, options);

            try result.put(key_num, tx_parse);
        }

        return .{ .nonce = result };
    }
    /// Uses similar approach as `jsonParse` but the value is already pre parsed from
    /// a dynamic `Value`
    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!PoolTransactionByNonce {
        var result = PoolPendingTransactionHashMap.init(allocator);
        var iter = source.object.iterator();

        while (iter.next()) |field| {
            const key = field.key_ptr.*;
            const key_num = try std.fmt.parseInt(u64, key, 10);

            const tx_parse = try std.json.parseFromValueLeaky(Transaction, allocator, field.value_ptr.*, options);

            try result.put(key_num, tx_parse);
        }

        return .{ .nonce = result };
    }
    /// Converts the nonces into strings.
    pub fn jsonStringify(value: PoolTransactionByNonce, source: anytype) !void {
        try source.beginObject();
        var iter = value.nonce.iterator();

        while (iter.next()) |field| {
            var buffer: [@sizeOf(u64)]u8 = undefined;
            var buf_writter = std.io.fixedBufferStream(&buffer);
            buf_writter.writer().print("{d}", .{field.key_ptr.*}) catch return error.OutOfMemory;

            try source.objectField(buf_writter.getWritten());
            try source.write(field.value_ptr.*);
        }

        try source.endObject();
    }
};
