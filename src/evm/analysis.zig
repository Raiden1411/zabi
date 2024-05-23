const std = @import("std");
const bytecode = @import("bytecode.zig");

const Allocator = std.mem.Allocator;
const Bytecode = bytecode.Bytecode;
const JumpTable = bytecode.JumpTable;

/// Analyzes the raw bytecode into a `analyzed` state. If the provided
/// code is already analyzed then it will just return it.
pub fn analyzeBytecode(allocator: Allocator, code: Bytecode) !Bytecode {
    const slice, const size = blk: {
        switch (code) {
            .analyzed => return code,
            .raw => |raw| {
                const size = raw.len;
                const list = try std.ArrayList(u8).initCapacity(allocator, size + 33);
                try list.appendSlice(raw);
                try list.writer().writeByteNTimes(0, 33);

                break :blk .{ try list.toOwnedSlice(), size };
            },
        }
    };

    const jump_table = try createJumpTable(allocator, slice);

    return .{ .analyzed = .{
        .bytecode = slice,
        .original_length = size,
        .jump_table = jump_table,
    } };
}
/// Creates the jump table based on the provided bytecode. Assumes that
/// this was already padded in advance.
pub fn createJumpTable(allocator: Allocator, prepared_code: []u8) !JumpTable {
    const table = try JumpTable.init(allocator, false, prepared_code.len);
    errdefer table.deinit(allocator);

    var start: usize = 0;
    while (start < prepared_code.len) {
        const opcode = prepared_code[start];

        if (opcode == 0x5b) {
            table.set(start, true);
            start += 1;
        } else {
            const push_offset = opcode -% 0x60;

            if (push_offset < 32) {
                start += push_offset + 2;
            } else {
                start += 1;
            }
        }
    }

    return table;
}
