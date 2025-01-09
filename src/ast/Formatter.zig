const ast = Ast.ast;
const std = @import("std");

const Ast = @import("Ast.zig");

/// Auto indentation  writer stream.
pub fn IndentingStream(comptime BaseWriter: type) type {
    return struct {
        const Self = @This();

        pub const WriterError = BaseWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriterError, write);

        /// The base writer for this wrapper
        base_writer: BaseWriter,
        /// Current amount of indentation to apply
        indentation_level: usize,
        /// Current amount of indentation to apply
        indentation_count: usize,

        /// Returns the writer with our writer function.
        pub fn writer(self: *Self) Writer {
            return .{
                .context = self,
            };
        }
        /// Write function that applies indentation and punctuation if necessary.
        pub fn write(
            self: *Self,
            bytes: []const u8,
        ) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyIndentation();
            return self.writeSimple(bytes);
        }
        /// Writes a new line into the stream and updates the level.
        pub fn writeNewline(self: *Self) WriterError!void {
            return self.writeSimple("\n");
        }
        /// Applies indentation if the current level * count is higher than 0.
        pub fn applyIndentation(self: *Self) WriterError!void {
            if (self.getCurrentIndentation() > 0)
                try self.base_writer.writeByteNTimes(' ', self.indentation_level);
        }
        /// Gets the current indentation level to apply. `indentation_level` * `indentation_count`
        pub fn getCurrentIndentation(self: *Self) usize {
            var current: usize = 0;
            if (self.indentation_count > 0)
                current = self.indentation_level * self.indentation_count;

            return current;
        }
        /// Pushes one level of indentation.
        pub fn pushIndentation(self: *Self) void {
            self.indentation_count += 1;
        }
        /// Pops one level of indentation.
        pub fn popIndentation(self: *Self) void {
            std.debug.assert(self.indentation_count > 0);
            self.indentation_count -= 1;
        }
        /// Writes to the base stream with no indentation and punctuation
        pub fn writeSimple(
            self: *Self,
            bytes: []const u8,
        ) WriterError!usize {
            if (bytes.len == 0)
                return bytes.len;

            if (bytes[bytes.len - 1] == '\n')
                self.indentation_level = 0;

            try self.base_writer.writeAll(bytes);

            return bytes.len;
        }
        /// Sets the indentation_level.
        pub fn setIndentation(self: *Self, indent: usize) void {
            if (self.indentation_level == indent)
                return;

            self.indentation_level = indent;
        }
    };
}

/// Solidity languange formatter.
///
/// It's opinionated and for now supports minimal set of configurations.
pub fn SolidityFormatter(
    comptime OutWriter: type,
    // comptime indent: comptime_int,
) type {
    return struct {
        /// Supported punctuation for this formatter.
        pub const Punctuation = enum {
            comma,
            comma_space,
            newline,
            none,
            semicolon,
            space,
            skip,
        };

        /// Set of errors when running the formatter.
        pub const Error = OutWriter.Error;

        const Formatter = @This();

        /// Auto indentation stream used to properly indent the code.
        stream: IndentingStream(OutWriter),
        /// Solidity Ast used as the base for formatting the source code.
        tree: Ast,

        /// Formats a single token.
        ///
        /// If the token is a `doc_comment*` it will trim the whitespace on the right.
        pub fn formatToken(
            self: *Formatter,
            token_index: Ast.TokenIndex,
            punctuation: Punctuation,
        ) Error!void {
            const slice = self.tokenSlice(token_index);

            try self
                .stream
                .writer()
                .writeAll(slice);

            return self.applyPunctuation(token_index, slice.len, punctuation);
        }
        /// Grabs the associated source code from a `token`
        ///
        /// If the token is a `doc_comment*` it will trim the whitespace on the right.
        pub fn tokenSlice(
            self: *Formatter,
            token_index: Ast.TokenIndex,
        ) []const u8 {
            var slice = self.tree.tokenSlice(token_index);

            switch (self.tree.tokens.items(.tag)[token_index]) {
                .doc_comment,
                .doc_comment_container,
                => slice = std.mem.trimRight(u8, slice, &std.ascii.whitespace),
                else => {},
            }

            return slice;
        }
    };
}
