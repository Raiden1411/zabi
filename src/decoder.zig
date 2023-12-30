const std = @import("std");
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiParameterToPrimative = @import("types.zig").AbiParameterToPrimative;
const AbiParametersToPrimative = @import("types.zig").AbiParametersToPrimative;
const Allocator = std.mem.Allocator;
const ParamType = @import("param_type.zig").ParamType;

fn Decoded(comptime T: type) type {
    return struct { consumed: usize, data: T };
}

fn decodeParameters(alloc: Allocator, comptime params: []const AbiParameter, hex: []u8) !AbiParametersToPrimative(params) {
    var pos: usize = 0;

    var result: AbiParametersToPrimative(params) = undefined;
    inline for (params, 0..) |param, i| {
        const decoded = try decodeParameter(alloc, param, hex, pos);
        pos += decoded.consumed;
        result[i] = decoded.data;
    }

    return result;
}

fn decodeParameter(alloc: Allocator, comptime param: AbiParameter, hex: []u8, position: usize) !Decoded(AbiParameterToPrimative(param)) {
    return switch (param.type) {
        .string => try decodeString(alloc, hex, position),
        .bytes => try decodeBytes(alloc, hex, position),
        .fixedBytes => |val| try decodeFixedBytes(alloc, val, hex, position),
        .int => try decodeNumber(alloc, i256, hex, position),
        .uint => try decodeNumber(alloc, u256, hex, position),
        .bool => try decodeBool(alloc, hex, position),
        .dynamicArray => |val| try decodeArray(alloc, .{ .type = val.*, .name = param.name, .internalType = param.internalType, .components = param.components }, hex, position),
        .fixedArray => |val| try decodeFixedArray(alloc, .{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }, val.size, hex, position),
        inline else => @compileError("Not implemented yet"),
    };
}

fn decodeNumber(alloc: Allocator, comptime T: type, hex: []u8, position: usize) !Decoded(T) {
    const info = @typeInfo(T);
    if (info != .Int) @compileError("Invalid type passed");

    const hexed = std.fmt.fmtSliceHexLower(hex[position .. position + 32]);
    const slice = try std.fmt.allocPrint(alloc, "{s}", .{hexed});

    return .{ .consumed = 32, .data = try std.fmt.parseInt(T, slice, 16) };
}

fn decodeBool(alloc: Allocator, hex: []u8, position: usize) !Decoded(bool) {
    const b = try decodeNumber(alloc, u1, hex, position);

    return .{ .consumed = 32, .data = b.data != 0 };
}

fn decodeString(alloc: Allocator, hex: []u8, position: usize) !Decoded([]const u8) {
    const offset = try decodeNumber(alloc, usize, hex, position);
    const length = try decodeNumber(alloc, usize, hex, offset.data);

    const slice = hex[offset.data + 32 .. offset.data + 32 + length.data];

    return .{ .consumed = 32, .data = try std.fmt.allocPrint(alloc, "{s}", .{slice}) };
}

fn decodeBytes(alloc: Allocator, hex: []u8, position: usize) !Decoded([]const u8) {
    const offset = try decodeNumber(alloc, usize, hex, position);
    const length = try decodeNumber(alloc, usize, hex, offset.data);

    const slice = hex[offset.data + 32 .. offset.data + 32 + length.data];

    return .{ .consumed = 32, .data = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(slice)}) };
}

fn decodeFixedBytes(alloc: Allocator, size: usize, hex: []u8, position: usize) !Decoded([]const u8) {
    return .{ .consumed = 32, .data = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(hex[position .. position + size])}) };
}

fn decodeArray(alloc: Allocator, comptime param: AbiParameter, hex: []u8, position: usize) !Decoded([]const AbiParameterToPrimative(param)) {
    const offset = try decodeNumber(alloc, usize, hex, position);
    const length = try decodeNumber(alloc, usize, hex, offset.data);

    var pos: usize = 0;

    var list = std.ArrayList(AbiParameterToPrimative(param)).init(alloc);

    for (0..length.data) |_| {
        const decoded = try decodeParameter(alloc, param, hex[offset.data + 32 ..], pos);
        pos += decoded.consumed;
        try list.append(decoded.data);
    }

    return .{ .consumed = 32, .data = try list.toOwnedSlice() };
}

fn decodeFixedArray(alloc: Allocator, comptime param: AbiParameter, comptime size: usize, hex: []u8, position: usize) !Decoded([size]AbiParameterToPrimative(param)) {
    if (isDynamicType(param)) {
        const offset = try decodeNumber(alloc, usize, hex, position);
        var pos: usize = 0;
        var result: [size]AbiParameterToPrimative(param) = undefined;
        const child = blk: {
            switch (param.type) {
                .dynamicArray => |val| break :blk val.*,
                inline else => {},
            }
        };

        for (0..size) |i| {
            const decoded = try decodeParameter(alloc, param, hex[offset.data..], if (@TypeOf(child) != void) pos else i * 32);
            pos += decoded.consumed;
            result[i] = decoded.data;
        }

        return .{ .consumed = 32, .data = result };
    }

    var pos: usize = 0;

    var result: [size]AbiParameterToPrimative(param) = undefined;
    for (0..size) |i| {
        const decoded = try decodeParameter(alloc, param, hex, pos + position);
        pos += decoded.consumed;
        result[i] = decoded.data;
    }

    return .{ .consumed = 32, .data = result };
}

inline fn isDynamicType(comptime param: AbiParameter) bool {
    return switch (param.type) {
        .string,
        .bytes,
        .dynamicArray,
        => true,
        .tuple => for (param.components.?) |component| isDynamicType(component),
        .fixedArray => |val| isDynamicType(.{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }),
        inline else => false,
    };
}

test "FOOO" {
    // const buffer = try std.testing.allocator.alloc(u8, 32);
    // std.testing.allocator.free(buffer);
    //
    // std.mem.writeInt(u256, buffer[0..32], 0, .big);
    // const a = std.fmt.bytesToHex(buffer[0..32], .lower);

    var buffer: [1024]u8 = undefined;
    const a = try std.fmt.hexToBytes(&buffer, "");
    const b = try decodeParameters(std.testing.allocator, &.{.{ .type = .{ .fixedArray = .{ .child = &.{ .fixedArray = .{ .child = &.{ .dynamicArray = &.{ .uint = 256 } }, .size = 2 } }, .size = 2 } }, .name = "" }}, a);
    std.debug.print("FOOO: {any}\n", .{b[0]});
    // std.debug.print("FOOO: {d}\n", .{try decodeNumber(u256, &a)});
}
