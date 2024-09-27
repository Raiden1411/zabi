const benchmark = @import("BenchmarkType.zig");
const constants = @import("constants.zig");
const std = @import("std");
const zabi_root = @import("zabi");
const generator = zabi_root.generator;

// Types
const Ast = zabi_root.ast.Ast;
const Allocator = std.mem.Allocator;
const Event = zabi_root.abi.abitypes.Event;
const HDWalletNode = zabi_root.hdwallet.HDWalletNode;
const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;
const HttpRpcClient = zabi_root.clients.PubClient;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Signer = zabi_root.Signer;
const TransactionEnvelope = zabi_root.types.transactions.TransactionEnvelope;

// Functions
const decodeAbiParameter = zabi_root.decoding.abi_decoder.decodeAbiParameter;
const decodeLogs = zabi_root.decoding.logs_decoder.decodeLogs;
const decodeRlp = zabi_root.decoding.rlp.decodeRlp;
const encodeAbiParameters = zabi_root.encoding.abi_encoding.encodeAbiParameters;
const encodeLogTopics = zabi_root.encoding.logs_encoding.encodeLogTopics;
const encodeRlp = zabi_root.encoding.rlp.encodeRlp;
const fromEntropy = zabi_root.mnemonic.fromEntropy;
const parseTransaction = zabi_root.decoding.parse_transacition.parseTransaction;
const parseHumanReadable = zabi_root.human_readable.parsing.parseHumanReadable;
const serializeTransaction = zabi_root.encoding.serialize.serializeTransaction;
const toEntropy = zabi_root.mnemonic.toEntropy;

const BORDER = "=" ** 80;
const PADDING = " " ** 35;

pub const std_options: std.Options = .{
    .log_level = .info,
};

const BenchmarkPrinter = struct {
    writer: std.fs.File.Writer,

    fn init(writer: std.fs.File.Writer) BenchmarkPrinter {
        return .{ .writer = writer };
    }

    fn fmt(self: BenchmarkPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch unreachable;
    }

    fn print(self: BenchmarkPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch @panic("Format failed!");
        self.fmt("\x1b[0m", .{});
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const printer = BenchmarkPrinter.init(std.io.getStdErr().writer());

    const uri = try std.Uri.parse("https://ethereum-rpc.publicnode.com");

    var client = try HttpRpcClient.init(.{
        .allocator = allocator,
        .network_config = .{ .endpoint = .{ .uri = uri } },
    });
    defer client.deinit();

    printer.print("{s}Benchmark running in {s} mode\n", .{ " " ** 20, @tagName(@import("builtin").mode) });
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Human-Readable ABI", BORDER });

    {
        const opts = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            const abi = try zabi_root.human_readable.parsing.parseHumanReadable(zabi_root.abi.abitypes.Abi, allocator, constants.slice);
            defer abi.deinit();
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            const abi = try zabi_root.human_readable.parsing.parseHumanReadable(zabi_root.abi.abitypes.Abi, allocator, constants.slice);
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

    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Http Client", BORDER });
    {
        printer.print("Get ChainId...", .{});
        const result = try benchmark.benchmark(
            allocator,
            HttpRpcClient.getChainId,
            .{client},
            .{ .runs = 5, .warmup_runs = 1 },
        );
        result.printSummary();
    }

    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Solidity AST", BORDER });
    {
        printer.print("Parsing solidity...", .{});

        const opts = .{ .warmup_runs = 5, .runs = 100 };

        const slice =
            \\   uint constant foo = 69;
            \\   struct Voter {
            \\       uint weight; // weight is accumulated by delegation
            \\       bool voted;  // if true, that person already voted
            \\       address delegate; // person delegated to
            \\       uint vote;   // index of the voted proposal
            \\   }
            \\
            \\       contract Ballot {
            \\   struct Voter {
            \\       uint weight; // weight is accumulated by delegation
            \\       bool voted;  // if true, that person already voted
            \\       address delegate; // person delegated to
            \\       uint vote;   // index of the voted proposal
            \\   }
            \\
            \\   struct Proposal {
            \\       // If you can limit the length to a certain number of bytes,
            \\       // always use one of bytes1 to bytes32 because they are much cheaper
            \\       bytes32 name;   // short name (up to 32 bytes)
            \\       uint voteCount; // number of accumulated votes
            \\   }
            \\
            \\   address public chairperson;
            \\
            \\   mapping(address => Voter) public voters;
            \\
            \\   Proposal[] public proposals;
            \\
            \\   /**
            \\    * @dev Create a new ballot to choose one of 'proposalNames'.
            \\    * @param proposalNames names of proposals
            \\    */
            \\   constructor(bytes32[] memory proposalNames) {
            \\       chairperson = msg.sender;
            \\       voters[chairperson].weight = 1;
            \\
            \\       for (uint i = 0; i < proposalNames.length; i++) {
            \\           // 'Proposal({...})' creates a temporary
            \\           // Proposal object and 'proposals.push(...)'
            \\           // appends it to the end of 'proposals'.
            \\           proposals.push(Proposal({
            \\               name: proposalNames[i],
            \\               voteCount: 0
            \\           }));
            \\       }
            \\ }
            \\
            \\   /**
            \\    * @dev Give 'voter' the right to vote on this ballot. May only be called by 'chairperson'.
            \\    * @param voter address of voter
            \\    */
            \\   function giveRightToVote(address voter) public {
            \\       require(
            \\           msg.sender == chairperson,
            \\           "Only chairperson can give right to vote."
            \\       );
            \\       require(
            \\           !voters[voter].voted,
            \\           "The voter already voted."
            \\       );
            \\       require(voters[voter].weight == 0);
            \\       voters[voter].weight = 1;
            \\   }
            \\
            \\   /**
            \\    * @dev Delegate your vote to the voter 'to'.
            \\    * @param to address to which vote is delegated
            \\    */
            \\   function delegate(address to) public {
            \\       Voter storage sender = voters[msg.sender];
            \\       require(!sender.voted, "You already voted.");
            \\       require(to != msg.sender, "Self-delegation is disallowed.");
            \\
            \\       while (voters[to].delegate != address(0)) {
            \\           to = voters[to].delegate;
            \\
            \\           // We found a loop in the delegation, not allowed.
            \\           require(to != msg.sender, "Found loop in delegation.");
            \\       }
            \\       sender.voted = true;
            \\       sender.delegate = to;
            \\       Voter storage delegate_ = voters[to];
            \\       if (delegate_.voted) {
            \\           // If the delegate already voted,
            \\           // directly add to the number of votes
            \\           proposals[delegate_.vote].voteCount += sender.weight;
            \\       } else {
            \\           // If the delegate did not vote yet,
            \\           // add to her weight.
            \\           delegate_.weight += sender.weight;
            \\       }
            \\    }
            \\
            \\   /**
            \\    * @dev Give your vote (including votes delegated to you) to proposal 'proposals[proposal].name'.
            \\    * @param proposal index of proposal in the proposals array
            \\    */
            \\   function vote(uint proposal) public {
            \\       Voter storage sender = voters[msg.sender];
            \\       require(sender.weight != 0, "Has no right to vote");
            \\       require(!sender.voted, "Already voted.");
            \\       sender.voted = true;
            \\       sender.vote = proposal;
            \\
            \\       // If 'proposal' is out of the range of the array,
            \\       // this will throw automatically and revert all
            \\       // changes.
            \\       proposals[proposal].voteCount += sender.weight;
            \\   }
            \\
            \\   /**
            \\    * @dev Computes the winning proposal taking all previous votes into account.
            \\    * @return winningProposal_ index of winning proposal in the proposals array
            \\    */
            \\   function winningProposal() public view
            \\           returns (uint winningProposal_)
            \\   {
            \\       uint winningVoteCount = 0;
            \\       for (uint p = 0; p < proposals.length; p++) {
            \\           if (proposals[p].voteCount > winningVoteCount) {
            \\               winningVoteCount = proposals[p].voteCount;
            \\               winningProposal_ = p;
            \\               fooo.send{value: msg.value}(p);
            \\           }
            \\       }
            \\   }
            \\
            \\
            \\   /**
            \\    * @dev Calls winningProposal() function to get the index of the winner contained in the proposals array and then
            \\    * @return winnerName_ the name of the winner
            \\    */
            \\   function winnerName(address foo, uint bar, uint jazz)
            \\   {
            \\       winnerName_ = proposals[winningProposal({foo: bar, jazz: baz})].name;
            \\   }
            \\}
        ;

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            var ast = try Ast.parse(allocator, slice);
            defer ast.deinit(allocator);
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            var ast = try Ast.parse(allocator, slice);
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

    try encodingFunctions(allocator, printer);
    try decodingFunctions(allocator, printer);
    try signerMethods(allocator, printer);
}

pub fn signerMethods(allocator: Allocator, printer: BenchmarkPrinter) !void {
    var buffer: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    const signer = try Signer.init(buffer);

    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Signer", BORDER });

    const start = "\x19Ethereum Signed Message:\n";
    const concated_message = try std.fmt.allocPrint(allocator, "{s}{d}{s}", .{ start, "Hello World!".len, "Hello World!" });
    defer allocator.free(concated_message);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(concated_message, &hash, .{});

    {
        printer.print("Ethereum message...", .{});
        const result = try benchmark.benchmark(
            allocator,
            Signer.sign,
            .{ signer, hash },
            .{ .runs = 100, .warmup_runs = 5 },
        );
        result.printSummary();
    }
    {
        printer.print("Verify message...", .{});
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
        printer.print("Recover Address...", .{});
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
        printer.print("Recover Public Key...", .{});
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
        printer.print("HDWallet Node...", .{});
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
        printer.print("Mnemonic Entropy...", .{});
        const seed = "test test test test test test test test test test test junk";

        const opts = .{ .warmup_runs = 5, .runs = 100 };

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
        printer.print("From Mnemonic Entropy...", .{});
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
pub fn decodingFunctions(allocator: Allocator, printer: BenchmarkPrinter) !void {
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "DECODING", BORDER });
    printer.print("Parse serialized transaction... ", .{});

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

    printer.print("RLP Decoding...", .{});
    {
        const multi: std.meta.Tuple(&[_]type{ u8, bool, []const u8 }) = .{ 127, false, "foobar" };

        const encoded = try encodeRlp(allocator, multi);
        defer allocator.free(encoded);

        const opts = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            _ = try zabi_root.decoding.rlp.decodeRlp(allocator, @TypeOf(multi), encoded);
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            _ = try zabi_root.decoding.rlp.decodeRlp(allocator, @TypeOf(multi), encoded);
        }

        const mean = @divFloor(timer.lap(), opts.runs);

        const result: benchmark.BenchmarkResult = .{
            .allocator = allocator,
            .opts = opts,
            .mean = mean,
        };
        result.printSummary();
    }

    printer.print("Abi Decoding... ", .{});
    {
        const encoded = try encodeAbiParameters(allocator, constants.params, constants.items);
        defer encoded.deinit();

        const opts = .{ .warmup_runs = 5, .runs = 100 };

        var count: usize = 0;
        while (count < opts.warmup_runs) : (count += 1) {
            const abi = try zabi_root.decoding.abi_decoder.decodeAbiParameter(
                zabi_root.meta.abi.AbiParametersToPrimative(constants.params),
                allocator,
                encoded.data,
                .{},
            );
            defer abi.deinit();
        }

        var timer = try std.time.Timer.start();
        while (count < opts.runs) : (count += 1) {
            const abi = try zabi_root.decoding.abi_decoder.decodeAbiParameter(
                zabi_root.meta.abi.AbiParametersToPrimative(constants.params),
                allocator,
                encoded.data,
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

    printer.print("Abi Logs Decoding... ", .{});
    {
        const event = try parseHumanReadable(
            Event,
            allocator,
            "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)",
        );
        defer event.deinit();

        const encoded = try encodeLogTopics(
            allocator,
            event.value,
            .{ 69, -420, true, "01234" },
        );
        defer allocator.free(encoded);

        const opts = .{ .warmup_runs = 5, .runs = 100 };

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
pub fn encodingFunctions(allocator: Allocator, printer: BenchmarkPrinter) !void {
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "ENCODING", BORDER });
    printer.print("Serialize Transaction... ", .{});
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

    printer.print("RLP Encoding... ", .{});

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

    printer.print("ABI Encoding... ", .{});
    {
        const result = try benchmark.benchmark(
            allocator,
            encodeAbiParameters,
            .{ allocator, constants.params, constants.items },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("ABI Logs Encoding... ", .{});
    {
        const event = try parseHumanReadable(
            Event,
            allocator,
            "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)",
        );
        defer event.deinit();

        const result = try benchmark.benchmark(allocator, zabi_root.encoding.logs_encoding.encodeLogTopics, .{
            allocator,
            event.value,
            .{ 69, -420, true, "01234" },
        }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }
}
