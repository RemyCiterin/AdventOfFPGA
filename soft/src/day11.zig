const UART = @import("print.zig");
const RV = @import("riscv.zig");
const std = @import("std");

const NodeList = std.ArrayList(u32);
const NodePaths = std.AutoHashMap(u32, u32);
const NodeSet = std.AutoHashMap(u32, bool);
const Graph = std.AutoHashMap(u32, NodeList);

pub fn topo_sort(node: u32, order: *NodeList, visited: *NodeSet, edges: *Graph) !void {
    if (visited.get(node).?) return;
    try visited.put(node, true);

    for (edges.get(node).?.items) |succ| {
        try topo_sort(succ, order, visited, edges);
    }

    try order.append(node);
}

pub fn solveDay11(allocator: std.mem.Allocator) !void {
    const cycle0 = RV.mcycle.read();
    const instr0 = RV.minstret.read();
    var buf: [1024]u8 = undefined;

    const source: u32 = @bitCast([4]u8{ 'y', 'o', 'u', 0 });
    const sink: u32 = @bitCast([4]u8{ 'o', 'u', 't', 0 });

    // A map used to store the edges of each node
    var map = Graph.init(allocator);
    defer map.deinit();
    defer {
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }

        map.deinit();
    }

    var paths = NodePaths.init(allocator);
    defer paths.deinit();

    var visited = NodeSet.init(allocator);
    defer visited.deinit();

    // Parse inputs
    while (true) {
        const result = UART.readLine(&buf);
        const line = result[0];

        const node: u32 = @bitCast([4]u8{ line[0], line[1], line[2], 0 });
        var list = NodeList.init(allocator);

        try visited.put(node, false);
        try paths.put(node, 0);

        var index: usize = 5;
        while (index < line.len) : (index += 4) {
            const ident = line[index .. index + 3];
            const ident_name: u32 = @bitCast([4]u8{ ident[0], ident[1], ident[2], 0 });
            try visited.put(ident_name, false);
            try paths.put(ident_name, 0);
            try list.append(ident_name);
        }

        try map.put(node, list);

        try UART.writer.print("read line {s}\n", .{line});

        if (result[1]) break;
    }

    var order = NodeList.init(allocator);
    defer order.deinit();

    try topo_sort(source, &order, &visited, &map);

    try paths.put(source, 1);
    for (0..order.items.len) |i| {
        const name = order.items[order.items.len - 1 - i];
        const p1 = paths.get(name).?;

        for (map.get(name).?.items) |succ| {
            const p2 = paths.get(succ).?;
            try paths.put(succ, p1 + p2);
        }
    }

    const cycle1 = RV.mcycle.read();
    const instr1 = RV.minstret.read();
    try UART.writer.print(
        "found {} paths in {} cycles and {} instructions\n",
        .{ paths.get(sink).?, cycle1 - cycle0, instr1 - instr0 },
    );
}
