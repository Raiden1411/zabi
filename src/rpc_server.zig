//! This is a simple JSON RPC server that
//! mimics a blockchain JSON RPC server.
//!
//! This sends responses based on the RPC method
//! and the responses are filled with random data.
//! This is mostly usefull for testing/fuzzing.
const args_parse = @import("tests/args.zig");
const std = @import("std");

const Server = @import("tests/clients/server.zig");

const Options = struct {
    send_error: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const parsed = args_parse.parseArgs(Options, &args);

    var server: Server = undefined;
    defer server.deinit();

    try server.init(.{ .allocator = gpa.allocator(), .port = 8545 });

    try server.listen(parsed.send_error);
}
