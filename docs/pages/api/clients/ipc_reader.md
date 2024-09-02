## IpcReader

Socket reader that is expected to be reading socket messages
that are json messages. Growth is linearly based on the provided `growth_rate`.

Will only allocate more memory if required.
Calling `deinit` will close the socket and clear the buffer.

### Properties

```zig
struct {
  /// The underlaying allocator used to manage the buffer.
  allocator: Allocator
  /// Buffer that contains all messages. Grows based on `growth_rate`.
  buffer: []u8
  /// The growth rate of the message buffer.
  growth_rate: usize
  /// The end of a json message.
  message_end: usize = 0
  /// The start of the json message.
  message_start: usize = 0
  /// The current position in the buffer.
  position: usize = 0
  /// The stream used to read or write.
  stream: Stream
  /// If the stream is closed for reading.
  closed: bool
}
```

## ReadError

Set of possible errors when reading from the socket.

```zig
Stream.ReadError || Allocator.Error || error{Closed}
```

### Init
Sets the initial reader state in order to perform any necessary actions.

**Example**
```zig
const stream = std.net.connectUnixSocket("tmp/tmp.socket");

const ipc_reader = try IpcReader.init(stream, null);
defer ipc_reader.deinit();
```

### Signature

```zig
pub fn init(allocator: Allocator, stream: Stream, growth_rate: ?usize) Allocator.Error!Self
```

### Deinit
Frees the buffer and closes the stream.

### Signature

```zig
pub fn deinit(self: Self) void
```

### Read
Reads the bytes directly from the socket. Will allocate more memory as needed.

### Signature

```zig
pub fn read(self: *Self) Self.ReadError!void
```

### Grow
Grows the reader buffer based on the growth rate. Will use the `allocator` resize
method if available.

### Signature

```zig
pub fn grow(self: *@This(), size: usize) Allocator.Error!void
```

### JsonMessage
"Reads" a json message and moves the necessary position members in order
to have the necessary message.

### Signature

```zig
pub fn jsonMessage(self: *@This()) usize
```

### ReadMessage
Reads one message from the socket stream.
Will only make the socket read request if the buffer is at max capacity.
Will grow the buffer as needed.

### Signature

```zig
pub fn readMessage(self: *Self) Self.ReadError![]u8
```

### PrepareForRead
Prepares the reader for the next message.

### Signature

```zig
pub fn prepareForRead(self: *Self) void
```

### WriteMessage
Writes a message to the socket stream.

### Signature

```zig
pub fn writeMessage(self: *Self, message: []u8) Stream.WriteError!void
```

## ReadError

Set of possible errors when reading from the socket.

```zig
Stream.ReadError || Allocator.Error || error{Closed}
```

