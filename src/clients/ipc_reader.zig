const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;

/// Socket reader that is expected to be reading socket messages
/// that are json messages. Growth is linearly based on the provided `growth_rate`.
///
/// Will only allocate more memory if required.
/// Calling `deinit` will close the socket and clear the buffer.
pub const IpcReader = struct {
    /// The underlaying allocator used to manage the buffer.
    allocator: Allocator,
    /// Buffer that contains all messages. Grows based on `growth_rate`.
    buffer: []u8,
    /// The growth rate of the message buffer.
    growth_rate: usize,
    /// The end of a json message.
    message_end: usize = 0,
    /// The start of the json message.
    message_start: usize = 0,
    /// The current position in the buffer.
    position: usize = 0,
    /// The stream used to read or write.
    stream: Stream,

    /// Sets the initial reader state in order to perform any necessary actions.
    pub fn init(allocator: Allocator, stream: Stream, growth_rate: ?usize) !@This() {
        return .{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, growth_rate orelse std.math.maxInt(u16)),
            .stream = stream,
            .growth_rate = growth_rate orelse std.math.maxInt(u16),
        };
    }
    /// Frees the buffer and closes the stream.
    pub fn deinit(self: @This()) void {
        self.allocator.free(self.buffer);
        self.stream.close();
    }
    /// Reads the bytes directly from the socket. Will allocate more memory as needed.
    pub fn read(self: *@This()) !void {
        var result: [std.math.maxInt(u16)]u8 = undefined;
        const size = try self.stream.read(result[0..]);

        if (size == 0)
            return error.Closed;

        if (self.position + size > self.buffer.len)
            try self.grow(size);

        std.debug.assert(self.buffer.len > self.position + size);
        @memcpy(self.buffer[self.position .. self.position + size], result[0..size]);
        self.position += size;
    }
    /// Grows the reader buffer based on the growth rate. Will use the `allocator` resize
    /// method if available.
    pub fn grow(self: *@This(), size: usize) !void {
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

        while (self.message_end < self.position) : (self.message_end += 1) {
            switch (self.buffer[self.message_end]) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }

            // Check if we read a message or not.
            if (depth == 0) {
                self.message_end += 1;
                return self.message_end - self.message_start;
            }
        }

        self.message_end = self.message_start;
        return 0;
    }
    /// Reads one message from the socket stream.
    /// Will only make the socket read request if the buffer is at max capacity.
    /// Will grow the buffer as needed.
    pub fn readMessage(self: *@This()) ![]u8 {
        self.prepareForRead();

        while (true) {
            if (self.message_start == self.message_end) {
                const size = self.jsonMessage();

                if (size == 0) {
                    try self.read();
                    continue;
                }
            }

            std.debug.assert(self.message_start < self.buffer.len);
            std.debug.assert(self.message_end < self.buffer.len);

            return self.buffer[self.message_start..self.message_end];
        }
    }
    /// Prepares the reader for the next message.
    pub fn prepareForRead(self: *@This()) void {
        self.message_start = self.message_end;
    }
    /// Writes a message to the socket stream.
    pub fn writeMessage(self: *@This(), message: []u8) !void {
        try self.stream.writeAll(message);
    }
};
