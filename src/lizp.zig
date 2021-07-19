const std = @import("std");
const expect = std.testing.expect;

pub const LizpExp = union(enum) {
    Symbol: []const u8,
    Number: f64,
    List: []const LizpExp,
    Func: fn ([]const LizpExp) LizpErr!*LizpExp,
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
