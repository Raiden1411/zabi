const std = @import("std");

/// Solidity token structure.
pub const Token = struct {
    /// Solidity token tag.
    tag: Tag,
    /// Location in the source code.
    location: Location,

    /// Location of the token in the source code.
    pub const Location = struct {
        start: usize,
        end: usize,
    };

    /// All possible solidity token tags.
    pub const Tag = enum {
        identifier,
        number_literal,
        invalid,
        eof,
        l_paren,
        r_paren,
        l_bracket,
        r_bracket,
        l_brace,
        r_brace,
        semicolon,
        colon,
        colon_equal,
        period,
        arrow,
        tilde,
        equal,
        equal_equal,
        equal_bracket_right,
        bang,
        bang_equal,
        pipe,
        pipe_equal,
        pipe_pipe,
        percent,
        percent_equal,
        caret,
        caret_equal,
        plus,
        plus_plus,
        plus_equal,
        minus,
        minus_minus,
        minus_equal,
        ampersand,
        ampersand_ampersand,
        ampersand_equal,
        slash,
        slash_equal,
        asterisk,
        asterisk_asterisk,
        asterisk_equal,
        angle_bracket_left,
        angle_bracket_left_equal,
        angle_bracket_left_angle_bracket_left,
        angle_bracket_left_angle_bracket_left_equal,
        angle_bracket_right,
        angle_bracket_right_equal,
        angle_bracket_right_angle_bracket_right,
        angle_bracket_right_angle_bracket_right_equal,
        angle_bracket_right_angle_bracket_right_angle_bracket_right,
        angle_bracket_right_angle_bracket_right_angle_bracket_right_equal,
        question_mark,
        doc_comment,
        doc_comment_container,
        comma,
        string_literal,

        // Keywords
        keyword_abstract,
        keyword_anonymous,
        keyword_as,
        keyword_assembly,
        keyword_break,
        keyword_catch,
        keyword_constant,
        keyword_constructor,
        keyword_continue,
        keyword_contract,
        keyword_do,
        keyword_delete,
        keyword_else,
        keyword_enum,
        keyword_emit,
        keyword_event,
        keyword_external,
        keyword_fallback,
        keyword_for,
        keyword_function,
        keyword_hex,
        keyword_if,
        keyword_indexed,
        keyword_interface,
        keyword_internal,
        keyword_immutable,
        keyword_import,
        keyword_is,
        keyword_library,
        keyword_mapping,
        keyword_memory,
        keyword_modifier,
        keyword_new,
        keyword_override,
        keyword_payable,
        keyword_public,
        keyword_pragma,
        keyword_private,
        keyword_pure,
        keyword_receive,
        keyword_return,
        keyword_returns,
        keyword_storage,
        keyword_calldata,
        keyword_struct,
        keyword_throw,
        keyword_try,
        keyword_type,
        keyword_unchecked,
        keyword_unicode,
        keyword_using,
        keyword_view,
        keyword_virtual,
        keyword_while,

        /// Unit keywords.
        keyword_wei,
        keyword_gwei,
        keyword_ether,
        keyword_seconds,
        keyword_minutes,
        keyword_hours,
        keyword_days,
        keyword_weeks,
        keyword_years,

        // Reserved keywords
        reserved_after,
        reserved_alias,
        reserved_apply,
        reserved_auto,
        reserved_byte,
        reserved_case,
        reserved_copyof,
        reserved_default,
        reserved_define,
        reserved_final,
        reserved_implements,
        reserved_in,
        reserved_inline,
        reserved_let,
        reserved_macro,
        reserved_match,
        reserved_mutable,
        reserved_null,
        reserved_of,
        reserved_partial,
        reserved_promise,
        reserved_reference,
        reserved_relocatable,
        reserved_sealed,
        reserved_sizeof,
        reserved_static,
        reserved_supports,
        reserved_switch,
        reserved_typedef,
        reserved_typeof,
        reserved_var,
    };

    /// All possibled keyword/reserved words in solidity.
    pub const keyword = std.StaticStringMap(Tag).initComptime(.{
        .{ "abstract", .keyword_abstract },
        .{ "anonymous", .keyword_anonymous },
        .{ "as", .keyword_as },
        .{ "assembly", .keyword_assembly },
        .{ "break", .keyword_break },
        .{ "catch", .keyword_catch },
        .{ "constant", .keyword_constant },
        .{ "constructor", .keyword_constructor },
        .{ "continue", .keyword_continue },
        .{ "contract", .keyword_contract },
        .{ "do", .keyword_do },
        .{ "delete", .keyword_delete },
        .{ "else", .keyword_else },
        .{ "enum", .keyword_enum },
        .{ "emit", .keyword_emit },
        .{ "event", .keyword_event },
        .{ "external", .keyword_external },
        .{ "fallback", .keyword_fallback },
        .{ "for", .keyword_for },
        .{ "function", .keyword_function },
        .{ "hex", .keyword_hex },
        .{ "if", .keyword_if },
        .{ "indexed", .keyword_indexed },
        .{ "interface", .keyword_interface },
        .{ "internal", .keyword_internal },
        .{ "immutable", .keyword_immutable },
        .{ "import", .keyword_import },
        .{ "is", .keyword_is },
        .{ "library", .keyword_library },
        .{ "mapping", .keyword_mapping },
        .{ "memory", .keyword_memory },
        .{ "modifier", .keyword_modifier },
        .{ "new", .keyword_new },
        .{ "override", .keyword_override },
        .{ "payable", .keyword_payable },
        .{ "public", .keyword_public },
        .{ "pragma", .keyword_pragma },
        .{ "private", .keyword_private },
        .{ "pure", .keyword_pure },
        .{ "receive", .keyword_receive },
        .{ "return", .keyword_return },
        .{ "returns", .keyword_returns },
        .{ "storage", .keyword_storage },
        .{ "calldata", .keyword_calldata },
        .{ "struct", .keyword_struct },
        .{ "throw", .keyword_throw },
        .{ "try", .keyword_try },
        .{ "type", .keyword_type },
        .{ "unchecked", .keyword_unchecked },
        .{ "unicode", .keyword_unicode },
        .{ "using", .keyword_using },
        .{ "view", .keyword_view },
        .{ "virtual", .keyword_virtual },
        .{ "while", .keyword_while },

        // Unit keywords.
        .{ "wei", .keyword_wei },
        .{ "gwei", .keyword_gwei },
        .{ "ether", .keyword_ether },
        .{ "seconds", .keyword_seconds },
        .{ "minutes", .keyword_minutes },
        .{ "hours", .keyword_hours },
        .{ "days", .keyword_days },
        .{ "weeks", .keyword_weeks },
        .{ "years", .keyword_years },

        // Reserved keywords.
        .{ "after", .reserved_after },
        .{ "alias", .reserved_alias },
        .{ "apply", .reserved_apply },
        .{ "auto", .reserved_auto },
        .{ "byte", .reserved_byte },
        .{ "case", .reserved_case },
        .{ "copyof", .reserved_copyof },
        .{ "default", .reserved_default },
        .{ "define", .reserved_define },
        .{ "final", .reserved_final },
        .{ "implements", .reserved_implements },
        .{ "in", .reserved_in },
        .{ "inline", .reserved_inline },
        .{ "let", .reserved_let },
        .{ "macro", .reserved_macro },
        .{ "match", .reserved_match },
        .{ "mutable", .reserved_mutable },
        .{ "null", .reserved_null },
        .{ "of", .reserved_of },
        .{ "partial", .reserved_partial },
        .{ "promise", .reserved_promise },
        .{ "reference", .reserved_reference },
        .{ "relocatable", .reserved_relocatable },
        .{ "sealed", .reserved_sealed },
        .{ "sizeof", .reserved_sizeof },
        .{ "static", .reserved_static },
        .{ "supports", .reserved_supports },
        .{ "switch", .reserved_switch },
        .{ "typedef", .reserved_typedef },
        .{ "typeof", .reserved_typeof },
        .{ "var", .reserved_var },
    });
};

/// Produces solidity tokens from the provided sentinel buffer.
///
/// This should never error even in case of incorrect tokens.
/// Instead it produces invalid tag tokens.
pub const Tokenizer = struct {
    /// Source to parse.
    buffer: [:0]const u8,
    /// Current position on the source.
    index: usize,

    /// Sets the initial state of the tokenizer.
    pub fn init(source: [:0]const u8) Tokenizer {
        // UTF-8 BOM
        const index: usize = if (std.mem.startsWith(u8, source, "\xEF\xBB\xBF")) 3 else 0;

        return .{
            .buffer = source,
            .index = index,
        };
    }

    /// Tokenizer's parsing state.
    const State = enum {
        start,
        identifier,
        invalid,
        expect_newline,
        plus,
        asterisk,
        equal,
        minus,
        bang,
        caret,
        slash,
        colon,
        ampersand,
        doc_comment_container_start,
        doc_comment_container,
        doc_comment_start,
        doc_comment,
        line_comment_start,
        line_comment,
        pipe,
        percent,
        angle_bracket_left,
        angle_bracket_left_angle_bracket_left,
        angle_bracket_right,
        angle_bracket_right_angle_bracket_right,
        angle_bracket_right_angle_bracket_right_angle_bracket_right,
        int,
        int_exponent,
        int_hex,
        int_period,
        float,
        string_literal,
    };

    /// Advances the tokenizer and produces a token.
    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .tag = undefined,
            .location = .{
                .start = self.index,
                .end = undefined,
            },
        };

        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    if (self.index == self.buffer.len)
                        return .{ .tag = .eof, .location = .{
                            .start = self.index,
                            .end = self.index,
                        } }
                    else
                        continue :state .invalid;
                },
                ' ', '\n', '\r', '\t' => {
                    result.location.start += 1;
                    self.index += 1;
                    continue :state .start;
                },
                '"' => {
                    result.tag = .string_literal;
                    continue :state .string_literal;
                },
                'a'...'z', 'A'...'Z', '_', '$' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    self.index += 1;
                    continue :state .int;
                },
                '=' => continue :state .equal,
                '*' => continue :state .asterisk,
                '/' => continue :state .slash,
                '-' => continue :state .minus,
                '+' => continue :state .plus,
                '&' => continue :state .ampersand,
                '|' => continue :state .pipe,
                '!' => continue :state .bang,
                '%' => continue :state .percent,
                '^' => continue :state .caret,
                '<' => continue :state .angle_bracket_left,
                '>' => continue :state .angle_bracket_right,
                ':' => continue :state .colon,
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                },
                '[' => {
                    result.tag = .l_bracket;
                    self.index += 1;
                },
                ']' => {
                    result.tag = .r_bracket;
                    self.index += 1;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },
                ',' => {
                    result.tag = .comma;
                    self.index += 1;
                },
                '?' => {
                    result.tag = .question_mark;
                    self.index += 1;
                },
                '.' => {
                    result.tag = .period;
                    self.index += 1;
                },
                '~' => {
                    result.tag = .tilde;
                    self.index += 1;
                },
                else => continue :state .invalid,
            },
            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },
            .colon => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .colon_equal;
                        self.index += 1;
                    },
                    else => result.tag = .colon,
                }
            },
            .ampersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .ampersand_equal;
                        self.index += 1;
                    },
                    '&' => {
                        result.tag = .ampersand_ampersand;
                        self.index += 1;
                    },
                    else => result.tag = .ampersand,
                }
            },
            .asterisk => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .asterisk_equal;
                        self.index += 1;
                    },
                    '/' => {
                        result.tag = .doc_comment;
                        continue :state .doc_comment;
                    },
                    '*' => {
                        result.tag = .asterisk_asterisk;
                        self.index += 1;
                    },
                    else => result.tag = .asterisk,
                }
            },
            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .bang_equal;
                        self.index += 1;
                    },
                    else => result.tag = .bang,
                }
            },
            .caret => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .caret_equal;
                        self.index += 1;
                    },
                    else => result.tag = .caret,
                }
            },
            .percent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .percent_equal;
                        self.index += 1;
                    },
                    else => result.tag = .percent,
                }
            },
            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '|' => {
                        result.tag = .pipe_pipe;
                        self.index += 1;
                    },
                    '=' => {
                        result.tag = .pipe_equal;
                        self.index += 1;
                    },
                    else => result.tag = .pipe,
                }
            },
            .minus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-' => {
                        result.tag = .minus_minus;
                        self.index += 1;
                    },
                    '=' => {
                        result.tag = .minus_equal;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .arrow;
                        self.index += 1;
                    },
                    else => result.tag = .minus,
                }
            },
            .plus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '+' => {
                        result.tag = .plus_plus;
                        self.index += 1;
                    },
                    '=' => {
                        result.tag = .plus_equal;
                        self.index += 1;
                    },
                    else => result.tag = .plus,
                }
            },
            .slash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .slash_equal;
                        self.index += 1;
                    },
                    '/' => continue :state .line_comment_start,
                    '*' => continue :state .doc_comment_container_start,
                    else => result.tag = .slash,
                }
            },
            .line_comment_start => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '\r' => continue :state .expect_newline,
                    '\n' => {
                        result.location.start = self.index + 1;
                        continue :state .start;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    '/' => continue :state .doc_comment_start,
                    else => continue :state .line_comment,
                }
            },
            .line_comment => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len)
                            continue :state .invalid;

                        return .{
                            .tag = .eof,
                            .location = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    },
                    '\r' => continue :state .expect_newline,
                    '\n' => {
                        result.location.start = self.index + 1;
                        continue :state .start;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .line_comment,
                }
            },
            .doc_comment_container_start => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => result.tag = .doc_comment_container,
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    else => {
                        result.tag = .doc_comment_container;
                        continue :state .doc_comment_container;
                    },
                }
            },
            .doc_comment_start => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => result.tag = .doc_comment,
                    '\r' => {
                        if (self.buffer[self.index + 1] == '\n') {
                            result.tag = .doc_comment;
                        } else {
                            continue :state .invalid;
                        }
                    },
                    '/' => continue :state .line_comment,
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => {
                        result.tag = .doc_comment;
                        continue :state .doc_comment;
                    },
                }
            },
            .doc_comment_container => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => result.tag = .doc_comment_container,
                    '*' => {
                        if (self.buffer[self.index + 1] == '/') {
                            self.index += 2;
                        } else continue :state .doc_comment_container;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .doc_comment_container,
                }
            },
            .doc_comment => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0, '\n' => {},
                    '\r' => if (self.buffer[self.index + 1] != '\n') {
                        continue :state .invalid;
                    },
                    0x01...0x09, 0x0b...0x0c, 0x0e...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .doc_comment,
                }
            },
            .equal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .equal_equal;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .equal_bracket_right;
                        self.index += 1;
                    },
                    else => result.tag = .equal,
                }
            },
            .string_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len)
                            continue :state .invalid;

                        result.tag = .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    '"' => self.index += 1,
                    0x01...0x09, 0x0b...0x1f, 0x7f => continue :state .invalid,
                    else => continue :state .string_literal,
                }
            },
            .expect_newline => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index == self.buffer.len)
                            result.tag = .invalid;

                        continue :state .invalid;
                    },
                    '\n' => {
                        result.location.start = self.index + 1;
                        continue :state .start;
                    },
                    else => continue :state .invalid,
                }
            },
            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_', '$' => continue :state .identifier,
                    else => {
                        if (Token.keyword.get(self.buffer[result.location.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },
            .angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '<' => continue :state .angle_bracket_left_angle_bracket_left,
                    '=' => {
                        result.tag = .angle_bracket_left_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_left,
                }
            },
            .angle_bracket_left_angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_left_angle_bracket_left_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_left_angle_bracket_left,
                }
            },
            .angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '>' => continue :state .angle_bracket_right_angle_bracket_right,
                    '=' => {
                        result.tag = .angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_right,
                }
            },
            .angle_bracket_right_angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '>' => continue :state .angle_bracket_right_angle_bracket_right_angle_bracket_right,
                    '=' => {
                        result.tag = .angle_bracket_right_angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_right_angle_bracket_right,
                }
            },
            .angle_bracket_right_angle_bracket_right_angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_right_angle_bracket_right_angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_right_angle_bracket_right_angle_bracket_right,
                }
            },
            .int => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'e', 'E' => continue :state .int_exponent,
                    'x' => continue :state .int_hex,
                    '0'...'9' => continue :state .int,
                    '.' => continue :state .int_period,
                    else => {},
                }
            },
            .int_period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => continue :state .float,
                    else => self.index -= 1,
                }
            },
            .int_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => continue :state .int_exponent,
                    else => {},
                }
            },
            .int_hex => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'f', 'A'...'F', '0'...'9' => continue :state .int_hex,
                    else => {},
                }
            },
            .float => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => continue :state .float,
                    else => {},
                }
            },
        }

        result.location.end = self.index;

        return result;
    }
};
