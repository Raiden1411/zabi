const abi = @import("../abi.zig");
const params = @import("../abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const Abitype = abi.Abitype;
const Allocator = std.mem.Allocator;
const ParamType = @import("../param_type.zig").ParamType;

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

pub fn RequestParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(alloc: Allocator, source: anytype, opts: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const info = @typeInfo(T);
            if (.object_begin != try source.next()) return error.UnexpectedToken;

            var result: T = undefined;

            while (true) {
                var name_token: ?std.json.Token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                const field_name = switch (name_token.?) {
                    inline .string, .allocated_string => |slice| slice,
                    .object_end => { // No more fields.
                        break;
                    },
                    else => {
                        return error.UnexpectedToken;
                    },
                };

                inline for (info.Struct.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        name_token = null;
                        @field(result, field.name) = try innerParseRequest(field.type, alloc, source, opts);
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

            return result;
        }

        fn innerParseRequest(comptime TT: type, alloc: Allocator, source: anytype, opts: std.json.ParseOptions) !TT {
            const info = @typeInfo(TT);

            switch (info) {
                .Int => {
                    const token = try source.nextAllocMax(alloc, .alloc_if_needed, opts.max_value_len.?);
                    const slice = switch (token) {
                        inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                        else => return error.UnexpectedToken,
                    };

                    return try std.fmt.parseInt(TT, slice, 0);
                },

                .Pointer => |ptrInfo| {
                    switch (ptrInfo.size) {
                        .Slice => {
                            switch (try source.peekNextTokenType()) {
                                .string => {
                                    if (ptrInfo.child != u8) return error.UnexpectedToken;
                                    if (ptrInfo.is_const) {
                                        switch (try source.nextAllocMax(alloc, opts.allocate.?, opts.max_value_len.?)) {
                                            inline .string, .allocated_string => |slice| return slice,
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

/// Convert sets of solidity ABI paramters to the representing Zig types.
/// This will create a tuple type of the subset of the resulting types
/// generated by `AbiParameterToPrimative`. If the paramters length is
/// O then the resulting type will be a void type.
pub fn AbiParametersToPrimative(comptime paramters: []const params.AbiParameter) type {
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
pub fn AbiParameterToPrimative(comptime param: params.AbiParameter) type {
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
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}
