//! Socket reader that is expected to be reading socket messages that are json messages.
//! Will only allocate more memory if required.
//!
//! Calling `deinit` will close the socket and clear the buffer.
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const Buffer = std.fifo.LinearFifo(u8, .Dynamic);

const Self = @This();

/// Set of possible errors when reading from the socket.
pub const ReadError = Stream.ReadError || Allocator.Error || error{Closed} || std.Io.Reader.Error;

/// Set of possible error when writting to the stream.
pub const WriteError = std.Io.Writer.Error;

/// LinearFifo that grows as needed.
buffer: Buffer,
/// Socket stream to read from the unix socket.
stream: Stream,
/// Amount of bytes to discard on a successfull read.
overflow: usize,
/// The tell reader if the stream is closed.
closed: bool,

/// Sets the initial reader state in order to perform any necessary actions.
///
/// **Example**
/// ```zig
/// const stream = std.net.connectUnixSocket("tmp/tmp.socket");
///
/// const ipc_reader = try IpcReader.init(std.heap.page_allocator, stream);
/// defer ipc_reader.deinit();
/// ```
pub fn init(
    allocator: Allocator,
    stream: Stream,
) Allocator.Error!@This() {
    return .{
        .buffer = Buffer.init(allocator),
        .stream = stream,
        .overflow = 0,
    };
}
/// Frees the buffer and closes the stream.
pub fn deinit(self: *@This()) void {
    if (@atomicRmw(bool, &self.closed, .Xchg, true, .acq_rel) == false) {
        self.buffer.deinit();
        self.stream.close();
    }
}
/// "Reads" a json message and moves the necessary position members in order
/// to have the necessary message.
pub fn jsonMessage(self: *@This()) usize {
    self.buffer.discard(self.overflow);
    self.buffer.realign();

    if (self.buffer.count <= 1) {
        self.overflow = 0;
        return 0;
    }

    var depth: usize = 0;
    var index: usize = 0;
    while (index < self.buffer.buf.len) : (index += 1) {
        switch (self.buffer.buf[index]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }

        // Check if we read a message or not.
        if (depth == 0) {
            self.overflow = index + 1;
            return index + 1;
        }
    }

    self.overflow = 0;
    return 0;
}
/// Reads the bytes directly from the socket. Will allocate more memory as needed.
pub fn read(self: *@This()) ReadError!void {
    const buffer = try self.buffer.writableWithSize(std.math.maxInt(u16));

    var reader = self.stream.reader(&.{});
    const read_amount = try reader.file_reader.read(buffer);

    if (read_amount == 0)
        return error.Closed;

    self.buffer.update(read_amount);
}
/// Reads one message from the socket stream.
///
/// Will only make the socket read request if the buffer is at max capacity.
/// Will grow the buffer as needed.
pub fn readMessage(self: *@This()) ReadError![]u8 {
    while (true) {
        const size = self.jsonMessage();

        if (size == 0) {
            try self.read();
            continue;
        }

        return @constCast(self.buffer.readableSliceOfLen(size));
    }
}
/// Writes a message to the socket stream.
pub fn writeMessage(
    self: *@This(),
    message: []u8,
) WriteError!void {
    var writer = self.stream.writer(&.{});
    try writer.interface.writeAll(message);
}
