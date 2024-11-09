const benchmark = @import("BenchmarkType.zig");
const constants = @import("constants.zig");
const std = @import("std");
const zabi_root = @import("zabi");
const generator = zabi_root.utils.generator;

// Types
const Ast = zabi_root.ast.Ast;
const Allocator = std.mem.Allocator;
const Event = zabi_root.abi.abitypes.Event;
const HDWalletNode = zabi_root.crypto.hdwallet.HDWalletNode;
const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;
const HttpRpcClient = zabi_root.clients.PubClient;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Signer = zabi_root.crypto.Signer;
const TerminalColors = std.io.tty.Color;
const TransactionEnvelope = zabi_root.types.transactions.TransactionEnvelope;
const ZigColor = std.zig.Color;

// Functions
const decodeAbiParameter = zabi_root.decoding.abi_decoder.decodeAbiParameter;
const decodeLogs = zabi_root.decoding.logs_decoder.decodeLogs;
const decodeRlp = zabi_root.decoding.rlp.decodeRlp;
const encodeAbiParameters = zabi_root.encoding.abi_encoding.encodeAbiParameters;
const encodeLogTopics = zabi_root.encoding.logs_encoding.encodeLogTopics;
const encodeRlp = zabi_root.encoding.rlp.encodeRlp;
const fromEntropy = zabi_root.crypto.mnemonic.fromEntropy;
const parseTransaction = zabi_root.decoding.parse_transacition.parseTransaction;
const parseHumanReadable = zabi_root.human_readable.parsing.parseHumanReadable;
const serializeTransaction = zabi_root.encoding.serialize.serializeTransaction;
const toEntropy = zabi_root.crypto.mnemonic.toEntropy;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var printer = ColorWriter(@TypeOf(std.io.getStdErr().writer())){
        .underlaying_writer = std.io.getStdErr().writer(),
        .color = .auto,
        .next_color = .white,
    };

    const uri = try std.Uri.parse("https://ethereum-rpc.publicnode.com");

    var client = try HttpRpcClient.init(.{
        .allocator = allocator,
        .network_config = .{ .endpoint = .{ .uri = uri } },
    });
    defer client.deinit();

    try printer.writer().print("{s}Benchmark running in {s} mode\n", .{ " " ** 20, @tagName(@import("builtin").mode) });
    try printer.writeBoarder(.HumanReadableAbi);

    {
        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            const abi = try zabi_root.human_readable.parsing.parseHumanReadable(allocator, constants.slice);
            defer abi.deinit();
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            const abi = try zabi_root.human_readable.parsing.parseHumanReadable(allocator, constants.slice);
            defer abi.deinit();
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }

    try printer.writeBoarder(.HttpClient);
    {
        try printer.writer().writeAll("Get ChainId...");
        const result = try benchmark.benchmark(
            allocator,
            HttpRpcClient.getChainId,
            .{client},
            .{ .runs = 5, .warmup_runs = 1 },
        );
        result.printSummary();
    }

    try printer.writeBoarder(.SolidityAst);
    {
        try printer.writer().writeAll("Parsing solidity...");

        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            var ast = try Ast.parse(allocator, constants.source_code);
            defer ast.deinit(allocator);
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            var ast = try Ast.parse(allocator, constants.source_code);
            defer ast.deinit(allocator);
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }

    try encodingFunctions(allocator, &printer);
    try decodingFunctions(allocator, &printer);
    try signerMethods(allocator, &printer);
}

pub fn signerMethods(allocator: Allocator, printer: *ColorWriter(@TypeOf(std.io.getStdErr().writer()))) !void {
    var buffer: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    const signer = try Signer.init(buffer);

    try printer.writeBoarder(.Signer);

    const start = "\x19Ethereum Signed Message:\n";
    const concated_message = try std.fmt.allocPrint(allocator, "{s}{d}{s}", .{ start, "Hello World!".len, "Hello World!" });
    defer allocator.free(concated_message);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(concated_message, &hash, .{});

    {
        try printer.writer().writeAll("Ethereum message...");
        const result = try benchmark.benchmark(
            allocator,
            Signer.sign,
            .{ signer, hash },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        try printer.writer().writeAll("Verify message...");
        const sig = try signer.sign(hash);
        const result = try benchmark.benchmark(
            allocator,
            Signer.verifyMessage,
            .{ signer, hash, sig },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        try printer.writer().writeAll("Recover Address...");
        const sig = try signer.sign(hash);
        const result = try benchmark.benchmark(
            allocator,
            Signer.recoverAddress,
            .{ sig, hash },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        try printer.writer().writeAll("Recover Public Key...");
        const sig = try signer.sign(hash);

        const result = try benchmark.benchmark(
            allocator,
            Signer.recoverPubkey,
            .{ sig, hash },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        try printer.writer().writeAll("HDWallet Node...");
        const seed = "test test test test test test test test test test test junk";
        var hashed: [64]u8 = undefined;

        try std.crypto.pwhash.pbkdf2(&hashed, seed, "mnemonic", 2048, HmacSha512);

        const result = try benchmark.benchmark(
            allocator,
            HDWalletNode.fromSeedAndPath,
            .{ hashed, "m/44'/60'/0'/0/0" },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        try printer.writer().writeAll("Mnemonic Entropy...");
        const seed = "test test test test test test test test test test test junk";

        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            _ = try toEntropy(12, seed, null);
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            _ = try toEntropy(12, seed, null);
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }
    {
        try printer.writer().writeAll("From Mnemonic Entropy...");
        const seed = "test test test test test test test test test test test junk";
        const entropy = try toEntropy(12, seed, null);

        const result = try benchmark.benchmark(
            allocator,
            fromEntropy,
            .{ allocator, 12, entropy, null },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
}
pub fn decodingFunctions(allocator: Allocator, printer: *ColorWriter(@TypeOf(std.io.getStdErr().writer()))) !void {
    try printer.writeBoarder(.Decoding);
    try printer.writer().writeAll("Parse serialized transaction... ");

    {
        const random_data = try generator.generateRandomData(TransactionEnvelope, allocator, 1, .{ .slice_size = 2 });
        defer random_data.deinit();

        const encoded = try serializeTransaction(allocator, random_data.generated, null);
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(
            allocator,
            parseTransaction,
            .{ allocator, encoded },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    try printer.writer().writeAll("RLP Decoding...");
    {
        const multi: std.meta.Tuple(&[_]type{ u8, bool, []const u8 }) = .{ 127, false, "foobar" };

        const encoded = try encodeRlp(allocator, multi);
        defer allocator.free(encoded);

        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            _ = try zabi_root.decoding.rlp.decodeRlp(@TypeOf(multi), allocator, encoded);
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            _ = try zabi_root.decoding.rlp.decodeRlp(@TypeOf(multi), allocator, encoded);
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }

    try printer.writer().writeAll("Abi Decoding... ");
    {
        const encoded = try encodeAbiParameters(constants.params, allocator, constants.items);
        defer allocator.free(encoded);

        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            const abi = try zabi_root.decoding.abi_decoder.decodeAbiParameter(
                zabi_root.meta.abi.AbiParametersToPrimative(constants.params),
                allocator,
                encoded,
                .{},
            );
            defer abi.deinit();
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            const abi = try zabi_root.decoding.abi_decoder.decodeAbiParameter(
                zabi_root.meta.abi.AbiParametersToPrimative(constants.params),
                allocator,
                encoded,
                .{},
            );
            defer abi.deinit();
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }

    try printer.writer().writeAll("Abi Logs Decoding... ");
    {
        const event: Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{ .type = .{ .uint = 256 }, .indexed = true, .name = "a" },
                .{ .type = .{ .int = 256 }, .indexed = true, .name = "b" },
                .{ .type = .{ .bool = {} }, .indexed = true, .name = "c" },
                .{ .type = .{ .fixedBytes = 5 }, .indexed = true, .name = "d" },
            },
        };

        const encoded = try encodeLogTopics(
            allocator,
            event,
            .{ 69, -420, true, "01234" },
        );
        defer allocator.free(encoded);

        const opts: benchmark.BenchmarkOptions = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            _ = try decodeLogs(struct { [32]u8, u256, i256, bool, [5]u8 }, encoded, .{ .bytes_endian = .little });
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            _ = try decodeLogs(struct { [32]u8, u256, i256, bool, [5]u8 }, encoded, .{ .bytes_endian = .little });
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }
}
/// Runs the encoding function of zabi.
pub fn encodingFunctions(allocator: Allocator, printer: *ColorWriter(@TypeOf(std.io.getStdErr().writer()))) !void {
    try printer.writeBoarder(.Encoding);
    try printer.writer().writeAll("Serialize Transaction...");
    {
        const random_data = try generator.generateRandomData(TransactionEnvelope, allocator, 69, .{ .slice_size = 2 });
        defer random_data.deinit();

        const result = try benchmark.benchmark(
            allocator,
            serializeTransaction,
            .{ allocator, random_data.generated, null },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    try printer.writer().writeAll("RLP Encoding... ");

    {
        const random_data = try generator.generateRandomData(struct { u256, []const u8, bool }, allocator, 0, .{});
        defer random_data.deinit();

        const result = try benchmark.benchmark(
            allocator,
            encodeRlp,
            .{ allocator, random_data.generated },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    try printer.writer().writeAll("ABI Encoding... ");
    {
        const result = try benchmark.benchmark(
            allocator,
            encodeAbiParameters,
            .{ constants.params, allocator, constants.items },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    try printer.writer().writeAll("ABI Logs Encoding... ");
    {
        const event: Event = .{
            .type = .event,
            .name = "Foo",
            .inputs = &.{
                .{ .type = .{ .uint = 256 }, .indexed = true, .name = "a" },
                .{ .type = .{ .int = 256 }, .indexed = true, .name = "b" },
                .{ .type = .{ .bool = {} }, .indexed = true, .name = "c" },
                .{ .type = .{ .fixedBytes = 5 }, .indexed = true, .name = "d" },
            },
        };

        const result = try benchmark.benchmark(allocator, zabi_root.encoding.logs_encoding.encodeLogTopics, .{
            allocator,
            event,
            .{ 69, -420, true, "01234" },
        }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }
}

/// Custom writer that we use to write tests result and with specific tty colors.
fn ColorWriter(comptime UnderlayingWriter: type) type {
    return struct {
        /// Set of possible errors from this writer.
        const Error = UnderlayingWriter.Error || std.os.windows.SetConsoleTextAttributeError;

        const Writer = std.io.Writer(*Self, Error, write);
        const Self = @This();

        pub const BORDER = "=" ** 80;
        pub const PADDING = " " ** 35;

        /// The writer that we will use to write to.
        underlaying_writer: UnderlayingWriter,
        /// Zig color tty config.
        color: ZigColor,
        /// Next tty color to apply in the stream.
        next_color: TerminalColors,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
        /// Write function that will write to the stream with the `next_color`.
        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (bytes.len == 0)
                return bytes.len;

            try self.applyColor(self.next_color);
            try self.writeNoColor(bytes);
            try self.applyColor(.reset);

            return bytes.len;
        }
        /// Writes the test boarder with the specified module.
        pub fn writeBoarder(self: *Self, module: @Type(.{ .enum_literal = {} })) Error!void {
            try self.applyColor(.green);
            try self.underlaying_writer.print("\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, @tagName(module), BORDER });
            try self.applyColor(.reset);
        }
        /// Sets the next color in the stream
        pub fn setNextColor(self: *Self, next: TerminalColors) void {
            self.next_color = next;
        }
        /// Writes the next color to the stream.
        pub fn applyColor(self: *Self, color: TerminalColors) Error!void {
            try self.color.renderOptions().ttyconf.setColor(self.underlaying_writer, color);
        }
        /// Writes to the stream without colors.
        pub fn writeNoColor(self: *Self, bytes: []const u8) UnderlayingWriter.Error!void {
            if (bytes.len == 0)
                return;

            try self.underlaying_writer.writeAll(bytes);
        }
    };
}
