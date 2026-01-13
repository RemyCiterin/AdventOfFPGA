# Requirements

You can use `nix-shell shell.nix` to install all the requirements

# Reproduce

To run the bluespec designs on the tiny examples you can use the command:

```bash
make bsim DAY=<insert a number, I support 1,9,10,11> USE_PERSONAL_INPUT=false
```

or

```bash
make bsim DAY=<insert a number, I support 1,9,10,11>
```

to use my personal puzzle input instead.

# Day 1



https://github.com/user-attachments/assets/ea64b168-f5a7-44a6-9a84-dac7d63e52d0



For the first day I directly used the DSL in bluespec to write finite state machines, this allow to
write the solution using sequence of actions, `if-then-else` and `while` blocks.

# Day 9 (part 1 and 2)



https://github.com/user-attachments/assets/21878be7-3cbd-4320-af5c-8413102e29b3



For this day I solved both parts using some kind of brute force algorithms. In the first part I just
iterate over all the possible boxes and save the best area I found. And in the second part I
additionally check if their is an intersection between the interior of the box and an edge.
I also needed to check that the box it at the interior of the shape
by testing the parity of the number of intersection between the vertical edges and a vertical rayon
starting from top-left corner of the box. To speed-ub the algorithm I perform the search over the
vertical and horizontal edges in parallel using the `par ... endpar` keywords from the
finite-state-machines DSL in Bluespec.

# Day 10

## Part 1

My way of solving this problem is by doing a brute-force search over the buttons to find the
solution. So I implemented a module of solver with the interface `Server#(SolverInput, Bit#(32))`
with

```bsv
typedef struct {
  BitVec target;                // Light target pattern
  Vector#(12, BitVec) patterns; // Pattern of each button
  Bit#(32) num_patterns;        // Number of buttons
} SolverInput deriving(Bits);
```

This module use a variable `counter` to iterate over all the combinations of buttons, and a rule to
perform this iteration:

```bsv
  rule step if (valid && counter != 1 << num_patterns);
    // The pattern corresponding to the current solution counter
    BitVec ret = 0;

    // Number of button pushs of the current solution counter
    Bit#(32) count = 0;
    for (Integer i=0; i < 12; i = i + 1) begin
      if (counter[i] == 1) begin
        ret = ret ^ patterns[i];
        count = count + 1;
      end
    end

    if (ret == target && count < best_solution) best_solution <= count;

    counter <= counter + 1;
  endrule
```

doing so it is possible to use multiple parallel solvers to minimize the solving time.

## Part 2

The part II was a lot harder that the part I for me. Initially, I misread the instructions and
thought the Joltages were minimum values per machine, not exact values. As a result, I wasted a lot
of time trying to adapt the Simplex algorithm and branch-and-bounds/Gomory cuts to run on an FPGA.
I was about to give up due to accuracy issues when I reread the instructions and realized my
mistake. Ultimately, I used Gauss-Jordan reduction to partition the variables into two groups:
- non-basic variables, which are unconstrained
- and basic variables, which are constrained. Each basic variable can be obtained through an affine
relationship on the non-basic variables.

Then I performed a brute-force search on the non-basic variables.

### Gauss-Jordan reduction

The main challenge to implement this algorithm is to deal with numeric stability: during each
steps of the Gauss-Jordan reduction we have to perform the division of the current row by the pivot
element of the matrix, this step can be a cause of instability. As example here is the pseudocode of
the algorithm from wikipedia (translated from french):

```
Gauss-Jordan
     r = 0
     For j from 1 to m
     |   Search k = max_i(|A[i,j]|, r+1 ≤ i ≤ n)
     |
     |   If A[k,j]≠0 then
     |   |   r=r+1
     |   |   Divide the row `k` by `A[k,j]`
     |   |   If k≠r then
     |   |       |   Swap(A[k,..], A[r, ..])
     |   |   End If
     |   |   For i from 1 to n
     |   |   |   If i≠r then
     |   |   |   |   A[i,..] = A[i,..] - A[i,j] * A[r,..]
     |   |   |   Enf If
     |   |   End For
     |   End If
     End For
  End Gauss-Jordan
```

To deal with that my first idea was to use rational numbers. But using rationals I would have to
normalize the matrix elements by calculating the GCD after each pivot. I therefore decided to lose
the invariant that `A[r][j] == 1` after each pivot by using natural numbers with the following
variant of the algorithm:

```
Gauss-Jordan
     r = 0
     For j from 1 to m
     |   Search k = max_i(|A[i,j]|, r+1 ≤ i ≤ n)
     |
     |   If A[k,j]≠0 then
     |   |   r=r+1
     |   |   If k≠r then
     |   |       |   Swap(A[k,..], A[r, ..])
     |   |   End If
     |   |   For i from 1 to n
     |   |   |   If i≠r then
     |   |   |   |   A[i,..] = A[r,j] * A[i,..] - A[i,j] * A[r,..]
     |   |   |   Enf If
     |   |   End For
     |   End If
     End For
  End Gauss-Jordan
```

But after experimenting with my puzzle input, I deduced that I should use 256-bit integers to
avoid overflow. However, larger integers mean using more multipliers, which are a rare resource on
my FPGA (I have 156 18x18 multipliers). Specifically, if I use sufficiently small integers, I can
hope to perform row multiplications in a single cycle.

So I tried this other variation by adding a division by a GCD (which can be calculated at the same
time as the GCD) in the right place:

```
Gauss-Jordan
     r = 0
     For j from 1 to m
     |   Search k = max_i(|A[i,j]|, r+1 ≤ i ≤ n)
     |
     |   If A[k,j]≠0 then
     |   |   r=r+1
     |   |   If k≠r then
     |   |       |   Swap(A[k,..], A[r, ..])
     |   |   End If
     |   |   For i from 1 to n
     |   |   |   If i≠r then
     |   |   |   |   a = A[r,j] / GCD(A[i,j], A[r,j])
     |   |   |   |   b = A[i,j] / GCD(A[i,j], A[r,j])
     |   |   |   |   A[i,..] = a * A[i,..] - b * A[r,..]
     |   |   |   Enf If
     |   |   End For
     |   End If
     End For
  End Gauss-Jordan
```

Thanks to this change, 16-bit integers are sufficient!

Then, to calculate divisions by the GCD, with `in0, in1` as inputs, I used `6` registers
`x,y,x1,x2,y1,y2` with the following invariants:

```
gcd(in0, in1) = gcd(x, y)
in0 / gcd(in0, in1) = x1 * (x / gcd(in0, in1)) + x2 * (y / (gcd(in0, in1)))
in1 / gcd(in0, in1) = y1 * (x / gcd(in0, in1)) + y2 * (y / (gcd(in0, in1)))
```

Then I adapted the classic algorithm for calculating the GCD by performing transitions for `x < 0`,
`y < 0`, `x > y > 0`, `0 < x < y`... while maintaining these invariants.

Here is the final implementation in Bluespec that I used for it:
```bsv
// Return (in[0] / gcd(in[0], in[1]), in[1] / gcd(in[0], in[1]))
module mkDivGcd(Server#(Tuple2#(Joltage, Joltage), Tuple2#(Joltage, Joltage)));
  Reg#(Joltage) x <- mkReg(?);
  Reg#(Joltage) y <- mkReg(?);

  Reg#(Joltage) x1 <- mkReg(?);
  Reg#(Joltage) x2 <- mkReg(?);
  Reg#(Joltage) y1 <- mkReg(?);
  Reg#(Joltage) y2 <- mkReg(?);

  Reg#(Bool) idle <- mkReg(True);

  Bool done = x >= 0 && y >= 0 && (y == 0 || y == 0 || x == y);

  rule step if (!idle && !done);
    if (x < 0) begin
      // x1 * (x / gcd(x,y)) + x2 * (y / gcd(x,y))
      // = -x1 * (-x / gcd(x,y)) + x2 * (y / gcd(x,y))
      // symetric argument for y1,y2
      x1 <= -x1;
      y1 <= -y1;
      x <= -x;
    end else if (y < 0) begin
      // symetric of the previous argument
      x2 <= -x2;
      y2 <= -y2;
      y <= -y;
    end else if (x > y) begin
      // x1 * (x / gcd(x,y)) + x2 * (y / gcd(x,y))
      // = x1 * ((x-y+y) / gcd(x,y)) + x2 * (y / gcd(x,y))
      // = x1 * ((x-y) / gcd(x,y)) + (x2+x1) * (y / gcd(x,y))
      // symetric argument for y1,y2
      x2 <= x1 + x2;
      y2 <= y1 + y2;
      x <= x - y;
    end else begin
      // symetric of the previous argument
      x1 <= x1 + x2;
      y1 <= y1 + y2;
      y <= y - x;
    end
  endrule

  interface Put request;
    method Action put(Tuple2#(Joltage, Joltage) req) if (idle);
      idle <= False;
      x <= req.fst;
      y <= req.snd;
      x1 <= 1;
      x2 <= 0;
      y1 <= 0;
      y2 <= 1;
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(Tuple2#(Joltage, Joltage)) get if (!idle && done);
      idle <= True;

      if (x == 0) return tuple2(x2, y2);
      else if (y == 0) return tuple2(x1, y1);
      else begin
        return tuple2(x1+x2, y1+y2);
      end
    endmethod
  endinterface
endmodule
```

### Brute-force

After doing the Gauss-Jordan reduction, we have two partitions of variables made of a set of basic
variables `B` and a set of non-basic (unconstrained) variables `N`, and for each basic variable
`Xi`, we have `Xi = (Bi - sum({ Aij * Xj | j in N })) / Ai` and we search the assignation from those
variables to the positive integers that minimize the sum of all the variables. To do so we can
iterate over all the possible assignations of the non-basic variables, and check for all the basic
variables `Xi` if `(Bi - sum({ Aij * Xj | j in N })) / Ai` is a positive integer. This is possible
because the initial problem give us some bounds about the assignations: if a button increment the
joltage of an engine, then it must be assigned to a value smaller than the required joltage of the
engine.

# Day 11 (part 1 and 2)

For this problem I focused on the first part, as the second part is just repeating the first one
four times, then use the formula:

```
num_paths("svr", "out", constraint=["dac", "fft"]) =
    num_paths("svr", "fft") * num_paths("fft", "dac") * num_paths("dac", "out") +
    num_paths("svr", "dac") * num_paths("dac", "fft") * num_paths("fft", "out")
```

## Algorithmic improvements

Since it was easy to make small mistakes in the algorithm, I started by writing a prototype in
Python, and I took the opportunity to measure the performance of my different ideas.

My first idea was to use a simple recursive search over the nodes, like so
(assuming the absence of cycles):

```python
def explore(node):
    if node == "out":
        return 1

    count = 0
    for x in edges[node]:
        count += explore(x)

    return count
explore("you")
```

This approach works great as the number of inputs of the problem is quite small but I wanted
to find a better solution to minimize the number of cycles I needed. In particular with this
approach, the complexity is superior to the sum of the length of all the paths from "you" to "out",
this can be problematic in the presence of a lot of diamond patterns:

```
      aaa      ddd
     ^   \    ^   \
    /     v  /     v
you       ccc      out
    \     ^  \     ^
     v   /    v   /
      bbb      eee
```

I quickly found another solution using dynamic programming and a topological sort:

```python
order = []
seen = {x: False for x in edges}

def topo_sort(node):
    if seen[node]: return
    seen[node] = True

    for x in edges[node]:
        topo_sort(x)

    order.append(node)

topo_sort("you")
print(order)
order.reverse()

counters = {x:0 for x in edges}
counters["you"] = 1

for node in order:
    for x in edges[node]:
        counters[x] += counters[node]

print("The number of paths from \"you\" to \"out\" is ", counters["out"])
```

This approach has a the complexity is `O(|E| + |V|)` (a **LOT** better than the previous algorithm).
Now the challenge was to implement the parsing and the search algorithm in hardware. I tested the
algorithm, and I found that the first approach used `1497` recursive calls, while the second used
only `425`, plus `212` loop iterations in the dynamic programming part of the algorithm.
For part 2 the difference is even greater; the answer is calculated instantly with dynamic
programming, whereas the naive algorithm is extremely long.

## Hardware implementation

The hardest part of the implementation was the topological sort because the parsing and dynamic
programming parts were relatively easy. For the sort, I started by rewriting the algorithm to a form
that manipulates contiguous arrays of nodes instead of single nodes. This is because it simplifies
the content of the call stack that I will represent explicitly.
```ocaml
let topo parent = function
    | [] ->
        order := parent : order;
        visited.(parent) <- true
    | x :: xs ->
        (* Visit `x`, then finish to visit `parent` *)
        if not visited.(x) then topo x edges.(x);
        topo parent xs
```

Then I transformed the algorithm using an explicit stack instead of recursive calls:

```ocaml
let stack = ref [(source, edges.(source))]

while not (List.is_empty !stack) do
    let (parent, succs) = List.hd !stack in
    stack := List.tl !stack in

    match succs with
    | [] -> begin
        order := parent : order;
        visited.(parent) <- true
    end
    | x :: xs -> begin
        (* We push `(parent,xs)` first to ensure we finish to explore `x` before `parent` *)
        stack := (parent, xs) :: stack;
        if not visited.(x) then stack := (x, edges.(x)) :: stack
    end
done
```

It is therefore now relatively straightforward to transform this algorithm into Bluespec using the
DSL for state machines.

```bsv
seq
  // Read the set of edges of the source node
  nodes.put(False, source, ?);

  // Initialize the stack with the source node, it's first successor, and it's number of successors
  stack.push(tuple3(source, nodes.read.index, nodes.read.length));

  while (!stack.empty) seq
    // Read the first element of the stack
    action
      match {.p, .i, .l} = stack.top;
      edges.put(False, i, ?);
      parent <= p;
      length <= l;
      index <= i;
      stack.pop;
    endaction

    if (length > 0) seq
      action
        // Push parent to the stack first
        stack.push(tuple3(parent, index+1, length-1));

        // Read if we already visited `edges.read` (`x` in the ocaml algorithm)
        visited.put(False, edges.read, ?);
        nodes.put(False, edges.read, ?);
      endaction

      if (!visited.read) stack.push(tuple3(edges.read, nodes.read.index, nodes.read.length));

    endseq else action
      // Mark `parent` as visited and add it to the output list
      order.put(True, order_length, parent);
      order_length <= order_length + 1;
      visited.put(True, parent, True);
    endaction
  endseq
endseq
```

# Performances

For all the problems, I compared the performance of my solution with an implementation in Zig
(Zig-0.12) running on my own out-of-order RISC-V CPU that I made a year ago. Doing so, it is
possible to see the improvement of an hardware implementation in Bluespec against a more standard
implementation in a compiled programming language. All the programs where compiled with
`-Doptimize=ReleaseFast`.

For the day 9, I also compared with 3DRiscV, a Soc that I made this year. It contains an in-order
RISC-V CPU and a RISC-V GPGPU connected together using a cache coherent interconnect. The GPGPU use
16 warps of 4 threads (so it can execute up to four instructions per cycle), the shaders are
compiled using my own optimizing compiler, which allows me to efficiently manage thread
reconvergence. For this example, the code running on the CPU is implemented in C with `gcc -O2`.
Unfortunately, the performance difference with DOoOM is not very impressive, even though using the
GPGPU greatly increases performance compared to the in-order CPU alone (186M cycles, versus 290M).

|                   | Bluespec cycles | DOoOM cycles | 3DRiscV cycles | Imrovement |
|-------------------|-----------------|--------------|----------------|------------|
| Day 1 (part 1)    | 35.9K           | 1.15M        | N/A            | 32x        |
| Day 9 (part 1&2)  | 6.41M           | 208M         | 186M           | 32x/29x    |
| Day 10 (part 1)   | 37.1K           | 13.5M        | N/A            | 364x       |
| Day 10 (part 1&2) | 12.4M           | 421M         | N/A            | 34x        |
| Day 11 (part 1)   | 47.9K           | 2.84M        | N/A            | 59.3x      |

These tests are cycle-accurate except for the UART, which responds in one cycle.
Indeed, if the UART were simulated with cycle accuracy, then most of the time would be spent waiting
for it. So I disabled it to get results that were representative of the time spent doing
calculations. All those tests where performed using my personal puzzle input.

Even though my CPU isn't as optimized as industrial CPUs (with superscalar execution, SIMD, etc.),
the performance difference is still very impressive.

