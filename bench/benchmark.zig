const benchmark = @import("Benchmark.zig");
const std = @import("std");
const zabi_root = @import("zabi");

const bench_log = std.log.scoped(.bench);

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    bench_log.debug("Starting benchmark runner...", .{});
    bench_log.debug("Benchmarking parsing Seaport\n", .{});

    const slice =
        \\constructor(address conduitController)
        \\struct OfferItem { uint8 itemType; address token; uint256 identifierOrCriteria; uint256 startAmount; uint256 endAmount; }
        \\struct AdditionalRecipient { uint256 amount; address recipient; }
        \\struct SpentItem { uint8 itemType; address token; uint256 identifier; uint256 amount; }
        \\struct ReceivedItem { uint8 itemType; address token; uint256 identifier; uint256 amount; address recipient; }
        \\struct ConsiderationItem { uint8 itemType; address token; uint256 identifierOrCriteria; uint256 startAmount; uint256 endAmount; address recipient; }
        \\struct CriteriaResolver { uint256 orderIndex; uint8 side; uint256 index; uint256 identifier; bytes32[] criteriaProof; }
        \\struct FulfillmentComponent { uint256 orderIndex; uint256 itemIndex; }
        \\struct Fulfillment { FulfillmentComponent[] offerComponents; FulfillmentComponent[] considerationComponents; }
        \\struct OrderComponents { address offerer; address zone; OfferItem[] offer; ConsiderationItem[] consideration; uint8 orderType; uint256 startTime; uint256 endTime; bytes32 zoneHash; uint256 salt; bytes32 conduitKey; uint256 counter; }
        \\struct OrderParameters { address offerer; address zone; OfferItem[] offer; ConsiderationItem[] consideration; uint8 orderType; uint256 startTime; uint256 endTime; bytes32 zoneHash; uint256 salt; bytes32 conduitKey; uint256 totalOriginalConsiderationItems; }
        \\struct Order { OrderParameters parameters; bytes signature; }
        \\struct OrderStatus { bool isValidated; bool isCancelled; uint120 numerator; uint120 denominator; }
        \\struct AdvancedOrder { OrderParameters parameters; uint120 numerator; uint120 denominator; bytes signature; bytes extraData; }
        \\struct Execution { ReceivedItem item; address offerer; bytes32 conduitKey; }
        \\struct BasicOrderParameters { address considerationToken; uint256 considerationIdentifier; uint256 considerationAmount; address offerer; address zone; address offerToken; uint256 offerIdentifier; uint256 offerAmount; uint8 basicOrderType; uint256 startTime; uint256 endTime; bytes32 zoneHash; uint256 salt; bytes32 offererConduitKey; bytes32 fulfillerConduitKey; uint256 totalOriginalAdditionalRecipients; AdditionalRecipient[] additionalRecipients; bytes signature; }
        \\function cancel(OrderComponents[] orders) external returns (bool cancelled)
        \\function fulfillBasicOrder(BasicOrderParameters parameters) external payable returns (bool fulfilled)
        \\function fulfillBasicOrder_efficient_6GL6yc(BasicOrderParameters parameters) external payable returns (bool fulfilled)
        \\function fulfillOrder(Order order, bytes32 fulfillerConduitKey) external payable returns (bool fulfilled)
        \\function fulfillAdvancedOrder(AdvancedOrder advancedOrder, CriteriaResolver[] criteriaResolvers, bytes32 fulfillerConduitKey, address recipient) external payable returns (bool fulfilled)
        \\function fulfillAvailableOrders(Order[] orders, FulfillmentComponent[][] offerFulfillments, FulfillmentComponent[][] considerationFulfillments, bytes32 fulfillerConduitKey, uint256 maximumFulfilled) external payable returns (bool[] availableOrders, Execution[] executions)
        \\function fulfillAvailableAdvancedOrders(AdvancedOrder[] advancedOrders, CriteriaResolver[] criteriaResolvers, FulfillmentComponent[][] offerFulfillments, FulfillmentComponent[][] considerationFulfillments, bytes32 fulfillerConduitKey, address recipient, uint256 maximumFulfilled) external payable returns (bool[] availableOrders, Execution[] executions)
        \\function getContractOffererNonce(address contractOfferer) external view returns (uint256 nonce)
        \\function getOrderHash(OrderComponents order) external view returns (bytes32 orderHash)
        \\function getOrderStatus(bytes32 orderHash) external view returns (bool isValidated, bool isCancelled, uint256 totalFilled, uint256 totalSize)
        \\function getCounter(address offerer) external view returns (uint256 counter)
        \\function incrementCounter() external returns (uint256 newCounter)
        \\function information() external view returns (string version, bytes32 domainSeparator, address conduitController)
        \\function name() external view returns (string contractName)
        \\function matchAdvancedOrders(AdvancedOrder[] orders, CriteriaResolver[] criteriaResolvers, Fulfillment[] fulfillments) external payable returns (Execution[] executions)
        \\function matchOrders(Order[] orders, Fulfillment[] fulfillments) external payable returns (Execution[] executions)
        \\function validate(Order[] orders) external returns (bool validated)
        \\event CounterIncremented(uint256 newCounter, address offerer)
        \\event OrderCancelled(bytes32 orderHash, address offerer, address zone)
        \\event OrderFulfilled(bytes32 orderHash, address offerer, address zone, address recipient, SpentItem[] offer, ReceivedItem[] consideration)
        \\event OrdersMatched(bytes32[] orderHashes)
        \\event OrderValidated(bytes32 orderHash, address offerer, address zone)
        \\error BadContractSignature()
        \\error BadFraction()
        \\error BadReturnValueFromERC20OnTransfer(address token, address from, address to, uint amount)
        \\error BadSignatureV(uint8 v)
        \\error CannotCancelOrder()
        \\error ConsiderationCriteriaResolverOutOfRange()
        \\error ConsiderationLengthNotEqualToTotalOriginal()
        \\error ConsiderationNotMet(uint orderIndex, uint considerationAmount, uint shortfallAmount)
        \\error CriteriaNotEnabledForItem()
        \\error ERC1155BatchTransferGenericFailure(address token, address from, address to, uint[] identifiers, uint[] amounts)
        \\error InexactFraction()
        \\error InsufficientNativeTokensSupplied()
        \\error Invalid1155BatchTransferEncoding()
        \\error InvalidBasicOrderParameterEncoding()
        \\error InvalidCallToConduit(address conduit)
        \\error InvalidConduit(bytes32 conduitKey, address conduit)
        \\error InvalidContractOrder(bytes32 orderHash)
        \\error InvalidERC721TransferAmount(uint256 amount)
        \\error InvalidFulfillmentComponentData()
        \\error InvalidMsgValue(uint256 value)
        \\error InvalidNativeOfferItem()
        \\error InvalidProof()
        \\error InvalidRestrictedOrder(bytes32 orderHash)
        \\error InvalidSignature()
        \\error InvalidSigner()
        \\error InvalidTime(uint256 startTime, uint256 endTime)
        \\error MismatchedFulfillmentOfferAndConsiderationComponents(uint256 fulfillmentIndex)
        \\error MissingFulfillmentComponentOnAggregation(uint8 side)
        \\error MissingItemAmount()
        \\error MissingOriginalConsiderationItems()
        \\error NativeTokenTransferGenericFailure(address account, uint256 amount)
        \\error NoContract(address account)
        \\error NoReentrantCalls()
        \\error NoSpecifiedOrdersAvailable()
        \\error OfferAndConsiderationRequiredOnFulfillment()
        \\error OfferCriteriaResolverOutOfRange()
        \\error OrderAlreadyFilled(bytes32 orderHash)
        \\error OrderCriteriaResolverOutOfRange(uint8 side)
        \\error OrderIsCancelled(bytes32 orderHash)
        \\error OrderPartiallyFilled(bytes32 orderHash)
        \\error PartialFillsNotEnabledForOrder()
        \\error TokenTransferGenericFailure(address token, address from, address to, uint identifier, uint amount)
        \\error UnresolvedConsiderationCriteria(uint orderIndex, uint considerationIndex)
        \\error UnresolvedOfferCriteria(uint256 orderIndex, uint256 offerIndex)
        \\error UnusedItemParameters()
    ;

    {
        const result = try benchmark.benchmark(allocator, zabi_root.human_readable.parsing.parseHumanReadable, .{ zabi_root.abi.abitypes.Abi, allocator, slice }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Steping throw encoding functions...", .{});
    bench_log.debug("Serialize...", .{});
    {
        const access: []const zabi_root.types.transactions.AccessList = &.{};
        const result = try benchmark.benchmark(allocator, zabi_root.encoding.serialize.serializeTransaction, .{ allocator, .{ .london = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try zabi_root.utils.parseGwei(2), .maxFeePerGas = try zabi_root.utils.parseGwei(2), .gas = 0, .to = try zabi_root.utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .value = try zabi_root.utils.parseEth(1), .data = null, .accessList = access } }, null }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("RLP...", .{});
    {
        const result = try benchmark.benchmark(allocator, zabi_root.encoding.rlp.encodeRlp, .{ allocator, .{ 69, "FOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO" } }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Abi...", .{});
    {
        const params: []const zabi_root.abi.abi_parameter.AbiParameter = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }};
        const items: zabi_root.meta.abi.AbiParametersToPrimative(params) = .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }};

        const result = try benchmark.benchmark(allocator, zabi_root.encoding.abi_encoding.encodeAbiParameters, .{ allocator, params, items }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Abi Logs...", .{});
    {
        const event = try zabi_root.human_readable.parsing.parseHumanReadable(zabi_root.abi.abitypes.Event, allocator, "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)");
        defer event.deinit();

        const result = try benchmark.benchmark(allocator, zabi_root.encoding.logs_encoding.encodeLogs, .{ allocator, event.value, .{ 69, -420, true, "01234" } }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Steping throw decoding functions...", .{});
    bench_log.debug("Parse...", .{});
    {
        const access: []const zabi_root.types.transactions.AccessList = &.{};
        const encoded = try zabi_root.encoding.serialize.serializeTransaction(allocator, .{ .london = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try zabi_root.utils.parseGwei(2), .maxFeePerGas = try zabi_root.utils.parseGwei(2), .gas = 0, .to = try zabi_root.utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .value = try zabi_root.utils.parseEth(1), .data = null, .accessList = access } }, null);
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(allocator, zabi_root.decoding.parse_transacition.parseTransaction, .{ allocator, encoded }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("RLP...", .{});
    {
        const multi: std.meta.Tuple(&[_]type{ u8, bool, []const u8 }) = .{ 127, false, "foobar" };
        const encoded = try zabi_root.encoding.rlp.encodeRlp(allocator, .{multi});
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(allocator, zabi_root.decoding.rlp.decodeRlp, .{ allocator, struct { u8, bool, []const u8 }, encoded }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Abi...", .{});
    {
        const params: []const zabi_root.abi.abi_parameter.AbiParameter = &.{.{ .type = .{ .tuple = {} }, .name = "fizzbuzz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .string = {} } }, .name = "foo" }, .{ .type = .{ .uint = 256 }, .name = "bar" }, .{ .type = .{ .dynamicArray = &.{ .tuple = {} } }, .name = "baz", .components = &.{ .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "fizz" }, .{ .type = .{ .bool = {} }, .name = "buzz" }, .{ .type = .{ .dynamicArray = &.{ .int = 256 } }, .name = "jazz" } } } } }};
        const items: zabi_root.meta.abi.AbiParametersToPrimative(params) = .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }};

        const encoded = try zabi_root.encoding.abi_encoding.encodeAbiParameters(allocator, params, items);
        defer encoded.deinit();

        const hexed = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded.data)});
        defer allocator.free(hexed);

        const result = try benchmark.benchmark(allocator, zabi_root.decoding.abi_decoder.decodeAbiParameters, .{ allocator, params, hexed, .{} }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    bench_log.debug("Abi Logs...", .{});
    {
        const event = try zabi_root.human_readable.parsing.parseHumanReadable(zabi_root.abi.abitypes.Event, allocator, "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)");
        defer event.deinit();

        const encoded = try zabi_root.encoding.logs_encoding.encodeLogs(allocator, event.value, .{ 69, -420, true, "01234" });
        defer encoded.deinit();

        const result = try benchmark.benchmark(allocator, zabi_root.decoding.logs_decoder.decodeLogs, .{ allocator, struct { []const u8, u256, i256, bool, [5]u8 }, event.value, encoded.data }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }
}
