const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const BlockExplorer = clients.BlockExplorer;

pub const CliOptions = struct {
    apikey: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var threaded_io: std.Io.Threaded = .init(gpa.allocator());
    defer threaded_io.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    var explorer = BlockExplorer.init(.{
        .allocator = gpa.allocator(),
        .io = threaded_io.io(),
        .apikey = parsed.apikey,
    });
    defer explorer.deinit();

    const result = try explorer.getEtherPrice();
    defer result.deinit();

    std.debug.print("Explorer result: {any}", .{result.response});
}
