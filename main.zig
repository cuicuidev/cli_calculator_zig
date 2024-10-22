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
    try lexer.tokenize();
    try lexer.printTokens(stdout);
}

const String = struct { slice: []const u8, start_idx: usize };

const TokenType = enum { INT, FLOAT, OPERATOR, OPEN_PAREN, CLOSE_PAREN };

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
            try writer.print("\", .type = {} }}\n", .{self._type});
        }
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
                            self._increment();
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
                            self._increment();
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

// TODO: shunting yard, binary tree, dfs
