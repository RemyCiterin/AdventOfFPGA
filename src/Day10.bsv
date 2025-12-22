import ClientServer::*;
import StmtFSM::*;
import Utils::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;

Ascii curlyOpen = charToAscii("{");
Ascii squareOpen = charToAscii("[");
Ascii squareClose = charToAscii("]");
Ascii fullCell = charToAscii("#");
Ascii emptyCell = charToAscii(".");
Ascii parentOpen = charToAscii("(");
Ascii parentClose = charToAscii(")");
Ascii comma = charToAscii(",");
Ascii space = charToAscii(" ");
Ascii lineFeed = charToAscii("\n");


typedef Int#(12) BitVec;

typedef struct {
  BitVec target;
  Vector#(12, BitVec) patterns;
  Bit#(32) num_patterns;
} SolverInput deriving(Bits);

// Solve the problem of setting all the buttons for a given light by brute-force
module mkLightsSolver(Server#(SolverInput, Bit#(32)));
  Reg#(BitVec) target <- mkReg(?);
  Reg#(Vector#(12, BitVec)) patterns <- mkReg(replicate(?));
  Reg#(Bit#(32)) num_patterns <- mkReg(?);

  Reg#(Bit#(32)) best_solution <- mkReg(?);

  Reg#(Bit#(16)) counter <- mkReg(?);
  Reg#(Bool) valid <- mkReg(False);

  rule step if (valid && counter != 1 << num_patterns);
    BitVec ret = 0;
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

  interface Put request;
    method Action put(SolverInput in) if (!valid);
      num_patterns <= in.num_patterns;
      patterns <= in.patterns;
      best_solution <= -1;
      target <= in.target;
      valid <= True;
      counter <= 0;
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(Bit#(32)) get if (valid && counter == 1 << num_patterns);
      $display("best: %d", best_solution);
      valid <= False;
      return best_solution;
    endmethod
  endinterface
endmodule

typedef 8 NumSolver;

module mkSolveDay10#(Put#(Ascii) transmit, Get#(Ascii) receive) (Empty);
  Reg#(Bit#(12)) num <- mkReg(?);

  Reg#(BitVec) target <- mkReg(?);
  Reg#(Vector#(12, BitVec)) patterns <- mkReg(replicate(?));
  Reg#(Bit#(32)) num_patterns <- mkReg(?);

  Reg#(Bit#(32)) result <- mkReg(0);

  Vector#(NumSolver, Server#(SolverInput, Bit#(32))) solvers <- replicateM(mkLightsSolver);
  Vector#(NumSolver, Reg#(Bool)) solvers_ready <- replicateM(mkReg(True));

  Bit#(TLog#(NumSolver)) next_solver = 0;
  for (Integer i=0; i < valueOf(NumSolver); i = i + 1) begin
    if (solvers_ready[i]) next_solver = fromInteger(i);
  end

  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule incr_cycle; cycle <= cycle+1; endrule

  Server#(void, Tuple2#(Ascii, Bit#(32))) parseInt <- mkIntegerParser(receive);

  Reg#(Bit#(12)) pos <- mkReg(0);

  Reg#(Bool) continue0 <- mkReg(True);
  Reg#(Bool) continue1 <- mkReg(True);

  for (Integer i=0; i < valueOf(NumSolver); i = i + 1) begin
    rule add_result;
      solvers_ready[i] <= True;
      let ret <- solvers[i].response.get;
      $display("increment result to %d at cycle %d", result + ret, cycle);
      transmit.put(ret[7:0]);
      result <= result + ret;
    endrule
  end

  let stmt = seq
    while (True) seq
      // Parse target pattern
      action
        let _ <- receive.get();
        continue0 <= True;
        target <= 0;
        pos <= 0;
      endaction

      while (continue0) action
        let ascii <- receive.get();
        pos <= pos + 1;

        if (ascii == squareClose) continue0 <= False;
        if (ascii == fullCell) target <= target | (1 << pos);
      endaction

      action let _ <- receive.get(); endaction

      action
        let ascii <- receive.get();
        continue0 <= ascii == parentOpen;
        num_patterns <= 0;
      endaction

      while (continue0) seq
        action
          continue1 <= True;
          patterns[num_patterns] <= 0;
        endaction

        while (continue1) seq
          parseInt.request.put(?);

          action
            match {.ascii, .idx} <- parseInt.response.get();
            patterns[num_patterns] <= patterns[num_patterns] | (1 << idx);
            continue1 <= ascii == comma;
          endaction
        endseq

        action let _ <- receive.get(); endaction

        action
          let ascii <- receive.get();
          continue0 <= ascii == parentOpen;
          num_patterns <= num_patterns + 1;
        endaction
      endseq

      action
        solvers_ready[next_solver] <= False;
        solvers[next_solver].request.put(SolverInput{
          num_patterns: num_patterns,
          patterns: patterns,
          target: target
        });
      endaction

      continue0 <= True;
      while (continue0) action
        let ascii <- receive.get();
        continue0 <= ascii != lineFeed;
      endaction
    endseq
  endseq;

  mkAutoFSM(stmt);
endmodule
