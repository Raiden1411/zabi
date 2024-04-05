const std = @import("std");

const ConvertToEnum = @import("../meta/utils.zig").ConvertToEnum;

const assert = std.debug.assert;

/// Parses console arguments in the style of --foo=bar
/// For now not all types are supported but might be in the future
/// if the need for them arises.
pub fn parseArgs(comptime T: type, args: *std.process.ArgIterator) T {
    const info = @typeInfo(T);

    assert(info == .Struct);

    const fields_count = info.Struct.fields.len;

    // Optional fields must have null value defaults
    // and bool fields must be false.
    inline for (info.Struct.fields) |field| {
        switch (@typeInfo(field.type)) {
            .Optional => assert(convertDefaultValueType(field).? == null),
            .Bool => assert(convertDefaultValueType(field).? == false),
            else => {},
        }
    }

    var result: T = undefined;
    var seen: std.enums.EnumFieldStruct(ConvertToEnum(T), u32, 0) = .{};

    assert(args.skip());

    next: while (args.next()) |args_str| {
        inline for (info.Struct.fields) |field| {
            const arg_flag = convertToArgFlag(field.name);
            if (std.mem.startsWith(u8, args_str, arg_flag)) {
                @field(seen, field.name) += 1;

                @field(result, field.name) = parseArgument(field.type, arg_flag, args_str);
                continue :next;
            }
        }
    }

    inline for (info.Struct.fields[0..fields_count]) |field| {
        const arg_flag = convertToArgFlag(field.name);
        switch (@field(seen, field.name)) {
            0 => if (convertDefaultValueType(field)) |default_value| {
                @field(result, field.name) = default_value;
            } else failWithMessage("Missing required field: {s}", .{arg_flag}),
            1 => {},
            else => failWithMessage("Duplicate field: {s}", .{arg_flag}),
        }
    }

    return result;
}
/// Parses a argument string like --foo=69
fn parseArgument(comptime T: type, expected: [:0]const u8, arg: []const u8) T {
    if (T == bool) {
        if (!std.mem.eql(u8, expected, arg))
            failWithMessage("Bool flags do not require values. Consider using just '{s}'", .{expected});

        return true;
    }

    const value = parseArgString(expected, arg);

    return parseArgValue(T, value);
}
/// Parses a argument string like --foo=
fn parseArgString(expected: [:0]const u8, arg: []const u8) []const u8 {
    assert(arg[0] == '-' and arg[1] == '-');

    assert(std.mem.startsWith(u8, arg, expected));

    // We should have here =69
    const value = arg[expected.len..];

    if (value.len == 0)
        failWithMessage("{s} argument incorrectly formated. Expected '=' after the flag", .{arg});

    if (value[0] != '=')
        failWithMessage("{s} argument incorrectly formated. Expected '=' after the flag but found {c}", .{ arg, value[0] });

    if (value.len == 1)
        failWithMessage("expected value for {s} flag", .{arg});

    return value[1..];
}
/// Parses the value of the provided argument.
/// Compilation will fail if an unsupported argument is passed.
fn parseArgValue(comptime T: type, value: []const u8) T {
    assert(value.len > 0);

    if (T == []const u8 or T == [:0]const u8)
        return value;

    switch (@typeInfo(T)) {
        .Int => {
            const parsed = std.fmt.parseInt(T, value, 0) catch |err| switch (err) {
                error.Overflow => failWithMessage("value bits {s} exceeds to provided type {s} capacity", .{ value, @typeName(T) }),
                error.InvalidCharacter => failWithMessage("expected a digit string but found '{s}'", .{value}),
            };

            return parsed;
        },
        .Float => {
            const parsed = std.fmt.parseFloat(T, value) catch |err| switch (err) {
                error.InvalidCharacter => failWithMessage("expected a digit string but found '{s}'", .{value}),
            };

            return parsed;
        },
        .Optional => |optional_info| {
            return parseArgValue(optional_info.child, value);
        },
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                var buffer: T = undefined;

                _ = std.fmt.hexToBytes(&buffer, value) catch {
                    failWithMessage("invalid hex string '{s}'", .{value});
                };

                return buffer;
            }

            @compileError(std.fmt.comptimePrint("Unsupported array type '{s}'", .{@typeName(T)}));
        },
        else => @compileError(std.fmt.comptimePrint("Unsupported type for parsing arguments. '{s}'", .{@typeName(T)})),
    }
}
/// Converts struct field in to a cli arg string.
fn convertToArgFlag(comptime field_name: [:0]const u8) [:0]const u8 {
    const flag: [:0]const u8 = comptime "--" ++ field_name;

    return flag;
}
/// Wraps the default value into it's correct type
fn convertDefaultValueType(comptime field: std.builtin.Type.StructField) ?field.type {
    return if (field.default_value) |opaque_value|
        @as(*const field.type, @ptrCast(@alignCast(opaque_value))).*
    else
        null;
}
/// Fails with message and exit's the process.
fn failWithMessage(comptime message: []const u8, values: anytype) noreturn {
    assert(@typeInfo(@TypeOf(values)) == .Struct);
    assert(@typeInfo(@TypeOf(values)).Struct.is_tuple);

    const stderr = std.io.getStdErr().writer();
    stderr.print("Failed with message: " ++ message ++ "\n", values) catch {};
    std.posix.exit(1);
}
