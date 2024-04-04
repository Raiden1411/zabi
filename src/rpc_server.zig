//! This is a simple JSON RPC server that
//! mimics a blockchain JSON RPC server.
//!
//! This sends responses based on the RPC method
//! and the responses are filled with random data.
//! This is mostly usefull for testing/fuzzing.
const std = @import("std");

const Server = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var server: Server = undefined;
    defer server.deinit();

    try server.init(.{
        .allocator = gpa.allocator(),
    });

    while (true) {
        try server.listenToOneRequest();
    }
}
