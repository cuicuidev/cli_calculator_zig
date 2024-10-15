const std = @import("std");

pub fn main() !void {
    // Allocator and standard I/O
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // User input
    try stdout.writeAll("This is a calculator. Input your expression:\n");
    const bare_expression = try stdin.readUntilDelimiterAlloc(allocator, '\n', 8192);
    defer allocator.free(bare_expression);
}

// TODO: Tokenizer, shunting yard, binary tree, dfs
