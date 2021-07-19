const std = @import("std");
const expect = std.testing.expect;

const lizp = @import("lizp.zig");
const LizpErr = lizp.LizpErr;
const LizpExp = lizp.LizpExp;
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
            const first_form = exp.List[0];
            const arg_forms = exp.List[1..];
            switch (first_form) {
                .Func => {
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
    std.log.warn("All your {s} are belong to us!", .{"homies"});
}
