const std = @import("std");
const testing = std.testing;

const assert = std.debug.assert;

/// Convert the struct fields into to a enum.
pub fn ConvertToEnum(comptime T: type) type {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var enum_fields: [info.@"struct".fields.len][]const u8 = undefined;
    var enum_values: [info.@"struct".fields.len]usize = undefined;

    for (&enum_fields, &enum_values, info.@"struct".fields, 0..) |*enum_field, *enum_value, struct_field, i| {
        enum_field.* = struct_field.name ++ "";
        enum_value.* = i;
    }

    return @Enum(usize, .exhaustive, &enum_fields, &enum_values);
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

    var enum_fields: [counter][]const u8 = undefined;
    var enum_values: [counter]usize = undefined;

    iter.reset();
    counter = 0;

    while (iter.next()) |tok| {
        inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, tok)) {
                enum_fields[counter] = field.name;
                enum_values[counter] = counter;
                counter += 1;
            }
        }
    }

    return @Enum(usize, .exhaustive, &enum_fields, &enum_values);
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

    const size = info_t.@"struct".fields.len + info_k.@"struct".fields.len;
    var counter: usize = 0;

    var fields_names: [size][]const u8 = undefined;
    var fields_types: [size]type = undefined;
    var fields_attr: [size]std.builtin.Type.StructField.Attributes = undefined;

    for (info_t.@"struct".fields) |field| {
        fields_names[counter] = field.name;
        fields_types[counter] = field.type;
        fields_attr[counter] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
        counter += 1;
    }

    for (info_k.@"struct".fields) |field| {
        fields_names[counter] = field.name;
        fields_types[counter] = field.type;
        fields_attr[counter] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
        counter += 1;
    }

    return @Struct(.auto, null, &fields_names, &fields_types, &fields_attr);
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
    var fields: [info_t.@"struct".fields.len + info_k.@"struct".fields.len]type = undefined;

    for (info_t.@"struct".fields) |field| {
        fields[counter] = field.type;
        counter += 1;
    }

    for (info_k.@"struct".fields) |field| {
        fields[counter] = field.type;
        counter += 1;
    }

    return @Tuple(&fields);
}

/// Convert a struct into a tuple type.
pub fn StructToTupleType(comptime T: type) type {
    const info = @typeInfo(T);

    if (info != .@"struct" and info.@"struct".is_tuple)
        @compileError("Expected non tuple struct type but found " ++ @typeName(T));

    var fields: [info.@"struct".fields.len]type = undefined;

    inline for (info.@"struct".fields, 0..) |field, i| {
        const field_info = @typeInfo(field.type);

        switch (field_info) {
            .@"struct" => {
                const Type = StructToTupleType(field.type);
                fields[i] = Type;
            },
            .array => |arr_info| {
                const arr_type_info = @typeInfo(arr_info.child);

                if (arr_type_info == .@"struct") {
                    const Type = StructToTupleType(arr_info.child);
                    fields[i] = [arr_info.len]Type;

                    continue;
                }

                fields[i] = field.type;
            },
            .pointer => |ptr_info| {
                const ptr_type_info = @typeInfo(ptr_info.child);

                if (ptr_type_info == .@"struct") {
                    const Type = StructToTupleType(ptr_info.child);
                    fields[i] = []const Type;

                    continue;
                }
                fields[i] = field.type;
            },
            else => fields[i] = field.type,
        }
    }

    return @Tuple(&fields);
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
    var fields_names: [size][]const u8 = undefined;
    var fields_types: [size]type = undefined;
    var fields_attr: [size]std.builtin.Type.StructField.Attributes = undefined;

    var counter: usize = 0;
    outer: inline for (info.@"struct".fields) |field| {
        for (keys) |key| {
            if (std.mem.eql(u8, key, field.name))
                continue :outer;
        }

        fields_names[counter] = field.name;
        fields_types[counter] = field.type;
        fields_attr[counter] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
        counter += 1;
    }

    return @Struct(.auto, null, &fields_names, &fields_types, &fields_attr);
}
