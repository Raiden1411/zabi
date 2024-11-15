const std = @import("std");
const utils = @import("zabi").utils.utils;

const NetworkConfig = @import("zabi").clients.network.NetworkConfig;
const Uri = std.Uri;

pub const anvil_mainnet: NetworkConfig = .{
    .endpoint = .{ .uri = Uri.parse("http://localhost:6969/") catch unreachable },
    .chain_id = .ethereum,
    .op_stack_contracts = .{},
    .ens_contracts = .{},
};

pub const anvil_op_sepolia: NetworkConfig = .{
    .endpoint = .{ .uri = Uri.parse("http://localhost:6969/") catch unreachable },
    .chain_id = .op_sepolia,
    .op_stack_contracts = .{
        .portalAddress = utils.addressToBytes("0x16Fc5058F25648194471939df75CF27A2fdC48BC") catch unreachable,
        .disputeGameFactory = utils.addressToBytes("0x05F9613aDB30026FFd634f38e5C4dFd30a197Fa1") catch unreachable,
    },
};

pub const anvil_sepolia: NetworkConfig = .{
    .endpoint = .{ .uri = Uri.parse("http://localhost:6969/") catch unreachable },
    .chain_id = .sepolia,
    .op_stack_contracts = .{
        .portalAddress = utils.addressToBytes("0x16Fc5058F25648194471939df75CF27A2fdC48BC") catch unreachable,
        .disputeGameFactory = utils.addressToBytes("0x05F9613aDB30026FFd634f38e5C4dFd30a197Fa1") catch unreachable,
    },
};
