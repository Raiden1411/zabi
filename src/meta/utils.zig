const std = @import("std");
const testing = std.testing;

const assert = std.debug.assert;

/// Convert the struct fields into to a enum.
pub fn ConvertToEnum(comptime T: type) type {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var enum_fields: [info.@"struct".fields.len]std.builtin.Type.EnumField = undefined;

    var count = 0;
    for (&enum_fields, info.@"struct".fields) |*enum_field, struct_field| {
        enum_field.* = .{
            .name = struct_field.name ++ "",
            .value = count,
        };
        count += 1;
    }

    return @Type(.{
        .@"enum" = .{
            .tag_type = usize,
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}
/// Type function use to extract enum members from any enum.
///
/// The needle can be just the tagName of a single member or a comma seperated value.
///
/// Compilation will fail if a invalid needle is provided.
pub fn Extract(
    comptime T: type,
    comptime needle: []const u8,
) type {
    if (std.meta.activeTag(@typeInfo(T)) != .@"enum")
        @compileError("Only supported for enum types");

    const info = @typeInfo(T).@"enum";
    var counter: usize = 0;

    var iter = std.mem.tokenizeScalar(u8, needle, ',');

    while (iter.next()) |tok| {
        inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, tok)) counter += 1;
        }
    }

    if (counter == 0)
        @compileError("Provided needle does not contain valid tagNames");

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

    return @Type(.{
        .@"enum" = .{
            .tag_type = info.tag_type,
            .fields = &enumFields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}
/// Merge structs into a single one
pub fn MergeStructs(
    comptime T: type,
    comptime K: type,
) type {
    const info_t = @typeInfo(T);
    const info_k = @typeInfo(K);

    if (info_t != .@"struct" or info_k != .@"struct")
        @compileError("Expected struct type");

    if (info_t.@"struct".is_tuple or info_k.@"struct".is_tuple)
        @compileError("Use `MergeTupleStructs` instead");

    var counter: usize = 0;
    var fields: [info_t.@"struct".fields.len + info_k.@"struct".fields.len]std.builtin.Type.StructField = undefined;

    for (info_t.@"struct".fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    for (info_k.@"struct".fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
/// Merge tuple structs
pub fn MergeTupleStructs(
    comptime T: type,
    comptime K: type,
) type {
    const info_t = @typeInfo(T);
    const info_k = @typeInfo(K);

    if (info_t != .@"struct" or info_k != .@"struct")
        @compileError("Expected struct type");

    if (!info_t.@"struct".is_tuple or !info_k.@"struct".is_tuple)
        @compileError("Use `MergeStructs` instead");

    var counter: usize = 0;
    var fields: [info_t.@"struct".fields.len + info_k.@"struct".fields.len]std.builtin.Type.StructField = undefined;

    for (info_t.@"struct".fields) |field| {
        fields[counter] = field;
        counter += 1;
    }

    for (info_k.@"struct".fields) |field| {
        fields[counter] = .{
            .name = std.fmt.comptimePrint("{d}", .{counter}),
            .type = field.type,
            .default_value_ptr = field.default_value_ptr,
            .alignment = field.alignment,
            .is_comptime = field.is_comptime,
        };
        counter += 1;
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}
/// Convert a struct into a tuple type.
pub fn StructToTupleType(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .@"struct" and info.@"struct".is_tuple)
        @compileError("Expected non tuple struct type but found " ++ @typeName(T));

    var fields: [info.@"struct".fields.len]std.builtin.Type.StructField = undefined;

    inline for (info.@"struct".fields, 0..) |field, i| {
        const field_info = @typeInfo(field.type);

        switch (field_info) {
            .@"struct" => {
                const Type = StructToTupleType(field.type);
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = Type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            },
            .array => |arr_info| {
                const arr_type_info = @typeInfo(arr_info.child);

                if (arr_type_info == .@"struct") {
                    const Type = StructToTupleType(arr_info.child);
                    fields[i] = .{
                        .name = std.fmt.comptimePrint("{d}", .{i}),
                        .type = [arr_info.len]Type,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = 0,
                    };

                    continue;
                }
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value_ptr = field.default_value_ptr,
                    .is_comptime = field.is_comptime,
                    .alignment = 0,
                };
            },
            .pointer => |ptr_info| {
                const ptr_type_info = @typeInfo(ptr_info.child);

                if (ptr_type_info == .@"struct") {
                    const Type = StructToTupleType(ptr_info.child);
                    fields[i] = .{
                        .name = std.fmt.comptimePrint("{d}", .{i}),
                        .type = []const Type,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = 0,
                    };

                    continue;
                }
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value_ptr = null,
                    .is_comptime = field.is_comptime,
                    .alignment = 0,
                };
            },
            else => {
                fields[i] = .{
                    .name = std.fmt.comptimePrint("{d}", .{i}),
                    .type = field.type,
                    .default_value_ptr = null,
                    .is_comptime = field.is_comptime,
                    .alignment = 0,
                };
            },
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}
/// Omits the selected keys from struct types.
pub fn Omit(
    comptime T: type,
    comptime keys: []const []const u8,
) type {
    const info = @typeInfo(T);

    if (info != .@"struct" and info.@"struct".is_tuple)
        @compileError("Expected non tuple struct type but found " ++ @typeName(T));

    if (keys.len >= info.@"struct".fields.len)
        @compileError("Key length exceeds struct field length");

    const size = info.@"struct".fields.len - keys.len;
    var fields: [size]std.builtin.Type.StructField = undefined;
    var fields_seen = [_]bool{false} ** size;

    var counter: usize = 0;
    outer: inline for (info.@"struct".fields) |field| {
        for (keys) |key| {
            if (std.mem.eql(u8, key, field.name))
                continue :outer;
        }

        fields[counter] = field;
        fields_seen[counter] = true;
        counter += 1;
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
