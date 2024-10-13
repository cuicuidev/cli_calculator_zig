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

    const expression = std.mem.trim(u8, bare_expression, "\r");

    // Bracket pairs used for parsing and eval
    var pairs = std.ArrayList(BracketPair).init(allocator);
    defer pairs.deinit();

    // Stack for bracket pairs validation
    var stack = std.ArrayList(usize).init(allocator);
    defer stack.deinit();

    // Bracket pairs validation logic
    for (expression, 0..) |char, i| {
        if (char == '(') try stack.append(i);
        if (char == ')') {
            if (stack.items.len == 0) unreachable; // If the stack is empty we should not be seeing closing brackets.
            try pairs.append(.{ .open = stack.pop(), .close = i });
        }
    }

    if (stack.items.len != 0) unreachable; // We should not have items in the stack after exhausting the expression.

    // Calculate depth of each bracket pair
    for (pairs.items) |*pair| {
        pair.setDepth(pairs);
    }

    // Sort based on depth. Larger depth means that it must be evaluated first.
    std.sort.insertion(BracketPair, pairs.items, {}, lessThanDepth);

    for (pairs.items) |pair| {
        try stdout.print("open = {any}, close = {any}, depth = {any}\n", .{ pair.open, pair.close, pair.depth });
    }
}

// TODO: A function that takes in a "[]const u8" with a simple expressión (no brackets) and evaluates it.
// It should return the result as a "[]const u8".

// TODO: Another function that can take the whole expression and the sorted array with the bracket pair indices and evaluate each one of the sub-expressions one by one.
// It should substitute each evaluated sub-expression with it's result before proceeding to the next.
// The return type should be a number (is it possible to have unions of integers and floats???).

// This struct holds the indices of the bracket pairs and their depth within the whole expression
const BracketPair = struct {
    open: usize,
    close: usize,
    depth: ?usize = null,

    const Self = @This();

    pub fn setDepth(self: *Self, other_pairs: std.ArrayList(BracketPair)) void {
        var depth: usize = 0;

        for (other_pairs.items) |other| {
            // If this pair is inside the other pair
            if (other.open < self.open and other.close > self.close) {
                depth += 1;
            }
        }

        self.depth = depth;
    }
};

fn lessThanDepth(context: @TypeOf({}), a: BracketPair, b: BracketPair) bool {
    _ = context;
    return a.depth.? > b.depth.?; // Using larger than because I want descending order.
}
