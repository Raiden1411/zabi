const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const Atomic = std.atomic.Value(usize);

/// Socket reader that is expected to be reading socket messages
/// that are json messages. Growth is linearly based on the provided `growth_rate`.
///
/// Will only allocate more memory if required.
/// Calling `deinit` will close the socket and clear the buffer.
pub const IpcReader = struct {
    /// Set of possible errors when reading from the socket.
    pub const ReadError = Stream.ReadError || Allocator.Error || error{Closed};

    /// Set of possible error when writting to the stream.
    pub const WriteError = Stream.WriteError;

    /// Reference to self.
    const Self = @This();

    /// The underlaying allocator used to manage the buffer.
    allocator: Allocator,
    /// Buffer that contains all messages. Grows based on `growth_rate`.
    buffer: []u8,
    /// The growth rate of the message buffer.
    growth_rate: usize,
    /// The end of a json message.
    message_end: usize,
    /// The start of the json message.
    message_start: usize,
    /// The current position in the buffer.
    position: usize,
    /// The stream used to read or write.
    stream: Stream,
    /// If the stream is closed for reading.
    closed: bool,

    /// Sets the initial reader state in order to perform any necessary actions.
    ///
    /// **Example**
    /// ```zig
    /// const stream = std.net.connectUnixSocket("tmp/tmp.socket");
    ///
    /// const ipc_reader = try IpcReader.init(stream, null);
    /// defer ipc_reader.deinit();
    /// ```
    pub fn init(allocator: Allocator, stream: Stream, growth_rate: ?usize) Allocator.Error!Self {
        return .{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, growth_rate orelse std.math.maxInt(u16)),
            .stream = stream,
            .growth_rate = growth_rate orelse std.math.maxInt(u16),
            .message_start = 0,
            .message_end = 0,
            .position = 0,
        };
    }
    /// Frees the buffer and closes the stream.
    pub fn deinit(self: *Self) void {
        if (@atomicRmw(bool, &self.closed, .Xchg, true, .acq_rel) == false) {
            self.allocator.free(self.buffer);
            self.stream.close();
        }
    }
    /// Reads the bytes directly from the socket. Will allocate more memory as needed.
    pub fn read(self: *Self) Self.ReadError!void {
        var result: [std.math.maxInt(u16)]u8 = undefined;
        const size = try self.stream.read(result[0..]);

        if (size == 0)
            return error.Closed;

        const position = self.position;

        if (position + size > self.buffer.len)
            try self.grow(size);

        std.debug.assert(self.buffer.len >= position + size);

        @memcpy(self.buffer[position .. position + size], result[0..size]);
        self.position += size;
    }
    /// Grows the reader buffer based on the growth rate. Will use the `allocator` resize
    /// method if available.
    pub fn grow(self: *Self, size: usize) Allocator.Error!void {
        if (self.allocator.resize(self.buffer, self.buffer.len + self.growth_rate + size))
            return;

        const new_buffer = try self.allocator.alloc(u8, self.buffer.len + self.growth_rate + size);

        @memcpy(new_buffer[0..self.buffer.len], self.buffer);
        self.allocator.free(self.buffer);
        self.buffer = new_buffer;
    }
    /// "Reads" a json message and moves the necessary position members in order
    /// to have the necessary message.
    pub fn jsonMessage(self: *@This()) usize {
        var depth: usize = 0;

        var message_end = self.message_end;
        const position = self.position;

        while (message_end < position) : (message_end += 1) {
            switch (self.buffer[message_end]) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }

            // Check if we read a message or not.
            if (depth == 0) {
                self.message_end = message_end + 1;
                return self.message_end - self.message_start;
            }
        }

        return 0;
    }
    /// Reads one message from the socket stream.
    /// Will only make the socket read request if the buffer is at max capacity.
    /// Will grow the buffer as needed.
    pub fn readMessage(self: *Self) Self.ReadError![]u8 {
        self.prepareForRead();

        while (true) {
            const size = self.jsonMessage();

            if (size == 0) {
                try self.read();
                continue;
            }

            std.debug.assert(self.message_start < self.buffer.len);
            std.debug.assert(self.message_end < self.buffer.len);

            return self.buffer[self.message_start..self.message_end];
        }
    }
    /// Prepares the reader for the next message.
    pub fn prepareForRead(self: *Self) void {
        self.message_start = self.message_end;
    }
    /// Writes a message to the socket stream.
    pub fn writeMessage(self: *Self, message: []u8) Stream.WriteError!void {
        try self.stream.writeAll(message);
    }
};
