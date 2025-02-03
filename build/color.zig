const std = @import("std");

/// Minimal set of ansi color codes.
pub const AnsiColorCodes = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    reset,
    bold,
    dim,
    italic,
    underline,
    strikethrough,

    /// Grabs the ansi escaped codes from the currently active one.
    pub fn toSlice(color: AnsiColorCodes) []const u8 {
        const color_string = switch (color) {
            .black => "\x1b[30m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .bright_black => "\x1b[90m",
            .bright_red => "\x1b[91m",
            .bright_green => "\x1b[92m",
            .bright_yellow => "\x1b[93m",
            .bright_blue => "\x1b[94m",
            .bright_magenta => "\x1b[95m",
            .bright_cyan => "\x1b[96m",
            .bright_white => "\x1b[97m",
            .reset => "\x1b[0m",
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .italic => "\x1b[3m",
            .underline => "\x1b[4m",
            .strikethrough => "\x1b[9m",
        };

        return color_string;
    }
};

/// Custom writer that we use to write tests result and with specific tty colors.
pub fn ColorWriter(comptime UnderlayingWriter: type) type {
    return struct {
        /// Set of possible errors from this writer.
        pub const Error = UnderlayingWriter.Error;

        const Writer = std.io.Writer(*Self, Error, write);
        const Self = @This();

        /// The writer that we will use to write to.
        underlaying_writer: UnderlayingWriter,
        /// Next tty color to apply in the stream.
        color: AnsiColorCodes,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
        /// Write function that will write to the stream with the `next_color`.
        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyColor();
            try self.writeNoColor(bytes);
            try self.applyReset();

            return bytes.len;
        }
        /// Sets the next color in the stream
        pub fn setNextColor(self: *Self, next: AnsiColorCodes) void {
            self.color = next;
        }
        /// Writes the next color to the stream.
        pub fn applyColor(self: *Self) Error!void {
            try self.underlaying_writer.writeAll(self.color.toSlice());
        }
        /// Writes the reset ansi to the stream
        pub fn applyReset(self: *Self) Error!void {
            try self.underlaying_writer.writeAll(AnsiColorCodes.toSlice(.reset));
        }
        /// Writes to the stream without colors.
        pub fn writeNoColor(self: *Self, bytes: []const u8) UnderlayingWriter.Error!void {
            if (bytes.len == 0)
                return;

            try self.underlaying_writer.writeAll(bytes);
        }
    };
}
