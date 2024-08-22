## IpcReader
Socket reader that is expected to be reading socket messages
that are json messages. Growth is linearly based on the provided `growth_rate`.\
Will only allocate more memory if required.\
Calling `deinit` will close the socket and clear the buffer.

## Init
Sets the initial reader state in order to perform any necessary actions.

## Deinit
Frees the buffer and closes the stream.

## Read
Reads the bytes directly from the socket. Will allocate more memory as needed.

## Grow
Grows the reader buffer based on the growth rate. Will use the `allocator` resize
method if available.

## JsonMessage
"Reads" a json message and moves the necessary position members in order
to have the necessary message.

## ReadMessage
Reads one message from the socket stream.\
Will only make the socket read request if the buffer is at max capacity.\
Will grow the buffer as needed.

## PrepareForRead
Prepares the reader for the next message.

## WriteMessage
Writes a message to the socket stream.

