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

pub fn solveDay10() !void {
    const cycle0 = RV.mcycle.read();
    const instr0 = RV.minstret.read();
    var buf: [256]u8 = undefined;

    var solution: usize = 0;

    while (true) {
        const line = UART.readLine(&buf);
        const result = line[0];

        if (result.len == 0) break;
        try UART.writer.print("read line: {s}\n", .{result});

        var patterns = [1]usize{0} ** 16;
        var button_index: usize = 0;
        var index: usize = 1;

        var target: usize = 0;

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
            }

            button_index += 1;

            index += 1;
            while (result[index] == ' ') index += 1;
        }

        std.debug.assert(result[index] == '{');

        solution += solveLights(target, &patterns, button_index);

        if (line[1]) break;
    }

    const cycle1 = RV.mcycle.read();
    const instr1 = RV.minstret.read();
    try UART.writer.print(
        "found {} in {} cycles and {} instructions\n",
        .{ solution, cycle1 - cycle0, instr1 - instr0 },
    );
}
