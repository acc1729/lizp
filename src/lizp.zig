const std = @import("std");
const expect = std.testing.expect;

pub const LizpExp = union(enum) {
    Symbol: []const u8,
    Number: f64,
    List: []const LizpExp,
    Func: fn ([]const LizpExp) LizpErr!*LizpExp,

    pub fn to_string(self: LizpExp, allocator: *std.mem.Allocator) anyerror![]const u8 {
        var a = allocator;
        return switch (self) {
            .Symbol => self.Symbol,
            .Number => number: {
                const space = ' ';
                var num = try std.fmt.allocPrint(a, "{d}", .{self.Number});
                var i: usize = 0;
                for (num) |char, index| {
                    if (char != space) {
                        i = index;
                        break;
                    }
                }
                break :number num[i..num.len];
            },
            .List => list: {
                var string = std.ArrayList(u8).init(a);
                try string.appendSlice("( ");
                for (self.List) |exp| {
                    var intermediate = try exp.to_string(a);
                    try string.appendSlice(intermediate);
                    try string.append(' ');
                }
                try string.append(')');
                break :list string.items;
            },
            .Func => try std.fmt.allocPrint(a, "Function", .{}), // TODO what to represent a function as?
        };
    }
};

pub const LizpErr = error{
    UnexpectedForm,
    UnexpectedClosingParen,
    NoClosingParen,
    NotANumber,
    NotAFunc,
    SymbolNotFound,
    EmptyList,
};

pub const LizpEnv = struct {
    data: std.StringHashMap(LizpExp),
};

pub const LizpExpRest = struct {
    exp: LizpExp,
    rest: [][]const u8,
};

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
    var env = std.StringHashMap(LizpExp).init(&gpa.allocator);
    try env.put("+", LizpExp{ .Func = lizpSum });
    try env.put("-", LizpExp{ .Func = lizpSub });
    return LizpEnv{ .data = env };
}

test "lizpExp.Number to_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const num: LizpExp = LizpExp{ .Number = 1.234 };
    var res = try num.to_string(&gpa.allocator);
    try expect(std.mem.eql(u8, res, "1.234"));

    const num2: LizpExp = LizpExp{ .Number = 1.2345678901234 };
    var res2 = try num2.to_string(&gpa.allocator);
    try expect(std.mem.eql(u8, res2, "1.2345678901234"));
}

test "lizpExp.Symbol to_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const num: LizpExp = LizpExp{ .Symbol = "my-symbol" };
    var res = try num.to_string(&gpa.allocator);
    try expect(std.mem.eql(u8, res, "my-symbol"));
}

test "lizpExp.List to_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
    var res = try exp.to_string(&gpa.allocator);
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
    var another_res = try another_exp.to_string(&gpa.allocator);
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

test "defaultEnv" {
    var env = try defaultEnv();
    var plus = env.data.get("+") orelse unreachable;
    try expect(plus == LizpExp.Func);
}
