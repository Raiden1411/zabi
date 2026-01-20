//! Socket reader that is expected to be reading socket messages that are json messages.
//! Will only allocate more memory if required.
//!
//! Calling `deinit` will close the socket and clear the buffer.
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const AllocWhen = std.json.AllocWhen;
const Diagnostics = std.json.Diagnostics;
const Io = std.Io;
const Reader = Io.Reader;
const Scanner = std.json.Scanner;
const Stream = Io.net.Stream;
const Writer = Io.Writer;

const Self = @This();

/// Copied from std with the only change being that it will detect earlier that
/// the object is complete instead of relying on `EndOfStream` error
pub const JsonReader = struct {
    scanner: Scanner,
    reader: *Io.Reader,

    /// The allocator is only used to track `[]` and `{}` nesting levels.
    pub fn init(allocator: Allocator, io_reader: *Io.Reader) @This() {
        return .{
            .scanner = Scanner.initStreaming(allocator),
            .reader = io_reader,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.scanner.deinit();
        self.* = undefined;
    }

    /// Calls `std.json.Scanner.enableDiagnostics`.
    pub fn enableDiagnostics(self: *@This(), diagnostics: *Diagnostics) void {
        self.scanner.enableDiagnostics(diagnostics);
    }

    pub const NextError = Reader.Error || Scanner.Error || Allocator.Error;
    pub const SkipError = JsonReader.NextError;
    pub const AllocError = JsonReader.NextError || error{ValueTooLong};
    pub const PeekError = Reader.Error || Scanner.Error;

    /// Equivalent to `nextAllocMax(allocator, when, default_max_value_len);`
    /// See also `std.json.Token` for documentation of `nextAlloc*()` function behavior.
    pub fn nextAlloc(self: *@This(), allocator: Allocator, when: AllocWhen) JsonReader.AllocError!Scanner.Token {
        return self.nextAllocMax(allocator, when, std.json.default_max_value_len);
    }

    /// See also `std.json.Token` for documentation of `nextAlloc*()` function behavior.
    pub fn nextAllocMax(self: *@This(), allocator: Allocator, when: AllocWhen, max_value_len: usize) JsonReader.AllocError!Scanner.Token {
        const token_type = try self.peekNextTokenType();
        switch (token_type) {
            .number, .string => {
                var value_list = std.array_list.Managed(u8).init(allocator);
                errdefer {
                    value_list.deinit();
                }
                if (try self.allocNextIntoArrayListMax(&value_list, when, max_value_len)) |slice| {
                    return if (token_type == .number)
                        .{ .number = slice }
                    else
                        .{ .string = slice };
                } else {
                    return if (token_type == .number)
                        .{ .allocated_number = try value_list.toOwnedSlice() }
                    else
                        .{ .allocated_string = try value_list.toOwnedSlice() };
                }
            },

            // Simple tokens never alloc.
            .object_begin,
            .object_end,
            .array_begin,
            .array_end,
            .true,
            .false,
            .null,
            .end_of_document,
            => return try self.next(),
        }
    }

    /// Equivalent to `allocNextIntoArrayListMax(value_list, when, default_max_value_len);`
    pub fn allocNextIntoArrayList(self: *@This(), value_list: *std.array_list.Managed(u8), when: AllocWhen) JsonReader.AllocError!?[]const u8 {
        return self.allocNextIntoArrayListMax(value_list, when, std.json.default_max_value_len);
    }

    /// Calls `std.json.Scanner.allocNextIntoArrayListMax` and handles `error.BufferUnderrun`.
    pub fn allocNextIntoArrayListMax(self: *@This(), value_list: *std.array_list.Managed(u8), when: AllocWhen, max_value_len: usize) JsonReader.AllocError!?[]const u8 {
        while (true) {
            return self.scanner.allocNextIntoArrayListMax(value_list, when, max_value_len) catch |err| switch (err) {
                error.BufferUnderrun => {
                    try self.refillBuffer();
                    continue;
                },
                else => |other_err| return other_err,
            };
        }
    }

    /// Like `std.json.Scanner.skipValue`, but handles `error.BufferUnderrun`.
    pub fn skipValue(self: *@This()) JsonReader.SkipError!void {
        switch (try self.peekNextTokenType()) {
            .object_begin, .array_begin => {
                try self.skipUntilStackHeight(self.stackHeight());
            },
            .number, .string => {
                while (true) {
                    switch (try self.next()) {
                        .partial_number,
                        .partial_string,
                        .partial_string_escaped_1,
                        .partial_string_escaped_2,
                        .partial_string_escaped_3,
                        .partial_string_escaped_4,
                        => continue,

                        .number, .string => break,

                        else => unreachable,
                    }
                }
            },
            .true, .false, .null => {
                _ = try self.next();
            },

            .object_end, .array_end, .end_of_document => unreachable, // Attempt to skip a non-value token.
        }
    }

    /// Like `std.json.Scanner.skipUntilStackHeight()` but handles `error.BufferUnderrun`.
    pub fn skipUntilStackHeight(self: *@This(), terminal_stack_height: usize) JsonReader.NextError!void {
        while (true) {
            return self.scanner.skipUntilStackHeight(terminal_stack_height) catch |err| switch (err) {
                error.BufferUnderrun => {
                    try self.refillBuffer();
                    continue;
                },
                else => |other_err| return other_err,
            };
        }
    }

    /// Calls `std.json.Scanner.stackHeight`.
    pub fn stackHeight(self: *const @This()) usize {
        return self.scanner.stackHeight();
    }

    /// Calls `std.json.Scanner.ensureTotalStackCapacity`.
    pub fn ensureTotalStackCapacity(self: *@This(), height: usize) Allocator.Error!void {
        try self.scanner.ensureTotalStackCapacity(height);
    }

    /// See `std.json.Token` for documentation of this function.
    pub fn next(self: *@This()) JsonReader.NextError!Scanner.Token {
        while (true) {
            return self.scanner.next() catch |err| switch (err) {
                error.BufferUnderrun => {
                    if (self.scanner.state == .post_value and self.stackHeight() == 0) {
                        self.scanner.endInput();
                        continue;
                    }

                    try self.refillBuffer();
                    continue;
                },
                else => |other_err| return other_err,
            };
        }
    }

    /// See `std.json.Scanner.peekNextTokenType()`.
    pub fn peekNextTokenType(self: *@This()) JsonReader.PeekError!Scanner.TokenType {
        while (true) {
            return self.scanner.peekNextTokenType() catch |err| switch (err) {
                error.BufferUnderrun => {
                    try self.refillBuffer();
                    continue;
                },
                else => |other_err| return other_err,
            };
        }
    }

    fn refillBuffer(self: *@This()) Reader.Error!void {
        if (self.scanner.state == .post_value and self.stackHeight() == 0)
            return self.scanner.endInput();

        const input = self.reader.peekGreedy(1) catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.EndOfStream => return self.scanner.endInput(),
        };

        self.reader.toss(input.len);
        self.scanner.feedInput(input);
    }
};

/// Representation of a ipc/pipe connection used by this client
///
/// This is similar to `std.http.Client.Connection` but adapted to our use case.
pub const Connection = struct {
    /// The writer that will be used to write to the stream connection.
    stream_writer: Stream.Writer,
    /// The reader that will be used to read data from the socket.
    stream_reader: Stream.Reader,

    /// Closes the network connection
    ///
    /// If the connection is a tls connection it will send and `end` message and flushes it.
    pub fn close(self: *Connection, io: Io) void {
        self.flush() catch {};

        self.getStream().shutdown(io, .both) catch {};
        self.getStream().close(io);
    }

    /// Frees the memory associated with the reader and writer buffers
    /// and the connection pointer
    pub fn destroyConnection(self: *Connection, allocator: Allocator) void {
        const plain: *Plain = @alignCast(@fieldParentPtr("connection", self));
        plain.destroy(allocator);
    }

    /// Flushes the buffered data and writes to it.
    pub fn flush(self: *Connection) Writer.Error!void {
        try self.stream_writer.interface.flush();
    }

    /// Gets the network stream associated with this connection
    pub fn getStream(self: *Connection) Stream {
        return self.stream_reader.stream;
    }

    /// Gets the reader independent of the connection type. Either tls or plain.
    pub fn reader(self: *Connection) *Reader {
        return &self.stream_reader.interface;
    }

    /// Gets the writer independent of the connection type. Either tls or plain.
    pub fn writer(self: *Connection) *Writer {
        return &self.stream_writer.interface;
    }

    /// Representation of a plain socket/pipe connection
    pub const Plain = struct {
        connection: Connection,

        const read_buffer_size = 8192;
        const write_buffer_size = 1024;
        const allocation_length = write_buffer_size + read_buffer_size + @sizeOf(Plain) + @sizeOf(usize);

        /// Creates the pointer and any buffers that the readers and writers need.
        pub fn create(
            allocator: Allocator,
            io: Io,
            stream: Stream,
        ) !*Plain {
            const base = try allocator.alignedAlloc(u8, .of(Plain), allocation_length);
            errdefer allocator.free(base);

            const host = base[@sizeOf(Plain)..][0..@sizeOf(usize)];
            const socket_read_buffer = host.ptr[host.len..][0..read_buffer_size];
            const socket_write_buffer = socket_read_buffer.ptr[socket_read_buffer.len..][0..write_buffer_size];

            const plain: *Plain = @ptrCast(base);
            std.debug.assert(base.ptr + allocation_length == socket_write_buffer.ptr + socket_write_buffer.len);

            plain.* = .{
                .connection = .{
                    .stream_writer = stream.writer(io, socket_write_buffer),
                    .stream_reader = stream.reader(io, socket_read_buffer),
                },
            };

            return plain;
        }

        /// Destroy the pointer and frees the read and write buffer
        pub fn destroy(plain: *Plain, allocator: Allocator) void {
            const base: [*]align(@alignOf(Plain)) u8 = @ptrCast(plain);

            allocator.free(base[0..allocation_length]);
        }
    };
};

/// The Io implementation used by this client
io: Io,
/// Underlaying socket/pipe connection
connection: *Connection,

/// Sets the initial reader state in order to perform any necessary actions.
///
/// **Example**
/// ```zig
/// const stream = std.net.connectUnixSocket("/tmp/tmp.socket");
///
/// const ipc_reader = try IpcReader.init(std.heap.page_allocator, stream);
/// defer {
///     ipc_reader.deinit();
///     ipc_reader.connection.destroyConnection(std.heap.page_allocator);
/// }
/// ```
pub fn init(
    allocator: Allocator,
    io: Io,
    stream: Stream,
) Allocator.Error!@This() {
    const connection = &(try Connection.Plain.create(allocator, io, stream)).connection;

    return .{
        .io = io,
        .connection = connection,
    };
}

/// Closes the connection but doesnt free the allocated memory.
///
/// That must be done seperatly via `Connection.destroyConnection`
pub fn deinit(self: *@This()) void {
    self.connection.close(self.io);
}

/// Reads one message from the socket stream.
///
/// Will only make the socket read request if the buffer is at max capacity.
/// Will grow the buffer as needed.
pub fn readMessage(self: *@This(), allocator: Allocator) !std.json.Parsed(std.json.Value) {
    var reader = JsonReader.init(allocator, self.connection.reader());
    defer reader.deinit();

    return std.json.parseFromTokenSource(
        std.json.Value,
        allocator,
        &reader,
        .{ .allocate = .alloc_always },
    );
}

/// Writes a message to the socket stream.
pub fn writeMessage(
    self: *@This(),
    message: []const u8,
) !void {
    var writer = self.connection.writer();

    try writer.writeAll(message);
    return self.connection.flush();
}

test "Fooo" {
    var threaded_io: Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    const unix = try Io.net.UnixAddress.init("/tmp/anvil.ipc");
    const stream = try unix.connect(threaded_io.io());

    var ipc_reader = try Self.init(std.testing.allocator, threaded_io.io(), stream);
    defer {
        ipc_reader.deinit();
        ipc_reader.connection.destroyConnection(std.testing.allocator);
    }

    try ipc_reader.writeMessage(
        \\{"jsonrpc": "2.0", "id": 31337, "method": "eth_getBlockByNumber", "params": ["latest", false]}
    );

    const parsed = try ipc_reader.readMessage(std.testing.allocator);
    defer parsed.deinit();
}
