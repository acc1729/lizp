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
        .Bool => {
            return exp;
        },
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

fn nextLine(reader: anytype, buffer: []u8) ![]const u8 {
    var line: []const u8 = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return "";
    // trim annoying windows-only carriage return character
    if (std.builtin.os.tag == .windows) {
        line = std.mem.trimRight(u8, line, "\r");
    }
    return line;
}

test "eval" {
    const env: LizpEnv = try lizp.defaultEnv();
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
    const env = try lizp.defaultEnv();
    const out = try eval(expression, env);
    try expect(out.Number == 17);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    const env = try lizp.defaultEnv();
    var buffer: [100]u8 = undefined;
    while (true) {
        try stdout.writeAll("Lizp > ");
        var in = (try nextLine(stdin.reader(), &buffer));
        if (std.mem.eql(u8, in, "")) break;
        const expression = try parse(try tokenize(in));
        var res = eval(expression, env) catch |err| {
            try stdout.writer().print("There was an error in the above expression: {s}\n", .{@errorName(err)});
            continue;
        };
        try stdout.writer().print("{s}\n", .{try res.to_string(&gpa.allocator)});
    }
}
