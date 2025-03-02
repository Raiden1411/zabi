const std = @import("std");
const formatter = @import("zabi").ast.formatter;
const testing = std.testing;

const Ast = @import("zabi").ast.Ast;
const Formatter = formatter.SolidityFormatter(std.ArrayList(u8).Writer);
const Parser = @import("zabi").ast.Parser;

test "Basic" {
    const slice =
        \\    function _transferOwnership(address newOwner) internal override(foo.bar, baz.foo) {
        \\        address oldOwner = _owner;
        \\        _owner = newOwner;
        \\        emit OwnershipTransferred(oldOwner, newOwner);
        \\        if (foo > 5) 
        \\ {foo +=       bar;}
        \\        if (foo > 5) 
        \\  foo +=       bar;
        \\      do {
        \\        uint ggggg = 42;
        \\       } while (true);
        \\
        \\        for (uint   foo   = 0;   foo > 5; ++foo) 
        \\ {foo +=       bar;}
        \\        for (uint   foo   = 0;   foo > 5; ++foo) 
        \\ foo +=       bar;
        \\ 
        \\        while (true) 
        \\ {foo +=       bar;}
        \\        if (foo > 5) 
        \\ {foo +=       bar;} else    {fooooo;}
        \\        if (foo > 5) 
        \\ foo +=       bar; else    {fooooo;}
        \\ unchecked        {bar      += fooo;}
        \\ continue;
        \\ break;
        \\ 
        \\ 
        \\      ++foo;
        \\          foo++;
        \\ 
        \\ 
        \\ 
        \\ //       This is a comment
        \\ return           foooooo +           6;
        \\ 
        \\    }
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, 4, list.writer());

    try format.formatStatement(@intCast(ast.nodes.len - 1), .none);
}

test "Element" {
    const slice =
        \\      //   Commentsssssss
        \\      /// I AM A DOC COMMENT
        \\          //   Comment
        \\contract SendToFallback is ForBar     ,   ASFASDSADASD      {
        \\ //       This is a comment
        \\    function transferToFallback(address payable _to) public payable {
        \\ assembly  {
        \\  fooo := 0x69
        \\  bar, jazz := sload(0x60)
        \\  let lol := 0x69
        \\  let lol, bar := sload(0x69)
        \\  if iszero(temp) { break }
        \\  for { let temp := value } 1 {} {
        \\  result := add(result, w)
        \\  mstore8(add(result, 1), mload(and(temp, 15)))
        \\  mstore8(result, mload(and(shr(4, temp), 15)))
        \\  temp := shr(8, temp)
        \\  if iszero(temp) { break }
        \\  }
        \\  switch lol(69)
        \\  case 69 {mload(0x80)}
        \\  case 0x40 {mload(0x80)}
        \\  case "FOOOOOOO" {mload(0x80)}
        \\  case bar {mload(0x80, 69)}
        \\  default {sload(0x80)}
        \\  function foo (bar, baz) -> fizz, buzz {mload(0x80)}
        \\    
        \\    
        \\    
        \\    
        \\    
        \\  function foo (bar, baz) {mload(0x80)}
        \\  }
        \\    
        \\    }
        \\
        \\
        \\
        \\ //       This is a comment
        \\
        \\              /// I AM A DOC COMMENT
        \\      function callFallback(address payable _to) public payable {
        \\ //       This is a comment
        \\        require(sent, "Failed to send Ether");
        \\    }
        \\}
    ;

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var format: Formatter = .init(ast, 4, list.writer());

    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}

test "It can format a contract without errors" {
    const slice =
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

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var format: Formatter = .init(ast, 4, list.writer());
    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}

test "Owner Contract" {
    const slice =
        \\// SPDX-License-Identifier: MIT
        \\// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)
        \\
        \\pragma solidity ^0.8.20;
        \\
        \\import {Context} from "../utils/Context.sol";
        \\
        \\/**
        \\ * @dev Contract module which provides a basic access control mechanism, where
        \\ * there is an account (an owner) that can be granted exclusive access to
        \\ * specific functions.
        \\ *
        \\ * The initial owner is set to the address provided by the deployer. This can
        \\ * later be changed with {transferOwnership}.
        \\ *
        \\ * This module is used through inheritance. It will make available the modifier
        \\ * `onlyOwner`, which can be applied to your functions to restrict their use to
        \\ * the owner.
        \\ */
        \\abstract contract Ownable is Context {
        \\    address private _owner;
        \\
        \\    /**
        \\     * @dev The caller account is not authorized to perform an operation.
        \\     */
        \\    error OwnableUnauthorizedAccount(address account);
        \\
        \\    /**
        \\     * @dev The owner is not a valid owner account. (eg. `address(0)`)
        \\     */
        \\    error OwnableInvalidOwner(address owner);
        \\
        \\    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
        \\
        \\    /**
        \\     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
        \\     */
        \\    constructor(address initialOwner) {
        \\        if (initialOwner == address(0)) {
        \\            revert OwnableInvalidOwner(address(0));
        \\        }
        \\        _transferOwnership(initialOwner);
        \\    }
        \\
        \\    /**
        \\     * @dev Throws if called by any account other than the owner.
        \\     */
        \\    modifier onlyOwner() {
        \\        _checkOwner();
        \\        _;
        \\    }
        \\
        \\    /**
        \\     * @dev Returns the address of the current owner.
        \\     */
        \\    function owner() public view virtual returns (address) {
        \\        return _owner;
        \\    }
        \\
        \\    /**
        \\     * @dev Throws if the sender is not the owner.
        \\     */
        \\    function _checkOwner() internal view override(foo) {
        \\        if (owner() != _msgSender()) {
        \\            revert OwnableUnauthorizedAccount(_msgSender());
        \\        }
        \\    }
        \\
        \\    /**
        \\     * @dev Leaves the contract without owner. It will not be possible to call
        \\     * `onlyOwner` functions. Can only be called by the current owner.
        \\     *
        \\     * NOTE: Renouncing ownership will leave the contract without an owner,
        \\     * thereby disabling any functionality that is only available to the owner.
        \\     */
        \\    function renounceOwnership() public virtual onlyOwner {
        \\        _transferOwnership(address(0));
        \\    }
        \\
        \\    /**
        \\     * @dev Transfers ownership of the contract to a new account (`newOwner`).
        \\     * Can only be called by the current owner.
        \\     */
        \\    function transferOwnership(address newOwner) public virtual onlyOwner {
        \\        if (newOwner == address(0)) {
        \\            revert OwnableInvalidOwner(address(0));
        \\        }
        \\      do {
        \\        uint ggggg = 42;
        \\       } while (true);
        \\        _transferOwnership(newOwner);
        \\    }
        \\
        \\    /**
        \\     * @dev Transfers ownership of the contract to a new account (`newOwner`).
        \\     * Internal function without access restriction.
        \\     */
        \\    function _transferOwnership(address newOwner) internal override(foo.bar, baz.foo) {
        \\        address oldOwner = _owner;
        \\        _owner = newOwner;
        \\        emit OwnershipTransferred(oldOwner, newOwner);
        \\    }
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var format: Formatter = .init(ast, 4, list.writer());
    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}

test "Uniswap" {
    const slice =
        \\// SPDX-License-Identifier: MIT
        \\pragma solidity ^0.8.26;
        \\
        \\address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        \\address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        \\
        \\interface IERC721Receiver {
        \\    function onERC721Received(
        \\        address operator,
        \\        address from,
        \\        uint256 tokenId,
        \\        bytes calldata data
        \\    ) external returns (bytes4);
        \\}
        \\
        \\contract UniswapV3Liquidity is IERC721Receiver {
        \\    IERC20 private immutable dai = IERC20(DAI);
        \\    IWETH private constant weth = IWETH(WETH);
        \\
        \\    int24 private MIN_TICK = -887272;
        \\    int24 private MAX_TICK = -MIN_TICK;
        \\    int24 private TICK_SPACING = 60;
        \\
        \\    INonfungiblePositionManager public nonfungiblePositionManager =
        \\        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        \\
        \\    function onERC721Received(
        \\        address operator,
        \\        address from,
        \\        uint256 tokenId,
        \\        bytes calldata
        \\    ) external returns (bytes4) {
        \\        return IERC721Receiver.onERC721Received.selector;
        \\    }
        \\
        \\    function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd)
        \\        external
        \\        returns (
        \\            uint256 tokenId,
        \\            uint128 liquidity,
        \\            uint256 amount0,
        \\            uint256 amount1
        \\        )
        \\    {
        \\        dai.transferFrom(msg.sender, address(this), amount0ToAdd);
        \\        weth.transferFrom(msg.sender, address(this), amount1ToAdd);
        \\
        \\        dai.approve(address(nonfungiblePositionManager), amount0ToAdd);
        \\        weth.approve(address(nonfungiblePositionManager), amount1ToAdd);
        \\
        \\        INonfungiblePositionManager.MintParams memory params =
        \\        INonfungiblePositionManager.MintParams({
        \\            token0: DAI,
        \\            token1: WETH,
        \\            fee: 3000,
        \\            tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
        \\            tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
        \\            amount0Desired: amount0ToAdd,
        \\            amount1Desired: amount1ToAdd,
        \\            amount0Min: 0,
        \\            amount1Min: 0,
        \\            recipient: address(this),
        \\            deadline: block.timestamp
        \\        });
        \\
        \\        (tokenId, liquidity, amount0, amount1) =
        \\            nonfungiblePositionManager.mint(params);
        \\
        \\        if (amount0 < amount0ToAdd) {
        \\            dai.approve(address(nonfungiblePositionManager), 0);
        \\            uint256 refund0 = amount0ToAdd - amount0;
        \\            dai.transfer(msg.sender, refund0);
        \\        }
        \\        if (amount1 < amount1ToAdd) {
        \\            weth.approve(address(nonfungiblePositionManager), 0);
        \\            uint256 refund1 = amount1ToAdd - amount1;
        \\            weth.transfer(msg.sender, refund1);
        \\        }
        \\    }
        \\
        \\    function collectAllFees(uint256 tokenId)
        \\        external
        \\        returns (uint256 amount0, uint256 amount1)
        \\    {
        \\        INonfungiblePositionManager.CollectParams memory params =
        \\        INonfungiblePositionManager.CollectParams({
        \\            tokenId: tokenId,
        \\            recipient: address(this),
        \\            amount0Max: type(uint128).max,
        \\            amount1Max: type(uint128).max
        \\        });
        \\
        \\        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        \\    }
        \\
        \\    function increaseLiquidityCurrentRange(
        \\        uint256 tokenId,
        \\        uint256 amount0ToAdd,
        \\        uint256 amount1ToAdd
        \\    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        \\        dai.transferFrom(msg.sender, address(this), amount0ToAdd);
        \\        weth.transferFrom(msg.sender, address(this), amount1ToAdd);
        \\
        \\        dai.approve(address(nonfungiblePositionManager), amount0ToAdd);
        \\        weth.approve(address(nonfungiblePositionManager), amount1ToAdd);
        \\
        \\        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        \\        INonfungiblePositionManager.IncreaseLiquidityParams({
        \\            tokenId: tokenId,
        \\            amount0Desired: amount0ToAdd,
        \\            amount1Desired: amount1ToAdd,
        \\            amount0Min: 0,
        \\            amount1Min: 0,
        \\            deadline: block.timestamp
        \\        });
        \\
        \\        (liquidity, amount0, amount1) =
        \\            nonfungiblePositionManager.increaseLiquidity(params);
        \\    }
        \\
        \\    function decreaseLiquidityCurrentRange(uint256 tokenId, uint128 liquidity)
        \\        external
        \\        returns (uint256 amount0, uint256 amount1)
        \\    {
        \\        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        \\        INonfungiblePositionManager.DecreaseLiquidityParams({
        \\            tokenId: tokenId,
        \\            liquidity: liquidity,
        \\            amount0Min: 0,
        \\            amount1Min: 0,
        \\            deadline: block.timestamp
        \\        });
        \\
        \\        (amount0, amount1) =
        \\            nonfungiblePositionManager.decreaseLiquidity(params);
        \\    }
        \\}
        \\
        \\interface INonfungiblePositionManager {
        \\    struct MintParams {
        \\        address token0;
        \\        address token1;
        \\        uint24 fee;
        \\        int24 tickLower;
        \\        int24 tickUpper;
        \\        uint256 amount0Desired;
        \\        uint256 amount1Desired;
        \\        uint256 amount0Min;
        \\        uint256 amount1Min;
        \\        address recipient;
        \\        uint256 deadline;
        \\    }
        \\
        \\    function mint(MintParams calldata params)
        \\        external
        \\        payable
        \\        returns (
        \\            uint256 tokenId,
        \\            uint128 liquidity,
        \\            uint256 amount0,
        \\            uint256 amount1
        \\        );
        \\
        \\    struct IncreaseLiquidityParams {
        \\        uint256 tokenId;
        \\        uint256 amount0Desired;
        \\        uint256 amount1Desired;
        \\        uint256 amount0Min;
        \\        uint256 amount1Min;
        \\        uint256 deadline;
        \\    }
        \\
        \\    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        \\        external
        \\        payable
        \\        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
        \\
        \\    struct DecreaseLiquidityParams {
        \\        uint256 tokenId;
        \\        uint128 liquidity;
        \\        uint256 amount0Min;
        \\        uint256 amount1Min;
        \\        uint256 deadline;
        \\    }
        \\
        \\    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        \\        external
        \\        payable
        \\        returns (uint256 amount0, uint256 amount1);
        \\
        \\    struct CollectParams {
        \\        uint256 tokenId;
        \\        address recipient;
        \\        uint128 amount0Max;
        \\        uint128 amount1Max;
        \\    }
        \\
        \\    function collect(CollectParams calldata params)
        \\        external
        \\        payable
        \\        returns (uint256 amount0, uint256 amount1);
        \\}
        \\
        \\interface IERC20 {
        \\    function totalSupply() external view returns (uint256);
        \\    function balanceOf(address account) external view returns (uint256);
        \\    function transfer(address recipient, uint256 amount)
        \\        external
        \\        returns (bool);
        \\    function allowance(address owner, address spender)
        \\        external
        \\        view
        \\        returns (uint256);
        \\    function approve(address spender, uint256 amount) external returns (bool);
        \\    function transferFrom(address sender, address recipient, uint256 amount)
        \\        external
        \\        returns (bool);
        \\}
        \\
        \\interface IWETH is IERC20 {
        \\    function deposit() external payable;
        \\    function withdraw(uint256 amount) external;
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var format: Formatter = .init(ast, 4, list.writer());
    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}

test "Fallback" {
    const slice =
        \\// SPDX-License-Identifier: MIT
        \\pragma solidity ^0.8.26;
        \\
        \\contract Fallback {
        \\    event Log(string func, uint256 gas);
        \\
        \\    // Fallback function must be declared as external.
        \\    fallback() external payable {
        \\        // send / transfer (forwards 2300 gas to this fallback function)
        \\        // call (forwards all of the gas)
        \\        emit Log("fallback", gasleft());
        \\    }
        \\
        \\    // Receive is a variant of fallback that is triggered when msg.data is empty
        \\    receive() external payable {
        \\        emit Log("receive", gasleft());
        \\    }
        \\
        \\    // Helper function to check the balance of this contract
        \\    function getBalance() public view returns (uint256) {
        \\        return address(this).balance;
        \\    }
        \\}
        \\
        \\contract SendToFallback {
        \\    function transferToFallback(address payable _to) public payable {
        \\        _to.transfer(msg.value);
        \\    }
        \\
        \\    function callFallback(address payable _to) public payable {
        \\        (bool sent,) = _to.call{value: msg.value}("");
        \\        require(sent, "Failed to send Ether");
        \\    }
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var format: Formatter = .init(ast, 4, list.writer());
    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}

test "Solady" {
    const slice =
        \\// SPDX-License-Identifier: MIT
        \\pragma solidity ^0.8.4;
        \\
        \\import {LibBytes} from "./LibBytes.sol";
        \\
        \\/// @notice Library for converting numbers into strings and other string operations.
        \\/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibString.sol)
        \\/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibString.sol)
        \\///
        \\/// @dev Note:
        \\/// For performance and bytecode compactness, most of the string operations are restricted to
        \\/// byte strings (7-bit ASCII), except where otherwise specified.
        \\/// Usage of byte string operations on charsets with runes spanning two or more bytes
        \\/// can lead to undefined behavior.
        \\library LibString {
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                          STRUCTS                           */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev Goated string storage struct that totally MOGs, no cap, fr.
        \\    /// Uses less gas and bytecode than Solidity's native string storage. It's meta af.
        \\    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
        \\    struct StringStorage {
        \\        bytes32 _spacer;
        \\    }
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                        CUSTOM ERRORS                       */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev The length of the output is too small to contain all the hex digits.
        \\    error HexLengthInsufficient();
        \\
        \\    /// @dev The length of the string is more than 32 bytes.
        \\    error TooBigForSmallString();
        \\
        \\    /// @dev The input string must be a 7-bit ASCII.
        \\    error StringNot7BitASCII();
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                         CONSTANTS                          */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev The constant returned when the `search` is not found in the string.
        \\    uint256 internal constant NOT_FOUND = type(uint256).max;
        \\
        \\    /// @dev Lookup for '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.
        \\    uint128 internal constant ALPHANUMERIC_7_BIT_ASCII = 0x7fffffe07fffffe03ff000000000000;
        \\
        \\    /// @dev Lookup for 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.
        \\    uint128 internal constant LETTERS_7_BIT_ASCII = 0x7fffffe07fffffe0000000000000000;
        \\
        \\    /// @dev Lookup for 'abcdefghijklmnopqrstuvwxyz'.
        \\    uint128 internal constant LOWERCASE_7_BIT_ASCII = 0x7fffffe000000000000000000000000;
        \\
        \\    /// @dev Lookup for 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.
        \\    uint128 internal constant UPPERCASE_7_BIT_ASCII = 0x7fffffe0000000000000000;
        \\
        \\    /// @dev Lookup for '0123456789'.
        \\    uint128 internal constant DIGITS_7_BIT_ASCII = 0x3ff000000000000;
        \\
        \\    /// @dev Lookup for '0123456789abcdefABCDEF'.
        \\    uint128 internal constant HEXDIGITS_7_BIT_ASCII = 0x7e0000007e03ff000000000000;
        \\
        \\    /// @dev Lookup for '01234567'.
        \\    uint128 internal constant OCTDIGITS_7_BIT_ASCII = 0xff000000000000;
        \\
        \\    /// @dev Lookup for '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c'.
        \\    uint128 internal constant PRINTABLE_7_BIT_ASCII = 0x7fffffffffffffffffffffff00003e00;
        \\
        \\    /// @dev Lookup for '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'.
        \\    uint128 internal constant PUNCTUATION_7_BIT_ASCII = 0x78000001f8000001fc00fffe00000000;
        \\
        \\    /// @dev Lookup for ' \t\n\r\x0b\x0c'.
        \\    uint128 internal constant WHITESPACE_7_BIT_ASCII = 0x100003e00;
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                 STRING STORAGE OPERATIONS                  */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev Sets the value of the string storage `$` to `s`.
        \\    function set(StringStorage storage $, string memory s) internal {
        \\        LibBytes.set(bytesStorage($), bytes(s));
        \\    }
        \\
        \\    /// @dev Sets the value of the string storage `$` to `s`.
        \\    function setCalldata(StringStorage storage $, string calldata s) internal {
        \\        LibBytes.setCalldata(bytesStorage($), bytes(s));
        \\    }
        \\
        \\    /// @dev Sets the value of the string storage `$` to the empty string.
        \\    function clear(StringStorage storage $) internal {
        \\        delete $._spacer;
        \\    }
        \\
        \\    /// @dev Returns whether the value stored is `$` is the empty string "".
        \\    function isEmpty(StringStorage storage $) internal view returns (bool) {
        \\        return uint256($._spacer) & 0xff == uint256(0);
        \\    }
        \\
        \\    /// @dev Returns the length of the value stored in `$`.
        \\    function length(StringStorage storage $) internal view returns (uint256) {
        \\        return LibBytes.length(bytesStorage($));
        \\    }
        \\
        \\    /// @dev Returns the value stored in `$`.
        \\    function get(StringStorage storage $) internal view returns (string memory) {
        \\        return string(LibBytes.get(bytesStorage($)));
        \\    }
        \\
        \\    /// @dev Helper to cast `$` to a `BytesStorage`.
        \\    function bytesStorage(StringStorage storage $)
        \\        internal
        \\        pure
        \\        returns (LibBytes.BytesStorage storage casted)
        \\    {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            casted.slot := $.slot
        \\        }
        \\    }
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                     DECIMAL OPERATIONS                     */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev Returns the base 10 decimal representation of `value`.
        \\    function toString(uint256 value) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
        \\            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
        \\            // We will need 1 word for the trailing zeros padding, 1 word for the length,
        \\            // and 3 words for a maximum of 78 digits.
        \\            result := add(mload(0x40), 0x80)
        \\            mstore(0x40, add(result, 0x20)) // Allocate memory.
        \\            mstore(result, 0) // Zeroize the slot after the string.
        \\
        \\            let end := result // Cache the end of the memory to calculate the length later.
        \\            let w := not(0) // Tsk.
        \\            // We write the string from rightmost digit to leftmost digit.
        \\            // The following is essentially a do-while loop that also handles the zero case.
        \\            for { let temp := value } 1 {} {
        \\                result := add(result, w) // `sub(result, 1)`.
        \\                // Store the character to the pointer.
        \\                // The ASCII index of the '0' character is 48.
        \\                mstore8(result, add(48, mod(temp, 10)))
        \\                temp := div(temp, 10) // Keep dividing `temp` until zero.
        \\                if iszero(temp) { break }
        \\            }
        \\            let n := sub(end, result)
        \\            result := sub(result, 0x20) // Move the pointer 32 bytes back to make room for the length.
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the base 10 decimal representation of `value`.
        \\    function toString(int256 value) internal pure returns (string memory result) {
        \\        if (value >= 0) return toString(uint256(value));
        \\        unchecked {
        \\            result = toString(~uint256(value) + 1);
        \\        }
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // We still have some spare memory space on the left,
        \\            // as we have allocated 3 words (96 bytes) for up to 78 digits.
        \\            let n := mload(result) // Load the string length.
        \\            mstore(result, 0x2d) // Store the '-' character.
        \\            result := sub(result, 1) // Move back the string pointer by a byte.
        \\            mstore(result, add(n, 1)) // Update the string length.
        \\        }
        \\    }
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                   HEXADECIMAL OPERATIONS                   */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`,
        \\    /// left-padded to an input length of `byteCount` bytes.
        \\    /// The output is prefixed with "0x" encoded using 2 hexadecimal digits per byte,
        \\    /// giving a total length of `byteCount * 2 + 2` bytes.
        \\    /// Reverts if `byteCount` is too small for the output to contain all the digits.
        \\    function toHexString(uint256 value, uint256 byteCount)
        \\        internal
        \\        pure
        \\        returns (string memory result)
        \\    {
        \\        result = toHexStringNoPrefix(value, byteCount);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := add(mload(result), 2) // Compute the length.
        \\            mstore(result, 0x3078) // Store the "0x" prefix.
        \\            result := sub(result, 2) // Move the pointer.
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`,
        \\    /// left-padded to an input length of `byteCount` bytes.
        \\    /// The output is not prefixed with "0x" and is encoded using 2 hexadecimal digits per byte,
        \\    /// giving a total length of `byteCount * 2` bytes.
        \\    /// Reverts if `byteCount` is too small for the output to contain all the digits.
        \\    function toHexStringNoPrefix(uint256 value, uint256 byteCount)
        \\        internal
        \\        pure
        \\        returns (string memory result)
        \\    {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // We need 0x20 bytes for the trailing zeros padding, `byteCount * 2` bytes
        \\            // for the digits, 0x02 bytes for the prefix, and 0x20 bytes for the length.
        \\            // We add 0x20 to the total and round down to a multiple of 0x20.
        \\            // (0x20 + 0x20 + 0x02 + 0x20) = 0x62.
        \\            result := add(mload(0x40), and(add(shl(1, byteCount), 0x42), not(0x1f)))
        \\            mstore(0x40, add(result, 0x20)) // Allocate memory.
        \\            mstore(result, 0) // Zeroize the slot after the string.
        \\
        \\            let end := result // Cache the end to calculate the length later.
        \\            // Store "0123456789abcdef" in scratch space.
        \\            mstore(0x0f, 0x30313233343536373839616263646566)
        \\
        \\            let start := sub(result, add(byteCount, byteCount))
        \\            let w := not(1) // Tsk.
        \\            let temp := value
        \\            // We write the string from rightmost digit to leftmost digit.
        \\            // The following is essentially a do-while loop that also handles the zero case.
        \\            for {} 1 {} {
        \\                result := add(result, w) // `sub(result, 2)`.
        \\                mstore8(add(result, 1), mload(and(temp, 15)))
        \\                mstore8(result, mload(and(shr(4, temp), 15)))
        \\                temp := shr(8, temp)
        \\                if iszero(xor(result, start)) { break }
        \\            }
        \\            if temp {
        \\                mstore(0x00, 0x2194895a) // `HexLengthInsufficient()`.
        \\                revert(0x1c, 0x04)
        \\            }
        \\            let n := sub(end, result)
        \\            result := sub(result, 0x20)
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is prefixed with "0x" and encoded using 2 hexadecimal digits per byte.
        \\    /// As address are 20 bytes long, the output will left-padded to have
        \\    /// a length of `20 * 2 + 2` bytes.
        \\    function toHexString(uint256 value) internal pure returns (string memory result) {
        \\        result = toHexStringNoPrefix(value);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := add(mload(result), 2) // Compute the length.
        \\            mstore(result, 0x3078) // Store the "0x" prefix.
        \\            result := sub(result, 2) // Move the pointer.
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is prefixed with "0x".
        \\    /// The output excludes leading "0" from the `toHexString` output.
        \\    /// `0x00: "0x0", 0x01: "0x1", 0x12: "0x12", 0x123: "0x123"`.
        \\    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        \\        result = toHexStringNoPrefix(value);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let o := eq(byte(0, mload(add(result, 0x20))), 0x30) // Whether leading zero is present.
        \\            let n := add(mload(result), 2) // Compute the length.
        \\            mstore(add(result, o), 0x3078) // Store the "0x" prefix, accounting for leading zero.
        \\            result := sub(add(result, o), 2) // Move the pointer, accounting for leading zero.
        \\            mstore(result, sub(n, o)) // Store the length, accounting for leading zero.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output excludes leading "0" from the `toHexStringNoPrefix` output.
        \\    /// `0x00: "0", 0x01: "1", 0x12: "12", 0x123: "123"`.
        \\    function toMinimalHexStringNoPrefix(uint256 value)
        \\        internal
        \\        pure
        \\        returns (string memory result)
        \\    {
        \\        result = toHexStringNoPrefix(value);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let o := eq(byte(0, mload(add(result, 0x20))), 0x30) // Whether leading zero is present.
        \\            let n := mload(result) // Get the length.
        \\            result := add(result, o) // Move the pointer, accounting for leading zero.
        \\            mstore(result, sub(n, o)) // Store the length, accounting for leading zero.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is encoded using 2 hexadecimal digits per byte.
        \\    /// As address are 20 bytes long, the output will left-padded to have
        \\    /// a length of `20 * 2` bytes.
        \\    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // We need 0x20 bytes for the trailing zeros padding, 0x20 bytes for the length,
        \\            // 0x02 bytes for the prefix, and 0x40 bytes for the digits.
        \\            // The next multiple of 0x20 above (0x20 + 0x20 + 0x02 + 0x40) is 0xa0.
        \\            result := add(mload(0x40), 0x80)
        \\            mstore(0x40, add(result, 0x20)) // Allocate memory.
        \\            mstore(result, 0) // Zeroize the slot after the string.
        \\
        \\            let end := result // Cache the end to calculate the length later.
        \\            mstore(0x0f, 0x30313233343536373839616263646566) // Store the "0123456789abcdef" lookup.
        \\
        \\            let w := not(1) // Tsk.
        \\            // We write the string from rightmost digit to leftmost digit.
        \\            // The following is essentially a do-while loop that also handles the zero case.
        \\            for { let temp := value } 1 {} {
        \\                result := add(result, w) // `sub(result, 2)`.
        \\                mstore8(add(result, 1), mload(and(temp, 15)))
        \\                mstore8(result, mload(and(shr(4, temp), 15)))
        \\                temp := shr(8, temp)
        \\                if iszero(temp) { break }
        \\            }
        \\            let n := sub(end, result)
        \\            result := sub(result, 0x20)
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is prefixed with "0x", encoded using 2 hexadecimal digits per byte,
        \\    /// and the alphabets are capitalized conditionally according to
        \\    /// https://eips.ethereum.org/EIPS/eip-55
        \\    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        \\        result = toHexString(value);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let mask := shl(6, div(not(0), 255)) // `0b010000000100000000 ...`
        \\            let o := add(result, 0x22)
        \\            let hashed := and(keccak256(o, 40), mul(34, mask)) // `0b10001000 ... `
        \\            let t := shl(240, 136) // `0b10001000 << 240`
        \\            for { let i := 0 } 1 {} {
        \\                mstore(add(i, i), mul(t, byte(i, hashed)))
        \\                i := add(i, 1)
        \\                if eq(i, 20) { break }
        \\            }
        \\            mstore(o, xor(mload(o), shr(1, and(mload(0x00), and(mload(o), mask)))))
        \\            o := add(o, 0x20)
        \\            mstore(o, xor(mload(o), shr(1, and(mload(0x20), and(mload(o), mask)))))
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is prefixed with "0x" and encoded using 2 hexadecimal digits per byte.
        \\    function toHexString(address value) internal pure returns (string memory result) {
        \\        result = toHexStringNoPrefix(value);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := add(mload(result), 2) // Compute the length.
        \\            mstore(result, 0x3078) // Store the "0x" prefix.
        \\            result := sub(result, 2) // Move the pointer.
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hexadecimal representation of `value`.
        \\    /// The output is encoded using 2 hexadecimal digits per byte.
        \\    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40)
        \\            // Allocate memory.
        \\            // We need 0x20 bytes for the trailing zeros padding, 0x20 bytes for the length,
        \\            // 0x02 bytes for the prefix, and 0x28 bytes for the digits.
        \\            // The next multiple of 0x20 above (0x20 + 0x20 + 0x02 + 0x28) is 0x80.
        \\            mstore(0x40, add(result, 0x80))
        \\            mstore(0x0f, 0x30313233343536373839616263646566) // Store the "0123456789abcdef" lookup.
        \\
        \\            result := add(result, 2)
        \\            mstore(result, 40) // Store the length.
        \\            let o := add(result, 0x20)
        \\            mstore(add(o, 40), 0) // Zeroize the slot after the string.
        \\            value := shl(96, value)
        \\            // We write the string from rightmost digit to leftmost digit.
        \\            // The following is essentially a do-while loop that also handles the zero case.
        \\            for { let i := 0 } 1 {} {
        \\                let p := add(o, add(i, i))
        \\                let temp := byte(i, value)
        \\                mstore8(add(p, 1), mload(and(temp, 15)))
        \\                mstore8(p, mload(shr(4, temp)))
        \\                i := add(i, 1)
        \\                if eq(i, 20) { break }
        \\            }
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hex encoded string from the raw bytes.
        \\    /// The output is encoded using 2 hexadecimal digits per byte.
        \\    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        \\        result = toHexStringNoPrefix(raw);
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := add(mload(result), 2) // Compute the length.
        \\            mstore(result, 0x3078) // Store the "0x" prefix.
        \\            result := sub(result, 2) // Move the pointer.
        \\            mstore(result, n) // Store the length.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the hex encoded string from the raw bytes.
        \\    /// The output is encoded using 2 hexadecimal digits per byte.
        \\    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := mload(raw)
        \\            result := add(mload(0x40), 2) // Skip 2 bytes for the optional prefix.
        \\            mstore(result, add(n, n)) // Store the length of the output.
        \\
        \\            mstore(0x0f, 0x30313233343536373839616263646566) // Store the "0123456789abcdef" lookup.
        \\            let o := add(result, 0x20)
        \\            let end := add(raw, n)
        \\            for {} iszero(eq(raw, end)) {} {
        \\                raw := add(raw, 1)
        \\                mstore8(add(o, 1), mload(and(mload(raw), 15)))
        \\                mstore8(o, mload(and(shr(4, mload(raw)), 15)))
        \\                o := add(o, 2)
        \\            }
        \\            mstore(o, 0) // Zeroize the slot after the string.
        \\            mstore(0x40, add(o, 0x20)) // Allocate memory.
        \\        }
        \\    }
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                   RUNE STRING OPERATIONS                   */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    /// @dev Returns the number of UTF characters in the string.
        \\    function runeCount(string memory s) internal pure returns (uint256 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            if mload(s) {
        \\                mstore(0x00, div(not(0), 255))
        \\                mstore(0x20, 0x0202020202020202020202020202020202020202020202020303030304040506)
        \\                let o := add(s, 0x20)
        \\                let end := add(o, mload(s))
        \\                for { result := 1 } 1 { result := add(result, 1) } {
        \\                    o := add(o, byte(0, mload(shr(250, mload(o)))))
        \\                    if iszero(lt(o, end)) { break }
        \\                }
        \\            }
        \\        }
        \\    }
        \\
        \\    /// @dev Returns if this string is a 7-bit ASCII string.
        \\    /// (i.e. all characters codes are in [0..127])
        \\    function is7BitASCII(string memory s) internal pure returns (bool result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := 1
        \\            let mask := shl(7, div(not(0), 255))
        \\            let n := mload(s)
        \\            if n {
        \\                let o := add(s, 0x20)
        \\                let end := add(o, n)
        \\                let last := mload(end)
        \\                mstore(end, 0)
        \\                for {} 1 {} {
        \\                    if and(mask, mload(o)) {
        \\                        result := 0
        \\                        break
        \\                    }
        \\                    o := add(o, 0x20)
        \\                    if iszero(lt(o, end)) { break }
        \\                }
        \\                mstore(end, last)
        \\            }
        \\        }
        \\    }
        \\
        \\    /// @dev Returns if this string is a 7-bit ASCII string,
        \\    /// AND all characters are in the `allowed` lookup.
        \\    /// Note: If `s` is empty, returns true regardless of `allowed`.
        \\    function is7BitASCII(string memory s, uint128 allowed) internal pure returns (bool result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := 1
        \\            if mload(s) {
        \\                let allowed_ := shr(128, shl(128, allowed))
        \\                let o := add(s, 0x20)
        \\                for { let end := add(o, mload(s)) } 1 {} {
        \\                    result := and(result, shr(byte(0, mload(o)), allowed_))
        \\                    o := add(o, 1)
        \\                    if iszero(and(result, lt(o, end))) { break }
        \\                }
        \\            }
        \\        }
        \\    }
        \\
        \\    /// @dev Converts the bytes in the 7-bit ASCII string `s` to
        \\    /// an allowed lookup for use in `is7BitASCII(s, allowed)`.
        \\    /// To save runtime gas, you can cache the result in an immutable variable.
        \\    function to7BitASCIIAllowedLookup(string memory s) internal pure returns (uint128 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            if mload(s) {
        \\                let o := add(s, 0x20)
        \\                for { let end := add(o, mload(s)) } 1 {} {
        \\                    result := or(result, shl(byte(0, mload(o)), 1))
        \\                    o := add(o, 1)
        \\                    if iszero(lt(o, end)) { break }
        \\                }
        \\                if shr(128, result) {
        \\                    mstore(0x00, 0xc9807e0d) // `StringNot7BitASCII()`.
        \\                    revert(0x1c, 0x04)
        \\                }
        \\            }
        \\        }
        \\    }
        \\
        \\    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        \\    /*                   BYTE STRING OPERATIONS                   */
        \\    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        \\
        \\    // For performance and bytecode compactness, byte string operations are restricted
        \\    // to 7-bit ASCII strings. All offsets are byte offsets, not UTF character offsets.
        \\    // Usage of byte string operations on charsets with runes spanning two or more bytes
        \\    // can lead to undefined behavior.
        \\
        \\    /// @dev Returns `subject` all occurrences of `needle` replaced with `replacement`.
        \\    function replace(string memory subject, string memory needle, string memory replacement)
        \\        internal
        \\        pure
        \\        returns (string memory)
        \\    {
        \\        return string(LibBytes.replace(bytes(subject), bytes(needle), bytes(replacement)));
        \\    }
        \\
        \\    /// @dev Returns the byte index of the first location of `needle` in `subject`,
        \\    /// needleing from left to right, starting from `from`.
        \\    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
        \\    function indexOf(string memory subject, string memory needle, uint256 from)
        \\        internal
        \\        pure
        \\        returns (uint256)
        \\    {
        \\        return LibBytes.indexOf(bytes(subject), bytes(needle), from);
        \\    }
        \\
        \\    /// @dev Returns the byte index of the first location of `needle` in `subject`,
        \\    /// needleing from left to right.
        \\    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
        \\    function indexOf(string memory subject, string memory needle) internal pure returns (uint256) {
        \\        return LibBytes.indexOf(bytes(subject), bytes(needle), 0);
        \\    }
        \\
        \\    /// @dev Returns the byte index of the first location of `needle` in `subject`,
        \\    /// needleing from right to left, starting from `from`.
        \\    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
        \\    function lastIndexOf(string memory subject, string memory needle, uint256 from)
        \\        internal
        \\        pure
        \\        returns (uint256)
        \\    {
        \\        return LibBytes.lastIndexOf(bytes(subject), bytes(needle), from);
        \\    }
        \\
        \\    /// @dev Returns the byte index of the first location of `needle` in `subject`,
        \\    /// needleing from right to left.
        \\    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
        \\    function lastIndexOf(string memory subject, string memory needle)
        \\        internal
        \\        pure
        \\        returns (uint256)
        \\    {
        \\        return LibBytes.lastIndexOf(bytes(subject), bytes(needle), type(uint256).max);
        \\    }
        \\
        \\    /// @dev Returns true if `needle` is found in `subject`, false otherwise.
        \\    function contains(string memory subject, string memory needle) internal pure returns (bool) {
        \\        return LibBytes.contains(bytes(subject), bytes(needle));
        \\    }
        \\
        \\    /// @dev Returns whether `subject` starts with `needle`.
        \\    function startsWith(string memory subject, string memory needle) internal pure returns (bool) {
        \\        return LibBytes.startsWith(bytes(subject), bytes(needle));
        \\    }
        \\
        \\    /// @dev Returns whether `subject` ends with `needle`.
        \\    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        \\        return LibBytes.endsWith(bytes(subject), bytes(needle));
        \\    }
        \\
        \\    /// @dev Returns `subject` repeated `times`.
        \\    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        \\        return string(LibBytes.repeat(bytes(subject), times));
        \\    }
        \\
        \\    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
        \\    /// `start` and `end` are byte offsets.
        \\    function slice(string memory subject, uint256 start, uint256 end)
        \\        internal
        \\        pure
        \\        returns (string memory)
        \\    {
        \\        return string(LibBytes.slice(bytes(subject), start, end));
        \\    }
        \\
        \\    /// @dev Returns a copy of `subject` sliced from `start` to the end of the string.
        \\    /// `start` is a byte offset.
        \\    function slice(string memory subject, uint256 start) internal pure returns (string memory) {
        \\        return string(LibBytes.slice(bytes(subject), start, type(uint256).max));
        \\    }
        \\
        \\    /// @dev Returns all the indices of `needle` in `subject`.
        \\    /// The indices are byte offsets.
        \\    function indicesOf(string memory subject, string memory needle)
        \\        internal
        \\        pure
        \\        returns (uint256[] memory)
        \\    {
        \\        return LibBytes.indicesOf(bytes(subject), bytes(needle));
        \\    }
        \\
        \\    /// @dev Returns a arrays of strings based on the `delimiter` inside of the `subject` string.
        \\    function split(string memory subject, string memory delimiter)
        \\        internal
        \\        pure
        \\        returns (string[] memory result)
        \\    {
        \\        bytes[] memory a = LibBytes.split(bytes(subject), bytes(delimiter));
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := a
        \\        }
        \\    }
        \\
        \\    /// @dev Returns a concatenated string of `a` and `b`.
        \\    /// Cheaper than `string.concat()` and does not de-align the free memory pointer.
        \\    function concat(string memory a, string memory b) internal pure returns (string memory) {
        \\        return string(LibBytes.concat(bytes(a), bytes(b)));
        \\    }
        \\
        \\    /// @dev Returns a copy of the string in either lowercase or UPPERCASE.
        \\    /// WARNING! This function is only compatible with 7-bit ASCII strings.
        \\    function toCase(string memory subject, bool toUpper)
        \\        internal
        \\        pure
        \\        returns (string memory result)
        \\    {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let n := mload(subject)
        \\            if n {
        \\                result := mload(0x40)
        \\                let o := add(result, 0x20)
        \\                let d := sub(subject, result)
        \\                let flags := shl(add(70, shl(5, toUpper)), 0x3ffffff)
        \\                for { let end := add(o, n) } 1 {} {
        \\                    let b := byte(0, mload(add(d, o)))
        \\                    mstore8(o, xor(and(shr(b, flags), 0x20), b))
        \\                    o := add(o, 1)
        \\                    if eq(o, end) { break }
        \\                }
        \\                mstore(result, n) // Store the length.
        \\                mstore(o, 0) // Zeroize the slot after the string.
        \\                mstore(0x40, add(o, 0x20)) // Allocate memory.
        \\            }
        \\        }
        \\    }
        \\
        \\    /// @dev Returns a string from a small bytes32 string.
        \\    /// `s` must be null-terminated, or behavior will be undefined.
        \\    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40)
        \\            let n := 0
        \\            for {} byte(n, s) { n := add(n, 1) } {} // Scan for '\0'.
        \\            mstore(result, n) // Store the length.
        \\            let o := add(result, 0x20)
        \\            mstore(o, s) // Store the bytes of the string.
        \\            mstore(add(o, n), 0) // Zeroize the slot after the string.
        \\            mstore(0x40, add(result, 0x40)) // Allocate memory.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the small string, with all bytes after the first null byte zeroized.
        \\    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            for {} byte(result, s) { result := add(result, 1) } {} // Scan for '\0'.
        \\            mstore(0x00, s)
        \\            mstore(result, 0x00)
        \\            result := mload(0x00)
        \\        }
        \\    }
        \\
        \\    /// @dev Returns the string as a normalized null-terminated small string.
        \\    function toSmallString(string memory s) internal pure returns (bytes32 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(s)
        \\            if iszero(lt(result, 33)) {
        \\                mstore(0x00, 0xec92f9a3) // `TooBigForSmallString()`.
        \\                revert(0x1c, 0x04)
        \\            }
        \\            result := shl(shl(3, sub(32, result)), mload(add(s, result)))
        \\        }
        \\    }
        \\
        \\    /// @dev Returns a lowercased copy of the string.
        \\    /// WARNING! This function is only compatible with 7-bit ASCII strings.
        \\    function lower(string memory subject) internal pure returns (string memory result) {
        \\        result = toCase(subject, false);
        \\    }
        \\
        \\    /// @dev Returns an UPPERCASED copy of the string.
        \\    /// WARNING! This function is only compatible with 7-bit ASCII strings.
        \\    function upper(string memory subject) internal pure returns (string memory result) {
        \\        result = toCase(subject, true);
        \\    }
        \\
        \\    /// @dev Escapes the string to be used within HTML tags.
        \\    function escapeHTML(string memory s) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40)
        \\            let end := add(s, mload(s))
        \\            let o := add(result, 0x20)
        \\            // Store the bytes of the packed offsets and strides into the scratch space.
        \\            // `packed = (stride << 5) | offset`. Max offset is 20. Max stride is 6.
        \\            mstore(0x1f, 0x900094)
        \\            mstore(0x08, 0xc0000000a6ab)
        \\            // Store "&quot;&amp;&#39;&lt;&gt;" into the scratch space.
        \\            mstore(0x00, shl(64, 0x2671756f743b26616d703b262333393b266c743b2667743b))
        \\            for {} iszero(eq(s, end)) {} {
        \\                s := add(s, 1)
        \\                let c := and(mload(s), 0xff)
        \\                // Not in `["\"","'","&","<",">"]`.
        \\                if iszero(and(shl(c, 1), 0x500000c400000000)) {
        \\                    mstore8(o, c)
        \\                    o := add(o, 1)
        \\                    continue
        \\                }
        \\                let t := shr(248, mload(c))
        \\                mstore(o, mload(and(t, 0x1f)))
        \\                o := add(o, shr(5, t))
        \\            }
        \\            mstore(o, 0) // Zeroize the slot after the string.
        \\            mstore(result, sub(o, add(result, 0x20))) // Store the length.
        \\            mstore(0x40, add(o, 0x20)) // Allocate memory.
        \\        }
        \\    }
        \\
        \\    /// @dev Escapes the string to be used within double-quotes in a JSON.
        \\    /// If `addDoubleQuotes` is true, the result will be enclosed in double-quotes.
        \\    function escapeJSON(string memory s, bool addDoubleQuotes)
        \\        internal
        \\        pure
        \\        returns (string memory result)
        \\    {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40)
        \\            let o := add(result, 0x20)
        \\            if addDoubleQuotes {
        \\                mstore8(o, 34)
        \\                o := add(1, o)
        \\            }
        \\            // Store "\\u0000" in scratch space.
        \\            // Store "0123456789abcdef" in scratch space.
        \\            // Also, store `{0x08:"b", 0x09:"t", 0x0a:"n", 0x0c:"f", 0x0d:"r"}`.
        \\            // into the scratch space.
        \\            mstore(0x15, 0x5c75303030303031323334353637383961626364656662746e006672)
        \\            // Bitmask for detecting `["\"","\\"]`.
        \\            let e := or(shl(0x22, 1), shl(0x5c, 1))
        \\            for { let end := add(s, mload(s)) } iszero(eq(s, end)) {} {
        \\                s := add(s, 1)
        \\                let c := and(mload(s), 0xff)
        \\                if iszero(lt(c, 0x20)) {
        \\                    if iszero(and(shl(c, 1), e)) {
        \\                        // Not in `["\"","\\"]`.
        \\                        mstore8(o, c)
        \\                        o := add(o, 1)
        \\                        continue
        \\                    }
        \\                    mstore8(o, 0x5c) // "\\".
        \\                    mstore8(add(o, 1), c)
        \\                    o := add(o, 2)
        \\                    continue
        \\                }
        \\                if iszero(and(shl(c, 1), 0x3700)) {
        \\                    // Not in `["\b","\t","\n","\f","\d"]`.
        \\                    mstore8(0x1d, mload(shr(4, c))) // Hex value.
        \\                    mstore8(0x1e, mload(and(c, 15))) // Hex value.
        \\                    mstore(o, mload(0x19)) // "\\u00XX".
        \\                    o := add(o, 6)
        \\                    continue
        \\                }
        \\                mstore8(o, 0x5c) // "\\".
        \\                mstore8(add(o, 1), mload(add(c, 8)))
        \\                o := add(o, 2)
        \\            }
        \\            if addDoubleQuotes {
        \\                mstore8(o, 34)
        \\                o := add(1, o)
        \\            }
        \\            mstore(o, 0) // Zeroize the slot after the string.
        \\            mstore(result, sub(o, add(result, 0x20))) // Store the length.
        \\            mstore(0x40, add(o, 0x20)) // Allocate memory.
        \\        }
        \\    }
        \\
        \\    /// @dev Escapes the string to be used within double-quotes in a JSON.
        \\    function escapeJSON(string memory s) internal pure returns (string memory result) {
        \\        result = escapeJSON(s, false);
        \\    }
        \\
        \\    /// @dev Encodes `s` so that it can be safely used in a URI,
        \\    /// just like `encodeURIComponent` in JavaScript.
        \\    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
        \\    /// See: https://datatracker.ietf.org/doc/html/rfc2396
        \\    /// See: https://datatracker.ietf.org/doc/html/rfc3986
        \\    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40)
        \\            // Store "0123456789ABCDEF" in scratch space.
        \\            // Uppercased to be consistent with JavaScript's implementation.
        \\            mstore(0x0f, 0x30313233343536373839414243444546)
        \\            let o := add(result, 0x20)
        \\            for { let end := add(s, mload(s)) } iszero(eq(s, end)) {} {
        \\                s := add(s, 1)
        \\                let c := and(mload(s), 0xff)
        \\                // If not in `[0-9A-Z-a-z-_.!~*'()]`.
        \\                if iszero(and(1, shr(c, 0x47fffffe87fffffe03ff678200000000))) {
        \\                    mstore8(o, 0x25) // '%'.
        \\                    mstore8(add(o, 1), mload(and(shr(4, c), 15)))
        \\                    mstore8(add(o, 2), mload(and(c, 15)))
        \\                    o := add(o, 3)
        \\                    continue
        \\                }
        \\                mstore8(o, c)
        \\                o := add(o, 1)
        \\            }
        \\            mstore(result, sub(o, add(result, 0x20))) // Store the length.
        \\            mstore(o, 0) // Zeroize the slot after the string.
        \\            mstore(0x40, add(o, 0x20)) // Allocate memory.
        \\        }
        \\    }
        \\
        \\    /// @dev Returns whether `a` equals `b`.
        \\    function eq(string memory a, string memory b) internal pure returns (bool result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := eq(keccak256(add(a, 0x20), mload(a)), keccak256(add(b, 0x20), mload(b)))
        \\        }
        \\    }
        \\
        \\    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small string.
        \\    function eqs(string memory a, bytes32 b) internal pure returns (bool result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // These should be evaluated on compile time, as far as possible.
        \\            let m := not(shl(7, div(not(iszero(b)), 255))) // `0x7f7f ...`.
        \\            let x := not(or(m, or(b, add(m, and(b, m)))))
        \\            let r := shl(7, iszero(iszero(shr(128, x))))
        \\            r := or(r, shl(6, iszero(iszero(shr(64, shr(r, x))))))
        \\            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
        \\            r := or(r, shl(4, lt(0xffff, shr(r, x))))
        \\            r := or(r, shl(3, lt(0xff, shr(r, x))))
        \\            // forgefmt: disable-next-item
        \\            result := gt(eq(mload(a), add(iszero(x), xor(31, shr(3, r)))),
        \\                xor(shr(add(8, r), b), shr(add(8, r), mload(add(a, 0x20)))))
        \\        }
        \\    }
        \\
        \\    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
        \\    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
        \\    function cmp(string memory a, string memory b) internal pure returns (int256) {
        \\        return LibBytes.cmp(bytes(a), bytes(b));
        \\    }
        \\
        \\    /// @dev Packs a single string with its length into a single word.
        \\    /// Returns `bytes32(0)` if the length is zero or greater than 31.
        \\    function packOne(string memory a) internal pure returns (bytes32 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            // We don't need to zero right pad the string,
        \\            // since this is our own custom non-standard packing scheme.
        \\            result :=
        \\                mul(
        \\                    // Load the length and the bytes.
        \\                    mload(add(a, 0x1f)),
        \\                    // `length != 0 && length < 32`. Abuses underflow.
        \\                    // Assumes that the length is valid and within the block gas limit.
        \\                    lt(sub(mload(a), 1), 0x1f)
        \\                )
        \\        }
        \\    }
        \\
        \\    /// @dev Unpacks a string packed using {packOne}.
        \\    /// Returns the empty string if `packed` is `bytes32(0)`.
        \\    /// If `packed` is not an output of {packOne}, the output behavior is undefined.
        \\    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            result := mload(0x40) // Grab the free memory pointer.
        \\            mstore(0x40, add(result, 0x40)) // Allocate 2 words (1 for the length, 1 for the bytes).
        \\            mstore(result, 0) // Zeroize the length slot.
        \\            mstore(add(result, 0x1f), packed) // Store the length and bytes.
        \\            mstore(add(add(result, 0x20), mload(result)), 0) // Right pad with zeroes.
        \\        }
        \\    }
        \\
        \\    /// @dev Packs two strings with their lengths into a single word.
        \\    /// Returns `bytes32(0)` if combined length is zero or greater than 30.
        \\    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            let aLen := mload(a)
        \\            // We don't need to zero right pad the strings,
        \\            // since this is our own custom non-standard packing scheme.
        \\            result :=
        \\                mul(
        \\                    or( // Load the length and the bytes of `a` and `b`.
        \\                    shl(shl(3, sub(0x1f, aLen)), mload(add(a, aLen))), mload(sub(add(b, 0x1e), aLen))),
        \\                    // `totalLen != 0 && totalLen < 31`. Abuses underflow.
        \\                    // Assumes that the lengths are valid and within the block gas limit.
        \\                    lt(sub(add(aLen, mload(b)), 1), 0x1e)
        \\                )
        \\        }
        \\    }
        \\
        \\    /// @dev Unpacks strings packed using {packTwo}.
        \\    /// Returns the empty strings if `packed` is `bytes32(0)`.
        \\    /// If `packed` is not an output of {packTwo}, the output behavior is undefined.
        \\    function unpackTwo(bytes32 packed)
        \\        internal
        \\        pure
        \\        returns (string memory resultA, string memory resultB)
        \\    {
        \\        /// @solidity memory-safe-assembly
        \\        assembly {
        \\            resultA := mload(0x40) // Grab the free memory pointer.
        \\            resultB := add(resultA, 0x40)
        \\            // Allocate 2 words for each string (1 for the length, 1 for the byte). Total 4 words.
        \\            mstore(0x40, add(resultB, 0x40))
        \\            // Zeroize the length slots.
        \\            mstore(resultA, 0)
        \\            mstore(resultB, 0)
        \\            // Store the lengths and bytes.
        \\            mstore(add(resultA, 0x1f), packed)
        \\            mstore(add(resultB, 0x1f), mload(add(add(resultA, 0x20), mload(resultA))))
        \\            // Right pad with zeroes.
        \\            mstore(add(add(resultA, 0x20), mload(resultA)), 0)
        \\            mstore(add(add(resultB, 0x20), mload(resultB)), 0)
        \\        }
        \\    }
        \\
        \\    /// @dev Directly returns `a` without copying.
        \\    function directReturn(string memory a) internal pure {
        \\        assembly {
        \\            // Assumes that the string does not start from the scratch space.
        \\            let retStart := sub(a, 0x20)
        \\            let retUnpaddedSize := add(mload(a), 0x40)
        \\            // Right pad with zeroes. Just in case the string is produced
        \\            // by a method that doesn't zero right pad.
        \\            mstore(add(retStart, retUnpaddedSize), 0)
        \\            mstore(retStart, 0x20) // Store the return offset.
        \\            // End the transaction, returning the string.
        \\            return(retStart, and(not(0x1f), add(0x1f, retUnpaddedSize)))
        \\        }
        \\    }
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    var list = std.ArrayList(u8).init(testing.allocator);
    errdefer list.deinit();

    var format: Formatter = .init(ast, 4, list.writer());
    try format.format();

    const fmt = try list.toOwnedSliceSentinel(0);
    defer testing.allocator.free(fmt);

    var ast_fmt = try Ast.parse(testing.allocator, fmt);
    defer ast_fmt.deinit(testing.allocator);

    try testing.expectEqual(0, ast_fmt.errors.len);
}
