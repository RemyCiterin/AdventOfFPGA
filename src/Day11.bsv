import StmtFSM::*;
import GetPut::*;
import Fifo::*;

import Vector::*;
import BuildVector::*;
import BRAMCore::*;

import Utils::*;
import Ehr::*;

// The names of the nodes in the graph are made of three characters
typedef Vector#(3, Bit#(5)) Name;

function Fmt showName(Name n);
  return $format(
    "%c%c%c",
    zeroExtend(n[0])+charToAscii("a"),
    zeroExtend(n[1])+charToAscii("a"),
    zeroExtend(n[2])+charToAscii("a")
  );
endfunction

typedef Bit#(16) Index;

typedef struct {
  // Index of the first successor of the node in `edges`
  Index index;

  // Length of the set of successors of the node in `edges`
  Index length;
} NodeEntry deriving(Bits);

module mkSolveDay11#(Put#(Ascii) transmit, Get#(Ascii) receive) (Empty);
  // Map each node to a contiguous array of edges given by it's first edge and it's length
  // This BRAM is big because I don't use any hash to encode the node names to avoid
  // collisions, but the design fit on my ECP5
  BRAM_PORT#(Name, NodeEntry) nodes <- mkBRAMCore1(valueOf(TExp#(SizeOf#(Name))), False);

  // Associate a destination to each edge
  BRAM_PORT#(Index, Name) edges <- mkBRAMCore1(valueOf(TExp#(SizeOf#(Index))), False);

  // A counter used to allocate new edges during parsing
  Reg#(Index) next_edge <- mkReg(0);

  // True iff a node has already been visited during the topological sort
  BRAM_PORT#(Name, Bool) visited <- mkBRAMCore1(valueOf(TExp#(SizeOf#(Name))), False);

  // Associate to each node it's position into the topological sort
  BRAM_PORT#(Name, Bit#(10)) position <- mkBRAMCore1(valueOf(TExp#(SizeOf#(Name))), False);

  // Topological sort as an array of nodes
  BRAM_PORT#(Bit#(10), Name) order <- mkBRAMCore1(1024, False);
  Reg#(Bit#(10)) order_length <- mkReg(0);

  // For each node in topological otder, associate the number paths from the source to this node
  BRAM_PORT#(Bit#(10), Bit#(32)) paths_from_source <- mkBRAMCore1(1024, False);


  Stack#(Tuple3#(Name, Index, Index), 8) stack <- mkStack;
  Reg#(Index) length <- mkReg(?);
  Reg#(Index) index <- mkReg(?);
  Reg#(Name) parent <- mkReg(?);

  Name source = vec(
    truncate(charToAscii("y") - charToAscii("a")),
    truncate(charToAscii("o") - charToAscii("a")),
    truncate(charToAscii("u") - charToAscii("a"))
  );

  Name sink = vec(
    truncate(charToAscii("o") - charToAscii("a")),
    truncate(charToAscii("u") - charToAscii("a")),
    truncate(charToAscii("t") - charToAscii("a"))
  );

  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule incr_cycle; cycle <= cycle + 1; endrule

  let topoSort = seq
    nodes.put(False, source, ?);
    stack.push(tuple3(source, nodes.read.index, nodes.read.length));

    while (!stack.empty) seq
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
          stack.push(tuple3(parent, index+1, length-1));
          visited.put(False, edges.read, ?);
          nodes.put(False, edges.read, ?);
        endaction

        if (!visited.read) stack.push(tuple3(edges.read, nodes.read.index, nodes.read.length));

      endseq else action
        paths_from_source.put(True, order_length, parent == source ? 1 : 0);
        position.put(True, parent, order_length);
        order.put(True, order_length, parent);
        order_length <= order_length + 1;
        visited.put(True, parent, True);
      endaction
    endseq
  endseq;

  Reg#(Bit#(32)) current_paths <- mkReg(0);

  // Could be optimize by recucing the number of actions inside each sequences
  let dynamic = seq
    while (order_length > 0) seq
      order_length <= order_length - 1;
      order.put(False, order_length, ?);
      nodes.put(False, order.read, ?);
      paths_from_source.put(False, order_length, ?);
      current_paths <= paths_from_source.read;
      length <= nodes.read.length;
      index <= nodes.read.index;

      while (length > 0) seq
        edges.put(False, index, ?);
        position.put(False, edges.read, ?);
        paths_from_source.put(False, position.read, ?);
        paths_from_source.put(True, position.read, current_paths+paths_from_source.read);
        length <= length - 1;
        index <= index + 1;
      endseq
    endseq

    position.put(False, sink, ?);
    paths_from_source.put(False, position.read, ?);
    $display("paths to out: %d", paths_from_source.read);
    transmit.put(truncate(paths_from_source.read));
  endseq;

  ///////////////////////////////////////////////////////////////////////////////////////
  // Parsing
  ///////////////////////////////////////////////////////////////////////////////////////

  // Each node is made of three characters, so I use two registers to store the values of the first
  // ones
  Reg#(Ascii) char1 <- mkReg(?);
  Reg#(Ascii) char2 <- mkReg(?);

  function Stmt getName(Reg#(Name) r) = seq
    action
      let x <- receive.get();
      char1 <= x;
    endaction

    action
      let x <- receive.get();
      char2 <= x;
    endaction

    action
      let a = charToAscii("a");
      let char3 <- receive.get();
      r <= vec(truncate(char1-a), truncate(char2-a), truncate(char3-a));
    endaction
  endseq;

  Reg#(Name) node1 <- mkReg(?);
  Reg#(Name) node2 <- mkReg(?);

  Reg#(Bool) continue0 <- mkReg(?);
  Reg#(Bool) continue1 <- mkReg(?);

  // I used a the Bluesec DSL for finite state machines for parsing
  let parseInputs = seq
    // Initialize the nodes memory with zeros
    $display("start to initialize the nodes at cycle: %d", cycle);
    node1 <= vec(0,0,0);
    continue0 <= True;
    while (continue0) action
      visited.put(True, node1, False);
      nodes.put(True, node1, NodeEntry{length:0,index:0});
      Name new_node = unpack(pack(node1)+1);
      continue0 <= pack(new_node) != 0;
      node1 <= new_node;
    endaction

    $display("finish to initialize the nodes at cycle: %d", cycle);

    continue0 <= True;
    while (continue0) seq
      length <= 0;
      getName(asReg(node1));

      // Ignore the ":"
      action let _ <- receive.get(); endaction

      // Ignore the " "
      action let _ <- receive.get(); endaction

      continue1 <= True;

      while (continue1) seq
        getName(asReg(node2));

        action
          edges.put(True, next_edge, node2);
          length <= length + 1;
          next_edge <= next_edge + 1;

          let x <- receive.get();
          if (x == charToAscii("\n")) continue1 <= False;
          if (x == 0 || x == charToAscii("#")) begin
            continue1 <= False;
            continue0 <= False;
          end
        endaction
      endseq

      nodes.put(True, node1,
        NodeEntry{index: next_edge - length, length: length});
    endseq

    $display("finish to parse the inputs at cycle: %d", cycle);

    topoSort;

    $display("finish the topological sort at cycle: %d", cycle);

    dynamic;

    $display("finish the dynamic programming at cycle: %d", cycle);

  endseq;

  mkAutoFSM(parseInputs);
endmodule
