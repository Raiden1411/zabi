const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;

pub const StateMutability = union(enum) {
    nonPayable,
    payable,
    view,
    pure,

    pub fn jsonParse(alloc: Alloc, source: *Scanner, opts: ParseOptions) !StateMutability {
        const info = @typeInfo(StateMutability);

        const name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
        const field_name = switch (name_token.?) {
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        inline for (info.Union.fields) |union_field| {
            if (std.mem.eql(u8, union_field.name, field_name)) {
                return @unionInit(StateMutability, union_field.name, {});
            }
        }

        return error.InvalidEnumTag;
    }
};

test "Json parse" {
    const slice =
        \\ [
        \\  "nonPayable",
        \\  "payable",
        \\  "view",
        \\  "pure"
        \\ ]
    ;

    const parsed = try std.json.parseFromSlice([]StateMutability, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expectEqual(StateMutability{ .nonPayable = {} }, parsed.value[0]);
    try testing.expectEqual(StateMutability{ .payable = {} }, parsed.value[1]);
    try testing.expectEqual(StateMutability{ .view = {} }, parsed.value[2]);
    try testing.expectEqual(StateMutability{ .pure = {} }, parsed.value[3]);
}
