const UART = @import("print.zig");
const RV = @import("riscv.zig");
const std = @import("std");

var hedges_y: [1024]usize = undefined;
var vedges_x: [1024]usize = undefined;
var hedges_xmin: [1024]usize = undefined;
var hedges_xmax: [1024]usize = undefined;
var vedges_ymin: [1024]usize = undefined;
var vedges_ymax: [1024]usize = undefined;

var x_buffer: [1024]usize = undefined;
var y_buffer: [1024]usize = undefined;

var num_points: usize = 0;
var num_hedges: usize = 0;
var num_vedges: usize = 0;

pub fn solveDay9() !void {
    const cycle0 = RV.mcycle.read();
    const instr0 = RV.minstret.read();
    var buf: [256]u8 = undefined;

    var best_area: u64 = 0;

    while (true) {
        const line = UART.readLine(&buf);
        const result = line[0];
        var index: usize = 0;

        if (result.len == 0) break;
        try UART.writer.print("\r{}", .{num_points + 1});

        var start = index;
        while (result[index] >= '0' and result[index] <= '9') index += 1;
        if (result[index] != ',') break;

        var int = try std.fmt.parseInt(usize, result[start..index], 10);
        x_buffer[num_points] = int;

        index += 1;
        start = index;
        while (result[index] >= '0' and result[index] <= '9') index += 1;
        int = try std.fmt.parseInt(usize, result[start..index], 10);
        y_buffer[num_points] = int;
        num_points += 1;
    }

    for (1..num_points) |i| {
        if (x_buffer[i] == x_buffer[i - 1]) {
            vedges_ymax[num_vedges] = @max(y_buffer[i], y_buffer[i - 1]);
            vedges_ymin[num_vedges] = @min(y_buffer[i], y_buffer[i - 1]);
            vedges_x[num_vedges] = x_buffer[i];
            num_vedges += 1;
        } else {
            hedges_xmax[num_vedges] = @max(x_buffer[i], x_buffer[i - 1]);
            hedges_xmin[num_vedges] = @min(x_buffer[i], x_buffer[i - 1]);
            hedges_y[num_vedges] = y_buffer[i];
            num_hedges += 1;
        }
    }

    if (x_buffer[0] == x_buffer[num_points - 1]) {
        vedges_ymax[num_vedges] = @max(y_buffer[0], y_buffer[num_points - 1]);
        vedges_ymin[num_vedges] = @min(y_buffer[0], y_buffer[num_points - 1]);
        vedges_x[num_vedges] = x_buffer[0];
        num_vedges += 1;
    } else {
        hedges_xmax[num_vedges] = @max(x_buffer[0], x_buffer[num_points - 1]);
        hedges_xmin[num_vedges] = @min(x_buffer[0], x_buffer[num_points - 1]);
        hedges_y[num_vedges] = y_buffer[0];
        num_hedges += 1;
    }

    for (0..num_points) |i| {
        UART.writer.print("point {}\n", .{i}) catch unreachable;
        point_loop: for (i + 1..num_points) |j| {
            const xmin = @min(x_buffer[i], x_buffer[j]) + 1;
            const xmax = @max(x_buffer[i], x_buffer[j]) - 1;
            const ymin = @min(y_buffer[i], y_buffer[j]) + 1;
            const ymax = @max(y_buffer[i], y_buffer[j]) - 1;

            const area = @as(u64, @intCast(xmax - xmin + 3)) * @as(u64, @intCast(ymax - ymin + 3));

            if (area <= best_area) continue;

            for (0..num_vedges) |k| {
                const ex = vedges_x[k];
                const eymin = vedges_ymin[k];
                const eymax = vedges_ymax[k];

                const inter =
                    xmin <= ex and ex <= xmax and ((eymin <= ymin and ymin <= eymax) or
                    (eymin <= ymax and ymax <= eymax));

                if (inter) continue :point_loop;
            }

            for (0..num_hedges) |k| {
                const ey = hedges_y[k];
                const exmin = hedges_xmin[k];
                const exmax = hedges_xmax[k];

                const inter =
                    ymin <= ey and ey <= ymax and ((exmin <= xmin and xmin <= exmax) or
                    (exmin <= xmax and xmax <= exmax));

                if (inter) continue :point_loop;
            }

            best_area = area;
        }
    }

    const cycle1 = RV.mcycle.read();
    const instr1 = RV.minstret.read();
    try UART.writer.print(
        "found {} in {} cycles and {} instructions\n",
        .{ best_area, cycle1 - cycle0, instr1 - instr0 },
    );
}
