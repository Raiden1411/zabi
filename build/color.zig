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
pub const ColorWriter = struct {
    /// Set of possible errors from this writer.
    pub const Error = std.Io.Writer.Error;

    const Self = @This();

    /// The writer that we will use to write to.
    underlaying_writer: *std.Io.Writer,
    /// Next tty color to apply in the stream.
    color: AnsiColorCodes,
    /// The writer impl for this stream
    writer: std.Io.Writer,

    pub fn init(out: *std.Io.Writer, buffer: []u8) @This() {
        return .initColorWriter(out, .reset, buffer);
    }

    pub fn initColorWriter(out: *std.Io.Writer, color: AnsiColorCodes, buffer: []u8) @This() {
        return .{
            .underlaying_writer = out,
            .color = color,
            .writer = .{
                .buffer = buffer,
                .vtable = &.{ .drain = @This().drain },
            },
        };
    }

    pub fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) Error!usize {
        const this: *@This() = @alignCast(@fieldParentPtr("writer", writer));
        const aux = writer.buffered();

        try this.underlaying_writer.writeAll(this.color.toSlice());
        const written = try this.underlaying_writer.writeSplatHeader(aux, data, splat);
        try this.underlaying_writer.writeAll(AnsiColorCodes.toSlice(.reset));

        const n = written - writer.end;
        writer.end = 0;

        return n;
    }

    /// Sets the next color in the stream
    pub fn setNextColor(self: *Self, next: AnsiColorCodes) void {
        self.color = next;
    }
};
