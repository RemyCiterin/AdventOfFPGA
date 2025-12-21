const std = @import("std");
const UART: usize = 0x10000000;
const UART_THR: *volatile u8 = @ptrFromInt(UART + 0x00); // THR:transmitter holding register
const UART_READ_REQ: *volatile u8 = @ptrFromInt(UART + 0x04); // LSR:line status register
const UART_LSR_EMPTY_MASK: usize = 0x40;

pub inline fn putChar(ch: u8) void {
    UART_THR.* = ch;
}

pub fn getChar() u8 {
    UART_READ_REQ.* = 1;
    asm volatile ("fence" ::: "memory");
    return UART_THR.*;
}

pub fn readLine(buf: []u8) struct { []u8, bool } {
    var index: usize = 0;

    while (true) {
        const char = getChar();
        buf[index] = char;

        switch (char) {
            '\n' => return .{ buf[0..index], false },
            0 => return .{ buf[0..index], true },
            else => {},
        }

        index += 1;
    }
}

fn writeFn(_: void, bytes: []const u8) error{}!usize {
    if (bytes.len == 0) return 0;

    putChar(bytes[0]);
    return 1;
}

pub fn putString(str: []const u8) void {
    for (str) |ch| {
        putChar(ch);
    }
}

pub const Writer = std.io.Writer(void, error{}, writeFn);
pub const writer: Writer = .{ .context = {} };
