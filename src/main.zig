const std = @import("std");
const expect = std.testing.expect;

const lizp = @import("lizp.zig");
const parse = @import("parse.zig").parse;
const tokenize = @import("tokenize.zig").tokenize;
const LizpErr = lizp.LizpErr;
const LizpExp = lizp.LizpExp;
const LizpEnv = lizp.LizpEnv;
const LizpExpRest = lizp.LizpExpRest;

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

pub fn repl() anyerror!void {
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

pub fn main() anyerror!void {
    repl();
}
