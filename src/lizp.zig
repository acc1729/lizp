const std = @import("std");
const expect = std.testing.expect;

const parse = @import("parse.zig").parse;
const tokenize = @import("tokenize.zig").tokenize;
const builtins = @import("builtins.zig");

pub const LizpExp = union(enum) {
    Number: f64,
    Bool: bool,
    Symbol: []const u8,
    List: []const LizpExp,
    Func: fn ([]const LizpExp) LizpErr!*LizpExp,
    Lambda: *LizpLambda,

    pub fn format(
        self: LizpExp,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        switch (self) {
            .Bool => |Bool| try writer.print("{}", .{Bool}),
            .Symbol => |Symbol| try writer.print("{s}", .{Symbol}),
            .Number => |Number| try writer.print("{d}", .{Number}),
            .List => |List| {
                try writer.writeAll("( ");
                for (List) |exp| {
                    try exp.format(fmt, options, writer);
                    try writer.writeByte(' ');
                }
                try writer.writeByte(')');
            },
            .Func => try writer.writeAll("Function"), // TODO what to represent a function as?
            .Lambda => try writer.writeAll("Lambda"), // TODO what to represent a lambda as?
        }
    }
};

pub const LizpLambda = struct {
    params_exp: *LizpExp,
    body_exp: *LizpExp,
};

pub const ArithmeticErr = error{ NotANumber, Incomprable };
pub const ParseErr = error{ UnexpectedClosingParen, NoClosingParen };
pub const RunTimeErr = error{ UnexpectedForm, NotAFunc, NotASymbol, NotAList, SymbolNotFound, EmptyList, OutOfMemory, NotEnoughArguments };
pub const LizpErr = ArithmeticErr || ParseErr || RunTimeErr;
pub const LizpEnv = struct {
    data: std.StringHashMap(LizpExp),
    outer: ?*LizpEnv,
};

pub const LizpExpRest = struct {
    exp: LizpExp,
    rest: [][]const u8,
};

fn ensureComparability(first: LizpExp, other: LizpExp) ArithmeticErr!void {
    if (!(first == LizpExp.Number)) return ArithmeticErr.NotANumber;
    if (!(other == LizpExp.Number)) return ArithmeticErr.NotANumber;
}

fn equal(first: LizpExp, other: LizpExp) ArithmeticErr!bool {
    ensureComparability(first, other) catch return ArithmeticErr.Incomprable;
    return first.Number == other.Number;
}

fn greater(first: LizpExp, other: LizpExp) ArithmeticErr!bool {
    ensureComparability(first, other) catch return ArithmeticErr.Incomprable;
    return first.Number > other.Number;
}

fn greaterThanOrEqual(first: LizpExp, other: LizpExp) ArithmeticErr!bool {
    ensureComparability(first, other) catch return ArithmeticErr.Incomprable;
    return first.Number >= other.Number;
}

fn less(first: LizpExp, other: LizpExp) ArithmeticErr!bool {
    ensureComparability(first, other) catch return ArithmeticErr.Incomprable;
    return first.Number < other.Number;
}

fn lessThanOrEqual(first: LizpExp, other: LizpExp) ArithmeticErr!bool {
    ensureComparability(first, other) catch return ArithmeticErr.Incomprable;
    return first.Number <= other.Number;
}

fn monotonicCompare(comptime compator: fn (LizpExp, LizpExp) ArithmeticErr!bool) (fn (list: []const LizpExp) ArithmeticErr!*LizpExp) {
    return struct {
        fn _monotonicCompare(list: []const LizpExp) ArithmeticErr!*LizpExp {
            var monotonic: bool = true;
            var i: usize = 0;
            // Access to second-to-last member of slice
            while (i <= list.len - 2) : (i += 1) {
                monotonic = try compator(list[i], list[i + 1]);
                if (!monotonic) break;
            }
            return &LizpExp{ .Bool = monotonic };
        }
    }._monotonicCompare;
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

pub fn defaultEnv() !LizpEnv {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var env = std.StringHashMap(LizpExp).init(alloc);
    try env.put("+", LizpExp{ .Func = lizpSum });
    try env.put("-", LizpExp{ .Func = lizpSub });
    try env.put("==", LizpExp{ .Func = monotonicCompare(equal) });
    try env.put(">", LizpExp{ .Func = monotonicCompare(greater) });
    try env.put(">=", LizpExp{ .Func = monotonicCompare(greaterThanOrEqual) });
    try env.put("<", LizpExp{ .Func = monotonicCompare(less) });
    try env.put("<=", LizpExp{ .Func = monotonicCompare(lessThanOrEqual) });
    return LizpEnv{ .data = env, .outer = null };
}

/// If the first form is a symbol, do a hard-coded lookup into our builtin arg_forms
/// If it's not a symbol, or it's not in our hard-coded lookup, return null
pub fn evalBuiltinForm(exp: LizpExp, args: []const LizpExp, env: LizpEnv, alloc: std.mem.Allocator) LizpErr!?LizpExp {
    if (exp != LizpExp.Symbol) return null;
    if (std.mem.eql(u8, exp.Symbol, "if")) {
        return try builtins.evalIfForm(args, env);
    } else if (std.mem.eql(u8, exp.Symbol, "def")) {
        return try builtins.evalDefForm(args, env);
    } else if (std.mem.eql(u8, exp.Symbol, "fn")) {
        const fn_form = try builtins.evalFnForm(args, alloc);
        return fn_form;
    }
    return null;
}

pub fn evalForms(forms: []const LizpExp, env: LizpEnv, alloc: std.mem.Allocator) LizpErr![]const LizpExp {
    var evaled_args = std.ArrayList(LizpExp).init(alloc);
    for (forms) |arg| {
        var evaluated_form = try eval(arg, env);
        evaled_args.append(evaluated_form) catch return LizpErr.OutOfMemory;
    }
    return evaled_args.items;
}

/// Recursively search up an environment tree to find a key.
pub fn envGet(key: []const u8, env: LizpEnv) ?LizpExp {
    return env.data.get(key) orelse dive: {
        if (env.outer == null) break :dive null;
        const concrete_outer = env.outer.?;
        break :dive envGet(key, concrete_outer.*);
    };
}

pub fn newEnvForLambda(params: LizpExp, args: []const LizpExp, env: LizpEnv, allocator: std.mem.Allocator) LizpErr!LizpEnv {
    const keys = try parseStringsFromSymbols(params, allocator);
    defer allocator.free(keys);
    if (keys.len != args.len) return LizpErr.NotEnoughArguments;
    const vals = try evalForms(args, env, allocator);
    var data = std.StringHashMap(LizpExp).init(allocator);
    var i = @as(usize, 0);
    // keys and vals have already been checked to be the same length,
    // so this is always legal
    while (i < keys.len) : (i += 1) {
        try data.put(keys[i], vals[i]);
    }
    var mut_outer = env;
    return LizpEnv{
        .data = data,
        .outer = &mut_outer,
    };
}

pub fn parseStringsFromSymbols(symbols: LizpExp, alloc: std.mem.Allocator) LizpErr![][]const u8 {
    if (symbols != LizpExp.List) return LizpErr.NotAList;
    var symbol_strings = std.ArrayList([]const u8).init(alloc);
    for (symbols.List) |symbol| {
        if (symbol != LizpExp.Symbol) return LizpErr.NotASymbol;
        try symbol_strings.append(symbol.Symbol);
    }
    return symbol_strings.items;
}

pub fn eval(exp: LizpExp, env: LizpEnv) LizpErr!LizpExp {
    return switch (exp) {
        .Bool => {
            return exp;
        },
        .Symbol => {
            return envGet(exp.Symbol, env) orelse return LizpErr.SymbolNotFound;
        },
        .Number => {
            return exp;
        },
        .List => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const alloc = gpa.allocator();
            if (exp.List.len == 0) return LizpErr.EmptyList;
            var first_form = exp.List[0];
            const arg_forms = exp.List[1..];

            // Check to see if there's a builtin, and whether or not it evals well.
            // If it does, return it right away.
            var builtin_result: LizpExp = (try evalBuiltinForm(first_form, arg_forms, env, alloc)) orelse {
                var first_eval = try eval(first_form, env);
                switch (first_eval) {
                    .Func => {
                        const evaled_args = try evalForms(arg_forms, env, alloc);
                        var res = try first_eval.Func(evaled_args);
                        return res.*;
                    },
                    .Lambda => {
                        const lambda = first_eval.Lambda.*;
                        const params = lambda.params_exp;
                        const body = lambda.body_exp;
                        var new_env = try newEnvForLambda(params.*, arg_forms, env, alloc);
                        defer new_env.data.deinit();
                        var res = try eval(body.*, new_env);
                        return res;
                    },
                    else => {
                        return LizpErr.NotAFunc;
                    },
                }
            };
            return builtin_result;
        },
        .Func => {
            return LizpErr.UnexpectedForm;
        },
        .Lambda => {
            return LizpErr.UnexpectedForm;
        },
    };
}

const ta = std.testing.allocator;

test "lizpExp.Bool format" {
    var true_res = try std.fmt.allocPrint(ta, "{}", .{LizpExp{.Bool = true}});
    defer ta.free(true_res);
    try expect(std.mem.eql(u8, true_res, "true"));

    var false_res = try std.fmt.allocPrint(ta, "{}", .{LizpExp{.Bool = false}});
    defer ta.free(false_res);
    try expect(std.mem.eql(u8, false_res, "false"));
}

test "lizpExp.Number format" {
    var res = try std.fmt.allocPrint(ta, "{}", .{LizpExp{ .Number = 1.234 }});
    defer ta.free(res);
    try expect(std.mem.eql(u8, res, "1.234"));

    var res2 = try std.fmt.allocPrint(ta, "{}", .{LizpExp{ .Number = 1.2345678901234 }});
    defer ta.free(res2);
    try expect(std.mem.eql(u8, res2, "1.2345678901234"));
}

test "lizpExp.Symbol format" {
    var res = try std.fmt.allocPrint(ta, "{}", .{LizpExp{ .Symbol = "my-symbol" }});
    defer ta.free(res);
    try expect(std.mem.eql(u8, res, "my-symbol"));
}

test "lizpExp.Func format" {
    var res = try std.fmt.allocPrint(ta, "{}", .{LizpExp{ .Func = lizpSum }});
    defer ta.free(res);
    try expect(std.mem.eql(u8, res, "Function"));
}

test "lizpExp.List format" {
    const array_of_lizpexp: [3]LizpExp = .{
        LizpExp{
            .Symbol = "some-symbol",
        },
        LizpExp{
            .Number = 1,
        },
        LizpExp{
            .Number = 2,
        },
    };
    var slice_of_lizpexp = array_of_lizpexp[0..array_of_lizpexp.len];
    const exp = LizpExp{ .List = slice_of_lizpexp };
    var res = try std.fmt.allocPrint(ta, "{}", .{exp});
    defer ta.free(res);
    try expect(std.mem.eql(u8, res, "( some-symbol 1 2 )"));
    var another_array: [3]LizpExp = .{
        LizpExp{
            .Symbol = "left",
        },
        exp,
        LizpExp{
            .Symbol = "right",
        },
    };
    var another_slice = another_array[0..another_array.len];
    var another_exp = LizpExp{ .List = another_slice };
    var another_res = try std.fmt.allocPrint(ta, "{}", .{another_exp});
    defer ta.free(another_res);
    try expect(std.mem.eql(u8, another_res, "( left ( some-symbol 1 2 ) right )"));
}

test "lizpSub" {
    const array: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    const result: *LizpExp = try lizpSub(slice);
    try expect(result.* == LizpExp.Number);
    try expect(result.*.Number == -6);
}

test "lizpSum" {
    const array: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    const result: *LizpExp = try lizpSum(slice);
    try expect(result.* == LizpExp.Number);
    try expect(result.*.Number == 12);
}

test "equal" {
    const will_be_equal: bool = try equal(LizpExp{ .Number = 3 }, LizpExp{ .Number = 3 });
    try expect(will_be_equal);
    const will_not_be_equal: bool = try equal(LizpExp{ .Number = 5 }, LizpExp{ .Number = 3 });
    try expect(!will_not_be_equal);
}

test "monotonicEqual" {
    const monotonicEqual = monotonicCompare(equal);
    const exp_arr: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 3 }, LizpExp{ .Number = 3 } };
    const exp_slice = exp_arr[0..3];
    const will_be_equal: *LizpExp = try monotonicEqual(exp_slice);
    try expect(will_be_equal.*.Bool);

    const exp_arr2: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Number = 5 }, LizpExp{ .Number = 3 } };
    const exp_slice2 = exp_arr2[0..3];
    const will_not_be_equal: *LizpExp = try monotonicEqual(exp_slice2);
    try expect(!will_not_be_equal.*.Bool);

    const exp_arr3: [3]LizpExp = .{ LizpExp{ .Number = 3 }, LizpExp{ .Symbol = "some-symbol" }, LizpExp{ .Number = 3 } };
    const exp_slice3 = exp_arr3[0..3];
    try std.testing.expectError(ArithmeticErr.Incomprable, monotonicEqual(exp_slice3));
}

test "defaultEnv" {
    var env = try defaultEnv();
    var plus = env.data.get("+") orelse unreachable;
    try expect(plus == LizpExp.Func);
}

test "eval" {
    const env: LizpEnv = try defaultEnv();
    const array: [3]LizpExp = .{ LizpExp{ .Symbol = "+" }, LizpExp{ .Number = 4 }, LizpExp{ .Number = 5 } };
    const slice = array[0..3];
    var exp = LizpExp{ .List = slice };
    const result = try eval(exp, env);
    try expect(result == LizpExp.Number);
    try expect(result.Number == 9);
}

test "tokenize-parse-eval" {
    const input = "(+ 1 7 (- 13 4))";
    const expression = try parse(try tokenize(input));
    const env = try defaultEnv();
    const out = try eval(expression, env);
    try expect(out.Number == 17);
}

test "parseStringsFromSymbols" {
    const symbols = "(symbol-0 symbol-1 symbol-2)";
    const expression = try parse(try tokenize(symbols));
    const symbol_slice = try parseStringsFromSymbols(expression, ta);
    defer ta.free(symbol_slice);
    try expect(std.mem.eql(u8, symbol_slice[1], "symbol-1"));
}

test "lambda call" {
    const input = "((fn (a b) (+ a b)) 12 8)";
    const expression = try parse(try tokenize(input));
    const env = try defaultEnv();
    const out = try eval(expression, env);
    try expect(out.Number == 20);
}

// The coup-de-grace: Define a lambda and assign it to a symbol,
// and then in a later expression, invoke the lambda.
test "lambda call" {
    const env = try defaultEnv();

    const function_def = "(def my-func (fn (a b) (+ a b)))";
    const function_def_exp = try parse(try tokenize(function_def));
    const function_def_out = try eval(function_def_exp, env);
    try expect(function_def_out == .Symbol);

    const lambda_expression = env.data.get("my-func") orelse unreachable;
    try expect(lambda_expression == .Lambda);

    const function_application = "(my-func 12 8)";
    const function_application_exp = try parse(try tokenize(function_application));
    const function_application_out = try eval(function_application_exp, env);
    try expect(function_application_out == .Number);
    try expect(function_application_out.Number == 20);
}
