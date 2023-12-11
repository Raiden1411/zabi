const std = @import("std");
const Abitype = @import("abi.zig").Abitype;

pub fn FromAbitypeToEnum(comptime T: Abitype) type {
    comptime {
        switch (T) {
            inline else => {
                const enumField: [1]std.builtin.Type.EnumField = [_]std.builtin.Type.EnumField{.{ .name = @tagName(T), .value = 0 }};
                return @Type(.{ .Enum = .{ .tag_type = std.math.IntFittingRange(0, 1), .fields = &enumField, .decls = &.{}, .is_exhaustive = true } });
            },
        }
    }
}

/// UnionParser used by `zls`. Usefull to use in `AbiItem`
/// https://github.com/zigtools/zls/blob/d1ad449a24ea77bacbeccd81d607fa0c11f87dd6/src/lsp.zig#L77
pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const json_value = try std.json.Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!T {
            inline for (std.meta.fields(T)) |field| {
                if (std.json.parseFromValueLeaky(field.type, allocator, source, options)) |result| {
                    return @unionInit(T, field.name, result);
                } else |_| {}
            }
            return error.UnexpectedToken;
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}
