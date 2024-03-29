const abi = @import("../abi/abi.zig");
const params = @import("../abi/abi_parameter.zig");
const std = @import("std");
const testing = std.testing;

// Types
const Abitype = abi.Abitype;
const AbiEventParameter = params.AbiEventParameter;
const AbiParameter = params.AbiParameter;
const ParamType = @import("../abi/param_type.zig").ParamType;

/// Sames as `AbiParametersToPrimative` but for event parameter types.
pub fn AbiEventParametersDataToPrimative(comptime paramters: []const AbiEventParameter) type {
    if (paramters.len == 0) return @Type(.{ .Struct = .{ .layout = .auto, .fields = &.{}, .decls = &.{}, .is_tuple = true } });

    var count: usize = 0;

    for (paramters) |param| {
        const EventType = AbiEventParameterToPrimativeType(param);

        if (EventType != void) count += 1;
    }

    var fields: [count]std.builtin.Type.StructField = undefined;

    count = 0;
    for (paramters) |paramter| {
        const EventType = AbiEventParameterDataToPrimative(paramter);

        if (EventType != void) {
            fields[count] = .{
                .name = std.fmt.comptimePrint("{d}", .{count}),
                .type = EventType,
                .default_value = null,
                .is_comptime = false,
                .alignment = if (@sizeOf(EventType) > 0) @alignOf(EventType) else 0,
            };
            count += 1;
        }
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
/// Sames as `AbiParameterToPrimative` but for event parameter types.
pub fn AbiEventParameterDataToPrimative(comptime param: AbiEventParameter) type {
    return switch (param.type) {
        .string, .bytes => []const u8,
        .address => [20]u8,
        .fixedBytes => |fixed| [fixed]u8,
        .bool => bool,
        .int => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .signed, .bits = val } }),
        .uint => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .unsigned, .bits = val } }),
        .dynamicArray => []const AbiParameterToPrimative(.{
            .type = param.type.dynamicArray.*,
            .name = param.name,
            .internalType = param.internalType,
            .components = param.components,
        }),
        .fixedArray => [param.type.fixedArray.size]AbiParameterToPrimative(.{
            .type = param.type.fixedArray.child.*,
            .name = param.name,
            .internalType = param.internalType,
            .components = param.components,
        }),
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

                return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
            } else @compileError("Expected components to not be null");
        },
        inline else => void,
    };
}
/// Convert sets of solidity ABI Event indexed parameters to the representing Zig types.
/// This will create a tuple type of the subset of the resulting types
/// generated by `AbiEventParameterToPrimativeType`. If the paramters length is
/// O then the resulting type a tuple of just the Hash type.
pub fn AbiEventParametersToPrimativeType(comptime event_params: []const AbiEventParameter) type {
    if (event_params.len == 0) {
        var fields: [1]std.builtin.Type.StructField = undefined;
        fields[0] = .{
            .name = std.fmt.comptimePrint("{d}", .{0}),
            .type = [32]u8,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf([32]u8),
        };

        return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
    }

    var count: usize = 0;

    for (event_params) |param| {
        const EventType = AbiEventParameterToPrimativeType(param);

        if (EventType != void) count += 1;
    }

    var fields: [count + 1]std.builtin.Type.StructField = undefined;
    fields[0] = .{
        .name = std.fmt.comptimePrint("{d}", .{0}),
        .type = [32]u8,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf([32]u8),
    };

    for (event_params, 1..) |param, i| {
        const EventType = AbiEventParameterToPrimativeType(param);

        if (EventType != void) {
            fields[i] = .{
                .name = std.fmt.comptimePrint("{d}", .{i}),
                .type = EventType,
                .default_value = null,
                .is_comptime = false,
                .alignment = if (@sizeOf(EventType) > 0) @alignOf(EventType) else 0,
            };
        }
    }

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}
/// Converts the abi event parameters into native zig types
/// This is intended to be used for log topic data or in
/// other words were the params are indexed.
pub fn AbiEventParameterToPrimativeType(comptime param: AbiEventParameter) type {
    if (!param.indexed) return void;

    return switch (param.type) {
        .tuple, .dynamicArray, .fixedArray, .string, .bytes => [32]u8,
        .address => [20]u8,
        .fixedBytes => |fixed| [fixed]u8,
        .bool => bool,
        .int => |val| if (val % 8 != 0 or val > 256)
            @compileError("Invalid bits passed in to int type")
        else
            @Type(.{ .Int = .{ .signedness = .signed, .bits = val } }),
        .uint => |val| if (val % 8 != 0 or val > 256)
            @compileError("Invalid bits passed in to int type")
        else
            @Type(.{ .Int = .{ .signedness = .unsigned, .bits = val } }),
        inline else => void,
    };
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

    return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
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
        .string => []const u8,
        .bytes => []u8,
        .address => [20]u8,
        .fixedBytes => |fixed| [fixed]u8,
        .bool => bool,
        .int => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .signed, .bits = val } }),
        .uint => |val| if (val % 8 != 0 or val > 256) @compileError("Invalid bits passed in to int type") else @Type(.{ .Int = .{ .signedness = .unsigned, .bits = val } }),
        .dynamicArray => []const AbiParameterToPrimative(.{
            .type = param.type.dynamicArray.*,
            .name = param.name,
            .internalType = param.internalType,
            .components = param.components,
        }),
        .fixedArray => [param.type.fixedArray.size]AbiParameterToPrimative(.{
            .type = param.type.fixedArray.child.*,
            .name = param.name,
            .internalType = param.internalType,
            .components = param.components,
        }),
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

                return @Type(.{ .Struct = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
            } else @compileError("Expected components to not be null");
        },
        inline else => void,
    };
}

test "Meta" {
    try testing.expectEqual(AbiParametersToPrimative(&.{}), void);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .string = {} }, .name = "foo" }), []const u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedBytes = 31 }, .name = "foo" }), [31]u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .uint = 120 }, .name = "foo" }), u120);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .int = 48 }, .name = "foo" }), i48);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bytes = {} }, .name = "foo" }), []u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .address = {} }, .name = "foo" }), [20]u8);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .bool = {} }, .name = "foo" }), bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .dynamicArray = &.{ .bool = {} } }, .name = "foo" }), []const bool);
    try testing.expectEqual(AbiParameterToPrimative(.{ .type = .{ .fixedArray = .{ .child = &.{ .bool = {} }, .size = 2 } }, .name = "foo" }), [2]bool);

    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .string = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .bytes = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .tuple = {} }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .dynamicArray = &.{ .bool = {} } }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .fixedArray = .{ .child = &.{ .bool = {} }, .size = 2 } }, .name = "foo", .indexed = true }), [32]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .bool = {} }, .name = "foo", .indexed = true }), bool);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .address = {} }, .name = "foo", .indexed = true }), [20]u8);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .uint = 64 }, .name = "foo", .indexed = true }), u64);
    try testing.expectEqual(AbiEventParameterToPrimativeType(.{ .type = .{ .int = 16 }, .name = "foo", .indexed = true }), i16);

    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }), struct { bar: bool });
    try expectEqualStructs(AbiParameterToPrimative(.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .tuple = {} }, .name = "bar", .components = &.{.{ .type = .{ .bool = {} }, .name = "baz" }} }} }), struct { bar: struct { baz: bool } });
}

test "EventParameters" {
    const event: abi.Event = .{
        .type = .event,
        .name = "Foo",
        .inputs = &.{
            .{
                .type = .{ .uint = 256 },
                .name = "bar",
                .indexed = true,
            },
        },
    };

    const ParamsTypes = AbiEventParametersToPrimativeType(event.inputs);

    try expectEqualStructs(ParamsTypes, struct { [32]u8, u256 });
    try expectEqualStructs(AbiEventParametersToPrimativeType(&.{}), struct { [32]u8 });
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
