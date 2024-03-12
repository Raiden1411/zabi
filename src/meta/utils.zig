const std = @import("std");
const testing = std.testing;

/// Type function use to extract enum members from any enum.
///
/// The needle can be just the tagName of a single member or a comma seperated value.
///
/// Compilation will fail if a invalid needle is provided.
pub fn Extract(comptime T: type, comptime needle: []const u8) type {
    if (std.meta.activeTag(@typeInfo(T)) != .Enum) @compileError("Only supported for enum types");

    const info = @typeInfo(T).Enum;
    var counter: usize = 0;

    var iter = std.mem.tokenizeSequence(u8, needle, ",");

    while (iter.next()) |tok| {
        inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, tok)) counter += 1;
        }
    }

    if (counter == 0) @compileError("Provided needle does not contain valid tagNames");

    var enumFields: [counter]std.builtin.Type.EnumField = undefined;

    iter.reset();
    counter = 0;

    while (iter.next()) |tok| {
        inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, tok)) {
                enumFields[counter] = field;
                counter += 1;
            }
        }
    }

    return @Type(.{ .Enum = .{ .tag_type = info.tag_type, .fields = &enumFields, .decls = &.{}, .is_exhaustive = true } });
}
/// Merge structs into a single one
pub fn MergeStructs(comptime T: type, comptime K: type) type {
    const info_t = @typeInfo(T);
    const info_k = @typeInfo(K);

    if (info_t != .Struct or info_k != .Struct)
        @compileError("Expected struct type");

    if (info_t.Struct.is_tuple or info_k.Struct.is_tuple)
        @compileError("Use `MergeTupleStructs` instead");

    var counter: usize = 0;
    var fields: [info_t.Struct.fields.len + info_k.Struct.fields.len]std.builtin.Type.StructField = undefined;

    for (info_t.Struct.fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    for (info_k.Struct.fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}
/// Merge tuple structs
pub fn MergeTupleStructs(comptime T: type, comptime K: type) type {
    const info_t = @typeInfo(T);
    const info_k = @typeInfo(K);

    if (info_t != .Struct or info_k != .Struct)
        @compileError("Expected struct type");

    if (!info_t.Struct.is_tuple or !info_k.Struct.is_tuple)
        @compileError("Use `MergeStructs` instead");

    var counter: usize = 0;
    var fields: [info_t.Struct.fields.len + info_k.Struct.fields.len]std.builtin.Type.StructField = undefined;

    for (info_t.Struct.fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    for (info_k.Struct.fields) |field| {
        fields[counter] = .{ .name = std.fmt.comptimePrint("{d}", .{counter}), .type = field.type, .default_value = field.default_value, .alignment = field.alignment, .is_comptime = field.is_comptime };
        counter += 1;
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
/// Convert a struct into a tuple type.
pub fn StructToTupleType(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .Struct and info.Struct.is_tuple)
        @compileError("Expected non tuple struct type but found " ++ @typeName(T));

    var fields: [info.Struct.fields.len]std.builtin.Type.StructField = undefined;

    inline for (info.Struct.fields, 0..) |field, i| {
        const field_info = @typeInfo(field.type);

        switch (field_info) {
            .Struct => {
                const Type = StructToTupleType(field.type);
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = Type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = if (@sizeOf(Type) > 0) @alignOf(Type) else 0,
                };
            },
            .Array => |arr_info| {
                const arr_type_info = @typeInfo(arr_info.child);

                if (arr_type_info == .Struct) {
                    const Type = StructToTupleType(arr_info.child);
                    fields[i] = .{
                        .name = std.fmt.comptimePrint("{d}", .{i}),
                        .type = [arr_info.len]Type,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = if (@sizeOf(Type) > 0) @alignOf(Type) else 0,
                    };

                    continue;
                }
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value = field.default_value,
                    .is_comptime = field.is_comptime,
                    .alignment = field.alignment,
                };
            },
            .Pointer => |ptr_info| {
                const ptr_type_info = @typeInfo(ptr_info.child);

                if (ptr_type_info == .Struct) {
                    const Type = StructToTupleType(ptr_info.child);
                    fields[i] = .{
                        .name = std.fmt.comptimePrint("{d}", .{i}),
                        .type = []const Type,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = if (@sizeOf(Type) > 0) @alignOf(Type) else 0,
                    };

                    continue;
                }
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value = field.default_value,
                    .is_comptime = field.is_comptime,
                    .alignment = field.alignment,
                };
            },
            else => {
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value = field.default_value,
                    .is_comptime = field.is_comptime,
                    .alignment = field.alignment,
                };
            },
        }
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
/// Omits the selected keys from struct types.
pub fn Omit(comptime T: type, comptime keys: []const []const u8) type {
    const info = @typeInfo(T);

    if (info != .Struct and info.Struct.is_tuple)
        @compileError("Expected non tuple struct type but found " ++ @typeName(T));

    if (keys.len >= info.Struct.fields.len)
        @compileError("Key length exceeds struct field length");

    const size = info.Struct.fields.len - keys.len;
    var fields: [size]std.builtin.Type.StructField = undefined;
    var fields_seen = [_]bool{false} ** size;

    var counter: usize = 0;
    outer: inline for (info.Struct.fields) |field| {
        for (keys) |key| {
            if (std.mem.eql(u8, key, field.name)) {
                continue :outer;
            }
        }
        fields[counter] = field;
        fields_seen[counter] = true;
        counter += 1;
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}

test "Meta" {
    try expectEqualStructs(struct { foo: u32, jazz: bool }, MergeStructs(struct { foo: u32 }, struct { jazz: bool }));
    try expectEqualStructs(struct { u32, bool }, MergeTupleStructs(struct { u32 }, struct { bool }));
    try expectEqualStructs(struct { foo: u32, jazz: bool }, Omit(struct { foo: u32, bar: u256, baz: i64, jazz: bool }, &.{ "bar", "baz" }));
    try expectEqualStructs(std.meta.Tuple(&[_]type{ u64, std.meta.Tuple(&[_]type{ u64, u256 }) }), StructToTupleType(struct { foo: u64, bar: struct { baz: u64, jazz: u256 } }));
}

fn expectEqualStructs(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).Struct;
    const actualInfo = @typeInfo(actual).Struct;

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);
    try testing.expectEqual(expectInfo.is_tuple, actualInfo.is_tuple);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .Struct) return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .Union) return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}

fn expectEqualUnions(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).Union;
    const actualInfo = @typeInfo(actual).Union;

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .Struct) return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .Union) return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}
