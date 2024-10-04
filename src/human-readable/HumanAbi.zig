const abi = @import("../abi/abi.zig");
const param = @import("../abi/abi_parameter.zig");
const param_types = @import("../abi/param_type.zig");
const std = @import("std");
const tokens = @import("tokens.zig");

const AbiParameter = param.AbiParameter;
const AbiEventParameter = param.AbiEventParameter;
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const AbiConstructor = abi.Constructor;
const AbiEvent = abi.Event;
const AbiError = abi.Error;
const AbiFallback = abi.Fallback;
const AbiReceive = abi.Receive;
const Node = Ast.Node;
const ParamErrors = param_types.ParamErrors;
const ParamType = param_types.ParamType;
const Parser = @import("ParserNew.zig");
const StateMutability = @import("../abi/state_mutability.zig").StateMutability;

/// Set of erros when generating the ABI
pub const HumanAbiErrors = ParamErrors || Allocator.Error;

const HumanAbi = @This();

allocator: Allocator,
ast: *const Ast,

pub fn toAbiConstructorMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiConstructor {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .constructor_proto_multi);

    const ast_constructor = self.ast.constructorProtoMulti(node);

    const params = try self.toAbiParameters(ast_constructor.ast.params);

    return .{
        .type = .constructor,
        .inputs = params,
        .stateMutability = if (ast_constructor.payable != null) .payable else .nonpayable,
    };
}

pub fn toAbiConstructorSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiConstructor {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .constructor_proto_simple);

    var buffer: [1]Node.Index = undefined;
    const ast_constructor = self.ast.constructorProtoSimple(&buffer, node);

    const params = try self.toAbiParameters(ast_constructor.ast.params);

    return .{
        .type = .constructor,
        .inputs = params,
        .stateMutability = if (ast_constructor.payable != null) .payable else .nonpayable,
    };
}

pub fn toAbiEventMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEvent {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .event_proto_multi);

    const ast_event = self.ast.eventProtoMulti(node);

    const params = try self.toAbiEventParameters(ast_event.ast.params);

    return .{
        .type = .event,
        .name = self.ast.tokenSlice(ast_event.name),
        .inputs = params,
    };
}

pub fn toAbiEventSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEvent {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .event_proto_simple);

    var buffer: [1]Node.Index = undefined;
    const ast_event = self.ast.eventProtoSimple(&buffer, node);

    const params = try self.toAbiEventParameters(ast_event.ast.params);

    return .{
        .type = .event,
        .name = self.ast.tokenSlice(ast_event.name),
        .inputs = params,
    };
}

pub fn toAbiErrorMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiError {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .error_proto_multi);

    const ast_error = self.ast.errorProtoMulti(node);

    const params = try self.toAbiParametersFromErrorDecl(ast_error.ast.params);

    return .{
        .type = .@"error",
        .name = self.ast.tokenSlice(ast_error.name),
        .inputs = params,
    };
}

pub fn toAbiErrorSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiError {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .error_proto_simple);

    var buffer: [1]Node.Index = undefined;
    const ast_error = self.ast.errorProtoSimple(&buffer, node);

    const params = try self.toAbiParametersFromErrorDecl(ast_error.ast.params);

    return .{
        .type = .@"error",
        .name = self.ast.tokenSlice(ast_error.name),
        .inputs = params,
    };
}

pub fn toAbiParameters(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiParameter {
    var params = try std.ArrayList(AbiParameter).initCapacity(self.allocator, nodes.len);
    errdefer params.deinit();

    for (nodes) |node| {
        params.appendAssumeCapacity(try self.toAbiParameter(node));
    }

    return params.toOwnedSlice();
}

pub fn toAbiParametersFromErrorDecl(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiParameter {
    var params = try std.ArrayList(AbiParameter).initCapacity(self.allocator, nodes.len);
    errdefer params.deinit();

    for (nodes) |node| {
        params.appendAssumeCapacity(try self.toAbiParameterFromErrorDecl(node));
    }

    return params.toOwnedSlice();
}

pub fn toAbiEventParameters(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiEventParameter {
    var params = try std.ArrayList(AbiEventParameter).initCapacity(self.allocator, nodes.len);
    errdefer params.deinit();

    for (nodes) |node| {
        params.appendAssumeCapacity(try self.toAbiEventParameter(node));
    }

    return params.toOwnedSlice();
}

pub fn toAbiParameter(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiParameter {
    const nodes = self.ast.nodes.items(.tag);
    const data = self.ast.nodes.items(.data);
    const main = self.ast.nodes.items(.main_token);
    std.debug.assert(nodes[node] == .var_decl);

    const type_slice = self.ast.tokenSlice(main[data[node].lhs]);
    const param_type = try ParamType.typeToUnion(type_slice, self.allocator);

    return .{
        .type = param_type,
        .name = if (data[node].rhs == 0) "" else self.ast.tokenSlice(data[node].rhs),
    };
}

pub fn toAbiEventParameter(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEventParameter {
    const nodes = self.ast.nodes.items(.tag);
    const data = self.ast.nodes.items(.data);
    const main = self.ast.nodes.items(.main_token);
    std.debug.assert(nodes[node] == .event_var_decl);

    const type_slice = self.ast.tokenSlice(main[data[node].lhs]);
    const param_type = try ParamType.typeToUnion(type_slice, self.allocator);

    return .{
        .type = param_type,
        .name = if (data[node].rhs == 0) "" else self.ast.tokenSlice(data[node].rhs),
        .indexed = if (main[node] != 0) true else false,
    };
}

pub fn toAbiParameterFromErrorDecl(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiParameter {
    const nodes = self.ast.nodes.items(.tag);
    const data = self.ast.nodes.items(.data);
    const main = self.ast.nodes.items(.main_token);
    std.debug.assert(nodes[node] == .error_var_decl);

    const type_slice = self.ast.tokenSlice(main[data[node].lhs]);
    const param_type = try ParamType.typeToUnion(type_slice, self.allocator);

    return .{
        .type = param_type,
        .name = if (main[node] == 0) "" else self.ast.tokenSlice(main[node]),
    };
}

pub fn toAbiFallbackMulti(self: HumanAbi, node: Node.Index) Allocator.Error!AbiFallback {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .fallback_proto_multi);

    const ast_fallback = self.ast.fallbackProtoMulti(node);

    return .{
        .type = .fallback,
        .stateMutability = if (ast_fallback.payable != null) .payable else .nonpayable,
    };
}

pub fn toAbiFallbackSimple(self: HumanAbi, node: Node.Index) Allocator.Error!AbiFallback {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .fallback_proto_simple);

    var buffer: [1]Node.Index = undefined;
    const ast_fallback = self.ast.fallbackProtoSimple(&buffer, node);

    return .{
        .type = .fallback,
        .stateMutability = if (ast_fallback.payable != null) .payable else .nonpayable,
    };
}

pub fn toAbiReceive(self: HumanAbi, node: Node.Index) (Allocator.Error || error{UnexpectedMutability})!AbiReceive {
    const nodes = self.ast.nodes.items(.tag);
    std.debug.assert(nodes[node] == .receive_proto);

    const ast_receive = self.ast.receiveProto(node);

    return .{
        .type = .receive,
        .stateMutability = if (ast_receive.payable == null) return error.UnexpectedMutability else .payable,
    };
}
