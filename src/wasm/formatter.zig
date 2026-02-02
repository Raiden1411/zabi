const formatter = zabi_ast.formatter;
const std = @import("std");
const wasm = @import("wasm.zig");
const zabi_ast = @import("zabi").ast;

const Ast = zabi_ast.Ast;
const Formatter = formatter.SolidityFormatter;
const String = wasm.String;

pub export fn formatSolidity(
    source: [*:0]const u8,
    len: usize,
) String {
    var list: std.Io.Writer.Allocating = .init(wasm.allocator);
    errdefer list.deinit();

    var ast = Ast.parse(wasm.allocator, source[0..len :0]) catch wasm.panic("Failed to parse code!", null, null);
    defer ast.deinit(wasm.allocator);

    if (ast.errors.len > 0) wasm.panic("Failed to parse code: syntax error", null, null);

    var format: Formatter = .init(ast, 4, &list.writer);
    format.format() catch wasm.panic("Failed to format the code!", null, null);

    return String.init(list.toOwnedSlice() catch wasm.panic("Out of memory", null, null));
}
