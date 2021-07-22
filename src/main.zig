const std = @import("std");
const expect = std.testing.expect;

const lizp = @import("lizp.zig");
const parse = @import("parse.zig").parse;
const tokenize = @import("tokenize.zig").tokenize;
const LizpErr = lizp.LizpErr;
const LizpExp = lizp.LizpExp;
const LizpEnv = lizp.LizpEnv;
const LizpExpRest = lizp.LizpExpRest;

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
            var first_form = exp.List[0];
            var first_eval = try eval(first_form, env);
            const arg_forms = exp.List[1..];
            switch (first_eval) {
                .Func => {
                    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                    var evaled_args = std.ArrayList(LizpExp).init(&gpa.allocator);
                    for (arg_forms) |arg| {
                        var evaluated_form = try eval(arg, env);
                        evaled_args.append(evaluated_form) catch return LizpErr.OutOfMemory;
                    }
                    var res = try first_eval.Func(evaled_args.items);
                    return res.*;
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

test "eval" {
    const env: LizpEnv = try lizp.defaultEnv();
    const array: [3]LizpExp = .{ LizpExp{ .Symbol = "+" }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    var exp = LizpExp{ .List = slice };
    const result = try eval(exp, env);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var s = result.to_string(&gpa.allocator);
    std.log.warn("Eval'd exp: '{s}'", .{s});
    try expect(result == LizpExp.Number);
    try expect(result.Number == 9);
}

test "tokenize-parse-eval" {
    const input = "(+ 1 7 (- 13 4))";
    const expression = try parse(try tokenize(input));
    const env = try lizp.defaultEnv();
    const out = try eval(expression.exp, env);
    try expect(out.Number == 17);
}

pub fn main() anyerror!void {
    std.log.warn("All your '{d:4.}' are belong to us!", .{1.2345});
}
