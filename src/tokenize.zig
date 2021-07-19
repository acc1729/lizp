const std = @import("std");
const expect = std.testing.expect;

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
