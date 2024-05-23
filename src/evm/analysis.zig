const std = @import("std");
const bytecode = @import("bytecode.zig");

const Allocator = std.mem.Allocator;
const Bytecode = bytecode.Bytecode;
const JumpTable = bytecode.JumpTable;

/// Analyzes the raw bytecode into a `analyzed` state. If the provided
/// code is already analyzed then it will just return it.
pub fn analyzeBytecode(allocator: Allocator, code: Bytecode) !Bytecode {
    switch (code) {
        .analyzed => return code,
        .raw => |raw| return bytecode.AnalyzedBytecode.init(allocator, raw),
    }
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
