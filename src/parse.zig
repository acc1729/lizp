const std = @import("std");
const expect = std.testing.expect;

const lizp = @import("lizp.zig");
const LizpErr = lizp.LizpErr;
const LizpExp = lizp.LizpExp;
const LizpExpRest = lizp.LizpExpRest;

pub fn parse(tokens: std.mem.TokenIterator) LizpErr!LizpExpRest {
    var token = tokens.next() orelse return LizpErr.NoClosingParen;
    std.log.info("First: {s}", .{token});
    return switch (token) {
        "(" => parseRest(tokens.rest()),
        ")" => return LizpErr.UnexpectedClosingParen,
        else => LizpExpRest{ .exp = parseAtom(token, tokens.rest()), .rest = tokens.rest() },
    };
}

pub fn parseAtom(atom: []const u8) LizpExp {
    var float_val: f64 = std.fmt.parseFloat(f64, atom) catch return LizpExp{ .Symbol = atom };
    return LizpExp{ .Number = float_val };
}

pub fn parseRest(tokens: []const u8) LizpErr!LizpExpRest {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var res = std.ArrayList(LizpExp).init(*gpa.allocator);
    var rest = tokens;
    while (true) {
        var next_token = rest[0];
        if (rest.length == 0) {
            return LizpErr.NoClosingParen;
        }
        rest = rest[1..rest.length];
        if (next_token == ')') {
            return LizpExpRest{ .exp = LizpExp{ .List = res }, .rest = rest };
        }
        var intermediate: LizpExpRest = parse(rest);
        res.addOne(intermediate.exp);
        rest = intermediate.rest;
    }
}

test "parseAtom" {
    var float_atom = parseAtom("1.234");
    try expect(float_atom == LizpExp.Number);
    try expect(float_atom.Number == 1.234);
    try expect(parseAtom("my-atom") == LizpExp.Symbol);
}

test "parse" {
    // const it: [][]u8 = &.{ "(", "+", "1", "some-exp", ")" };
    // std.log.warn("Type of it: {s}", .{@TypeOf(it)});
    // _ = parse([][]u8{ "(", "+", "1", "some-exp", ")" });
}
