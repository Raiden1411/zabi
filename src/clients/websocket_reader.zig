const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Base64Encoder = std.base64.standard.Encoder;
const CertificateBundle = std.crypto.Certificate.Bundle;
const LinearFifo = std.fifo.LinearFifo(u8, .Dynamic);
const OpcodeHeader = std.http.WebSocket.Header0;
const Opcodes = std.http.WebSocket.Opcode;
const Parsed = std.json.Parsed;
const ParsedError = std.json.ParseError;
const PayloadHeader = std.http.WebSocket.Header1;
const Protocol = std.http.Client.Connection.Protocol;
const RecvFromError = std.posix.RecvFromError;
const Scanner = std.json.Scanner;
const Sha1 = std.crypto.hash.Sha1;
const Stream = std.net.Stream;
const TlsClient = std.crypto.tls.Client;
const Uri = std.Uri;
const Value = std.json.Value;

const wsclient_log = std.log.scoped(.ws_client);

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

pub const SendHandshakeError = TlsClient.InitError(Stream) || Stream.WriteError || error{NoSpaceLeft};

pub const ReadHandshakeError = RecvFromError || Stream.ReadError || error{ NoSpaceLeft, Overflow, TlsBadLength } || AssertionError || TlsClient.InitError(Stream);

pub const SocketReadError = Stream.ReadError || Allocator.Error || error{ EndOfStream, Overflow, TlsBadLength } || TlsClient.InitError(Stream);

pub const ReadMessageError = SocketReadError || ParsedError(Scanner) ||
    error{ Closed, UnfragmentedContinue, MessageSizeOverflow, UnsupportedOpcode, ConnectionClosedByServer, UnexpectedFragment, MaskedServerMessage };

const WebsocketClient = @This();

const protocol_map = std.StaticStringMap(Protocol).initComptime(.{
    .{ "http", .plain },
    .{ "ws", .plain },
    .{ "https", .tls },
    .{ "wss", .tls },
});

// TODO:
// Add tls support.
allocator: Allocator,
stream: NetStream,
recieve_fifo: LinearFifo,
fragment_fifo: LinearFifo,
over_read: usize,
uri: Uri,
closed: bool,

pub fn connect(allocator: Allocator, uri: Uri) !WebsocketClient {
    const scheme = protocol_map.get(uri.scheme) orelse return error.UnsupportedSchema;

    const port: u16 = uri.port orelse switch (scheme) {
        .plain => 80,
        .tls => 443,
    };

    const hostname = switch (uri.host orelse return error.UnspecifiedHostName) {
        .raw => |raw| raw,
        .percent_encoded => |host| host,
    };

    const fifo: LinearFifo = .init(allocator);
    const fragment_fifo: LinearFifo = .init(allocator);
    const stream = try std.net.tcpConnectToHost(allocator, hostname, port);

    var tls_client: ?TlsClient = null;
    if (scheme == .tls) {
        var bundle: CertificateBundle = .{};
        defer bundle.deinit(allocator);

        try bundle.rescan(allocator);

        tls_client = try TlsClient.init(stream, .{
            .host = .{ .explicit = hostname },
            .ca = .{ .bundle = bundle },
        });
    }

    return .{
        .allocator = allocator,
        .recieve_fifo = fifo,
        .fragment_fifo = fragment_fifo,
        .stream = .{
            .net_stream = stream,
            .tls_stream = tls_client,
        },
        .over_read = 0,
        .uri = uri,
        .closed = false,
    };
}

pub fn deinit(self: *WebsocketClient) void {
    self.recieve_fifo.deinit();
    self.fragment_fifo.deinit();
    self.stream.close();
}

pub fn generateHandshakeKey() [24]u8 {
    var nonce: [16]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    var base_64: [24]u8 = undefined;
    _ = Base64Encoder.encode(&base_64, &nonce);

    return base_64;
}

pub fn writeHeaderFrame(self: *WebsocketClient, message: []const u8, opcode: Opcodes) Stream.WriteError![4]u8 {
    var buffer: [14]u8 = undefined;

    buffer[0] = @bitCast(@as(OpcodeHeader, .{
        .opcode = opcode,
        .fin = true,
    }));

    switch (message.len) {
        0...125 => {
            buffer[1] = @bitCast(@as(PayloadHeader, .{
                .payload_len = @enumFromInt(message.len),
                .mask = true,
            }));
            std.crypto.random.bytes(buffer[2..6]);
            try self.stream.writeAll(buffer[0..6]);

            return buffer[2..6].*;
        },
        126...0xFFFF => {
            buffer[1] = @bitCast(@as(PayloadHeader, .{
                .payload_len = .len16,
                .mask = true,
            }));

            std.mem.writeInt(u16, buffer[2..4], @intCast(message.len), .big);
            std.crypto.random.bytes(buffer[4..8]);
            try self.stream.writeAll(buffer[0..8]);

            return buffer[4..8].*;
        },
        else => {
            buffer[1] = @bitCast(@as(PayloadHeader, .{
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

pub fn writeCloseFrame(self: *WebsocketClient, exit_code: u16) !void {
    if (@atomicLoad(bool, &self.closed, .acquire))
        // Connection is already closed
        return;

    var buffer: [4]u8 = undefined;

    buffer[0] = @bitCast(@as(OpcodeHeader, .{
        .opcode = .connection_close,
        .fin = true,
    }));
    buffer[1] = @bitCast(@as(PayloadHeader, .{
        .payload_len = .len16,
        .mask = false,
    }));

    std.mem.writeInt(u16, buffer[2..4], exit_code, .big);

    try self.stream.writeAll(buffer[0..]);
}

pub fn writeFrame(self: *WebsocketClient, message: []u8, opcode: Opcodes) !void {
    const mask = try self.writeHeaderFrame(message, opcode);

    if (message.len > 0) {
        maskMessage(message, mask);

        try self.stream.writeAll(message);
    }
}

pub fn maskMessage(message: []u8, mask: [4]u8) void {
    const vec_size = std.simd.suggestVectorLength(u8) orelse @sizeOf(usize);
    const Vector = @Vector(vec_size, u8);

    var remainder = message;

    while (true) {
        if (remainder.len < vec_size) return for (remainder, 0..) |*char, i| {
            char.* ^= mask[i & 3];
        };
        const slice = remainder[0..vec_size];
        const mask_vector = std.simd.repeat(vec_size, @as(@Vector(4, u8), mask));

        slice.* = @as(Vector, slice.*) ^ mask_vector;
        remainder = remainder[vec_size..];
    }
}

pub fn handshake(self: *WebsocketClient, host: []const u8) (ReadHandshakeError || SendHandshakeError)!void {
    const key = generateHandshakeKey();
    errdefer self.deinit();

    try self.sendHandshake(host, key);
    try self.readHandshake(key);
}

pub fn readHandshake(self: *WebsocketClient, handshake_key: [24]u8) ReadHandshakeError!void {
    // Handshake shouldn't exceed this.
    var read_buffer: [4096]u8 = undefined;
    // const size = try std.posix.recv(self.stream.net_stream.handle, &read_buffer, std.os.linux.MSG.PEEK);

    const read = try self.stream.read(&read_buffer);
    _ = try parseHandshakeResponse(handshake_key, read_buffer[0..read]);
}

pub fn sendHandshake(self: *WebsocketClient, host: []const u8, key: [24]u8) SendHandshakeError!void {
    // Dont support paths that exceed this.
    var buffer: [4096]u8 = undefined;

    var buf_stream = std.io.fixedBufferStream(&buffer);
    var writer = buf_stream.writer();

    const path: []const u8 = if (self.uri.path.isEmpty()) "/" else switch (self.uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };

    try writer.print("GET {s} HTTP/1.1\r\n", .{path});
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

    var checks: usize = 0;
    var message_len: usize = 0;

    wsclient_log.debug("Handshake message: {s}", .{response});
    while (iter.next()) |header| {
        const index = std.mem.indexOfScalar(u8, header, ':') orelse {
            if (std.ascii.startsWithIgnoreCase(header, "HTTP/1.1 101")) {
                // checks = switch (checks) {
                //     .none => .checked_protocol,
                //     .duplicate => return error.DuplicateHandshakeHeader,
                //     else => return error.InvalidHandshakeMessage,
                // };
                checks |= 1;

                message_len += header.len + 2; // adds the \r\n
            }

            continue;
        };

        if (std.ascii.eqlIgnoreCase(header[0..index], "sec-websocket-accept")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            websocket_key = trimmed;

            checks |= 8;
            // checks = switch (checks) {
            //     .checked_upgrade => .checked_key,
            //     .duplicate => return error.DuplicateHandshakeHeader,
            //     else => return error.InvalidHandshakeMessage,
            // };
        }

        if (std.ascii.eqlIgnoreCase(header[0..index], "connection")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            if (!std.ascii.eqlIgnoreCase(trimmed, "upgrade"))
                return error.InvalidHandshakeMessage;

            checks |= 2;
            // checks = switch (checks) {
            //     .checked_protocol => .checked_connection,
            //     .duplicate => return error.DuplicateHandshakeHeader,
            //     else => return error.InvalidHandshakeMessage,
            // };
        }

        if (std.ascii.eqlIgnoreCase(header[0..index], "upgrade")) {
            const trimmed = std.mem.trim(u8, header[index + 1 ..], " ");
            if (!std.ascii.eqlIgnoreCase(trimmed, "websocket"))
                return error.InvalidHandshakeMessage;

            checks |= 4;
            // checks = switch (checks) {
            //     .checked_connection => .checked_upgrade,
            //     .duplicate => return error.DuplicateHandshakeHeader,
            //     else => return error.InvalidHandshakeMessage,
            // };
        }

        message_len += header.len + 2; // adds the \r\n
    }

    if (checks != 15) {
        wsclient_log.debug("Here: {d}", .{checks});
        return error.InvalidHandshakeMessage;
    }

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

pub fn readFromSocket(self: *WebsocketClient, size: usize) SocketReadError![]const u8 {
    self.recieve_fifo.discard(self.over_read);

    if (size > self.recieve_fifo.count) {
        const amount = size - self.recieve_fifo.count;
        const buffer = self.recieve_fifo.writableSlice(0);

        const writable_buf = if (buffer.len > amount) buffer else blk: {
            const new_buffer = try self.recieve_fifo.writableWithSize(amount);
            self.recieve_fifo.realign();

            break :blk new_buffer;
        };

        const read = try self.stream.readAtLeast(writable_buf, amount);

        if (read < amount)
            return error.EndOfStream;

        self.recieve_fifo.update(read);
    }

    self.over_read = size;

    return self.recieve_fifo.readableSliceOfLen(size);
}

pub fn readMessage(self: *WebsocketClient) ReadMessageError!Parsed(Value) {
    while (true) {
        const headers = (try self.readFromSocket(2))[0..2];

        const op_head: OpcodeHeader = @bitCast(headers[0]);
        const payload_head: PayloadHeader = @bitCast(headers[1]);

        switch (op_head.opcode) {
            .text,
            .continuation,
            => {},
            // Doesn't get handled.
            .ping,
            .pong,
            .binary,
            => continue,
            .connection_close => {
                try self.close(0);
                return error.ConnectionClosedByServer;
            },
            _ => return error.UnsupportedOpcode,
        }

        if (payload_head.mask)
            return error.MaskedServerMessage;

        const total = switch (payload_head.payload_len) {
            .len16 => blk: {
                const size = (try self.readFromSocket(@sizeOf(u16)))[0..@sizeOf(u16)];

                break :blk std.mem.readInt(u16, size, .big);
            },
            .len64 => blk: {
                const size = (try self.readFromSocket(@sizeOf(u64)))[0..@sizeOf(u64)];
                const int = std.mem.readInt(u64, size, .big);

                break :blk std.math.cast(usize, int) orelse return error.MessageSizeOverflow;
            },
            _ => @intFromEnum(payload_head.payload_len),
        };

        const payload = try self.readFromSocket(total);

        if (!op_head.fin) {
            wsclient_log.debug("Incomplete message... Expecting continuation opcode next!", .{});

            try self.fragment_fifo.write(payload);
            continue;
        }

        if (op_head.opcode == .continuation) {
            if (self.fragment_fifo.count == 0)
                return error.UnfragmentedContinue;

            try self.fragment_fifo.write(payload);

            const slice = try self.fragment_fifo.toOwnedSlice();
            defer self.allocator.free(slice);

            wsclient_log.debug("Got complete fragmented websocket message: {s}", .{slice});
            const parsed = try std.json.parseFromSlice(Value, self.allocator, slice, .{ .allocate = .alloc_always });

            return parsed;
        }

        if (self.fragment_fifo.count != 0)
            return error.UnexpectedFragment;

        // wsclient_log.debug("Got websocket message: {s}", .{payload});
        const parsed = try std.json.parseFromSlice(Value, self.allocator, payload, .{ .allocate = .alloc_always });

        return parsed;
    }
}

pub fn close(self: *WebsocketClient, error_code: u16) !void {
    if (@atomicLoad(bool, &self.closed, .acquire))
        return;

    defer self.stream.close();

    try self.writeCloseFrame(error_code);
}

pub const NetStream = struct {
    net_stream: Stream,
    tls_stream: ?TlsClient = null,

    pub fn writeAll(self: *NetStream, message: []const u8) !void {
        if (self.tls_stream) |*tls_stream|
            return tls_stream.writeAll(self.net_stream, message);

        return self.net_stream.writeAll(message);
    }

    pub fn readAtLeast(self: *NetStream, buffer: []u8, size: usize) !usize {
        if (self.tls_stream) |*tls_stream|
            return tls_stream.readAtLeast(self.net_stream, buffer, size);

        return self.net_stream.readAtLeast(buffer, size);
    }

    pub fn read(self: *NetStream, buffer: []u8) !usize {
        if (self.tls_stream) |*tls_stream|
            return tls_stream.read(self.net_stream, buffer);

        return self.net_stream.read(buffer);
    }

    pub fn close(self: *NetStream) void {
        if (self.tls_stream) |*tls_stream|
            _ = tls_stream.writeEnd(self.net_stream, "", true) catch {};

        self.net_stream.close();
    }
};

test "Connection" {
    const uri = try Uri.parse("http://localhost:6969/");
    var client = try WebsocketClient.connect(testing.allocator, uri);
    defer client.deinit();

    try client.handshake("localhost");
    {
        var message =
            \\{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":"0x1"}
        .*;

        try client.writeFrame(message[0..], .text);
        const messages = try client.readMessage();
        defer messages.deinit();

        std.debug.print("Foo: {}\n", .{messages});
    }
    {
        var message =
            \\{"jsonrpc": "2.0", "id": 31337, "method": "eth_getBlockByNumber", "params": ["latest", false]}
        .*;

        try client.writeFrame(message[0..], .text);
        const messages = try client.readMessage();
        defer messages.deinit();

        std.debug.print("Foo: {}\n", .{messages});
    }
}
