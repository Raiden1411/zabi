## ConnectionErrors

Set of possible error's when trying to perform the initial connection to the host.

```zig
TlsClient.InitError(Stream) || TcpConnectToHostError || CertificateBundle.RescanError || error{ UnsupportedSchema, UnspecifiedHostName }
```

## AssertionError

Set of possible errors when asserting a handshake response.

```zig
error{ DuplicateHandshakeHeader, InvalidHandshakeMessage, InvalidHandshakeKey }
```

## SendHandshakeError

Set of possible errors when sending a handshake response.

```zig
Stream.WriteError || error{NoSpaceLeft} || TlsAlertErrors
```

## ReadHandshakeError

Set of possible errors when reading a handshake response.

```zig
Allocator.Error || Stream.ReadError || AssertionError || TlsError
```

## SocketReadError

Set of possible errors when trying to read values directly from the socket.

```zig
Stream.ReadError || Allocator.Error || error{EndOfStream} || TlsError
```

## PayloadErrors

RFC Compliant set of errors.

```zig
error{
    UnnegociatedReservedBits,
    ControlFrameTooBig,
    UnfragmentedContinue,
    MessageSizeOverflow,
    UnsupportedOpcode,
    UnexpectedFragment,
    MaskedServerMessage,
    InvalidUtf8Payload,
    FragmentedControl,
}
```

## TlsError

Set of Tls errors outside of alerts.

```zig
error{
    Overflow,
    TlsUnexpectedMessage,
    TlsIllegalParameter,
    TlsRecordOverflow,
    TlsBadRecordMac,
    TlsConnectionTruncated,
    TlsDecodeError,
    TlsBadLength,
} || TlsAlertErrors
```

## ReadMessageError

Possible errors when reading a websocket frame.

```zig
SocketReadError || PayloadErrors
```

## Checks

### Properties

```zig
union(enum) {
  none
  checked_protocol
  checked_upgrade
  checked_connection
  checked_key
}
```

## WebsocketMessage

Structure of a websocket message.

### Properties

```zig
struct {
  /// Websocket valid opcodes.
  opcode: Opcodes
  /// Payload data read.
  data: []const u8
}
```

## Fragment

Wrapper around a websocket fragmented frame.

### Properties

```zig
struct {
  /// FIFO stream of all fragments.
  fragment_fifo: LinearFifo
  /// The type of message that the fragment is. Control fragment's are not supported.
  message_type: ?Opcodes
}
```

### Deinit
Clears any allocated memory.

### Signature

```zig
pub fn deinit(self: *Self) void
```

### WriteAll
Writes the payload into the stream.

### Signature

```zig
pub fn writeAll(self: *Self, payload: []const u8) Allocator.Error!void
```

### Reset
Reset the fragment but keeps the allocated memory.
Also reset the message type back to null.

### Signature

```zig
pub fn reset(self: *Self) void
```

### Slice
Returns a slice of the currently written values on the buffer.

### Signature

```zig
pub fn slice(self: Self) []const u8
```

### Size
Returns the total amount of bytes that were written.

### Signature

```zig
pub fn size(self: Self) usize
```

## NetStream

Wrapper stream around a `std.net.Stream` and a `TlsClient`.

### Properties

```zig
struct {
  /// The connection to the socket that will be used by the
  /// client or the tls_stream if available.
  net_stream: Stream
  /// Null by default since we might want to connect
  /// locally and don't want to enforce it.
  tls_stream: ?TlsClient = null
}
```

### WriteAll
Depending on if the tls_stream is not null it will use that instead.

### Signature

```zig
pub fn writeAll(self: *NetStream, message: []const u8) !void
```

### ReadAtLeast
Depending on if the tls_stream is not null it will use that instead.

### Signature

```zig
pub fn readAtLeast(self: *NetStream, buffer: []u8, size: usize) !usize
```

### Read
Depending on if the tls_stream is not null it will use that instead.

### Signature

```zig
pub fn read(self: *NetStream, buffer: []u8) !usize
```

### Close
Close the tls client if it's not null and the stream.

### Signature

```zig
pub fn close(self: *NetStream) void
```

## Connect
Connects to the specficed uri. Creates a tls connection depending on the `uri.scheme`

Check out `protocol_map` to see when tls is enable. For now this doesn't respect zig's
`disable_tls` option.

### Signature

```zig
pub fn connect(allocator: Allocator, uri: Uri) ConnectionErrors!WebsocketClient
```

## GenerateHandshakeKey
Generate a base64 set of random bytes.

### Signature

```zig
pub fn generateHandshakeKey() [24]u8
```

## MaskMessage
Masks a websocket message. Uses simd when possible.

### Signature

```zig
pub fn maskMessage(message: []u8, mask: [4]u8) void
```

## WriteHeaderFrame
Generates the websocket header frame based on the message len and the opcode provided.

 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               |Masking-key, if MASK set to 1  |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+

### Signature

```zig
pub fn writeHeaderFrame(self: *WebsocketClient, message: []const u8, opcode: Opcodes) Stream.WriteError![4]u8
```

## WriteCloseFrame
Writes to the server a close frame with a provided `exit_code`.

For more details please see: https://www.rfc-editor.org/rfc/rfc6455#section-5.5.1

### Signature

```zig
pub fn writeCloseFrame(self: *WebsocketClient, exit_code: u16) Stream.WriteError!void
```

## WriteFrame
Writes a websocket frame directly to the socket.

The message is masked according to the websocket RFC.
More details here: https://www.rfc-editor.org/rfc/rfc6455#section-6.1

### Signature

```zig
pub fn writeFrame(self: *WebsocketClient, message: []u8, opcode: Opcodes) Stream.WriteError!void
```

## Handshake
Performs the websocket handshake and validates that it got a valid response.

More info here: https://www.rfc-editor.org/rfc/rfc6455#section-1.2

### Signature

```zig
pub fn handshake(self: *WebsocketClient, host: []const u8) (ReadHandshakeError || SendHandshakeError)!void
```

## ReadHandshake
Read the handshake message from the socket and asserts that we got a valid server response.

Places the amount of parsed bytes from the handshake to be discarded on the next socket read.

### Signature

```zig
pub fn readHandshake(self: *WebsocketClient, handshake_key: [24]u8) ReadHandshakeError!void
```

## SendHandshake
Send the handshake message to the server. Doesn't support url's higher than 4096 bits.

Also writes the query of the path if the `uri` was able to parse it.

### Signature

```zig
pub fn sendHandshake(self: *WebsocketClient, host: []const u8, key: [24]u8) SendHandshakeError!void
```

## ParseHandshakeResponse
Validates that the handshake response is valid and returns the amount of bytes read.

The return bytes are then used to discard in case where we read more than handshake from the stream.

### Signature

```zig
pub fn parseHandshakeResponse(key: [24]u8, response: []const u8) AssertionError!usize
```

## ReadFromSocket
Read data directly from the socket and return that data.

Returns end of stream if the amount requested is higher than the
amount of bytes that were actually read.

### Signature

```zig
pub fn readFromSocket(self: *WebsocketClient, size: usize) SocketReadError![]const u8
```

## ReadMessage
Reads a websocket frame from the socket and decodes it based on
the frames headers.

This will fail if the server sends masked data as per the RFC the server
must always send unmasked data.

More info here: https://www.rfc-editor.org/rfc/rfc6455#section-6.2

### Signature

```zig
pub fn readMessage(self: *WebsocketClient) ReadMessageError!WebsocketMessage
```

