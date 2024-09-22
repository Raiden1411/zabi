const tokenizer = @import("../../ast/tokenizer.zig");
const std = @import("std");
const testing = std.testing;

const Parser = @import("../../ast/Parser.zig");
const Ast = @import("../../ast/Ast.zig");

// test "Pragma" {
//     var tokens: Ast.TokenList = .{};
//     defer tokens.deinit(testing.allocator);
//
//     var parser: Parser = undefined;
//     defer parser.deinit();
//
//     try buildParser("pragma solidity >=0.8.20 <=0.8.0;", &tokens, &parser);
//
//     _ = try parser.parsePragmaDirective();
// }

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

        try buildParser("function(address foobar) external payable returns()", &tokens, &parser);
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

        try buildParser("error Foo(uint foo)", &tokens, &parser);

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

        try buildParser("error Foo(uint foo, foo bar)", &tokens, &parser);

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

        try buildParser("error Foo(uint foo,)", &tokens, &parser);

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

test "Expr" {
    {
        const slice =
            \\ uint constant foo = 69;
            \\   struct Voter {
            \\       uint weight; // weight is accumulated by delegation
            \\       bool voted;  // if true, that person already voted
            \\       address delegate; // person delegated to
            \\       uint vote;   // index of the voted proposal
            \\   }
            \\
            \\       contract Ballot {
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

        // var buffer: [2]u32 = undefined;

        // std.debug.print("FOOOOOO: {}\n", .{ast.variableDecl(4)});
        std.debug.print("FOOOOOO: {any}\n", .{ast.nodes.items(.tag)});
        std.debug.print("FOOOOOO: {any}\n", .{ast.errors});
    }
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
