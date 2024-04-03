const std = @import("std");

const assert = std.debug.assert;

pub fn parseArgs(comptime T: type, args: *std.process.ArgIterator) T {
    const info = @typeInfo(T);

    assert(info == .Struct);

    inline for (info.Struct.fields) |field| {
        switch (@typeInfo(field.type)) {
            .Optional => assert(convertDefaultValueType(field).? == null),
            else => {},
        }
    }

    var result: T = .{};
    next: while (args.next()) |args_str| {
        inline for (info.Struct.fields) |field| {
            const arg_flag = convertToArgFlag(field.name);
            if (std.mem.startsWith(u8, args_str, arg_flag)) {
                @field(result, field.name) = parseArgument(field.type, arg_flag, args_str);
                continue :next;
            }
        }
    }

    return result;
}

fn parseArgument(comptime T: type, expected: [:0]const u8, arg: []const u8) T {
    const value = parseArgString(expected, arg);

    return parseArgValue(T, value);
}

/// Parses a argument string like --foo=69
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

fn parseArgValue(comptime T: type, value: []const u8) T {
    assert(value.len > 0);

    const Value = switch (@typeInfo(T)) {
        .Optional => |optional| optional.child,
        else => T,
    };

    if (Value == []const u8 or Value == [:0]const u8)
        return value;

    if (@typeInfo(Value) == .Int) {
        const parsed = std.fmt.parseInt(Value, value, 0) catch |err| switch (err) {
            error.Overflow => failWithMessage("value bits {s} exceeds to provided type {s} capacity", .{ value, @typeName(T) }),
            error.InvalidCharacter => failWithMessage("expected a digit string but found '{s}'", .{value}),
        };

        return parsed;
    }

    // Most types are not supported since we don't have a need for it yet.
    // So we just fail if we reach this point.
    unreachable;
}

fn convertToArgFlag(comptime field_name: [:0]const u8) [:0]const u8 {
    const flag: [:0]const u8 = comptime "--" ++ field_name;

    return flag;
}

fn convertDefaultValueType(comptime field: std.builtin.Type.StructField) ?field.type {
    return if (field.default_value) |opaque_value|
        @as(*const field.type, @ptrCast(@alignCast(opaque_value))).*
    else
        null;
}

fn failWithMessage(comptime message: []const u8, values: anytype) noreturn {
    assert(@typeInfo(@TypeOf(values)) == .Struct);
    assert(@typeInfo(@TypeOf(values)).Struct.is_tuple);

    const stderr = std.io.getStdErr().writer();
    stderr.print("Failed with message: " ++ message ++ "\n", values) catch {};
    std.posix.exit(1);
}
