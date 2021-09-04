const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const lizp = @import("lizp.zig");
const LizpErr = lizp.LizpErr;
const LizpExp = lizp.LizpExp;
const LizpExpRest = lizp.LizpExpRest;

/// Parses an array of tokens into a LizpExp
pub fn parse(input: [][]const u8) LizpErr!LizpExp {
    const expression = try parseTokens(input);
    return expression.exp;
}

/// Take an array of tokens and parses into a potentially nested
/// LizpExp, sealed in a LizpExpRest to help with recursion.
fn parseTokens(tokens: [][]const u8) LizpErr!LizpExpRest {
    var token = tokens[0];
    if (std.mem.eql(u8, token, "(")) {
        return parseRest(tokens[1..tokens.len]);
    } else if (std.mem.eql(u8, token, ")")) {
        return LizpErr.UnexpectedClosingParen;
    } else {
        return LizpExpRest{ .exp = parseAtom(token), .rest = tokens[1..tokens.len] };
    }
}

/// Takes a single token and returns, in order of precedence:
/// 1. A boolean, if possible,
/// 2. A number, if possible,
/// 3. A symbol.
fn parseAtom(atom: []const u8) LizpExp {
    if (std.mem.eql(u8, atom, "true")) return LizpExp{ .Bool = true };
    if (std.mem.eql(u8, atom, "false")) return LizpExp{ .Bool = false };
    var float_val: f64 = std.fmt.parseFloat(f64, atom) catch return LizpExp{ .Symbol = atom };
    return LizpExp{ .Number = float_val };
}

/// Parses everything up to next the ")" and then returns a LizpExp.List
/// with the parsed list, and then the rest of the tokens after the ")".
fn parseRest(tokens: [][]const u8) LizpErr!LizpExpRest {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var res = std.ArrayList(LizpExp).init(&gpa.allocator);
    var rest: [][]const u8 = tokens;
    while (true) {
        if (rest.len == 0) {
            return LizpErr.NoClosingParen;
        }
        var next_token: []const u8 = rest[0];
        if (std.mem.eql(u8, next_token, ")")) {
            rest = rest[1..rest.len]; // Skip over the ) and return the rest of the tokens
            return LizpExpRest{ .exp = LizpExp{ .List = res.items }, .rest = rest };
        }
        var intermediate: LizpExpRest = try parseTokens(rest);
        res.append(intermediate.exp) catch unreachable;
        rest = intermediate.rest;
    }
}

test "parseAtom" {
    var float_atom = parseAtom("1.234");
    try expect(float_atom == LizpExp.Number);
    try expect(float_atom.Number == 1.234);

    try expect(parseAtom("my-atom") == LizpExp.Symbol);

    var bool_atom = parseAtom("true");
    try expect(bool_atom == LizpExp.Bool);
    try expect(bool_atom.Bool == true);
}

test "parse" {
    const tokenize = @import("tokenize.zig");
    var token_string = "(+ 1 2)";
    var tokens = try tokenize.tokenize(token_string);
    var lizp_expression = try parse(tokens);
    try expect(lizp_expression == LizpExp.List);
    try expect(lizp_expression.List[0] == LizpExp.Symbol);
    try expect(lizp_expression.List[1] == LizpExp.Number);
    try expect(lizp_expression.List[1].Number == 1);
}

test "parseTokens happy-path" {
    const tokenize = @import("tokenize.zig");
    var token_string = "(+ 1 2)";
    var tokens = try tokenize.tokenize(token_string);
    var parse_result = try parseTokens(tokens);
    var lizp_expression = parse_result.exp;
    try expect(lizp_expression == LizpExp.List);
    try expect(lizp_expression.List[0] == LizpExp.Symbol);
    try expect(lizp_expression.List[1] == LizpExp.Number);
    try expect(lizp_expression.List[1].Number == 1);
}

test "parseTokens bad-expression" {
    const tokenize = @import("tokenize.zig");
    var token_string = ") bad-exp (";
    var tokens = try tokenize.tokenize(token_string);
    try expectError(LizpErr.UnexpectedClosingParen, parseTokens(tokens));
}

test "parseTokens no closing" {
    const tokenize = @import("tokenize.zig");
    var token_string = "(+ 1 2";
    var tokens = try tokenize.tokenize(token_string);
    try expectError(LizpErr.NoClosingParen, parseTokens(tokens));
}

test "parseRest" {
    const tokenize = @import("tokenize.zig");
    var token_string = "+ 1 2 ) some more expressions";
    var tokens = try tokenize.tokenize(token_string);
    var result = try parseRest(tokens);
    try expect(result.exp == LizpExp.List);
    try expect(std.mem.eql(u8, result.rest[1], "more"));
}
