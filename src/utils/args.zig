const std = @import("std");

const Allocator = std.mem.Allocator;
const ArgIterator = std.process.Args.Iterator;
const ConvertToEnum = @import("zabi-meta").utils.ConvertToEnum;
const EnumFieldStruct = std.enums.EnumFieldStruct;

const assert = std.debug.assert;

/// Parses console arguments in the style of --foo=bar
/// For now not all types are supported but might be in the future
/// if the need for them arises.
///
/// Allocations are only made for slices and pointer types.
/// Slice or arrays that aren't u8 are expected to be comma seperated.
pub fn parseArgs(
    comptime T: type,
    allocator: Allocator,
    args: *ArgIterator,
) T {
    const info = @typeInfo(T);

    assert(info == .@"struct");

    const fields_count = info.@"struct".fields.len;

    // Optional fields must have null value defaults
    // and bool fields must be false.
    inline for (info.@"struct".fields) |field| {
        switch (@typeInfo(field.type)) {
            .optional => assert(convertDefaultValueType(field).? == null),
            .bool => assert(convertDefaultValueType(field).? == false),
            else => {},
        }
    }

    var result: T = undefined;
    var seen: EnumFieldStruct(ConvertToEnum(T), u32, 0) = .{};

    assert(args.skip());

    next: while (args.next()) |args_str| {
        inline for (info.@"struct".fields) |field| {
            const arg_flag = convertToArgFlag(field.name);
            if (std.mem.startsWith(u8, args_str, arg_flag)) {
                @field(seen, field.name) += 1;

                @field(result, field.name) = parseArgument(field.type, allocator, arg_flag, args_str);
                continue :next;
            }
        }
    }

    inline for (info.@"struct".fields[0..fields_count]) |field| {
        const arg_flag = convertToArgFlag(field.name);
        switch (@field(seen, field.name)) {
            0 => if (convertDefaultValueType(field)) |default_value| {
                @field(result, field.name) = default_value;
            } else failWithMessage("Missing required field {s}", .{arg_flag}),
            1 => {},
            else => failWithMessage("Duplicate field {s}", .{arg_flag}),
        }
    }

    return result;
}
/// Parses a argument string like --foo=69
fn parseArgument(
    comptime T: type,
    allocator: Allocator,
    expected: [:0]const u8,
    arg: []const u8,
) T {
    if (T == bool) {
        if (!std.mem.eql(u8, expected, arg))
            failWithMessage("Bool flags do not require values. Consider using just '{s}'", .{expected});

        return true;
    }

    const value = parseArgString(expected, arg);

    return parseArgValue(T, allocator, value);
}
/// Parses a argument string like --foo=
fn parseArgString(
    expected: [:0]const u8,
    arg: []const u8,
) []const u8 {
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
fn parseArgValue(
    comptime T: type,
    allocator: Allocator,
    value: []const u8,
) T {
    assert(value.len > 0);

    if (T == []const u8 or T == [:0]const u8)
        return value;

    switch (@typeInfo(T)) {
        .int => {
            const parsed = std.fmt.parseInt(T, value, 0) catch |err| switch (err) {
                error.Overflow => failWithMessage("value bits {s} exceeds to provided type {s} capacity", .{ value, @typeName(T) }),
                error.InvalidCharacter => failWithMessage("expected a digit string but found '{s}'", .{value}),
            };

            return parsed;
        },
        .float => {
            const parsed = std.fmt.parseFloat(T, value) catch |err| switch (err) {
                error.InvalidCharacter => failWithMessage("expected a digit string but found '{s}'", .{value}),
            };

            return parsed;
        },
        .optional => |optional_info| {
            return parseArgValue(optional_info.child, allocator, value);
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                var buffer: T = undefined;

                _ = std.fmt.hexToBytes(&buffer, value) catch {
                    failWithMessage("invalid hex string '{s}'", .{value});
                };

                return buffer;
            }

            var arr: T = undefined;
            var iter = std.mem.tokenizeScalar(u8, value, ",");

            var index: usize = 0;
            while (iter.next()) |slice| {
                assert(index < arr_info.len);
                arr[index] = try parseArgValue(arr_info.child, allocator, slice);
                index += 1;
            }

            return arr;
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
                    const pointer = allocator.create(ptr_info.child) catch failWithMessage("Process ran out of memory", .{});
                    errdefer allocator.destroy(pointer);

                    pointer.* = parseArgValue(ptr_info.child, allocator, value);

                    return pointer;
                },
                .slice => {
                    var list = std.ArrayList(ptr_info.child).init(allocator);
                    errdefer list.deinit();

                    var iter = std.mem.tokenizeScalar(u8, value, ",");

                    while (iter.next()) |slice| {
                        list.ensureTotalCapacity(1) catch failWithMessage("Process ran out of memory", .{});
                        list.appendAssumeCapacity(parseArgValue(ptr_info.child, allocator, slice));
                    }

                    const slice = list.toOwnedSlice() catch failWithMessage("Process ran out of memory", .{});
                    return slice;
                },
                else => @compileError(std.fmt.comptimePrint("Unsupported pointer type '{s}'", .{@typeName(T)})),
            }
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
    return if (field.default_value_ptr) |opaque_value|
        @as(*const field.type, @ptrCast(@alignCast(opaque_value))).*
    else
        null;
}

/// Fails with message and exit's the process.
fn failWithMessage(
    comptime message: []const u8,
    values: anytype,
) noreturn {
    assert(@typeInfo(@TypeOf(values)) == .@"struct");
    assert(@typeInfo(@TypeOf(values)).@"struct".is_tuple);
    var buffer: [1024]u8 = undefined;

    const stderr = std.debug.lockStderr(&buffer).terminal().writer;
    defer std.debug.unlockStderr();

    stderr.writeAll("Failed with message: ") catch {};
    stderr.writeAll(message) catch {};
    std.process.exit(1);
}
