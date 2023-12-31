const std = @import("std");
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiParameterToPrimative = @import("types.zig").AbiParameterToPrimative;
const AbiParametersToPrimative = @import("types.zig").AbiParametersToPrimative;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ParamType = @import("param_type.zig").ParamType;

fn Decoded(comptime T: type) type {
    return struct { consumed: usize, data: T };
}

pub fn AbiDecoded(comptime params: []const AbiParameter) type {
    return struct {
        arena: *ArenaAllocator,
        values: AbiParametersToPrimative(params),

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();

            allocator.destroy(self.arena);
        }
    };
}

pub fn decodeAbiParameters(alloc: Allocator, comptime params: []const AbiParameter, hex: []const u8) !AbiDecoded(params) {
    var decoded: AbiDecoded(params) = .{ .arena = try alloc.create(ArenaAllocator), .values = undefined };
    errdefer alloc.destroy(decoded.arena);

    decoded.arena.* = ArenaAllocator.init(alloc);
    errdefer decoded.arena.deinit();

    const allocator = decoded.arena.allocator();
    decoded.values = try decodeAbiParametersLeaky(allocator, params, hex);

    return decoded;
}

pub fn decodeAbiParametersLeaky(alloc: Allocator, comptime params: []const AbiParameter, hex: []const u8) !AbiParametersToPrimative(params) {
    const buffer = try alloc.alloc(u8, hex.len / 2);
    const bytes = try std.fmt.hexToBytes(buffer, hex);

    return decodeParameters(alloc, params, bytes);
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
        .address => try decodeAddress(alloc, hex, position),
        .fixedBytes => |val| try decodeFixedBytes(alloc, val, hex, position),
        .int => try decodeNumber(alloc, i256, hex, position),
        .uint => try decodeNumber(alloc, u256, hex, position),
        .bool => try decodeBool(alloc, hex, position),
        .dynamicArray => |val| try decodeArray(alloc, .{ .type = val.*, .name = param.name, .internalType = param.internalType, .components = param.components }, hex, position),
        .fixedArray => |val| try decodeFixedArray(alloc, .{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }, val.size, hex, position),
        .tuple => try decodeTuple(alloc, param, hex, position),
        inline else => @compileLog("Not implemented"),
    };
}

fn decodeAddress(alloc: Allocator, hex: []u8, position: usize) !Decoded([]const u8) {
    const slice = hex[position + 12 .. position + 32];

    // TODO: Checksum address
    return .{ .consumed = 32, .data = try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(slice)}) };
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

fn decodeTuple(alloc: Allocator, comptime param: AbiParameter, hex: []u8, position: usize) !Decoded(AbiParameterToPrimative(param)) {
    var result: AbiParameterToPrimative(param) = undefined;

    if (param.components) |components| {
        if (isDynamicType(param)) {
            var pos: usize = 0;
            const offset = try decodeNumber(alloc, usize, hex, position);

            inline for (components) |component| {
                const decoded = try decodeParameter(alloc, component, hex[offset.data..], pos);
                pos += decoded.consumed;
                @field(result, component.name) = decoded.data;
            }

            return .{ .consumed = 32, .data = result };
        }

        var pos: usize = 0;
        inline for (components) |component| {
            const decoded = try decodeParameter(alloc, component, hex, position + pos);
            pos += decoded.consumed;
            @field(result, component.name) = decoded.data;
        }

        return .{ .consumed = 32, .data = result };
    } else @compileError("Expected components to not be null");
}

inline fn isDynamicType(comptime param: AbiParameter) bool {
    return switch (param.type) {
        .string,
        .bytes,
        .dynamicArray,
        => true,
        .tuple => inline for (param.components.?) |component| return isDynamicType(component),
        .fixedArray => |val| isDynamicType(.{ .type = val.child.*, .name = param.name, .internalType = param.internalType, .components = param.components }),
        inline else => false,
    };
}

test "FOOO" {
    const b = try decodeAbiParameters(std.testing.allocator, &.{.{ .type = .{ .tuple = {} }, .name = "foo", .components = &.{.{ .type = .{ .bool = {} }, .name = "bar" }} }}, "0000000000000000000000000000000000000000000000000000000000000001");
    defer b.deinit();
    std.debug.print("Bar: {}\n", .{b.values[0]});
    // std.debug.print("FOOO: {d}\n", .{try decodeNumber(u256, &a)});
}
