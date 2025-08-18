//! Websocket client implementation that is spec compliant and autobahn compliant.
//!
//! This implementation relies on multithreading for the read loop but there are future plans to
//! implement different solution for this and the IPC client

const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const TlsAlertErrors = std.crypto.tls.Alert.Description.Error;
const Allocator = std.mem.Allocator;
const Base64Encoder = std.base64.standard.Encoder;
const CertificateBundle = std.crypto.Certificate.Bundle;
const OpcodeHeader = std.http.Server.WebSocket.Header0;
const Opcode = std.http.Server.WebSocket.Opcode;
const PayloadHeader = std.http.Server.WebSocket.Header1;
const Protocol = std.http.Client.Protocol;
const Reader = std.Io.Reader;
const Scanner = std.json.Scanner;
const Sha1 = std.crypto.hash.Sha1;
const Stream = std.net.Stream;
const TcpConnectToHostError = std.net.TcpConnectToHostError;
const TlsClient = std.crypto.tls.Client;
const Uri = std.Uri;
const Value = std.json.Value;
const Writer = std.Io.Writer;

pub const disable_tls = std.options.http_disable_tls;

/// Inner websocket client logger.
const wsclient_log = std.log.scoped(.ws_client);

// Reference to self.
const WebsocketClient = @This();

// State for checking a handshake response.
pub const Checks = union(enum) {
    none,
    checked_protocol,
    checked_upgrade,
    checked_connection,
    checked_key,
};

/// Structure of a websocket message.
pub const WebsocketMessage = struct {
    /// Websocket valid opcodes.
    opcode: Opcode,
    /// Payload data read.
    data: []const u8,
};

/// Wrapper around a websocket fragmented frame.
pub const Fragment = struct {
    const Self = @This();
    const Error = Allocator.Error || Writer.Error;

    /// FIFO stream of all fragments.
    alloc_writer: Writer.Allocating,
    /// The type of message that the fragment is. Control fragment's are not supported.
    message_type: ?Opcode,

    /// Clears any allocated memory.
    pub fn deinit(self: *Self) void {
        self.alloc_writer.deinit();
    }

    /// Writes the payload into the stream.
    pub fn writeAll(self: *Self, payload: []const u8) Error!void {
        try self.alloc_writer.ensureUnusedCapacity(payload.len);
        return self.alloc_writer.writer.writeAll(payload);
    }

    /// Reset the fragment but keeps the allocated memory.
    /// Also reset the message type back to null.
    pub fn reset(self: *Self) void {
        self.alloc_writer.shrinkRetainingCapacity(0);
        self.message_type = null;
    }

    /// Returns a slice of the currently written values on the buffer.
    pub fn slice(self: *Self) []u8 {
        return self.alloc_writer.written();
    }

    /// Returns the total amount of bytes that were written.
    pub fn size(self: Self) usize {
        return self.alloc_writer.writer.end;
    }
};

/// Representation of a websocket connection used by this client
///
/// This is similar to `std.http.Client.Connection` but adapted to our use case.
pub const Connection = struct {
    /// The writer that will be used to write to the stream connection.
    stream_writer: Stream.Writer,
    /// The reader that will be used to read data from the socket.
    stream_reader: Stream.Reader,
    /// The uri that this client is connected too.
    uri: Uri,
    /// The http protocol that this connection will use.
    protocol: Protocol,
    /// The allocated size of hostname
    host_len: u8,

    /// Closes the network connection
    ///
    /// If the connection is a tls connection it will send and `end` message and flushes it.
    pub fn close(self: *Connection) void {
        self.end() catch {};

        std.posix.shutdown(self.getStream().handle, .both) catch {};
        self.getStream().close();
    }

    /// Frees the memory associated with the reader and writer buffers
    /// and the connection pointer
    pub fn destroyConnection(self: *Connection, allocator: Allocator) void {
        switch (self.protocol) {
            .tls => {
                const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));
                tls.destroy(allocator);
            },
            .plain => {
                const plain: *Plain = @alignCast(@fieldParentPtr("connection", self));
                plain.destroy(allocator);
            },
        }
    }

    /// Sends end message if its a tls connection and flushes any buffered data still in the writer.
    pub fn end(self: *Connection) !void {
        if (self.protocol == .tls) {
            if (disable_tls) unreachable;
            const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));
            try tls.tls_client.end();
        }

        try self.stream_writer.interface.flush();
    }

    /// Flushes the buffered data and writes to it.
    pub fn flush(self: *Connection) Writer.Error!void {
        if (self.protocol == .tls) {
            if (disable_tls) unreachable;
            const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));
            try tls.tls_client.writer.flush();
        }

        try self.stream_writer.interface.flush();
    }

    /// Gets the network stream associated with this connection
    pub fn getStream(self: *Connection) Stream {
        return self.stream_reader.getStream();
    }

    /// Gets the hostname associated with this connection
    pub fn getHostname(self: *Connection) []const u8 {
        return switch (self.protocol) {
            .tls => {
                if (disable_tls) unreachable;
                const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));

                return tls.getHostname();
            },
            .plain => {
                const plain: *Plain = @alignCast(@fieldParentPtr("connection", self));

                return plain.getHostname();
            },
        };
    }

    /// Gets the reader independent of the connection type. Either tls or plain.
    pub fn reader(self: *Connection) *Reader {
        return switch (self.protocol) {
            .tls => {
                if (disable_tls) unreachable;
                const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));
                return &tls.tls_client.reader;
            },
            .plain => self.stream_reader.interface(),
        };
    }

    /// Gets the writer independent of the connection type. Either tls or plain.
    pub fn writer(self: *Connection) *Writer {
        return switch (self.protocol) {
            .tls => {
                if (disable_tls) unreachable;
                const tls: *Tls = @alignCast(@fieldParentPtr("connection", self));
                return &tls.tls_client.writer;
            },
            .plain => &self.stream_writer.interface,
        };
    }

    /// Representation of a plain websocket connection
    pub const Plain = struct {
        connection: Connection,

        const read_buffer_size = 8192;
        const write_buffer_size = 1024;
        const allocation_length = write_buffer_size + read_buffer_size + @sizeOf(Plain);

        /// Creates the pointer and any buffers that the readers and writers need.
        pub fn create(
            allocator: Allocator,
            uri: Uri,
            stream: Stream,
        ) !*Plain {
            var host_name_buffer: [Uri.host_name_max]u8 = undefined;
            const hostname = try uri.getHost(&host_name_buffer);

            const base = try allocator.alignedAlloc(u8, .of(Plain), allocation_length + hostname.len);
            errdefer allocator.free(base);

            const host = base[@sizeOf(Plain)..][0..hostname.len];
            const socket_read_buffer = host.ptr[host.len..][0..read_buffer_size];
            const socket_write_buffer = socket_read_buffer.ptr[socket_read_buffer.len..][0..write_buffer_size];

            const plain: *Plain = @ptrCast(base);
            @memcpy(host, hostname);

            plain.* = .{
                .connection = .{
                    .stream_writer = stream.writer(socket_write_buffer),
                    .stream_reader = stream.reader(socket_read_buffer),
                    .uri = uri,
                    .protocol = .plain,
                    .host_len = @intCast(hostname.len),
                },
            };

            return plain;
        }

        /// Destroy the pointer and frees the read and write buffer
        pub fn destroy(plain: *Plain, allocator: Allocator) void {
            const base: [*]align(@alignOf(Plain)) u8 = @ptrCast(plain);

            allocator.free(base[0 .. allocation_length + @as(usize, @intCast(plain.connection.host_len))]);
        }

        /// Gets the hostname associated with this connection
        pub fn getHostname(plain: *Plain) []u8 {
            const base: [*]u8 = @ptrCast(plain);
            return base[@sizeOf(Plain)..][0..plain.connection.host_len];
        }
    };

    /// Representation of a tls websocket connection
    pub const Tls = struct {
        connection: Connection,
        tls_client: TlsClient,

        const tls_buffer_size = if (disable_tls) 0 else TlsClient.min_buffer_len;
        const read_buffer_size = 8192;
        const write_buffer_size = 1024;

        const allocation_length = write_buffer_size + read_buffer_size +
            tls_buffer_size + tls_buffer_size + tls_buffer_size + @sizeOf(Tls);

        /// Creates the pointer and any buffers that the readers and writers need.
        pub fn create(
            allocator: Allocator,
            uri: Uri,
            stream: Stream,
        ) !*Tls {
            var host_name_buffer: [Uri.host_name_max]u8 = undefined;
            const hostname = try uri.getHost(&host_name_buffer);

            const base = try allocator.alignedAlloc(u8, .of(Tls), allocation_length + hostname.len);
            errdefer allocator.free(base);

            const host = base[@sizeOf(Tls)..][0..hostname.len];
            const tls_read_buffer = host.ptr[host.len..][0 .. tls_buffer_size + read_buffer_size];
            const tls_write_buffer = tls_read_buffer.ptr[tls_read_buffer.len..][0..tls_buffer_size];

            const write_buffer = tls_write_buffer.ptr[tls_write_buffer.len..][0..write_buffer_size];
            const read_buffer = write_buffer.ptr[write_buffer.len..][0..tls_buffer_size];

            const tls: *Tls = @ptrCast(base);

            @memcpy(host, hostname);

            var bundle: CertificateBundle = .{};
            defer bundle.deinit(allocator);

            try bundle.rescan(allocator);

            tls.* = .{
                .connection = .{
                    .stream_writer = stream.writer(tls_write_buffer),
                    .stream_reader = stream.reader(tls_read_buffer),
                    .uri = uri,
                    .protocol = .tls,
                    .host_len = @intCast(hostname.len),
                },
                .tls_client = try TlsClient.init(
                    tls.connection.stream_reader.interface(),
                    &tls.connection.stream_writer.interface,
                    .{
                        .host = .{ .explicit = hostname },
                        .ca = .{ .bundle = bundle },
                        .ssl_key_log = null,
                        .read_buffer = read_buffer,
                        .write_buffer = write_buffer,
                        // This is appropriate for HTTPS because the HTTP headers contain
                        // the content length which is used to detect truncation attacks.
                        .allow_truncation_attacks = true,
                    },
                ),
            };

            return tls;
        }

        /// Destroy the pointer and frees the read and write buffer
        pub fn destroy(tls: *Tls, allocator: Allocator) void {
            const base: [*]align(@alignOf(Tls)) u8 = @ptrCast(tls);
            allocator.free(base[0 .. allocation_length + @as(usize, @intCast(tls.connection.host_len))]);
        }

        /// Gets the hostname associated with this connection
        pub fn getHostname(tls: *Tls) []u8 {
            const base: [*]u8 = @ptrCast(Tls);
            return base[@sizeOf(Tls)..][0..tls.connection.host_len];
        }
    };
};

/// Clients allocator used to allocate the read and write buffers
allocator: Allocator,
/// Wrapper stream of a `std.net.Stream` and a `std.crypto.tls.Client`.
connection: *Connection,
/// Fifo structure that builds websocket frames that are fragmeneted.
fragment: Fragment,
/// Storage for large responses from the server
storage: Writer.Allocating,
/// Indicates that the connection is closed or not
closed: bool,

pub fn connect(
    allocator: Allocator,
    uri: Uri,
) !WebsocketClient {
    const scheme = Protocol.fromScheme(uri.scheme) orelse return error.UnsupportedSchema;

    const port: u16 = uri.port orelse switch (scheme) {
        .plain => 80,
        .tls => 443,
    };

    const hostname = switch (uri.host orelse return error.UnspecifiedHostName) {
        .raw => |raw| raw,
        .percent_encoded => |host| host,
    };

    const storage: Writer.Allocating = .init(allocator);
    const fragment: Fragment = .{
        .alloc_writer = .init(allocator),
        .message_type = null,
    };

    const stream = try std.net.tcpConnectToHost(allocator, hostname, port);
    errdefer stream.close();

    const connection = switch (scheme) {
        .plain => &(try Connection.Plain.create(allocator, uri, stream)).connection,
        .tls => &(try Connection.Tls.create(allocator, uri, stream)).connection,
    };

    return .{
        .allocator = allocator,
        .fragment = fragment,
        .connection = connection,
        .storage = storage,
        .closed = false,
    };
}

/// Send close handshake and closes the net stream.
pub fn close(
    self: *WebsocketClient,
    exit_code: u16,
) void {
    if (@atomicRmw(bool, &self.closed, .Xchg, true, .acq_rel) == false) {
        self.writeCloseFrame(exit_code) catch {};
        self.connection.close();
    }
}

/// Clears the inner data structures. And closes the connection.
///
/// The connection is not destroyed by this method and must be called seperatly.
///
/// This was done because the `readLoop` might get ran in different threads.
/// So this avoid potential segfaults when deiniting the client.
///
/// See:
/// * `Connection.destroyConnection`
pub fn deinit(self: *WebsocketClient) void {
    self.close(0);
    self.fragment.deinit();
    self.storage.deinit();
}

/// Generate a base64 set of random bytes.
pub fn generateHandshakeKey() [24]u8 {
    var nonce: [16]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    var base_64: [24]u8 = undefined;
    _ = Base64Encoder.encode(&base_64, &nonce);

    return base_64;
}

/// Masks a websocket message. Uses simd when possible.
pub fn maskMessage(
    message: []u8,
    mask: [4]u8,
) void {
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

/// Performs the websocket handshake and validates that it got a valid response.
///
/// More info here: https://www.rfc-editor.org/rfc/rfc6455#section-1.2
pub fn handshake(
    self: *WebsocketClient,
    host: []const u8,
) !void {
    const key = generateHandshakeKey();
    errdefer self.deinit();

    try self.sendHandshake(host, key);

    const headers = try self.readHandshake();
    try parseHandshakeResponse(key, headers);
}

/// Validates that the handshake response is valid and returns the amount of bytes read.
///
/// The return bytes are then used to discard in case where we read more than handshake from the stream.
pub fn parseHandshakeResponse(
    key: [24]u8,
    response: []const u8,
) !void {
    var iter = std.mem.tokenizeAny(u8, response, "\r\n");
    var websocket_key: ?[]const u8 = null;

    var checks: Checks = .none;
    while (iter.next()) |header| {
        const index = std.mem.indexOfScalar(u8, header, ':') orelse {
            if (std.ascii.startsWithIgnoreCase(header, "HTTP/1.1 101")) {
                checks = switch (checks) {
                    .none => .checked_protocol,
                    .checked_protocol => return error.DuplicateHandshakeHeader,
                    else => return error.InvalidHandshakeMessage,
                };
            }

            continue;
        };

        if (std.ascii.eqlIgnoreCase(header[0..index], "sec-websocket-accept")) {
            @branchHint(.likely);

            const trimmed = std.mem.trim(u8, header[index + 1 ..], &std.ascii.whitespace);
            websocket_key = trimmed;

            checks = switch (checks) {
                .checked_upgrade,
                .checked_connection,
                => .checked_key,
                .checked_key => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }

        if (std.ascii.eqlIgnoreCase(header[0..index], "connection")) {
            @branchHint(.likely);

            const trimmed = std.mem.trim(u8, header[index + 1 ..], &std.ascii.whitespace);
            if (!std.ascii.eqlIgnoreCase(trimmed, "upgrade"))
                return error.InvalidHandshakeMessage;

            checks = switch (checks) {
                .checked_protocol,
                .checked_upgrade,
                => .checked_connection,
                .checked_connection => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }

        if (std.ascii.eqlIgnoreCase(header[0..index], "upgrade")) {
            @branchHint(.likely);

            const trimmed = std.mem.trim(u8, header[index + 1 ..], &std.ascii.whitespace);
            if (!std.ascii.eqlIgnoreCase(trimmed, "websocket"))
                return error.InvalidHandshakeMessage;

            checks = switch (checks) {
                .checked_protocol,
                .checked_connection,
                => .checked_upgrade,
                .checked_upgrade => return error.DuplicateHandshakeHeader,
                else => return error.InvalidHandshakeMessage,
            };
        }
    }

    const ws_key = websocket_key orelse {
        @branchHint(.unlikely);
        return error.InvalidHandshakeKey;
    };

    var hash: [Sha1.digest_length]u8 = undefined;

    var hasher = Sha1.init(.{});
    hasher.update(&key);
    hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    hasher.final(&hash);

    var buffer: [28]u8 = undefined;
    _ = Base64Encoder.encode(&buffer, &hash);

    const encoded_int: u224 = @bitCast(buffer);

    std.debug.assert(ws_key.len == 28); // Invalid websocket_key
    const reponse_int: u224 = @bitCast(ws_key[0..28].*);

    if (encoded_int != reponse_int) {
        @branchHint(.unlikely);
        return error.InvalidHandshakeKey;
    }
}

/// Buffers the entire handshake inside of the `reader`.
///
/// The resulting memory is invalidated by any subsequent consumption of
/// the input stream.
pub fn readHandshake(self: *WebsocketClient) ![]const u8 {
    const reader = self.connection.reader();

    var hp: std.http.HeadParser = .{};
    var head_len: usize = 0;

    while (true) {
        if (reader.buffer.len - head_len == 0) return error.HandshakeOversize;

        const remaining = reader.buffered()[head_len..];

        if (remaining.len == 0) {
            reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => switch (head_len) {
                    0 => return error.Closing,
                    else => return error.RequestTruncated,
                },
                error.ReadFailed => return error.ReadFailed,
            };
            continue;
        }

        head_len += hp.feed(remaining);

        if (hp.state == .finished) {
            const head_buffer = reader.buffered()[0..head_len];
            reader.toss(head_len);
            return head_buffer;
        }
    }
}

/// Reads a websocket frame from the socket and decodes it based on
/// the frames headers.
///
/// This will fail if the server sends masked data as per the RFC the server
/// must always send unmasked data.
///
/// More info here: https://www.rfc-editor.org/rfc/rfc6455#section-6.2
pub fn readMessage(self: *WebsocketClient) !WebsocketMessage {
    var reader = self.connection.reader();

    while (true) {
        const headers = try reader.takeArray(2);

        const op_head: OpcodeHeader = @bitCast(headers[0]);
        const payload_head: PayloadHeader = @bitCast(headers[1]);

        if (payload_head.mask)
            return error.MaskedServerMessage;

        if (@bitCast(op_head.rsv1) or @bitCast(op_head.rsv2) or @bitCast(op_head.rsv3))
            return error.UnnegociatedReservedBits;

        const total = switch (payload_head.payload_len) {
            .len16 => try reader.takeInt(u16, .big),
            .len64 => std.math.cast(usize, try reader.takeInt(u64, .big)) orelse return error.MessageSizeOverflow,
            _ => @intFromEnum(payload_head.payload_len),
        };

        const payload = blk: {
            if (total < reader.buffered().len)
                break :blk try reader.take(total);

            try self.storage.ensureUnusedCapacity(total);
            try reader.streamExact(&self.storage.writer, total);
            defer self.storage.shrinkRetainingCapacity(0);

            break :blk self.storage.written();
        };

        switch (op_head.opcode) {
            .text,
            .binary,
            => {
                if (!op_head.fin) {
                    try self.fragment.writeAll(payload);
                    self.fragment.message_type = op_head.opcode;

                    continue;
                }

                if (self.fragment.size() != 0)
                    return error.UnexpectedFragment;

                if (op_head.opcode == .text and !std.unicode.utf8ValidateSlice(payload))
                    return error.InvalidUtf8Payload;

                wsclient_log.debug("Got websocket message: {s}", .{payload});

                return .{
                    .opcode = op_head.opcode,
                    .data = payload,
                };
            },
            .continuation,
            => {
                const message_type = self.fragment.message_type orelse return error.FragmentedControl;

                if (!op_head.fin) {
                    try self.fragment.writeAll(payload);
                    continue;
                }

                try self.fragment.writeAll(payload);
                defer self.fragment.reset();

                const slice = self.fragment.slice();

                if (message_type == .text and !std.unicode.utf8ValidateSlice(slice))
                    return error.InvalidUtf8Payload;

                wsclient_log.debug("Got complete fragmented websocket message: {s}", .{slice});

                return .{
                    .opcode = message_type,
                    .data = slice,
                };
            },
            .ping,
            .pong,
            .connection_close,
            => {
                if (total > 125 or !op_head.fin)
                    return error.ControlFrameTooBig;

                return .{
                    .opcode = op_head.opcode,
                    .data = payload,
                };
            },
            _ => return error.UnsupportedOpcode,
        }
    }
}

/// Send the handshake message to the server. Doesn't support url's higher than 4096 bits.
///
/// Also writes the query of the path if the `uri` was able to parse it.
pub fn sendHandshake(
    self: *WebsocketClient,
    host: []const u8,
    key: [24]u8,
) !void {
    var writer = self.connection.writer();

    try writer.writeAll("GET ");

    if (self.connection.uri.path.isEmpty()) {
        try writer.writeByte('/');
    } else try writer.writeAll(try self.connection.uri.path.toRaw(writer.buffer[writer.end..]));

    if (self.connection.uri.query) |query| {
        try writer.writeByte('?');
        try writer.writeAll(try query.toRaw(writer.buffer[writer.end..]));
    }

    try writer.writeAll(" HTTP/1.1\r\n");
    try writer.print("Host: {s}\r\n", .{host});
    try writer.writeAll("Content-length: 0\r\n");
    try writer.writeAll("Upgrade: websocket\r\n");
    try writer.writeAll("Connection: Upgrade\r\n");
    try writer.print("Sec-WebSocket-Key: {s}\r\n", .{key});
    try writer.writeAll("Sec-WebSocket-Version: 13\r\n");
    try writer.writeAll("\r\n");

    try self.connection.flush();
}

/// Writes to the server a close frame with a provided `exit_code`.
///
/// For more details please see: https://www.rfc-editor.org/rfc/rfc6455#section-5.5.1
pub fn writeCloseFrame(
    self: *WebsocketClient,
    exit_code: u16,
) !void {
    if (exit_code == 0)
        return self.writeFrame("", .connection_close);

    var buffer: [2]u8 = undefined;
    std.mem.writeInt(u16, buffer[0..2], exit_code, .big);

    return self.writeFrame(buffer[0..], .connection_close);
}

/// Writes a websocket frame directly to the socket.
///
/// The message is masked according to the websocket RFC.
/// More details here: https://www.rfc-editor.org/rfc/rfc6455#section-6.1
pub fn writeFrame(
    self: *WebsocketClient,
    message: []u8,
    opcode: Opcode,
) !void {
    const mask = try self.writeHeaderFrame(message, opcode);
    try self.connection.flush();

    if (message.len > 0) {
        @branchHint(.likely);

        maskMessage(message, mask);

        try self.connection.writer().writeAll(message);
        try self.connection.flush();
    }
}

/// Generates the websocket header frame based on the message len and the opcode provided.
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-------+-+-------------+-------------------------------+
/// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
/// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
/// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
/// | |1|2|3|       |K|             |                               |
/// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
/// |     Extended payload length continued, if payload len == 127  |
/// + - - - - - - - - - - - - - - - +-------------------------------+
/// |                               |Masking-key, if MASK set to 1  |
/// +-------------------------------+-------------------------------+
/// | Masking-key (continued)       |          Payload Data         |
/// +-------------------------------- - - - - - - - - - - - - - - - +
/// :                     Payload Data continued ...                :
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// |                     Payload Data continued ...                |
/// +---------------------------------------------------------------+
pub fn writeHeaderFrame(
    self: *WebsocketClient,
    message: []const u8,
    opcode: Opcode,
) ![4]u8 {
    var writer = self.connection.writer();

    var buffer: [4]u8 = undefined;

    try writer.writeByte(@bitCast(@as(OpcodeHeader, .{
        .opcode = opcode,
        .fin = true,
    })));

    switch (message.len) {
        0...125 => {
            try writer.writeByte(@bitCast(@as(PayloadHeader, .{
                .payload_len = @enumFromInt(message.len),
                .mask = true,
            })));

            std.crypto.random.bytes(buffer[0..]);
            try writer.writeAll(buffer[0..]);

            return buffer;
        },
        126...0xFFFF => {
            try writer.writeByte(@bitCast(@as(PayloadHeader, .{
                .payload_len = .len16,
                .mask = true,
            })));

            try writer.writeInt(u16, @intCast(message.len), .big);

            std.crypto.random.bytes(buffer[0..]);
            try writer.writeAll(buffer[0..]);

            return buffer;
        },
        else => {
            try writer.writeByte(@bitCast(@as(PayloadHeader, .{
                .payload_len = .len64,
                .mask = true,
            })));

            try writer.writeInt(u64, @intCast(message.len), .big);

            std.crypto.random.bytes(buffer[0..]);
            try writer.writeAll(buffer[0..]);

            return buffer;
        },
    }
}

test "handshake" {
    const path = try std.fmt.allocPrint(testing.allocator, "http://localhost:9001/runCase?casetuple={s}&agent=zabi.zig", .{"5.6"});
    defer testing.allocator.free(path);

    const uri = try std.Uri.parse(path);

    var client = try WebsocketClient.connect(testing.allocator, uri);
    defer client.deinit();

    try client.handshake("localhost:9001");

    while (true) {
        const message = client.readMessage() catch |err| switch (err) {
            error.EndOfStream => {
                client.close(1002);
                return;
            },
            error.InvalidUtf8Payload => {
                client.close(1007);
                return err;
            },
            else => {
                client.close(1002);
                return err;
            },
        };

        switch (message.opcode) {
            .binary,
            => try client.writeFrame(@constCast(message.data), .binary),
            .text,
            => try client.writeFrame(@constCast(message.data), .text),
            .ping,
            => try client.writeFrame(@constCast(message.data), .pong),
            .connection_close,
            => return client.close(0),
            // Ignore unsolicited pong messages.
            .pong,
            => continue,
            else => return error.UnexpectedOpcode,
        }
    }
}
