const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const BlockExplorer = clients.BlockExplorer;

pub const CliOptions = struct {
    apikey: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var threaded_io: std.Io.Threaded = .init(init.gpa, .{
        .environ = init.minimal.environ,
    });
    defer threaded_io.deinit();

    var iter = init.minimal.args.iterate();
    const parsed = args_parser.parseArgs(CliOptions, init.gpa, &iter);

    var explorer = BlockExplorer.init(.{
        .allocator = init.gpa,
        .io = threaded_io.io(),
        .apikey = parsed.apikey,
    });
    defer explorer.deinit();

    const result = try explorer.getEtherPrice();
    defer result.deinit();

    std.debug.print("Explorer result: {any}", .{result.response});
}
