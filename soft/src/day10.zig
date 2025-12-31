const UART = @import("print.zig");
const RV = @import("riscv.zig");
const std = @import("std");

pub fn solveLights(target: usize, patterns: []usize, num_patterns: usize) usize {
    const num_seed = @as(usize, 1) << @intCast(num_patterns);
    var best_count: usize = 100;

    for (0..num_seed) |seed| {
        var pattern: usize = 0;
        var count: usize = 0;

        for (0..num_patterns) |i| {
            if (seed & (@as(usize, 1) << @intCast(i)) != 0) {
                pattern = pattern ^ patterns[i];
                count += 1;
            }
        }

        if (pattern == target)
            best_count = @min(best_count, count);
    }

    return best_count;
}

pub const JoltageSolver = struct {
    const N: usize = 15;
    const M: usize = 15;

    matrix: [N][M + 1]i16 = .{.{0} ** (M + 1)} ** N,

    basic: [M]?usize = .{null} ** M,

    num_vars: usize = 0,

    // Bound of each variable in the original problem, used to perform a brute-force analysis over
    // the non-basic variables
    bounds: [M]i16 = .{std.math.maxInt(i16)} ** M,

    assign: [M]i16 = .{0} ** M,

    // Approximation of the number of cycles required in hardware usign a finite state machine
    cycles: usize = 0,

    pub fn dump(self: *JoltageSolver) void {
        for (0..N) |i| {
            var empty: bool = true;

            for (0..M) |j| {
                if (self.matrix[i][j] != 0) {
                    if (!empty) UART.writer.print(" + ", .{}) catch unreachable;
                    UART.writer.print("{} * x{}", .{ self.matrix[i][j], j }) catch unreachable;
                }

                empty = empty and self.matrix[i][j] == 0;
            }

            if (!empty) UART.writer.print(" = {}\n", .{self.matrix[i][M]}) catch unreachable;
        }

        UART.writer.print("cycles needed: {}\n", .{self.cycles}) catch unreachable;

        var score: i256 = 1;
        for (0..self.num_vars) |j| {
            if (self.basic[j] == null)
                score *= @as(i256, @intCast(self.bounds[j])) + 1;
        }

        // Number of steps of brute-force needed to find the optimal solution
        UART.writer.print("brute-force range: {}\n", .{score}) catch unreachable;
    }

    fn abs(x: i16) i16 {
        return if (x > 0) x else -x;
    }

    fn nextAssign(self: *JoltageSolver) bool {
        self.cycles += 1;
        for (0..self.num_vars) |j| {
            // We brute-force over the non-basic variables
            if (self.basic[j] == null) {
                self.assign[j] += 1;

                if (self.assign[j] > self.bounds[j]) {
                    self.assign[j] = 0;
                    continue;
                }

                return false;
            }
        }

        return true;
    }

    // return a / b if b divide a, null otherwise
    fn division(self: *JoltageSolver, x: i16, y: i16) ?i16 {
        self.cycles += 16;
        if (@mod(x, y) != 0) return null;
        return @divExact(x, y);
    }

    fn checkAssign(self: *JoltageSolver) ?i32 {
        var total: i32 = 0;

        for (0..self.num_vars) |j| {
            self.cycles += 1;

            if (self.basic[j]) |i| {
                const coef = self.matrix[i][j];
                var acc = self.matrix[i][M];

                for (0..M) |k| {
                    if (k != j) acc -= self.matrix[i][k] * self.assign[k];
                }

                const div = self.division(acc, coef) orelse return null;
                if (div < 0) return null;
                total += @intCast(div);
            } else {
                total += @intCast(self.assign[j]);
            }
        }

        return total;
    }

    // return { gcd(x,y), x / gcd(x,y), y / gcd(x,y) } using a finite state machine
    fn gcd(self: *JoltageSolver, _x: i16, _y: i16) struct { i16, i16, i16 } {
        var x1: i16 = 1;
        var x2: i16 = 0;
        var y1: i16 = 0;
        var y2: i16 = 1;
        var x = _x;
        var y = _y;

        // X / gcd(X, Y) = x1 * (x / gcd(x,y)) + x2 * (y / gcd(x,y))
        // Y / gcd(X, Y) = y1 * (x / gcd(x,y)) + y2 * (y / gcd(x,y))

        while (true) {
            self.cycles += 1;

            if (x < 0) {
                x1 *= -1;
                y1 *= -1;
                x *= -1;
                continue;
            }

            if (y < 0) {
                x2 *= -1;
                y2 *= -1;
                y *= -1;
                continue;
            }

            if (x == 0) return .{ y, x2, y2 };
            if (y == 0) return .{ x, x1, y1 };

            if (x > y) {
                // x1 * (x / gcd(x,y)) + x2 * (y / gcd(x,y))
                // = x1 * ((x-y+y) / gcd(x,y)) + x2 * (y / gcd(x,y))
                // = x1 * ((x-y) / gcd(x,y)) + (x2+x1) * (y / gcd(x,y))
                x2 = x2 + x1;
                y2 = y2 + y1;
                x -= y;
                continue;
            }

            if (x < y) {
                x1 = x1 + x2;
                y1 = y1 + y2;
                y -= x;
                continue;
            }

            return .{ x, x1 + x2, y1 + y2 };
        }
    }

    pub fn reduce(self: *JoltageSolver) i32 {
        for (0..N) |i| {
            for (0..M) |j| {
                if (self.matrix[i][j] != 0)
                    self.bounds[j] = @min(self.bounds[j], self.matrix[i][M]);
            }
        }

        var r: usize = 0;

        for (0..M) |j| {
            var k: usize = r;
            for (r..N) |i| {
                self.cycles += 1;
                if (abs(self.matrix[i][j]) > abs(self.matrix[k][j]))
                    k = i;
            }

            if (self.matrix[k][j] != 0) {
                self.basic[j] = r;

                const coef = self.matrix[k][j];

                for (0..M + 1) |j0| std.mem.swap(i16, &self.matrix[k][j0], &self.matrix[r][j0]);
                self.cycles += M + 1;

                for (0..N) |i| {
                    self.cycles += 1;
                    if (i != r) {
                        const aij = self.matrix[i][j];

                        const p = self.gcd(coef, aij);

                        for (0..M + 1) |j0| {
                            self.matrix[i][j0] =
                                self.matrix[i][j0] * p[1] - p[2] * self.matrix[r][j0];
                        }
                        self.cycles += 1;
                    }
                }

                r = r + 1;
            }
        }

        var total: i32 = std.math.maxInt(i32);
        self.dump();

        while (true) {
            if (self.checkAssign()) |t|
                total = @min(total, t);

            if (self.nextAssign()) break;
        }

        return total;
    }
};

pub fn solveDay10() !void {
    const cycle0 = RV.mcycle.read();
    const instr0 = RV.minstret.read();
    var buf: [256]u8 = undefined;

    var light_total: usize = 0;
    var joltage_total: i32 = 0;

    while (true) {
        const line = UART.readLine(&buf);
        const result = line[0];

        if (result.len == 0) break;
        try UART.writer.print("read line: {s}\n", .{result});

        var patterns = [1]usize{0} ** 16;
        var button_index: usize = 0;
        var index: usize = 1;

        var target: usize = 0;

        var solver = JoltageSolver{};
        var engine_index: usize = 0;

        while (result[index] != ']') {
            if (result[index] == '#')
                target |= @as(usize, 1) << @intCast(index - 1);
            index += 1;
        }

        index += 2;

        while (result[index] == '(') {
            while (result[index] != ')') {
                index += 1;
                const start = index;
                while (result[index] != ',' and result[index] != ')') index += 1;
                const int = try std.fmt.parseInt(usize, result[start..index], 10);
                patterns[button_index] |= @as(usize, 1) << @intCast(int);
                solver.matrix[int][button_index] = 1;
            }

            button_index += 1;

            index += 1;
            while (result[index] == ' ') index += 1;
        }

        solver.num_vars = button_index;
        std.debug.assert(result[index] == '{');

        while (result[index] != '}') {
            index += 1;
            const start = index;
            while (result[index] != ',' and result[index] != '}') index += 1;
            const int = try std.fmt.parseInt(i16, result[start..index], 10);
            solver.matrix[engine_index][JoltageSolver.M] = int;
            engine_index += 1;
        }

        joltage_total += solver.reduce();
        //solver.dump();

        light_total += solveLights(target, &patterns, button_index);

        const cycle1 = RV.mcycle.read();
        const instr1 = RV.minstret.read();
        try UART.writer.print("cycle: {} instr: {}\n", .{ cycle1 - cycle0, instr1 - instr0 });

        if (line[1]) break;
    }

    const cycle1 = RV.mcycle.read();
    const instr1 = RV.minstret.read();
    try UART.writer.print(
        "found (light: {}, joltage: {}) in {} cycles and {} instructions\n",
        .{ light_total, joltage_total, cycle1 - cycle0, instr1 - instr0 },
    );
}
