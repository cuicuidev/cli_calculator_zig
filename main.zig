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

// TODO: I need to figure out how to tokeninize the input.
// The tokens I need are '(', ')', '^', '*', '/', '+', '-' and 'number'.
//
// TODO: I need a function that takes two numeric tokens and an operator token. Then it must perform a simple mathematical operation and return the result as a
// numeric token.
//
// TODO: I need to figure out how to build an abstract syntax tree with the tokens. So far I know it has to be a binary tree where the leafs are the numbers and
// the nodes are the operators. The deepest operations are the first one on the PEMDAS priority rule, so I need to implement a DFS that can simplify the nodes
// to a leaf, recursively. The base condition is when we are left with a stump that holds a numeric token, which would be the result.

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
