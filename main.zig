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

    var lexer = Lexer.init(&allocator, bare_expression);
    defer lexer.deinit();
    try lexer.tokenize();
    try stdout.writeAll("\n\nORIGINALTOKENS\n\n");
    try lexer.printTokens(stdout);
    try stdout.writeAll("\n\nSORTEDTOKENS\n\n");
    try shuntingYard(&allocator, &lexer);
    try lexer.printTokens(stdout);
}

const String = struct { slice: []const u8, start_idx: usize };

const TokenType = enum { INT, FLOAT, OPERATOR, OPEN_PAREN, CLOSE_PAREN };

const Associativity = enum { LEFT, RIGHT };

fn Map(comptime K: type, comptime V: type, comptime size: usize) type {
    return struct {
        keys: [size]K,
        values: [size]V,

        const Self = @This();

        pub fn init(keys: [size]K, values: [size]V) Self {
            return .{ .keys = keys, .values = values };
        }

        pub fn get(self: Self, key: K) V {
            var value: V = undefined;
            var idx: usize = 0;

            while (idx < self.keys.len) : (idx += 1) {
                // std.debug.print("{c} == {c}\n", .{ self.keys[idx], key });
                if (self.keys[idx] == key) {
                    value = self.values[idx];
                    return value;
                }
            }
            unreachable;
        }
    };
}

const associativity = Map(u8, Associativity, 5).init([_]u8{ '-', '+', '/', '*', '^' }, [_]Associativity{ Associativity.LEFT, Associativity.LEFT, Associativity.LEFT, Associativity.LEFT, Associativity.RIGHT });

const precedence = Map(u8, u2, 5).init([_]u8{ '-', '+', '/', '*', '^' }, [_]u2{ 0, 0, 1, 1, 2 });

const Token = struct {
    value: []const u8,
    _type: TokenType,

    const Self = @This();

    pub fn println(self: *Self, writer: std.fs.File.Writer) !void {
        try writer.print("Token{{ .value=\"", .{});
        for (self.value) |c| {
            if (c == '\n') {
                try writer.writeAll("\\n");
            } else {
                try writer.print("{c}", .{c});
            }
        }
        try writer.print("\", .type = {} }}\n", .{self._type});
    }
};

const LexerState = enum { NEW_TOKEN, COMPLETE_TOKEN, INT, FLOAT, OPERATOR, OPEN_PAREN, CLOSE_PAREN };

const Lexer = struct {
    source: []const u8,
    pos: usize,
    max_idx: usize,
    state: LexerState,
    byte_buffer: String,
    tokens: std.ArrayList(Token),
    allocator: *std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, source: []const u8) Self {
        const tokens = std.ArrayList(Token).init(allocator.*);
        const byte_buffer = String{
            .slice = source[0..0],
            .start_idx = 0,
        };
        return .{ .source = source, .pos = 0, .max_idx = source.len, .state = LexerState.NEW_TOKEN, .byte_buffer = byte_buffer, .tokens = tokens, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn printTokens(self: *Self, writer: std.fs.File.Writer) !void {
        for (self.tokens.items) |*t| {
            try t.*.println(writer);
        }
    }

    pub fn tokenize(self: *Self) !void {
        while (self.pos < self.max_idx) {
            try self._next();
        }
    }

    fn _next(self: *Self) !void {
        const char = self.source[self.pos];
        var next_char: ?u8 = undefined;
        if (self.pos < self.source.len - 1) {
            next_char = self.source[self.pos + 1];
        } else {
            next_char = null;
        }

        switch (self.state) {
            LexerState.NEW_TOKEN => {
                switch (char) {
                    ' ' => {
                        self.pos += 1;
                        self.state = LexerState.COMPLETE_TOKEN;
                    },
                    '(' => {
                        self.state = LexerState.OPEN_PAREN;
                    },
                    ')' => {
                        self.state = LexerState.CLOSE_PAREN;
                    },
                    '*', '/', '+', '-', '^' => {
                        self.state = LexerState.OPERATOR;
                    },
                    '0'...'9' => {
                        self.state = LexerState.INT;
                    },
                    '.' => {
                        self.state = LexerState.FLOAT;
                    },
                    else => {
                        unreachable;
                    },
                }
            },
            LexerState.COMPLETE_TOKEN => {
                self.byte_buffer.start_idx = self.pos;
                self.byte_buffer.slice = self.source[self.pos..self.pos];
                self.state = LexerState.NEW_TOKEN;
            },
            LexerState.INT => {
                self._increment();
                if (next_char) |c| {
                    switch (c) {
                        '0'...'9' => {
                            return;
                        },
                        '.' => {
                            self.state = LexerState.FLOAT;
                        },
                        else => {
                            try self._create_token(TokenType.INT);
                        },
                    }
                } else {
                    try self._create_token(TokenType.INT);
                }
            },
            LexerState.FLOAT => {
                self._increment();
                if (next_char) |c| {
                    switch (c) {
                        '0'...'9' => {
                            return;
                        },
                        '.' => {
                            unreachable;
                        },
                        else => {
                            try self._create_token(TokenType.FLOAT);
                        },
                    }
                } else {
                    try self._create_token(TokenType.FLOAT);
                }
            },
            LexerState.OPERATOR => {
                self._increment();
                try self._create_token(TokenType.OPERATOR);
            },
            LexerState.OPEN_PAREN => {
                self._increment();
                try self._create_token(TokenType.OPEN_PAREN);
            },
            LexerState.CLOSE_PAREN => {
                self._increment();
                try self._create_token(TokenType.CLOSE_PAREN);
            },
        }
    }

    fn _increment(self: *Self) void {
        self.pos += 1;
        self.byte_buffer.slice = self.source[self.byte_buffer.start_idx..self.pos];
    }

    fn _create_token(self: *Self, token_type: TokenType) !void {
        const token = Token{ .value = self.byte_buffer.slice, ._type = token_type };
        try self.tokens.append(token);
        self.state = LexerState.COMPLETE_TOKEN;
    }
};

fn shuntingYard(allocator: *std.mem.Allocator, lexer: *Lexer) !void {
    const tokens = &lexer.tokens;

    var output = std.ArrayList(Token).init(allocator.*);
    errdefer output.deinit();

    var stack = std.ArrayList(Token).init(allocator.*);
    defer stack.deinit();

    for (tokens.items) |token| {
        switch (token._type) {
            TokenType.FLOAT, TokenType.INT => {
                try output.append(token);
            },
            TokenType.OPERATOR => {
                const this_token_val = token.value[0];
                const is_left = associativity.get(this_token_val) == Associativity.LEFT;
                const this_precedence = precedence.get(this_token_val);

                var stack_last = stack.getLastOrNull();

                while (stack.items.len > 0 and stack_last != null and stack_last.?._type == TokenType.OPERATOR and ((is_left and this_precedence <= precedence.get(stack_last.?.value[0])) or (!is_left and this_precedence < precedence.get(stack_last.?.value[0])))) {
                    const popped = stack.pop();
                    try output.append(popped);
                    stack_last = stack.getLastOrNull();
                }

                try stack.append(token);
            },
            TokenType.OPEN_PAREN => {
                try stack.append(token);
            },
            TokenType.CLOSE_PAREN => {
                var stack_last = stack.getLastOrNull();
                while (stack.items.len > 0 and stack_last != null and stack_last.?._type != TokenType.OPEN_PAREN) {
                    try output.append(stack.pop());
                    stack_last = stack.getLastOrNull();
                }
                if (stack_last) |stack_last_token| {
                    if (stack_last_token._type == TokenType.OPEN_PAREN) {
                        _ = stack.pop();
                    }
                }
            },
        }
    }

    while (stack.items.len != 0) {
        const top_token = stack.pop();
        if (top_token._type == TokenType.OPEN_PAREN) {
            unreachable;
        }
        try output.append(top_token);
    }

    const output_slice = try output.toOwnedSlice();
    lexer.tokens.clearAndFree();
    try lexer.tokens.appendSlice(output_slice);
}

// TODO: binary tree, dfs
