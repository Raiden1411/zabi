const std = @import("std");
const testing = std.testing;
const Token = std.json.Token;
const ParamType = @import("param_type.zig").ParamType;

pub const AbiParameter = struct {
    name: []const u8,
    type: ParamType,
    internal_type: ?[]const u8 = null,
    components: ?[]const AbiParameter = null,
};

pub const AbiEventParameter = struct {
    name: []const u8,
    type: ParamType,
    internal_type: ?[]const u8 = null,
    indexed: bool,
    components: ?[]const AbiParameter = null,
};

test "Json parse simple paramter" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "address"
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internal_type);
    try testing.expect(null == parsed.value.components);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.type);
    try testing.expectEqualStrings("foo", parsed.value.name);
}

test "Json parse simple event paramter" {
    const sliceIndexed =
        \\ {
        \\  "name": "foo",
        \\  "type": "address",
        \\  "indexed": true
        \\ }
    ;

    const parsedEvent = try std.json.parseFromSlice(AbiEventParameter, testing.allocator, sliceIndexed, .{});
    defer parsedEvent.deinit();

    try testing.expect(null == parsedEvent.value.internal_type);
    try testing.expect(null == parsedEvent.value.components);
    try testing.expect(parsedEvent.value.indexed);
    try testing.expectEqual(ParamType{ .address = {} }, parsedEvent.value.type);
    try testing.expectEqualStrings("foo", parsedEvent.value.name);
}

test "Json parse with components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internal_type);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
}

test "Json parse with multiple components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      },
        \\      {
        \\          "type": "int",
        \\          "name": "baz"
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internal_type);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqual(ParamType{ .int = 256 }, parsed.value.components.?[1].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
    try testing.expectEqualStrings("baz", parsed.value.components.?[1].name);
}

test "Json parse with nested components" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      },
        \\      {
        \\      "name": "foo",
        \\      "type": "tuple",
        \\      "components": [
        \\              {
        \\                  "type": "address",
        \\                  "name": "bar"
        \\              }
        \\          ]
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internal_type);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.components.?[1].type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[1].components.?[0].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
    try testing.expectEqualStrings("foo", parsed.value.components.?[1].name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[1].components.?[0].name);
}

test "Json parse error" {
    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "adress"
        \\ }
    ;

    try testing.expectError(error.InvalidEnumTag, std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{}));

    const sslice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple[]",
        \\  "components": [
        \\       {
        \\          "type": "address",
        \\          "name": "bar",
        \\          "indexed": false
        \\       }
        \\   ]
        \\ }
    ;

    try testing.expectError(error.UnknownField, std.json.parseFromSlice(AbiParameter, testing.allocator, sslice, .{}));
}
