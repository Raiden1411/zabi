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

test "It can parse a contract without errors" {
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

    try ast_fmt.renderError(ast_fmt.errors[0], std.io.getStdErr().writer());
    std.debug.print("\nFormatted:\n{s}", .{fmt});

    try testing.expectEqual(0, ast_fmt.errors.len);
}
