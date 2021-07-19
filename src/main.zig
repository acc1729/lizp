const std = @import("std");
const expect = std.testing.expect;

// const LizpFunc = fn (LizpExp.List) LizpErr!LizpExp;

const LizpExp = union(enum) {
    Symbol: []const u8,
    Number: f64,
    List: []const LizpExp,
    Func: fn ([]const LizpExp) LizpErr!*LizpExp,
};

const LizpErr = error{
    UnexpectedForm,
    UnexpectedClosingParen,
    NoClosingParen,
    NotANumber,
    NotAFunc,
    SymbolNotFound,
    EmptyList,
};

const LizpEnv = struct {
    data: std.StringHashMap(LizpExp),
};

const LizpExpRest = struct {
    exp: LizpExp,
    rest: []const u8,
};

fn tokenizePrepass(str: []const u8) []u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var neededSize1: usize = std.mem.replacementSize(u8, str, "(", " ( ");
    var buff1 = gpa.allocator.alloc(u8, neededSize1) catch unreachable;
    _ = std.mem.replace(u8, str, "(", " ( ", buff1);
    var neededSize2 = std.mem.replacementSize(u8, buff1, ")", " ) ");
    var buff2 = gpa.allocator.alloc(u8, neededSize2) catch unreachable;
    _ = std.mem.replace(u8, buff1, ")", " ) ", buff2);
    return buff2;
}

pub fn tokenize(str: []const u8) std.mem.TokenIterator {
    var prepass = tokenizePrepass(str);
    return std.mem.tokenize(prepass, " ");
}

pub fn parse(tokens: std.mem.TokenIterator) LizpErr!LizpExpRest {
    var token = tokens.next() orelse return LizpErr.NoClosingParen;
    std.log.info("First: {s}", .{token});
    return switch (token) {
        "(" => parseRest(tokens.rest()),
        ")" => return LizpErr.UnexpectedClosingParen,
        else => LizpExpRest{ .exp = parseAtom(token, tokens.rest()), .rest = tokens.rest() },
    };
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

fn lizpSum(list: []const LizpExp) LizpErr!*LizpExp {
    var sum: f64 = 0;
    for (list) |elem| {
        switch (elem) {
            .Number => {
                sum += elem.Number;
            },
            else => {
                return LizpErr.NotANumber;
            },
        }
    }
    return &LizpExp{ .Number = sum };
}

test "lizpSum" {
    const array: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    const result: *LizpExp = try lizpSum(slice);
    try expect(result.* == LizpExp.Number);
    try expect(result.*.Number == 12);
}

fn lizpSub(list: []const LizpExp) LizpErr!*LizpExp {
    var sum: f64 = 0;
    var first: LizpExp = list[0];
    var first_num: f64 = undefined;
    switch (first) {
        .Number => first_num = first.Number,
        else => return LizpErr.NotANumber,
    }
    var rest = list[1..list.len];
    for (rest) |elem| {
        switch (elem) {
            .Number => sum += elem.Number,
            else => return LizpErr.NotANumber,
        }
    }
    return &LizpExp{ .Number = first_num - sum };
}

test "lizpSub" {
    const array: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    const result: *LizpExp = try lizpSub(slice);
    try expect(result.* == LizpExp.Number);
    try expect(result.*.Number == -6);
}

pub fn defaultEnv() !LizpEnv {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var env = std.StringHashMap(LizpExp).init(&gpa.allocator);
    try env.put("+", LizpExp{ .Func = lizpSum });
    try env.put("-", LizpExp{ .Func = lizpSub });
    return LizpEnv{ .data = env };
}

pub fn parseAtom(atom: []const u8) LizpExp {
    var float_val: f64 = std.fmt.parseFloat(f64, atom) catch return LizpExp{ .Symbol = atom };
    return LizpExp{ .Number = float_val };
}

test "parseAtom" {
    var float_atom = parseAtom("1.234");
    try expect(float_atom == LizpExp.Number);
    try expect(float_atom.Number == 1.234);
    try expect(parseAtom("my-atom") == LizpExp.Symbol);
}

pub fn eval(exp: LizpExp, env: LizpEnv) LizpErr!LizpExp {
    return switch (exp) {
        .Symbol => {
            return env.data.get(exp.Symbol) orelse return LizpErr.SymbolNotFound;
        },
        .Number => {
            return exp;
        },
        .List => {
            if (exp.List.len == 0) return LizpErr.EmptyList;
            const first_form = exp.List[0];
            const arg_forms = exp.List[1..];
            switch (first_form) {
                .Func => {
                    // const lizp_list = std.ArrayList(LizpExp);
                    // const gpa = std.heap.GeneralPurposeAllocator(.{}){};
                    // var evaled_args = lizp_list.init(*gpa.allocator);

                    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                    var evaled_args = std.ArrayList(LizpExp).init(&gpa.allocator);
                    for (arg_forms) |arg| {
                        var evaluated_form = try eval(arg, env);
                        try evaled_args.addOne(evaluated_form);
                    }
                    return first_form(&evaled_args.items);
                },
                else => {
                    return LizpErr.NotAFunc;
                },
            }
        },
        .Func => {
            return LizpErr.UnexpectedForm;
        },
    };
}

// test "eval" {
//     const env = defaultEnv();
//     const array: [3]LizpExp = .{ LizpExp{ .Symbol = "+" }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
//     const slice = array[0..3];
//     var exp = LizpExp{ .List = slice };
//     const result = try eval(exp, env);
//     try expect(result == LizpExp.Number);
//     try expect(result.Number == 9);
// }

pub fn main() anyerror!void {
    std.log.warn("All your {s} are belong to us!", .{"CreamTeam"});
}

test "tokenizePrepass" {
    try expect(std.mem.eql(u8, tokenizePrepass("no parens"), "no parens"));
    try expect(std.mem.eql(u8, tokenizePrepass("some (parens)"), "some  ( parens ) "));
    try expect(std.mem.eql(u8, tokenizePrepass("(many () parens)"), " ( many  (  )  parens ) "));
}

test "tokenize" {
    var tokens = tokenize("some (parens)");
    try expect(std.mem.eql(u8, tokens.next() orelse unreachable, "some"));
    try expect(std.mem.eql(u8, tokens.next() orelse unreachable, "("));
    try expect(std.mem.eql(u8, tokens.next() orelse unreachable, "parens"));
}

test "parse" {
    // const it: [][]u8 = &.{ "(", "+", "1", "some-exp", ")" };
    // std.log.warn("Type of it: {s}", .{@TypeOf(it)});
    // _ = parse([][]u8{ "(", "+", "1", "some-exp", ")" });
}
