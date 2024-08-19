const abi = zabi.abi;
const args_parser = zabi.args;
const human = zabi.human_readable.parsing;
const std = @import("std");
const utils = zabi.utils;
const zabi = @import("zabi");

const Abi = abi.abitypes.Abi;
const Contract = zabi.clients.contract.Contract(.http);
const Wallet = zabi.clients.wallet.Wallet(.http);

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    const slice =
        \\  function transfer(address to, uint256 amount)
        \\  function approve(address operator, uint256 size) external returns (bool)
        \\  function balanceOf(address owner) public view returns (uint256)
    ;
    var abi_parsed = try human.parseHumanReadable(Abi, gpa.allocator(), slice);
    defer abi_parsed.deinit();

    var contract = try Contract.init(.{
        .private_key = parsed.priv_key,
        .abi = abi_parsed.value,
        .wallet_opts = .{
            .allocator = gpa.allocator(),
            .uri = uri,
        },
    });
    defer contract.deinit();

    const approve = try contract.writeContractFunction("transfer", .{ try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), 0 }, .{
        .type = .london,
        .to = try utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
    });
    defer approve.deinit();

    var receipt = try contract.wallet.waitForTransactionReceipt(approve.response, 0);
    defer receipt.deinit();

    const hash = switch (receipt.response) {
        inline else => |tx_receipt| tx_receipt.transactionHash,
    };

    std.debug.print("Transaction receipt: {s}", .{std.fmt.fmtSliceHexLower(&hash)});

    const balance = try contract.readContractFunction(u256, "balanceOf", .{contract.wallet.getWalletAddress()}, .{
        .london = .{
            .to = try utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        },
    });
    defer balance.deinit();

    std.debug.print("BALANCE: {d}\n", .{balance.result});
}
