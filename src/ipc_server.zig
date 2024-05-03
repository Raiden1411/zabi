const args_parse = @import("tests/args.zig");
const std = @import("std");

const InitOpts = IpcServer.InitOpts;
const IpcServer = @import("tests/clients/ipc_server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const parsed = args_parse.parseArgs(InitOpts, gpa.allocator(), &args);

    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(gpa.allocator(), parsed);

    try server.start();
}
