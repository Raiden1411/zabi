const std = @import("std");

const Allocator = std.mem.Allocator;
const EnvMap = std.process.EnvMap;

/// Token structure produced my the tokenizer.
pub const Token = struct {
    token: Tag,
    location: Location,

    pub const Location = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        identifier,
        value,
        value_int,
        eof,
        invalid,
    };
};

/// Index used to know token starts and ends.
pub const Offset = u32;
/// Index used to know token tags.
pub const TokenIndex = u32;

/// MultiArrayList used to generate the neccessary information for the parser to use.
pub const TokenList = std.MultiArrayList(struct {
    tag: Token.Tag,
    start: Offset,
    end: Offset,
});

/// Tokenizer that will produce lexicar tokens so that the
/// parser can consume and load it to the `EnvMap`.
pub const Tokenizer = struct {
    /// The source that will be used to produce tokens.
    buffer: [:0]const u8,
    /// Current index into the source
    index: usize,

    /// Possible states that the tokenizer might be in.
    const State = enum {
        assignment,
        identifier,
        invalid,
        start,
        value,
        value_int,
    };

    /// Sets the initial state.
    pub fn init(source: [:0]const u8) Tokenizer {
        return .{
            .buffer = source,
            .index = 0,
        };
    }
    /// Advances the tokenizer's state and produces a single token.
    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result: Token = .{ .token = undefined, .location = .{
            .start = self.index,
            .end = undefined,
        } };

        while (true) : (self.index += 1) {
            const char = self.buffer[self.index];
            switch (state) {
                .start => switch (char) {
                    0 => {
                        if (self.index == self.buffer.len)
                            return .{ .token = .eof, .location = .{
                                .start = self.index,
                                .end = self.index,
                            } };
                    },
                    ' ',
                    '\n',
                    '\t',
                    '\r',
                    '"',
                    => result.location.start += 1,
                    'a'...'z',
                    'A'...'Z',
                    '_',
                    => {
                        state = .identifier;
                        result.token = .identifier;
                    },
                    '=' => {
                        state = .assignment;
                        result.location.start += 1;
                    },
                    else => state = .invalid,
                },
                .invalid => switch (char) {
                    0 => if (self.index == self.buffer.len) {
                        result.token = .invalid;
                        break;
                    },
                    '\n' => {
                        result.token = .invalid;
                        break;
                    },
                    else => continue,
                },
                .identifier => switch (char) {
                    'a'...'z',
                    'A'...'Z',
                    '_',
                    '0'...'9',
                    => continue,
                    else => break,
                },
                .assignment => switch (char) {
                    0 => {
                        if (self.index == self.buffer.len)
                            return .{ .token = .invalid, .location = .{
                                .start = self.index,
                                .end = self.index,
                            } };
                    },
                    '\'',
                    '"',
                    ' ',
                    => result.location.start += 1,
                    '\n',
                    '\r',
                    '\t',
                    => {
                        result.token = .invalid;
                        state = .invalid;
                    },
                    '0'...'9' => {
                        result.token = .value_int;
                        state = .value_int;
                    },
                    else => {
                        result.token = .value;
                        state = .value;
                    },
                },
                .value_int => switch (char) {
                    '0'...'9' => continue,
                    else => break,
                },
                .value => switch (char) {
                    0,
                    '\'',
                    '"',
                    => break,
                    '\n',
                    '\r',
                    '\t',
                    ' ',
                    => {
                        result.token = .invalid;
                        state = .invalid;
                    },
                    else => if (std.ascii.isAscii(char)) continue else break,
                },
            }
        }

        result.location.end = self.index;

        return result;
    }
};

/// Parses the enviroment variables strings and loads them
/// into a `EnvMap`.
pub const ParserEnv = struct {
    /// Slice of produced token tags from the tokenizer.
    token_tags: []const Token.Tag,
    /// Slice of produced start indexes the tokenizer.
    starts: []const Offset,
    /// Slice of produced end indexes from the tokenizer.
    ends: []const Offset,
    /// The current index in any of the previous slices.
    token_index: TokenIndex,
    /// The source that will be used to load values from.
    source: []const u8,
    /// The enviroment map that will be used to load the variables to.
    env_map: *EnvMap,

    /// Parses all token tags and loads the all into the `EnvMap`.
    pub fn parseAndLoad(self: *ParserEnv) !void {
        while (true) {
            if (self.token_tags[@intCast(self.token_index)] == .eof)
                return;

            try self.parseAndLoadOne();
        }
    }
    /// Parses a single line and load it to memory.
    /// IDENT -> VALUE/VALUE_INT
    pub fn parseAndLoadOne(self: *ParserEnv) (Allocator.Error || error{UnexpectedToken})!void {
        const identifier_index = try self.parseIdentifier();
        const value_index = try self.parseValue();

        const identifier = self.source[self.starts[@intCast(identifier_index)]..self.ends[@intCast(identifier_index)]];
        const value = self.source[self.starts[@intCast(value_index)]..self.ends[@intCast(value_index)]];

        try self.env_map.put(identifier, value);
    }
    /// Parses the identifier token.
    /// Returns and error if the current token is not a `identifier` one.
    pub fn parseIdentifier(self: *ParserEnv) error{UnexpectedToken}!TokenIndex {
        return if (self.consumeToken(.identifier)) |index| return index else error.UnexpectedToken;
    }
    /// Parses the value_int token.
    /// Returns null if the current token is not a `value_int` one.
    pub fn parseIntValue(self: *ParserEnv) ?TokenIndex {
        return if (self.consumeToken(.value_int)) |index| return index else null;
    }
    /// Parses the value or value_int token.
    /// Returns and error if the current token is not a `value` or `value_int` one.
    pub fn parseValue(self: *ParserEnv) error{UnexpectedToken}!TokenIndex {
        if (self.consumeToken(.value)) |index|
            return index;

        if (self.parseIntValue()) |index|
            return index;

        return error.UnexpectedToken;
    }
    /// Consumes a single token and returns null if the expected_token is not
    /// the same as the one consumed.
    fn consumeToken(self: *ParserEnv, expected_token: Token.Tag) ?TokenIndex {
        return if (self.token_tags[self.token_index] != expected_token) null else self.nextToken();
    }
    /// Like assert by it produces and error if not present.
    fn expectToken(self: *ParserEnv, index: TokenIndex, expected_token: Token.Tag) !void {
        if (self.token_tags[index] != expected_token)
            return error.UnexpectedToken;
    }
    /// Advances the index and returns the current one.
    fn nextToken(self: *ParserEnv) TokenIndex {
        const result = self.token_index;
        self.token_index += 1;

        return result;
    }
};

/// Parses and loads all possible enviroment variables from the
/// provided `source`.
///
/// Can error if the parser encounters unexpected token values.
pub fn parseToEnviromentVariables(
    allocator: Allocator,
    source: [:0]const u8,
    env_map: *EnvMap,
) (Allocator.Error || error{UnexpectedToken})!void {
    var tokens: TokenList = .{};
    defer tokens.deinit(allocator);

    var lexer = Tokenizer.init(source);

    while (true) {
        const token = lexer.next();
        try tokens.append(allocator, .{
            .tag = token.token,
            .start = @intCast(token.location.start),
            .end = @intCast(token.location.end),
        });

        if (token.token == .eof)
            break;
    }

    var parser: ParserEnv = .{
        .source = source,
        .env_map = env_map,
        .token_tags = tokens.items(.tag),
        .starts = tokens.items(.start),
        .ends = tokens.items(.end),
        .token_index = 0,
    };

    try parser.parseAndLoad();
}
