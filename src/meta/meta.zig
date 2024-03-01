const abi = @import("../abi/abi.zig");
const params = @import("../abi/abi_parameter.zig");
const std = @import("std");
const testing = std.testing;

// Types
const Abitype = abi.Abitype;
const AbiParameter = params.AbiParameter;
const Allocator = std.mem.Allocator;
const ParamType = @import("../abi/param_type.zig").ParamType;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Token = std.json.Token;
const Value = std.json.Value;

/// UnionParser used by `zls`. Usefull to use in `AbiItem`
/// https://github.com/zigtools/zls/blob/d1ad449a24ea77bacbeccd81d607fa0c11f87dd6/src/lsp.zig#L77
pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!T {
            const json_value = try Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!T {
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
/// Custom jsonParse that is mostly used to enable
/// the ability to parse hex string values into native `int` types,
/// since parsing hex values is not part of the JSON RFC we need to rely on
/// the hability of zig to create a custom jsonParse method for structs
pub fn RequestParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(alloc: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!T {
            const info = @typeInfo(T);
            if (.object_begin != try source.next()) return error.UnexpectedToken;

            var result: T = undefined;
            var fields_seen = [_]bool{false} ** info.Struct.fields.len;

            while (true) {
                var name_token: ?Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };

                inline for (info.Struct.fields, 0..) |field, i| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        name_token = null;
                        @field(result, field.name) = try innerParseRequest(field.type, alloc, source, opts);
                        fields_seen[i] = true;
                        break;
                    }
                } else {
                    if (opts.ignore_unknown_fields) {
                        try source.skipValue();
                    } else {
                        return error.UnknownField;
                    }
                }
            }

            inline for (info.Struct.fields, 0..) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default_value| {
                        const default = @as(*align(1) const field.type, @ptrCast(default_value)).*;
                        @field(result, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
            }

            return result;
        }

        pub fn jsonParseFromValue(alloc: Allocator, source: Value, opts: ParseOptions) ParseFromValueError!T {
            const info = @typeInfo(T);
            if (source != .object) return error.UnexpectedToken;

            var result: T = undefined;
            var fields_seen = [_]bool{false} ** info.Struct.fields.len;

            var iter = source.object.iterator();

            while (iter.next()) |token| {
                const field_name = token.key_ptr.*;

                inline for (info.Struct.fields, 0..) |field, i| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        @field(result, field.name) = try innerParseValueRequest(field.type, alloc, token.value_ptr.*, opts);
                        fields_seen[i] = true;
                        break;
                    }
                } else {
                    if (!opts.ignore_unknown_fields)
                        return error.UnknownField;
                }
            }

            inline for (info.Struct.fields, 0..) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default_value| {
                        const default = @as(*align(1) const field.type, @ptrCast(default_value)).*;
                        @field(result, field.name) = default;
                    } else {
                        return error.MissingField;
                    }
                }
            }

            return result;
        }

        fn innerParseValueRequest(comptime TT: type, alloc: Allocator, source: anytype, opts: ParseOptions) ParseFromValueError!TT {
            switch (@typeInfo(TT)) {
                .Bool => {
                    switch (source) {
                        .bool => |val| return val,
                        .string => |val| return try std.fmt.parseInt(u1, val, 0) != 0,
                        else => return error.UnexpectedToken,
                    }
                },
                .Float, .ComptimeFloat => {
                    switch (source) {
                        .float => |f| return @as(T, @floatCast(f)),
                        .integer => |i| return @as(T, @floatFromInt(i)),
                        .number_string, .string => |s| return std.fmt.parseFloat(T, s),
                        else => return error.UnexpectedToken,
                    }
                },
                .Int => {
                    switch (source) {
                        .number_string, .string => |str| return try std.fmt.parseInt(TT, str, 0),
                        else => return error.UnexpectedToken,
                    }
                },
                .Optional => |opt_info| {
                    switch (source) {
                        .null => return null,
                        else => return try innerParseValueRequest(opt_info.child, alloc, source, opts),
                    }
                },
                .Array => |arr_info| {
                    switch (source) {
                        .array => |arr| {
                            var result: TT = undefined;
                            for (arr.items, 0..) |item, i| {
                                result[i] = try innerParseValueRequest(arr_info.child, alloc, item, opts);
                            }

                            return result;
                        },
                        .string => |str| {
                            if (arr_info.child != u8)
                                return error.UnexpectedToken;

                            var result: TT = undefined;

                            const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str[0..];
                            if (std.fmt.hexToBytes(&result, slice)) |_| {
                                if (arr_info.len != slice.len / 2)
                                    return error.LengthMismatch;

                                return result;
                            } else |_| {
                                if (slice.len != result.len)
                                    return error.LengthMismatch;

                                @memcpy(result[0..], slice[0..]);
                            }
                            return result;
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .Pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .One => {
                            const result: *ptr_info.child = try alloc.create(ptr_info.child);
                            result.* = try innerParseRequest(ptr_info.child, alloc, source, opts);
                            return result;
                        },
                        .Slice => {
                            switch (source) {
                                .array => |array| {
                                    const arr = try alloc.alloc(ptr_info.child, array.items.len);
                                    for (array.items, arr) |item, *res| {
                                        res.* = try innerParseValueRequest(ptr_info.child, alloc, item, opts);
                                    }

                                    return arr;
                                },
                                .string => |str| {
                                    if (ptr_info.child != u8) return error.UnexpectedToken;

                                    const hex = if (std.mem.startsWith(u8, str, "0x")) str[2..] else str;
                                    const buf = try alloc.alloc(u8, if (@mod(str.len, 2) == 0) @divExact(str.len, 2) else str.len);
                                    if (std.fmt.hexToBytes(buf, hex)) |result| return result else |_| {
                                        defer alloc.free(buf);

                                        return str;
                                    }
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => @compileError("Unable to parse type " ++ @typeName(TT)),
                    }
                },
                .Struct => {
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(alloc, source, opts) else @compileError("Unable to parse structs without jsonParseFromValue custom declaration");
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParseFromValue")) return TT.jsonParseFromValue(alloc, source, opts) else @compileError("Unable to parse structs without jsonParseFromValue custom declaration");
                },

                else => @compileError("Unable to parse type " ++ @typeName(TT)),
            }
        }

        fn innerParseRequest(comptime TT: type, alloc: Allocator, source: anytype, opts: ParseOptions) ParseError(@TypeOf(source.*))!TT {
            const info = @typeInfo(TT);

            switch (info) {
                .Bool => {
                    return switch (try source.next()) {
                        .true => true,
                        .false => false,
                        .string => |slice| try std.fmt.parseInt(u1, slice, 0) != 0,
                        else => error.UnexpectedToken,
                    };
                },
                .Int => {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };

                    return try std.fmt.parseInt(TT, slice, 0);
                },
                .Float, .ComptimeFloat => {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };
                    return try std.fmt.parseFloat(TT, slice);
                },
                .Optional => |opt_info| {
                    switch (try source.peekNextTokenType()) {
                        .null => {
                            _ = try source.next();
                            return null;
                        },
                        else => return try innerParseRequest(opt_info.child, alloc, source, opts),
                    }
                },
                .Array => |arr_info| {
                    switch (try source.peekNextTokenType()) {
                        .array_begin => {
                            _ = try source.next();

                            var result: TT = undefined;

                            var index: usize = 0;
                            while (index < arr_info.len) : (index += 1) {
                                result[index] = try innerParseRequest(arr_info.child, alloc, source, opts);
                            }

                            if (.array_end != try source.next())
                                return error.UnexpectedToken;

                            return result;
                        },
                        .string => {
                            var result: TT = undefined;

                            switch (try source.next()) {
                                .string => |str| {
                                    const slice = if (std.mem.startsWith(u8, str, "0x")) str[2..] else return error.UnexpectedToken;
                                    if (std.fmt.hexToBytes(&result, slice)) |_| {
                                        return result;
                                    } else |_| {
                                        if (slice.len != result.len)
                                            return error.LengthMismatch;

                                        @memcpy(result[0..], slice[0..]);
                                    }
                                    return result;
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => return error.UnexpectedToken,
                    }
                },

                .Pointer => |ptrInfo| {
                    switch (ptrInfo.size) {
                        .Slice => {
                            switch (try source.peekNextTokenType()) {
                                .array_begin => {
                                    _ = try source.next();

                                    // Typical array.
                                    var arraylist = std.ArrayList(ptrInfo.child).init(alloc);
                                    while (true) {
                                        switch (try source.peekNextTokenType()) {
                                            .array_end => {
                                                _ = try source.next();
                                                break;
                                            },
                                            else => {},
                                        }

                                        try arraylist.ensureUnusedCapacity(1);
                                        arraylist.appendAssumeCapacity(try innerParseRequest(ptrInfo.child, alloc, source, opts));
                                    }

                                    return try arraylist.toOwnedSlice();
                                },
                                .string => {
                                    if (ptrInfo.child != u8)
                                        return error.UnexpectedToken;

                                    if (ptrInfo.is_const) {
                                        switch (try source.nextAllocMax(alloc, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |slice| {
                                                const hex = if (std.mem.startsWith(u8, slice, "0x")) slice[2..] else slice;

                                                const buf = try alloc.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);
                                                const bytes = if (std.fmt.hexToBytes(buf, hex)) |result| result else |_| slice;

                                                return bytes;
                                            },
                                            else => unreachable,
                                        }
                                    } else {
                                        // Have to allocate to get a mutable copy.
                                        switch (try source.nextAllocMax(alloc, .alloc_always, alloc.max_value_len.?)) {
                                            .allocated_string => |slice| return slice,
                                            else => unreachable,
                                        }
                                    }
                                },
                                else => return error.UnexpectedToken,
                            }
                        },
                        else => @compileError("Unable to parse type " ++ @typeName(TT)),
                    }
                },
                .Struct => {
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(alloc, source, opts) else @compileError("Unable to parse structs without jsonParse custom declaration");
                },
                .Union => {
                    if (@hasDecl(TT, "jsonParse")) return TT.jsonParse(alloc, source, opts) else @compileError("Unable to parse structs without jsonParse custom declaration");
                },
                else => @compileError("Unable to parse type " ++ @typeName(TT)),
            }
        }
    };
}
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

    return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
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

    return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}
/// Convert sets of solidity ABI paramters to the representing Zig types.
/// This will create a tuple type of the subset of the resulting types
/// generated by `AbiParameterToPrimative`. If the paramters length is
/// O then the resulting type will be a void type.
pub fn AbiParametersToPrimative(comptime paramters: []const AbiParameter) type {
    if (paramters.len == 0) return void;
    var fields: [paramters.len]std.builtin.Type.StructField = undefined;

    for (paramters, 0..) |paramter, i| {
        const FieldType = AbiParameterToPrimative(paramter);

        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = FieldType,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(FieldType) > 0) @alignOf(FieldType) else 0,
        };
    }

    return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
/// Convert solidity ABI paramter to the representing Zig types.
///
/// The resulting type will depend on the parameter passed in.
/// `string, fixed/bytes and addresses` will result in the zig **string** type.
///
/// For the `int/uint` type the resulting type will depend on the values attached to them.
/// **If the value is not divisable by 8 or higher than 256 compilation will fail.**
/// For example `ParamType{.int = 120}` will result in the **i120** type.
///
/// If the param is a `dynamicArray` then the resulting type will be
/// a **slice** of the set of base types set above.
///
/// If the param type is a `fixedArray` then the a **array** is returned
/// with its size depending on the *size* property on it.
///
/// Finally for tuple type a **struct** will be created where the field names are property names
/// that the components array field has. If this field is null compilation will fail.
pub fn AbiParameterToPrimative(comptime param: AbiParameter) type {
    return switch (param.type) {
        .string, .bytes, .address => []const u8,
        .bool => bool,
        .fixedBytes => []const u8,
        .int => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .signed, .bits = val } }),
        .uint => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .unsigned, .bits = val } }),
        .dynamicArray => []const AbiParameterToPrimative(.{ .type = param.type.dynamicArray.*, .name = param.name, .internalType = param.internalType, .components = param.components }),
        .fixedArray => [param.type.fixedArray.size]AbiParameterToPrimative(.{ .type = param.type.fixedArray.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }),
        .tuple => {
            if (param.components) |components| {
                var fields: [components.len]std.builtin.Type.StructField = undefined;
                for (components, 0..) |component, i| {
                    const FieldType = AbiParameterToPrimative(component);
                    fields[i] = .{
                        .name = component.name ++ "",
                        .type = FieldType,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = if (@sizeOf(FieldType) > 0) @alignOf(FieldType) else 0,
                    };
                }

                return @Type(.{ .Struct = .{ .layout = .Auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
            } else @compileError("Expected components to not be null");
        },
        inline else => void,
    };
}

test "Meta" {
    try testing.expectEqual(AbiParametersToPrimative(&.{}), void);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .string = {} }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedBytes = 31 }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .uint = 120 }, .name = "foo" }), u120);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .int = 48 }, .name = "foo" }), i48);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bytes = {} }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .address = {} }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bool = {} }, .name = "foo" }), bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .dynamicArray = &.{ .bool = {} } }, .name = "foo" }), []const bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedArray = .{ .child = &.{ .bool = {} }, .size = 2 } }, .name = "foo" }), [2]bool);

    try expectEqualStructs(struct { foo: u32, jazz: bool }, Omit(struct { foo: u32, bar: u256, baz: i64, jazz: bool }, &.{ "bar", "baz" }));
    try expectEqualStructs(std.meta.Tuple(&[_]type{ u64, std.meta.Tuple(&[_]type{ u64, u256 }) }), StructToTupleType(struct { foo: u64, bar: struct { baz: u64, jazz: u256 } }));
    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }), struct { bar: bool });
    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }), struct { bar: struct { baz: bool } });
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
