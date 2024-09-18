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
        keyword_solidity,
        keyword_error,
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

        // Elementary type keywords.
        keyword_address,
        keyword_bool,
        keyword_tuple,
        keyword_string,
        keyword_bytes,
        keyword_bytes1,
        keyword_bytes2,
        keyword_bytes3,
        keyword_bytes4,
        keyword_bytes5,
        keyword_bytes6,
        keyword_bytes7,
        keyword_bytes8,
        keyword_bytes9,
        keyword_bytes10,
        keyword_bytes11,
        keyword_bytes12,
        keyword_bytes13,
        keyword_bytes14,
        keyword_bytes15,
        keyword_bytes16,
        keyword_bytes17,
        keyword_bytes18,
        keyword_bytes19,
        keyword_bytes20,
        keyword_bytes21,
        keyword_bytes22,
        keyword_bytes23,
        keyword_bytes24,
        keyword_bytes25,
        keyword_bytes26,
        keyword_bytes27,
        keyword_bytes28,
        keyword_bytes29,
        keyword_bytes30,
        keyword_bytes31,
        keyword_bytes32,
        keyword_uint,
        keyword_uint8,
        keyword_uint16,
        keyword_uint24,
        keyword_uint32,
        keyword_uint40,
        keyword_uint48,
        keyword_uint56,
        keyword_uint64,
        keyword_uint72,
        keyword_uint80,
        keyword_uint88,
        keyword_uint96,
        keyword_uint104,
        keyword_uint112,
        keyword_uint120,
        keyword_uint128,
        keyword_uint136,
        keyword_uint144,
        keyword_uint152,
        keyword_uint160,
        keyword_uint168,
        keyword_uint176,
        keyword_uint184,
        keyword_uint192,
        keyword_uint200,
        keyword_uint208,
        keyword_uint216,
        keyword_uint224,
        keyword_uint232,
        keyword_uint240,
        keyword_uint248,
        keyword_uint256,
        keyword_int,
        keyword_int8,
        keyword_int16,
        keyword_int24,
        keyword_int32,
        keyword_int40,
        keyword_int48,
        keyword_int56,
        keyword_int64,
        keyword_int72,
        keyword_int80,
        keyword_int88,
        keyword_int96,
        keyword_int104,
        keyword_int112,
        keyword_int120,
        keyword_int128,
        keyword_int136,
        keyword_int144,
        keyword_int152,
        keyword_int160,
        keyword_int168,
        keyword_int176,
        keyword_int184,
        keyword_int192,
        keyword_int200,
        keyword_int208,
        keyword_int216,
        keyword_int224,
        keyword_int232,
        keyword_int240,
        keyword_int248,
        keyword_int256,
    };

    /// All possibled keyword/reserved words in solidity.
    pub const keyword = std.StaticStringMap(Tag).initComptime(.{
        .{ "abstract", .keyword_abstract },        .{ "anonymous", .keyword_anonymous },     .{ "as", .keyword_as },
        .{ "assembly", .keyword_assembly },        .{ "break", .keyword_break },             .{ "catch", .keyword_catch },
        .{ "constant", .keyword_constant },        .{ "constructor", .keyword_constructor }, .{ "continue", .keyword_continue },
        .{ "contract", .keyword_contract },        .{ "do", .keyword_do },                   .{ "delete", .keyword_delete },
        .{ "else", .keyword_else },                .{ "enum", .keyword_enum },               .{ "emit", .keyword_emit },
        .{ "event", .keyword_event },              .{ "external", .keyword_external },       .{ "fallback", .keyword_fallback },
        .{ "for", .keyword_for },                  .{ "function", .keyword_function },       .{ "hex", .keyword_hex },
        .{ "if", .keyword_if },                    .{ "indexed", .keyword_indexed },         .{ "interface", .keyword_interface },
        .{ "internal", .keyword_internal },        .{ "immutable", .keyword_immutable },     .{ "import", .keyword_import },
        .{ "is", .keyword_is },                    .{ "library", .keyword_library },         .{ "mapping", .keyword_mapping },
        .{ "memory", .keyword_memory },            .{ "modifier", .keyword_modifier },       .{ "new", .keyword_new },
        .{ "override", .keyword_override },        .{ "payable", .keyword_payable },         .{ "public", .keyword_public },
        .{ "pragma", .keyword_pragma },            .{ "private", .keyword_private },         .{ "pure", .keyword_pure },
        .{ "receive", .keyword_receive },          .{ "return", .keyword_return },           .{ "returns", .keyword_returns },
        .{ "storage", .keyword_storage },          .{ "calldata", .keyword_calldata },       .{ "struct", .keyword_struct },
        .{ "throw", .keyword_throw },              .{ "try", .keyword_try },                 .{ "type", .keyword_type },
        .{ "unchecked", .keyword_unchecked },      .{ "unicode", .keyword_unicode },         .{ "using", .keyword_using },
        .{ "view", .keyword_view },                .{ "virtual", .keyword_virtual },         .{ "while", .keyword_while },
        .{ "solidity", .keyword_solidity },        .{ "error", .keyword_error },

        // Unit keywords.
                    .{ "wei", .keyword_wei },
        .{ "gwei", .keyword_gwei },                .{ "ether", .keyword_ether },             .{ "seconds", .keyword_seconds },
        .{ "minutes", .keyword_minutes },          .{ "hours", .keyword_hours },             .{ "days", .keyword_days },
        .{ "weeks", .keyword_weeks },              .{ "years", .keyword_years },

        // Reserved keywords.
                    .{ "after", .reserved_after },
        .{ "alias", .reserved_alias },             .{ "apply", .reserved_apply },            .{ "auto", .reserved_auto },
        .{ "byte", .reserved_byte },               .{ "case", .reserved_case },              .{ "copyof", .reserved_copyof },
        .{ "default", .reserved_default },         .{ "define", .reserved_define },          .{ "final", .reserved_final },
        .{ "implements", .reserved_implements },   .{ "in", .reserved_in },                  .{ "inline", .reserved_inline },
        .{ "let", .reserved_let },                 .{ "macro", .reserved_macro },            .{ "match", .reserved_match },
        .{ "mutable", .reserved_mutable },         .{ "null", .reserved_null },              .{ "of", .reserved_of },
        .{ "partial", .reserved_partial },         .{ "promise", .reserved_promise },        .{ "reference", .reserved_reference },
        .{ "relocatable", .reserved_relocatable }, .{ "sealed", .reserved_sealed },          .{ "sizeof", .reserved_sizeof },
        .{ "static", .reserved_static },           .{ "supports", .reserved_supports },      .{ "switch", .reserved_switch },
        .{ "typedef", .reserved_typedef },         .{ "typeof", .reserved_typeof },          .{ "var", .reserved_var },
    });

    /// Converts type string keywords into its enum representation.
    pub const typesKeywordMap = std.StaticStringMap(Tag).initComptime(.{
        .{ "address", .keyword_address }, .{ "bool", .keyword_bool },       .{ "string", .keyword_string },   .{ "bytes", .keyword_bytes },
        .{ "bytes1", .keyword_bytes1 },   .{ "bytes2", .keyword_bytes2 },   .{ "bytes3", .keyword_bytes3 },   .{ "bytes4", .keyword_bytes4 },
        .{ "bytes5", .keyword_bytes5 },   .{ "bytes6", .keyword_bytes6 },   .{ "bytes7", .keyword_bytes7 },   .{ "bytes8", .keyword_bytes8 },
        .{ "bytes9", .keyword_bytes9 },   .{ "bytes10", .keyword_bytes10 }, .{ "bytes11", .keyword_bytes11 }, .{ "bytes12", .keyword_bytes12 },
        .{ "bytes13", .keyword_bytes13 }, .{ "bytes14", .keyword_bytes14 }, .{ "bytes15", .keyword_bytes15 }, .{ "bytes16", .keyword_bytes16 },
        .{ "bytes17", .keyword_bytes17 }, .{ "bytes18", .keyword_bytes18 }, .{ "bytes19", .keyword_bytes19 }, .{ "bytes20", .keyword_bytes20 },
        .{ "bytes21", .keyword_bytes21 }, .{ "bytes22", .keyword_bytes22 }, .{ "bytes23", .keyword_bytes23 }, .{ "bytes24", .keyword_bytes24 },
        .{ "bytes25", .keyword_bytes25 }, .{ "bytes26", .keyword_bytes26 }, .{ "bytes27", .keyword_bytes27 }, .{ "bytes28", .keyword_bytes28 },
        .{ "bytes29", .keyword_bytes29 }, .{ "bytes30", .keyword_bytes30 }, .{ "bytes31", .keyword_bytes31 }, .{ "bytes32", .keyword_bytes32 },
        .{ "int", .keyword_int },         .{ "int8", .keyword_int8 },       .{ "int16", .keyword_int16 },     .{ "int24", .keyword_int24 },
        .{ "int32", .keyword_int32 },     .{ "int40", .keyword_int40 },     .{ "int48", .keyword_int48 },     .{ "int56", .keyword_int56 },
        .{ "int64", .keyword_int64 },     .{ "int72", .keyword_int72 },     .{ "int80", .keyword_int80 },     .{ "int88", .keyword_int88 },
        .{ "int96", .keyword_int96 },     .{ "int104", .keyword_int104 },   .{ "int112", .keyword_int112 },   .{ "int120", .keyword_int120 },
        .{ "int128", .keyword_int128 },   .{ "int136", .keyword_int136 },   .{ "int144", .keyword_int144 },   .{ "int152", .keyword_int152 },
        .{ "int160", .keyword_int160 },   .{ "int168", .keyword_int168 },   .{ "int176", .keyword_int176 },   .{ "int184", .keyword_int184 },
        .{ "int192", .keyword_int192 },   .{ "int200", .keyword_int200 },   .{ "int208", .keyword_int208 },   .{ "int216", .keyword_int216 },
        .{ "int224", .keyword_int224 },   .{ "int232", .keyword_int232 },   .{ "int240", .keyword_int240 },   .{ "int248", .keyword_int248 },
        .{ "int256", .keyword_int256 },   .{ "uint", .keyword_uint },       .{ "uint8", .keyword_uint8 },     .{ "uint16", .keyword_uint16 },
        .{ "uint24", .keyword_uint24 },   .{ "uint32", .keyword_uint32 },   .{ "uint40", .keyword_uint40 },   .{ "uint48", .keyword_uint48 },
        .{ "uint56", .keyword_uint56 },   .{ "uint64", .keyword_uint64 },   .{ "uint72", .keyword_uint72 },   .{ "uint80", .keyword_uint80 },
        .{ "uint88", .keyword_uint88 },   .{ "uint96", .keyword_uint96 },   .{ "uint104", .keyword_uint104 }, .{ "uint112", .keyword_uint112 },
        .{ "uint120", .keyword_uint120 }, .{ "uint128", .keyword_uint128 }, .{ "uint136", .keyword_uint136 }, .{ "uint144", .keyword_uint144 },
        .{ "uint152", .keyword_uint152 }, .{ "uint160", .keyword_uint160 }, .{ "uint168", .keyword_uint168 }, .{ "uint176", .keyword_uint176 },
        .{ "uint184", .keyword_uint184 }, .{ "uint192", .keyword_uint192 }, .{ "uint200", .keyword_uint200 }, .{ "uint208", .keyword_uint208 },
        .{ "uint216", .keyword_uint216 }, .{ "uint224", .keyword_uint224 }, .{ "uint232", .keyword_uint232 }, .{ "uint240", .keyword_uint240 },
        .{ "uint248", .keyword_uint248 }, .{ "uint256", .keyword_uint256 },
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
                        if (Token.keyword.get(self.buffer[result.location.start..self.index])) |tag|
                            result.tag = tag;

                        if (Token.typesKeywordMap.get(self.buffer[result.location.start..self.index])) |tag|
                            result.tag = tag;
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
            .int => switch (self.buffer[self.index]) {
                'e', 'E' => continue :state .int_exponent,
                'x' => continue :state .int_hex,
                '0'...'9', '_' => {
                    self.index += 1;
                    continue :state .int;
                },
                '.' => continue :state .int_period,
                else => {},
            },
            .int_period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9', '_' => continue :state .float,
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
                    'a'...'f', 'A'...'F', '0'...'9', '_' => continue :state .int_hex,
                    else => {},
                }
            },
            .float => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9', '_' => continue :state .float,
                    else => {},
                }
            },
        }

        result.location.end = self.index;

        return result;
    }
};
