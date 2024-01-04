const abi = @import("../abi.zig");
const params = @import("../abi_parameter.zig");
const std = @import("std");
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

        pub fn format(self: T, comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
            switch (self) {
                inline else => |value| try value.format(layout, opts, writer),
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

pub fn AbiParametersToPrimative(comptime paramters: []const params.AbiParameter) type {
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
                        .name = component.name,
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

// pub fn DecodedTopic(comptime param: ParamType) type {
//     return switch (param) {
//         .string, .bytes, .tuple, .dynamicArray, .fixedArray => []const u8,
//         inline else => ParamTypeToPrimativeType(param),
//     };
// }
