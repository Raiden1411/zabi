const abi = @import("../abi/abi.zig");
const param = @import("../abi/abi_parameter.zig");
const std = @import("std");
const testing = std.testing;
const tokens = @import("tokens.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Extract = @import("../meta/utils.zig").Extract;
const ParamType = @import("../abi/param_type.zig").ParamType;
const StateMutability = @import("../abi/state_mutability.zig").StateMutability;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("Parser.zig");

pub fn AbiParsed(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

/// Main function to use when wanting to use the human readable parser
/// This function will allocate and use and ArenaAllocator for its allocations
/// Caller owns the memory and must free the memory.
/// Use the handy `deinit()` method provided by the return type
///
/// The return value will depend on the abi type selected.
/// The function will return an error if the provided type doesn't match the
/// tokens from the provided signature
pub fn parseHumanReadable(comptime T: type, alloc: Allocator, source: [:0]const u8) !AbiParsed(T) {
    std.debug.assert(source.len > 0);

    var abi_parsed = AbiParsed(T){ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(abi_parsed.arena);

    abi_parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer abi_parsed.arena.deinit();

    const allocator = abi_parsed.arena.allocator();

    var lex = Lexer.init(source);
    var list = Parser.TokenList{};
    errdefer list.deinit(allocator);

    while (true) {
        const tok = lex.scan();
        try list.append(allocator, .{ .token_type = tok.syntax, .start = tok.location.start, .end = tok.location.end });

        if (tok.syntax == .EndOfFileToken) break;
    }

    var parser: Parser = .{ .alloc = allocator, .tokens = list.items(.token_type), .tokens_start = list.items(.start), .tokens_end = list.items(.end), .token_index = 0, .source = source, .structs = .{} };

    abi_parsed.value = try innerParse(T, &parser);

    return abi_parsed;
}

fn innerParse(comptime T: type, parser: *Parser) !T {
    return switch (T) {
        abi.Abi => parser.parseAbiProto(),
        abi.AbiItem => parser.parseAbiItemProto(),
        abi.Function => parser.parseFunctionFnProto(),
        abi.Event => parser.parseEventFnProto(),
        abi.Error => parser.parseErrorFnProto(),
        abi.Constructor => parser.parseConstructorFnProto(),
        abi.Fallback => parser.parseFallbackFnProto(),
        abi.Receive => parser.parseReceiveFnProto(),
        []const param.AbiParameter => parser.parseFuncParamsDecl(),
        []const param.AbiEventParameter => parser.parseEventParamsDecl(),
        inline else => @compileError("Provided type is not supported for human readable parsing"),
    };
}

test "AbiParameter" {
    const slice = "address foo";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    for (params.value) |val| {
        try testing.expectEqual(val.type, ParamType{ .address = {} });
        try testing.expectEqualStrings(val.name, "foo");
    }
}

test "AbiParameters" {
    const slice = "address foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters dynamic array" {
    const slice = "address[] foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type.dynamicArray.*);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters 2d dynamic array" {
    const slice = "address[][] foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type.dynamicArray.dynamicArray.*);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters mixed 2d array" {
    const slice = "address[5][] foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type.dynamicArray.fixedArray.child.*);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters with fixed array" {
    const slice = "address[5] foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type.fixedArray.child.*);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters with data location" {
    const slice = "string calldata foo, int120 bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .string = {} }, params.value[0].type);
    try testing.expectEqual(ParamType{ .int = 120 }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);
}

test "AbiParameters with tuple" {
    const slice = "address foo, (bytes32 baz) bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .address = {} }, params.value[0].type);
    try testing.expectEqual(ParamType{ .tuple = {} }, params.value[1].type);

    try testing.expectEqualStrings("foo", params.value[0].name);
    try testing.expectEqualStrings("bar", params.value[1].name);

    try testing.expectEqual(params.value.len, 2);

    try testing.expect(params.value[1].components != null);
    try testing.expectEqual(ParamType{ .fixedBytes = 32 }, params.value[1].components.?[0].type);
    try testing.expectEqualStrings("baz", params.value[1].components.?[0].name);
}

test "AbiParameters with nested tuple" {
    const slice = "((bytes32 baz)[] fizz) bar";

    const params = try parseHumanReadable([]const param.AbiParameter, testing.allocator, slice);
    defer params.deinit();

    try testing.expectEqual(ParamType{ .tuple = {} }, params.value[0].type);
    try testing.expectEqualStrings("bar", params.value[0].name);
    try testing.expectEqual(params.value.len, 1);

    try testing.expect(params.value[0].components != null);
    try testing.expect(params.value[0].components.?[0].components != null);
    try testing.expectEqual(ParamType{ .tuple = {} }, params.value[0].components.?[0].type.dynamicArray.*);
    try testing.expectEqual(ParamType{ .fixedBytes = 32 }, params.value[0].components.?[0].components.?[0].type);
    try testing.expectEqualStrings("fizz", params.value[0].components.?[0].name);
    try testing.expectEqualStrings("baz", params.value[0].components.?[0].components.?[0].name);
}

test "Receive signature" {
    const slice = "receive() external payable";
    const signature = try parseHumanReadable(abi.Receive, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .receive);
    try testing.expectEqual(signature.value.stateMutability, .payable);
}

test "Fallback signature" {
    const slice = "fallback()";
    const signature = try parseHumanReadable(abi.Fallback, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .fallback);
    try testing.expectEqual(signature.value.stateMutability, .nonpayable);
}

test "Fallback signature payable" {
    const slice = "fallback() payable";
    const signature = try parseHumanReadable(abi.Fallback, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .fallback);
    try testing.expectEqual(signature.value.stateMutability, .payable);
}

test "Constructor signature" {
    const slice = "constructor(bool foo)";
    const signature = try parseHumanReadable(abi.Constructor, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .constructor);
    try testing.expectEqual(ParamType{ .bool = {} }, signature.value.inputs[0].type);
    try testing.expectEqual(signature.value.stateMutability, .nonpayable);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
}

test "Constructor signature payable" {
    const slice = "constructor(bool foo) payable";
    const signature = try parseHumanReadable(abi.Constructor, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .constructor);
    try testing.expectEqual(ParamType{ .bool = {} }, signature.value.inputs[0].type);
    try testing.expectEqual(signature.value.stateMutability, .payable);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
}

test "Error signature" {
    const slice = "error Foo(bytes foo)";
    const signature = try parseHumanReadable(abi.Error, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .@"error");
    try testing.expectEqual(ParamType{ .bytes = {} }, signature.value.inputs[0].type);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
}

test "Event signature" {
    const slice = "event Foo(bytes foo, address indexed bar)";
    const signature = try parseHumanReadable(abi.Event, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .event);
    try testing.expectEqual(ParamType{ .bytes = {} }, signature.value.inputs[0].type);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
    try testing.expect(!signature.value.inputs[0].indexed);
    try testing.expectEqual(ParamType{ .address = {} }, signature.value.inputs[1].type);
    try testing.expectEqualStrings("bar", signature.value.inputs[1].name);
    try testing.expect(signature.value.inputs[1].indexed);
}

test "Function signature" {
    const slice = "function Foo(bytes foo, address bar)";
    const signature = try parseHumanReadable(abi.Function, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .function);
    try testing.expectEqual(ParamType{ .bytes = {} }, signature.value.inputs[0].type);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, signature.value.inputs[1].type);
    try testing.expectEqualStrings("bar", signature.value.inputs[1].name);
    try testing.expectEqual(signature.value.stateMutability, .nonpayable);
    try testing.expectEqualSlices(param.AbiParameter, &.{}, signature.value.outputs);
}

test "Function signature with state" {
    const slice = "function Foo(bytes foo, address bar) external view";
    const signature = try parseHumanReadable(abi.Function, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .function);
    try testing.expectEqual(ParamType{ .bytes = {} }, signature.value.inputs[0].type);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, signature.value.inputs[1].type);
    try testing.expectEqualStrings("bar", signature.value.inputs[1].name);
    try testing.expectEqual(signature.value.stateMutability, .view);
    try testing.expectEqualSlices(param.AbiParameter, &.{}, signature.value.outputs);
}

test "Function signature with return" {
    const slice = "function Foo(bytes foo, address bar) public pure returns (string baz)";
    const signature = try parseHumanReadable(abi.Function, testing.allocator, slice);
    defer signature.deinit();

    try testing.expectEqual(signature.value.type, .function);
    try testing.expectEqual(ParamType{ .bytes = {} }, signature.value.inputs[0].type);
    try testing.expectEqualStrings("foo", signature.value.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, signature.value.inputs[1].type);
    try testing.expectEqualStrings("bar", signature.value.inputs[1].name);
    try testing.expectEqual(signature.value.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .string = {} }, signature.value.outputs[0].type);
    try testing.expectEqualStrings("baz", signature.value.outputs[0].name);
}

test "AbiItem" {
    const slice = "function Foo(bytes foo, address bar) public pure returns (string baz)";
    const signature = try parseHumanReadable(abi.AbiItem, testing.allocator, slice);
    defer signature.deinit();

    const function = signature.value.abiFunction;
    try testing.expectEqual(function.type, .function);
    try testing.expectEqual(ParamType{ .bytes = {} }, function.inputs[0].type);
    try testing.expectEqualStrings("foo", function.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, function.inputs[1].type);
    try testing.expectEqualStrings("bar", function.inputs[1].name);
    try testing.expectEqual(function.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .string = {} }, function.outputs[0].type);
    try testing.expectEqualStrings("baz", function.outputs[0].name);
}

test "Abi" {
    const slice = "function Foo(bytes foo, address bar) public pure returns (string baz)";
    const signature = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer signature.deinit();

    const function = signature.value[0].abiFunction;
    try testing.expectEqual(function.type, .function);
    try testing.expectEqual(ParamType{ .bytes = {} }, function.inputs[0].type);
    try testing.expectEqualStrings("foo", function.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, function.inputs[1].type);
    try testing.expectEqualStrings("bar", function.inputs[1].name);
    try testing.expectEqual(function.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .string = {} }, function.outputs[0].type);
    try testing.expectEqualStrings("baz", function.outputs[0].name);
}

test "Abi with struct" {
    const slice =
        \\struct Foo {address bar; string baz;}
        \\function Fizz(Foo buzz) public pure returns (string baz)
    ;

    const signature = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer signature.deinit();

    const function = signature.value[0].abiFunction;
    try testing.expectEqual(function.type, .function);
    try testing.expectEqualStrings("Fizz", function.name);
    try testing.expectEqual(ParamType{ .tuple = {} }, function.inputs[0].type);
    try testing.expectEqualStrings("buzz", function.inputs[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, function.inputs[0].components.?[0].type);
    try testing.expectEqual(ParamType{ .string = {} }, function.inputs[0].components.?[1].type);
    try testing.expectEqualStrings("bar", function.inputs[0].components.?[0].name);
    try testing.expectEqualStrings("baz", function.inputs[0].components.?[1].name);
    try testing.expectEqual(function.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .string = {} }, function.outputs[0].type);
    try testing.expectEqualStrings("baz", function.outputs[0].name);
}

test "Abi with nested struct" {
    const slice =
        \\struct Foo {address bar; string baz;}
        \\struct Bar {Foo foo;}
        \\function Fizz(Bar bar) public pure returns (Foo foo)
    ;

    const signature = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer signature.deinit();

    const function = signature.value[0].abiFunction;
    try testing.expectEqual(function.type, .function);
    try testing.expectEqualStrings("Fizz", function.name);
    try testing.expectEqual(ParamType{ .tuple = {} }, function.inputs[0].type);
    try testing.expectEqualStrings("bar", function.inputs[0].name);
    try testing.expectEqual(ParamType{ .tuple = {} }, function.inputs[0].components.?[0].type);
    try testing.expectEqualStrings("foo", function.inputs[0].components.?[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, function.inputs[0].components.?[0].components.?[0].type);
    try testing.expectEqual(ParamType{ .string = {} }, function.inputs[0].components.?[0].components.?[1].type);
    try testing.expectEqualStrings("bar", function.inputs[0].components.?[0].components.?[0].name);
    try testing.expectEqualStrings("baz", function.inputs[0].components.?[0].components.?[1].name);
    try testing.expectEqual(function.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .address = {} }, function.outputs[0].components.?[0].type);
    try testing.expectEqual(ParamType{ .string = {} }, function.outputs[0].components.?[1].type);
    try testing.expectEqualStrings("bar", function.outputs[0].components.?[0].name);
    try testing.expectEqualStrings("baz", function.outputs[0].components.?[1].name);
}

test "Seaport" {
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

    const parsed = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer parsed.deinit();

    try testing.expectEqual(parsed.value.len, 68);

    const last = parsed.value[67].abiError;
    try testing.expectEqual(last.type, .@"error");
    try testing.expectEqualSlices(param.AbiParameter, &.{}, last.inputs);
    try testing.expectEqualStrings("UnusedItemParameters", last.name);

    // try std.json.stringify(parsed.value, .{ .whitespace = .indent_2, .emit_null_optional_fields = false }, std.io.getStdErr().writer());
}

test "Parsing errors parameters" {
    try testing.expectError(error.UnexceptedToken, parseHumanReadable([]const param.AbiParameter, testing.allocator, "adddress foo"));
    try testing.expectError(error.UnexceptedToken, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address foo,"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiParameter, testing.allocator, "(address calldata foo)"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address indexed foo"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address calldata foo"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address storage foo"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address memory foo"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable([]const param.AbiEventParameter, testing.allocator, "address[] storage foo"));
    try testing.expectError(error.ExpectedCommaAfterParam, parseHumanReadable([]const param.AbiParameter, testing.allocator, "address foo."));
    try testing.expectError(error.UnexceptedToken, parseHumanReadable([]const param.AbiParameter, testing.allocator, "(((address))"));
}

test "Parsing errors signatures" {
    try testing.expectError(error.UnexceptedToken, parseHumanReadable(abi.Constructor, testing.allocator, "function foo()"));
    try testing.expectError(error.UnexceptedToken, parseHumanReadable(abi.Abi, testing.allocator, "function foo(address)) view"));
    try testing.expectError(error.UnexceptedToken, parseHumanReadable(abi.Abi, testing.allocator, "function foo(address) nonpayable"));
    try testing.expectError(error.InvalidDataLocation, parseHumanReadable(abi.Abi, testing.allocator, "function foo(((((address indexed foo))))) view return(bool)"));
    try testing.expectError(error.EmptyReturnParams, parseHumanReadable(abi.Abi, testing.allocator, "function foo(((((address foo))))) view returns()"));
}

test "Match snapshot" {
    const expected =
        \\{
        \\  "type": "function",
        \\  "inputs": [
        \\    {
        \\      "name": "bar",
        \\      "type": "address[]"
        \\    }
        \\  ],
        \\  "name": "foo",
        \\  "outputs": [],
        \\  "stateMutability": "nonpayable"
        \\}
    ;

    try testSnapshot(abi.Function, expected, "function foo(address[] bar)");
}

fn testSnapshot(comptime T: type, expected: []const u8, source: [:0]const u8) !void {
    const value = try parseHumanReadable(T, testing.allocator, source);
    defer value.deinit();

    var out_buf: [1024]u8 = undefined;
    var slice_stream = std.io.fixedBufferStream(&out_buf);
    const out = slice_stream.writer();

    try std.json.stringify(value.value, .{ .whitespace = .indent_2, .emit_null_optional_fields = false }, out);

    try testing.expectEqualStrings(expected, slice_stream.getWritten());
}
