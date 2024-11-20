const tokenizer = @import("zabi").ast.tokenizer;
const std = @import("std");
const testing = std.testing;

const Parser = @import("zabi").ast.Parser;
const Ast = @import("zabi").ast.Ast;

test "Pragma" {
    var tokens: Ast.TokenList = .{};
    defer tokens.deinit(testing.allocator);

    var parser: Parser = undefined;
    defer parser.deinit();

    try buildParser("pragma solidity >=0.8.20 <=0.8.0;", &tokens, &parser);

    _ = try parser.parsePragmaDirective();
}

test "Import" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_path, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import \"foo/bar/baz\" as Baz;", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_path_identifier, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import * as console from \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_asterisk, parser.nodes.items(.tag)[import]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("import {fooo, bar, bazz} from \"foo/bar/baz\";", &tokens, &parser);

        const import = try parser.parseImportDirective();

        try testing.expectEqual(.import_directive_symbol, parser.nodes.items(.tag)[import]);
    }
}

test "Enum" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum foo{bar, baz}", &tokens, &parser);

        const enum_tag = try parser.parseEnum();

        try testing.expectEqual(.enum_decl, parser.nodes.items(.tag)[enum_tag]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum foo{bar}", &tokens, &parser);

        const enum_tag = try parser.parseEnum();

        try testing.expectEqual(.enum_decl_one, parser.nodes.items(.tag)[enum_tag]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum foo{bar, baz,}", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEnum());
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("enum{bar, baz}", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEnum());
    }
}

test "Mapping" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => mapping(uint => int)foo)bar", &tokens, &parser);

        const mapping = try parser.parseMapping();

        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => mapping(uint => int)foo;)bar;", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping());
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => )bar", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping());
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping( => uint )bar", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseMapping());
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => address)bar", &tokens, &parser);

        const mapping = try parser.parseMapping();

        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(uint => foo.bar)bar", &tokens, &parser);

        const mapping = try parser.parseMapping();

        const data = parser.nodes.items(.data)[mapping];
        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
        try testing.expectEqual(.elementary_type, parser.nodes.items(.tag)[data.lhs]);
        try testing.expectEqual(.field_access, parser.nodes.items(.tag)[data.rhs]);
    }

    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("mapping(foo.bar => uint)bar", &tokens, &parser);

        const mapping = try parser.parseMapping();

        const data = parser.nodes.items(.data)[mapping];
        try testing.expectEqual(.mapping_decl, parser.nodes.items(.tag)[mapping]);
        try testing.expectEqual(.field_access, parser.nodes.items(.tag)[data.lhs]);
    }
}

test "Function Type" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function() external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_type_simple, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address bar) external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_type_simple, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar, foo.bar calldata baz) external payable", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_type_multi, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar) external payable returns(string)", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_type_one, parser.nodes.items(.tag)[fn_proto]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("function(address foobar, bar calldata baz) external payable returns(bool, string memory)", &tokens, &parser);
        const fn_proto = try parser.parseFunctionType();

        try testing.expectEqual(.function_type, parser.nodes.items(.tag)[fn_proto]);
    }
}

test "Struct" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("struct Foo{uint foo;}", &tokens, &parser);

        try parser.nodes.append(testing.allocator, .{
            .tag = .root,
            .main_token = 0,
            .data = undefined,
        });
        const struct_key = try parser.parseStruct();

        const data = parser.nodes.items(.data)[struct_key];
        try testing.expectEqual(.struct_decl_one, parser.nodes.items(.tag)[struct_key]);
        try testing.expectEqual(.identifier, parser.token_tags[data.lhs]);
        try testing.expectEqual(.struct_field, parser.nodes.items(.tag)[data.rhs]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("struct Foo{uint foo;\n bar baz;}", &tokens, &parser);
        try parser.nodes.append(testing.allocator, .{
            .tag = .root,
            .main_token = 0,
            .data = undefined,
        });

        const struct_key = try parser.parseStruct();

        try testing.expectEqual(.struct_decl, parser.nodes.items(.tag)[struct_key]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("struct Foo{;}", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseStruct());
    }
}

test "Event" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("event Foo(uint[foo.bar * 69] foo);", &tokens, &parser);

        const event = try parser.parseEvent();

        const data = parser.nodes.items(.data)[event];
        try testing.expectEqual(.event_proto_simple, parser.nodes.items(.tag)[event]);
        try testing.expectEqual(.event_variable_decl, parser.nodes.items(.tag)[parser.extra_data.items[data.lhs]]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("event Foo(bar foo, address indexed bar);", &tokens, &parser);

        const event = try parser.parseEvent();

        const data = parser.nodes.items(.data)[event];
        try testing.expectEqual(.event_proto_multi, parser.nodes.items(.tag)[event]);
        try testing.expectEqual(.event_variable_decl, parser.nodes.items(.tag)[parser.extra_data.items[data.lhs]]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("event Foo(bar calldata foo, address indexed bar);", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEvent());
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("event Foo(bar,, foo, address indexed bar)", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseEvent());
    }
}

test "Error" {
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("error Foo(uint foo);", &tokens, &parser);

        const event = try parser.parseError();

        const data = parser.nodes.items(.data)[event];
        try testing.expectEqual(.error_proto_simple, parser.nodes.items(.tag)[event]);
        try testing.expectEqual(.error_variable_decl, parser.nodes.items(.tag)[data.rhs]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("error Foo();", &tokens, &parser);

        const err = try parser.parseError();

        const data = parser.nodes.items(.data)[err];
        try testing.expectEqual(.error_proto_simple, parser.nodes.items(.tag)[err]);
        try testing.expectEqual(0, data.rhs);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("error Foo(uint foo, foo bar);", &tokens, &parser);

        const event = try parser.parseError();

        const data = parser.nodes.items(.data)[event];
        try testing.expectEqual(.error_proto_multi, parser.nodes.items(.tag)[event]);
        try testing.expectEqual(.error_variable_decl, parser.nodes.items(.tag)[parser.extra_data.items[data.lhs]]);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("error Foo(uint foo,);", &tokens, &parser);

        _ = try parser.parseError();
        // Trailing comma but we keep parsing.
        try testing.expectEqual(1, parser.errors.items.len);
    }
    {
        var tokens: Ast.TokenList = .{};
        defer tokens.deinit(testing.allocator);

        var parser: Parser = undefined;
        defer parser.deinit();

        try buildParser("error Foo(address, bar, calldata)", &tokens, &parser);

        try testing.expectError(error.ParsingError, parser.parseError());
    }
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

    try testing.expectEqual(ast.nodes.items(.tag)[ast.nodes.len - 1], .contract_decl);
    try testing.expectEqual(0, ast.errors.len);
}

test "Parsing source units" {
    const slice =
        \\   function vote(uint proposal) public;
        \\   function votee(uint proposal) public {}
        \\   pragma solidity >=0.8.20 <=0.8.0;
        \\   error Jazz(uint boo);
        \\   enum Bazz {boooooooooo}
        \\   enum Bazzz {boooooooooo, foooooooooo}
        \\   using foo.bar for int256;
        \\   using {console, hello} for * global;
        \\   type foo_bar is address;
        \\   uint constant foo = 69;
        \\
        \\   event Foo(address bar);
        \\   event Baz(address indexed bar) anonymous;
        \\   interface Bar is foo.baz {}
        \\   interface Bar is foo.baz, baz.foo {uint public lol = 69;}
        \\   library Bar {address public ads; int8 private fds;}
        \\   function winningProposal() public view
        \\           returns (uint winningProposal_, address l)
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
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    try testing.expectEqual(0, ast.errors.len);
}

test "It can parse a even with errors" {
    const slice =
        \\   pragma solidity 0.8.20;
        \\   import \"foo/bar/baz\" as Baz;
        \\   uint constant foo = 69;
        \\   struct Voter {
        \\       uint weight; // weight is accumulated by delegation
        \\       bool voted;  // if true, that person already voted
        \\       address delegate; // person delegated to
        \\       uint vote;   // index of the voted proposal
        \\   }
        \\
        \\       abstract contract Ballot {
        \\
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
        \\   foo + bar != baz;
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
        \\   }
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
        \\           }
        \\       }
        \\   }
        \\
        \\
        \\   /**
        \\    * @dev Calls winningProposal() function to get the index of the winner contained in the proposals array and then
        \\    * @return winnerName_ the name of the winner
        \\    */
        \\   function winnerName() public view
        \\           returns (bytes32 winnerName_)
        \\   {
        \\       winnerName_ = proposals[winningProposal()].name;
        \\   }
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    try testing.expect(ast.errors.len != 0);
}

test "Try and Catch" {
    const slice =
        \\contract Bar {
        \\    event Log(string message);
        \\    event LogBytes(bytes data);
        \\
        \\    Foo public foo;
        \\
        \\    constructor() {
        \\        // This Foo contract is used for example of try catch with external call
        \\        foo = new Foo(msg.sender);
        \\    }
        \\
        \\    // Example of try / catch with external call
        \\    // tryCatchExternalCall(0) => Log("external call failed")
        \\    // tryCatchExternalCall(1) => Log("my func was called")
        \\    function tryCatchExternalCall(uint256 _i) public {
        \\        try foo.myFunc(_i) returns (string memory result) {
        \\            emit Log(result);
        \\        } catch {
        \\            emit Log("external call failed");
        \\        }
        \\    }
        \\
        \\    // Example of try / catch with contract creation
        \\    // tryCatchNewContract(0x0000000000000000000000000000000000000000) => Log("invalid address")
        \\    // tryCatchNewContract(0x0000000000000000000000000000000000000001) => LogBytes("")
        \\    // tryCatchNewContract(0x0000000000000000000000000000000000000002) => Log("Foo created")
        \\    function tryCatchNewContract(address _owner) public {
        \\        try new Foo(_owner) returns (Foo foo) {
        \\            // you can use variable foo here
        \\            emit Log("Foo created");
        \\        } catch Error(string memory reason) {
        \\            // catch failing revert() and require()
        \\            emit Log(reason);
        \\        } catch (bytes memory reason) {
        \\            // catch failing assert()
        \\            emit LogBytes(reason);
        \\        }
        \\    }
        \\}
    ;

    var ast = try Ast.parse(testing.allocator, slice);
    defer ast.deinit(testing.allocator);

    try testing.expectEqual(0, ast.errors.len);
}

test "Uniswap V3" {
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
        \\    IERC20 private dai = IERC20(DAI);
        \\    IWETH private weth = IWETH(WETH);
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

    try testing.expectEqual(0, ast.errors.len);
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

    try testing.expectEqual(0, ast.errors.len);
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

    try testing.expectEqual(0, ast.errors.len);
}

fn buildParser(source: [:0]const u8, tokens: *Ast.TokenList, parser: *Parser) !void {
    var lexer = tokenizer.Tokenizer.init(source);

    while (true) {
        const token = lexer.next();

        try tokens.append(testing.allocator, .{
            .tag = token.tag,
            .start = @intCast(token.location.start),
        });

        if (token.tag == .eof) break;
    }

    parser.* = .{
        .source = source,
        .allocator = testing.allocator,
        .token_index = 0,
        .token_tags = tokens.items(.tag),
        .token_starts = tokens.items(.start),
        .nodes = .{},
        .errors = .{},
        .scratch = .{},
        .extra_data = .{},
    };
}
