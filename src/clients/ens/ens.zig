const abi_ens = @import("abi_ens.zig");
const block = @import("../../types/block.zig");
const clients = @import("../../root.zig");
const decoder = @import("../../decoding/decoder.zig");
const ens_utils = @import("ens_utils.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

const AbiDecoded = decoder.AbiDecoded;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const BlockNumberRequest = block.BlockNumberRequest;
const Clients = clients.clients.wallet.WalletClients;
const EnsContracts = @import("contracts.zig").EnsContracts;
const Hex = types.Hex;
const InitOptsHttp = PubClient.InitOptions;
const InitOptsWs = WebSocketClient.InitOptions;
const InitOptsIpc = IpcClient.InitOptions;
const IpcClient = clients.clients.IpcClient;
const PubClient = clients.clients.PubClient;
const RPCResponse = types.RPCResponse;
const WebSocketClient = clients.clients.WebSocket;

/// A public client that interacts with the ENS contracts.
///
/// Currently ENSAvatar is not supported but will be in future versions.
pub fn ENSClient(comptime client_type: Clients) type {
    return struct {
        const ENS = @This();

        /// The underlaying rpc client type (ws or http)
        const ClientType = switch (client_type) {
            .http => PubClient,
            .websocket => WebSocketClient,
            .ipc => IpcClient,
        };

        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
            .ipc => InitOptsIpc,
        };

        /// This is the same allocator as the rpc_client.
        /// Its a field mostly for convinience
        allocator: Allocator,
        /// The http or ws client that will be use to query the rpc server
        rpc_client: *ClientType,
        /// ENS contracts to be used by this client.
        ens_contracts: EnsContracts,

        /// Starts the RPC connection
        /// If the contracts are null it defaults to mainnet contracts.
        pub fn init(opts: InitOpts, ens_contracts: ?EnsContracts) !*ENS {
            const self = try opts.allocator.create(ENS);
            errdefer opts.allocator.destroy(self);

            if (opts.chain_id) |id| {
                switch (id) {
                    .ethereum, .sepolia => {},
                    else => return error.InvalidChain,
                }
            }

            self.* = .{
                .rpc_client = try ClientType.init(opts),
                .allocator = opts.allocator,
                .ens_contracts = ens_contracts orelse .{},
            };

            return self;
        }
        /// Frees and destroys any allocated memory
        pub fn deinit(self: *ENS) void {
            self.rpc_client.deinit();
            const allocator = self.allocator;
            allocator.destroy(self);
        }
        /// Gets the ENS address associated with the ENS name.
        ///
        /// Caller owns the memory if the request is successfull.
        /// Calls the resolver address and decodes with address resolver.
        ///
        /// The names are not normalized so make sure that the names are normalized before hand.
        pub fn getEnsAddress(self: *ENS, name: []const u8, opts: BlockNumberRequest) !AbiDecoded(Address) {
            const hash = try ens_utils.hashName(name);

            const encoded = try abi_ens.addr_resolver.encode(self.allocator, .{hash});
            defer self.allocator.free(encoded);

            var buffer: [1024]u8 = undefined;
            const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

            const resolver_encoded = try abi_ens.resolver.encode(self.allocator, .{ buffer[0..bytes_read], encoded });
            defer self.allocator.free(resolver_encoded);

            const value = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.ens_contracts.ensUniversalResolver,
                .data = resolver_encoded,
            } }, opts);
            defer value.deinit();

            if (value.response.len == 0)
                return error.EvmFailedToExecute;

            const decoded = try decoder.decodeAbiParameter(struct { []u8, [20]u8 }, self.allocator, value.response, .{ .allow_junk_data = true, .allocate_when = .alloc_always });
            defer decoded.deinit();

            if (decoded.result[0].len == 0)
                return error.FailedToDecodeResponse;

            const decoded_result = try decoder.decodeAbiParameter([20]u8, self.allocator, decoded.result[0], .{ .allow_junk_data = true, .allocate_when = .alloc_always });

            if (decoded_result.result.len == 0)
                return error.FailedToDecodeResponse;

            return decoded_result;
        }
        /// Gets the ENS name associated with the address.
        ///
        /// Caller owns the memory if the request is successfull.
        /// Calls the reverse resolver and decodes with the same.
        ///
        /// This will fail if its not a valid checksumed address.
        pub fn getEnsName(self: *ENS, address: []const u8, opts: BlockNumberRequest) !RPCResponse([]const u8) {
            if (!utils.isAddress(address))
                return error.InvalidAddress;

            var address_reverse: [53]u8 = undefined;
            var buf: [40]u8 = undefined;
            _ = std.ascii.lowerString(&buf, address[2..]);

            @memcpy(address_reverse[0..40], buf[0..40]);
            @memcpy(address_reverse[40..], ".addr.reverse");

            var buffer: [100]u8 = undefined;
            const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], address_reverse[0..]);

            const encoded = try abi_ens.reverse_resolver.encode(self.allocator, .{buffer[0..bytes_read]});
            defer self.allocator.free(encoded);

            const value = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.ens_contracts.ensUniversalResolver,
                .data = encoded,
            } }, opts);
            defer value.deinit();

            const address_bytes = try utils.addressToBytes(address);

            if (value.response.len == 0)
                return error.EvmFailedToExecute;

            const decoded = try decoder.decodeAbiParameter(struct { []u8, [20]u8, [20]u8, [20]u8 }, self.allocator, value.response, .{ .allocate_when = .alloc_always });
            errdefer decoded.deinit();

            if (!std.mem.eql(u8, &address_bytes, &decoded.result[1]))
                return error.InvalidAddress;

            return RPCResponse([]const u8).fromJson(decoded.arena, decoded.result[0]);
        }
        /// Gets the ENS resolver associated with the name.
        ///
        /// Caller owns the memory if the request is successfull.
        /// Calls the find resolver and decodes with the same one.
        ///
        /// The names are not normalized so make sure that the names are normalized before hand.
        pub fn getEnsResolver(self: *ENS, name: []const u8, opts: BlockNumberRequest) !Address {
            var buffer: [1024]u8 = undefined;
            const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

            const encoded = try abi_ens.find_resolver.encode(self.allocator, .{buffer[0..bytes_read]});
            defer self.allocator.free(encoded);

            const value = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.ens_contracts.ensUniversalResolver,
                .data = encoded,
            } }, opts);
            defer value.deinit();

            const decoded = try decoder.decodeAbiParameterLeaky(struct { Address, [32]u8 }, self.allocator, value.response, .{ .allow_junk_data = true });

            return decoded[0];
        }
        /// Gets a text record for a specific ENS name.
        ///
        /// Caller owns the memory if the request is successfull.
        /// Calls the resolver and decodes with the text resolver.
        ///
        /// The names are not normalized so make sure that the names are normalized before hand.
        pub fn getEnsText(self: *ENS, name: []const u8, key: []const u8, opts: BlockNumberRequest) !AbiDecoded([]const u8) {
            var buffer: [1024]u8 = undefined;
            const bytes_read = ens_utils.convertEnsToBytes(buffer[0..], name);

            const hash = try ens_utils.hashName(name);
            const text_encoded = try abi_ens.text_resolver.encode(self.allocator, .{ hash, key });
            defer self.allocator.free(text_encoded);

            const encoded = try abi_ens.resolver.encode(self.allocator, .{ buffer[0..bytes_read], text_encoded });
            defer self.allocator.free(encoded);

            const value = try self.rpc_client.sendEthCall(.{ .london = .{
                .to = self.ens_contracts.ensUniversalResolver,
                .data = encoded,
            } }, opts);
            errdefer value.deinit();

            if (value.response.len == 0)
                return error.EvmFailedToExecute;

            const decoded = try decoder.decodeAbiParameter(struct { []u8, Address }, self.allocator, value.response, .{});
            defer decoded.deinit();

            const decoded_text = try decoder.decodeAbiParameter([]const u8, self.allocator, decoded.result[0], .{ .allocate_when = .alloc_always });
            errdefer decoded_text.deinit();

            if (decoded_text.result.len == 0)
                return error.FailedToDecodeResponse;

            return decoded_text;
        }
    };
}
