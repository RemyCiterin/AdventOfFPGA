const UART = @import("print.zig");
const RV = @import("riscv.zig");
const std = @import("std");

pub fn solveDay1() !void {
    const cycle0 = RV.mcycle.read();
    const instr0 = RV.minstret.read();
    var buf: [16]u8 = undefined;

    var pos: isize = 50;
    var zeros: usize = 0;

    while (true) {
        const line = UART.readLine(&buf);

        if (line[0].len == 0 and line[1]) break;
        if (line[0].len == 0) continue;

        const left = line[0][0] == 'L';
        const number = try std.fmt.parseInt(isize, line[0][1..], 10);

        if (left) {
            pos -= number;
        } else pos += number;

        pos = @mod(pos, 100);

        if (pos == 0) zeros += 1;
    }

    const cycle1 = RV.mcycle.read();
    const instr1 = RV.minstret.read();
    try UART.writer.print(
        "found password {} in {} cycles and {} instructions\n",
        .{ zeros, cycle1 - cycle0, instr1 - instr0 },
    );
}
