
# Day 1

For the first day I directly used the DSL in bluespec to write finite state machines, this allow to
write the solution using sequence of actions, `if-then-else` and `while` blocks.

# Day 10

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

This module use a variable `counter` to iterate over all the combinations of buttons, and a rule

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

# Day 11

For this problem I foccused on the first part as the second part is just repeating the first one
four times, then use the formula:

```
num_paths("svr", "out", constraint=["dac", "fft"]) =
    num_paths("svr", "fft") * num_paths("fft", "dac") * num_paths("dac", "out") +
    num_paths("svr", "dac") * num_paths("dac", "fft") * num_paths("fft", "out")
```

## Algorithmic improvments

Since it was easy to make small mistakes in the algorithm, I started by writing a prototype in Python, and I took the opportunity to measure the performance of my different ideas.

My first idea was to use a simple recursive search over the nodes, like so
(assuming the abscence of cycles):

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

This approach works great as the number of inputs of the problem is quite small by I wanted
to find a better solution to minimize the number of cycles I needed. in particular with this
approach the complexity is superior to the sum of the length of all the paths from "you" to "out",
this can be problematic in presence of a lot a diamond patterns:

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
algorithm and I found that the first approach used `1497` recursive calls while the second used only
`425`, plus `212` loop iterations in the dynamic programming part of the algorithm.
For part 2 the difference is even greater, the answer is calculated instantly with dynamic programming whereas the naive algorithm is extremely long.

## Hardware implementation

The hardest part of the implementation was the topological sort because the parsing and dynamic
programming parts where relatively easy. For the sort I started by rewriting the algorithm to a form
that manipulate contiguous arrays of nodes insteads of sigle node. This is because it simplify the
content of the call stack that I will represent explicitly.

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

It is therefore now very straightforward to transform this algorithm into Bluespec using the DSL for state machines.

```verilog
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
```

# Performances

For all the problems I compared the performance of my solution with an implementation in Zig
(Zig-0.12) running on my own out-of-order CPU that I made a year ago. Doing so it is possible to
see the improvment of the direct implementation in Bluespec against a standard implementation in a
compiled programming language (Zig in my case).

|                 | Bluespec version | OOO CPU cycle | OOO CPU instructions | Imrovement |
|-----------------|------------------|---------------|----------------------|------------|
| Day 1 (part 1)  | 35.9K            | 4.94M         | 4.06M                | 138x       |
| Day 10 (part 1) | 37.1K            |               |                      |            |
| Day 11 (part 1) | 47.9K            | 62.2M         | 52.0M                | 1086x      |

These tests are cycle-accurate except for the UART, which responds in one cycle.
Indeed, if the UART were simulated with cycle accuracy, then most of the time would be spent waiting for it.
So I disabled it to get results that were representative of the time spent doing calculations.
