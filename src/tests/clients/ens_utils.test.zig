const ens_utils = @import("zabi-ens").utils;
const std = @import("std");
const testing = std.testing;

const convertEnsToBytes = ens_utils.convertEnsToBytes;
const hashName = ens_utils.hashName;

test "Namehash" {
    const hash = try hashName("zzabi.eth");
    const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("0x5ebecd8698825286699948626f12835f42f21c118e164aba567ede63911000c8", hex);
}

test "EnsToBytes" {
    {
        const name = "zzabi.eth";
        var buffer: [11]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x057a7a6162690365746800", hex);
    }
    {
        const name = "zzabi.zig.eth";
        var buffer: [15]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x057a7a616269037a69670365746800", hex);
    }
    {
        const name = "f" ** 256;
        var buffer: [68]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x425b316462356632623439323936626434316439316462636130373938633335393764633036656561623166623661386437326235393233343264633762336133365d00", hex);
    }
    {
        const name = "[1db5f2b49296bd41d91dbca0798c3597dc06eeab1fb6a8d72b592342dc7b3a36]";
        var buffer: [68]u8 = undefined;
        const bytes_read = convertEnsToBytes(buffer[0..], name);

        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(buffer[0..bytes_read])});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x425b316462356632623439323936626434316439316462636130373938633335393764633036656561623166623661386437326235393233343264633762336133365d00", hex);
    }
}
