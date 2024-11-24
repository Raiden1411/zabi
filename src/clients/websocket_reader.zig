const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Base64Encoder = std.base64.standard.Encoder;
const Header = std.http.WebSocket.Header0;
const Header1 = std.http.WebSocket.Header1;
const Opcodes = std.http.WebSocket.Opcode;
const RecvFromError = std.posix.RecvFromError;
const Sha1 = std.crypto.hash.Sha1;
const Stream = std.net.Stream;

// State for checking a handshake response.
pub const Checks = union(enum) {
    none,
    checked_protocol,
    checked_upgrade,
    checked_connection,
    checked_key,
    duplicate,
};

pub const AssertionError = error{ DuplicateHandshakeHeader, InvalidHandshakeMessage, InvalidHandshakeKey };
pub const SendHandshakeError = Stream.WriteError || error{NoSpaceLeft};
pub const ReadHandshakeError = RecvFromError || Stream.ReadError || error{NoSpaceLeft} || AssertionError;

const WebsocketClient = @This();

stream: Stream,

pub fn generateHandshakeKey() [24]u8 {
    var nonce: [16]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    var base_64: [24]u8 = undefined;
    _ = Base64Encoder.encode(&base_64, &nonce);

    return base_64;
}

pub fn writeHeaderFrame(self: *WebsocketClient, message: []const u8, opcode: Opcodes) Stream.WriteError![4]u8 {
    var buffer: [14]u8 = undefined;

    buffer[0] = @bitCast(@as(Header, .{
        .opcode = opcode,
        .fin = true,
    }));

    switch (message.len) {
        0...125 => {
            buffer[1] = @bitCast(@as(Header1, .{
                .payload_len = @enumFromInt(message.len),
                .mask = true,
            }));
            std.crypto.random.bytes(buffer[2..6]);
            try self.stream.writeAll(buffer[0..6]);

            return buffer[2..6].*;
        },
        126...0xFFFF => {
            buffer[1] = @bitCast(@as(Header1, .{
                .payload_len = .len16,
                .mask = true,
            }));

            std.mem.writeInt(u16, buffer[2..4], @intCast(message.len), .big);
            std.crypto.random.bytes(buffer[4..8]);
            try self.stream.writeAll(buffer[0..8]);

            return buffer[4..8].*;
        },
        else => {
            buffer[1] = @bitCast(@as(Header1, .{
                .payload_len = .len64,
                .mask = true,
            }));
            std.mem.writeInt(u64, buffer[2..10], @intCast(message.len), .big);
            std.crypto.random.bytes(buffer[10..14]);
            try self.stream.writeAll(buffer[0..]);

            return buffer[10..].*;
        },
    }
}

pub fn writeFrame(self: *WebsocketClient, message: []u8, opcode: Opcodes) !void {
    const mask = try self.writeHeaderFrame(message, opcode);

    for (message, 0..) |*char, i| {
        char.* ^= mask[i & 3];
    }

    if (message.len > 0)
        try self.stream.writeAll(message);
}

pub fn handshake(self: *WebsocketClient, host: []const u8) (ReadHandshakeError || SendHandshakeError)!void {
    const key = generateHandshakeKey();

    try self.sendHandshake(host, key);
    try self.readHandshake(key);
}

pub fn readHandshake(self: *WebsocketClient, handshake_key: [24]u8) ReadHandshakeError!void {
    // TODO: Make it support higher than 1024 bits.
    var read_buffer: [1024]u8 = undefined;
    const size = try std.posix.recv(self.stream.handle, &read_buffer, std.os.linux.MSG.PEEK);

    const read = try parseHandshakeResponse(handshake_key, read_buffer[0..size]);
    _ = try self.stream.readAtLeast(&read_buffer, read);
}

pub fn sendHandshake(self: *WebsocketClient, host: []const u8, key: [24]u8) SendHandshakeError!void {
    // TODO: Make it support higher than 1024 bits.
    var buffer: [1024]u8 = undefined;

    var buf_stream = std.io.fixedBufferStream(&buffer);
    var writer = buf_stream.writer();

    try writer.writeAll("GET / HTTP/1.1\r\n");
    try writer.print("Host: {s}\r\n", .{host});
    try writer.writeAll("Content-length: 0\r\n");
    try writer.writeAll("Upgrade: websocket\r\n");
    try writer.writeAll("Connection: Upgrade\r\n");
    try writer.print("Sec-WebSocket-Key: {s}\r\n", .{key});
    try writer.writeAll("Sec-WebSocket-Version: 13\r\n");
    try writer.writeAll("\r\n");

    const written = buf_stream.getWritten();

    try self.stream.writeAll(written);
}

pub fn parseHandshakeResponse(key: [24]u8, response: []const u8) AssertionError!usize {
    var iter = std.mem.tokenizeAny(u8, response, "\r\n");
    var websocket_key: ?[]const u8 = null;

    var checks: Checks = .none;
    var message_len: usize = 0;
    while (iter.next()) |header| {
        const index = std.mem.indexOfScalar(u8, header, ':') orelse {
            if (std.ascii.startsWithIgnoreCase(header, "HTTP/1.1 101")) {
                checks = switch (checks) {
                    .none => .checked_protocol,
                    .duplicate => return error.DuplicateHandshakeHeader,
                    else => return error.InvalidHandshakeMessage,
                };

                message_len += header.len + 2; // adds the \r\n
            }

            continue;
        };

        if (std.ascii.eqlIgnoreCase(header[0..index], "sec-websocket-accept")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            websocket_key = trimmed;

            checks = switch (checks) {
                .checked_upgrade => .checked_key,
                .duplicate => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }

        if (std.mem.eql(u8, header[0..index], "connection")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            if (!std.ascii.eqlIgnoreCase(trimmed, "upgrade"))
                return error.InvalidHandshakeMessage;

            checks = switch (checks) {
                .checked_protocol => .checked_connection,
                .duplicate => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }

        if (std.mem.eql(u8, header[0..index], "upgrade")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            if (!std.ascii.eqlIgnoreCase(trimmed, "websocket"))
                return error.InvalidHandshakeMessage;

            checks = switch (checks) {
                .checked_connection => .checked_upgrade,
                .duplicate => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }

        message_len += header.len + 2; // adds the \r\n
    }

    if (checks != .checked_key)
        return error.InvalidHandshakeMessage;

    const ws_key = websocket_key orelse return error.InvalidHandshakeKey;
    var hash: [Sha1.digest_length]u8 = undefined;

    var hasher = Sha1.init(.{});
    hasher.update(&key);
    hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    hasher.final(&hash);

    var buffer: [28]u8 = undefined;
    _ = Base64Encoder.encode(&buffer, &hash);

    const encoded_int: u224 = @bitCast(buffer);
    const reponse_int: u224 = @bitCast(ws_key[0..28].*);

    if (encoded_int != reponse_int)
        return error.InvalidHandshakeKey;

    return message_len + 2; // add the final \r\n
}

test "Connection" {
    const stream = try std.net.tcpConnectToHost(testing.allocator, "localhost", 6969);
    defer stream.close();

    var client: WebsocketClient = .{
        .stream = stream,
    };

    try client.handshake("localhost");
    var message =
        \\{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":"0x1"}
    .*;

    try client.writeFrame(message[0..], .text);
    var read_buffer: [1024]u8 = undefined;
    const size = try stream.read(&read_buffer);

    std.debug.print("Foo: {any}\n", .{size});
    std.debug.print("Foo: {s}\n", .{read_buffer[0..size]});
    std.debug.print("Foo: {any}\n", .{read_buffer[0..2]});
    const a = read_buffer[1];
    std.debug.print("Foo: {s}\n", .{read_buffer[2 .. a + 2]});
}
