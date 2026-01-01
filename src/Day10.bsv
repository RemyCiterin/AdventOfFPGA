import ClientServer::*;
import StmtFSM::*;
import Utils::*;
import GetPut::*;
import Vector::*;
import RegFile::*;
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
  Vector#(15, BitVec) patterns;
  Bit#(32) num_patterns;
} SolverInput deriving(Bits);

// Solve the problem of setting all the buttons for a given light by brute-force
module mkLightsSolver(Server#(SolverInput, Bit#(32)));
  Reg#(BitVec) target <- mkReg(?);
  Reg#(Vector#(15, BitVec)) patterns <- mkReg(replicate(?));
  Reg#(Bit#(32)) num_patterns <- mkReg(?);

  Reg#(Bit#(32)) best_solution <- mkReg(?);

  Reg#(Bit#(16)) counter <- mkReg(?);
  Reg#(Bool) valid <- mkReg(False);

  rule step if (valid && counter != 1 << num_patterns);
    BitVec ret = 0;
    Bit#(32) count = 0;
    for (Integer i=0; i < 15; i = i + 1) begin
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

typedef Bit#(4) Machine;
typedef Bit#(4) Button;
typedef Int#(16) Joltage;

typedef Vector#(16, Joltage) Row;

typedef enum {
  Idle,
  Rst,
  Busy,
  BruteForce,
  ComputeBounds,
  SearchNonZero,
  MultiplyRows,
  Output
} JoltageSolverState deriving(Bits, FShow, Eq);

interface JoltageSolver;
  method Action reset;

  method Action setJoltage(Machine machine, Joltage joltage);

  method Action setButton(Machine machine, Button button);

  method Action call();

  method ActionValue#(Bit#(32)) getResult();
endinterface



(* synthesize *)
module mkJoltageSolver(JoltageSolver);
  RegFile#(Machine, Row) matrix <- mkRegFileFull;
  Vector#(15, Reg#(Joltage)) bounds <- replicateM(mkReg(maxBound));
  Vector#(15, Reg#(Joltage)) assigns <- replicateM(mkReg(maxBound));
  Vector#(15, Reg#(Maybe#(Machine))) basics <- replicateM(mkReg(Invalid));
  Button cnstr = 15;

  Reg#(Button) max_buttons <- mkReg(0);
  Reg#(Button) max_machines <- mkReg(0);

  Server#(Tuple2#(Joltage, Joltage), Tuple2#(Joltage, Joltage)) gcdServer <- mkDivGcd;
  Server#(Tuple2#(Joltage, Joltage), Maybe#(Joltage)) divServer <- mkExactDivider;

  Reg#(Machine) resetMachine <- mkReg(0);
  Reg#(JoltageSolverState) state <- mkReg(Rst);

  rule resetRule if (state == Rst);
    for (Integer i=0; i < 15; i = i + 1) begin
      bounds[i] <= maxBound;
      basics[i] <= Invalid;
      assigns[i] <= 0;
    end

    matrix.upd(resetMachine, replicate(0));
    if (resetMachine + 1 == 0) state <= Idle;
    resetMachine <= resetMachine + 1;
    max_machines <= 0;
    max_buttons <= 0;
  endrule

  Reg#(Machine) i0 <- mkReg(?);
  Reg#(Machine) i1 <- mkReg(?);
  Reg#(Machine) i2 <- mkReg(?);

  Reg#(Button) j0 <- mkReg(?);
  Reg#(Button) j1 <- mkReg(?);
  Reg#(Button) j2 <- mkReg(?);

  Reg#(Bool) continue0 <- mkReg(?);
  Reg#(Bool) continue1 <- mkReg(?);
  Reg#(Bool) continue2 <- mkReg(?);
  Reg#(Bool) continue3 <- mkReg(?);

  Reg#(Joltage) coef <- mkReg(?);

  Reg#(Machine) r <- mkReg(?);
  Reg#(Machine) k <- mkReg(?);
  Reg#(Row) currentRow <- mkReg(?);

  function ActionValue#(Bool) nextAssign();
    actionvalue
      Bool result = True;

      for (Integer j=0; j < 15; j = j + 1)
      if (basics[j] matches Invalid &&& result &&& fromInteger(j) <= max_buttons) begin
        if (assigns[j] > bounds[j]) assigns[j] <= 0;
        else begin
          assigns[j] <= assigns[j] + 1;
          result = False;
        end
      end

      return result;
    endactionvalue
  endfunction

  Reg#(Bit#(32)) currentCost <- mkReg(?);
  Reg#(Bit#(32)) bestCost <- mkReg(?);
  Reg#(Bool) validAssign <- mkReg(?);

  // Check that the current assignment of the non-basic variables give a valid assignment of the
  // basic variables and compute the cost in `currentCost`
  let checkAssign = seq
    action
      validAssign <= True;
      continue0 <= True;
      currentCost <= 0;
      i0 <= 0;
      j0 <= 0;
    endaction

    while (continue0) seq
      i0 <= unJust(basics[j0]);

      if (isJust(basics[j0])) seq
        action
          Row row = matrix.sub(i0);
          Joltage acc = row[cnstr];

          for (Integer j=0; j < 15; j = j + 1) begin
            if (fromInteger(j) != j0) acc = acc - row[j] * assigns[j];
          end

          divServer.request.put(tuple2(acc, row[j0]));
          //$write("div(%d, %d) = ", acc, row[j0]);
        endaction

        action
          let resp <- divServer.response.get;
          case (resp) matches
            tagged Valid .r : begin
              //$display("%d", r);
              validAssign <= r >= 0;
              assigns[j0] <= r;
            end
            Invalid : validAssign <= False;
          endcase
        endaction
      endseq

      action
        Bit#(32) newCost = zeroExtend(pack(assigns[j0]));
        continue0 <= validAssign && j0 < max_buttons && currentCost + newCost < bestCost;
        currentCost <= currentCost + newCost;
        j0 <= j0 + 1;
      endaction
    endseq
  endseq;

  mkAlwaysFSMWithPred(seq
    continue0 <= True;
    bestCost <= maxBound;

    while (continue0) seq
      checkAssign;

      action
        if (validAssign && currentCost < bestCost) begin
          bestCost <= currentCost;
        end

        let nextPossible <- nextAssign;
        continue0 <= !nextPossible;
      endaction
    endseq

    state <= Output;
  endseq, state == BruteForce);

  // Compute for bounds for the brute force phase, i0 and j0 must be set to 0 after this phase
  rule computeBounds if (state == ComputeBounds);
    Row row = matrix.sub(i0);
    if (row[j0] != 0 && bounds[j0] > row[cnstr]) bounds[j0] <= row[cnstr];

    if (j0 + 1 == cnstr && i0 + 1 == 0) state <= SearchNonZero;
    j0 <= j0 + 1 == cnstr ? 0 : j0 + 1;
    if (j0 + 1 == cnstr) i0 <= i0 + 1;
    r <= 0;
  endrule

  function Joltage abs(Joltage x) = x > 0 ? x : -x;

  // Look for a row `k` such that `matrix[k][j0] != 0` and swap the row `k` and `r`, and set `j0`
  // as a basic variable of column `r`.
  mkAlwaysFSMWithPred(seq
      action
        coef <= matrix.sub(r)[j0];
        continue0 <= True;
        i0 <= r;
        k <= r;
      endaction

      while (continue0) action
        Row row = matrix.sub(i0);
        if (abs(row[j0]) > abs(coef)) begin
          coef <= row[j0];
          k <= i0;
        end

        continue0 <= i0 < max_machines;
        i0 <= i0 + 1;
      endaction

      if (coef != 0) seq
        basics[j0] <= Valid(r);
        currentRow <= matrix.sub(k);
        matrix.upd(k, matrix.sub(r));
        matrix.upd(r, currentRow);
        state <= MultiplyRows;
      endseq else action
        if (j0 == max_buttons) state <= BruteForce;
        j0 <= j0 + 1;
      endaction
  endseq, state == SearchNonZero);

  Reg#(Tuple2#(Joltage, Joltage)) gcdResponse <- mkReg(?);

  mkAlwaysFSMWithPred(seq
      action
        i0 <= 0;
        continue0 <= True;
      endaction

      while (continue0) seq
        if (i0 != r) seq
          action
            Row row = matrix.sub(i0);
            gcdServer.request.put(tuple2(coef, row[j0]));
          endaction

          action
            let resp <- gcdServer.response.get;
            gcdResponse <= resp;
          endaction

          action
            Row row = matrix.sub(i0);
            for (Integer j=0; j < 16; j = j + 1) begin
              row[j] = gcdResponse.fst * row[j] - gcdResponse.snd * currentRow[j];
            end

            matrix.upd(i0, row);
          endaction
        endseq

        action
          i0 <= i0 + 1;
          continue0 <= i0 < max_machines;
        endaction
      endseq

      action
        r <= r + 1;
        j0 <= j0 + 1;
        state <= j0 == max_buttons ? BruteForce : SearchNonZero;
      endaction
  endseq, state == MultiplyRows);

  method Action call if (state == Idle);
    state <= ComputeBounds;
    i0 <= 0;
    i1 <= 0;
    i2 <= 0;
    j0 <= 0;
    j1 <= 0;
    j2 <= 0;
  endmethod

  method getResult if (state == Output);
    actionvalue
      state <= Idle;
      return bestCost;
    endactionvalue
  endmethod

  method Action setJoltage(Machine machine, Joltage joltage) if (state == Idle);
    max_machines <= max(machine, max_machines);
    Row row = matrix.sub(machine);
    row[cnstr] = joltage;
    matrix.upd(machine, row);
  endmethod

  method Action setButton(Machine machine, Button button) if (state == Idle);
    max_machines <= max(machine, max_machines);
    max_buttons <= max(button, max_buttons);
    Row row = matrix.sub(machine);
    row[button] = 1;
    matrix.upd(machine, row);
  endmethod

  method Action reset if (state == Idle);
    resetMachine <= 0;
    state <= Rst;
  endmethod
endmodule

typedef 8 NumLightSolver;

module mkSolveDay10#(Put#(Ascii) transmit, Get#(Ascii) receive) (Empty);
  Reg#(Bit#(15)) num <- mkReg(?);

  Reg#(BitVec) target <- mkReg(?);
  Reg#(Vector#(15, BitVec)) patterns <- mkReg(replicate(?));
  Reg#(Bit#(32)) num_patterns <- mkReg(?);

  Reg#(Bit#(32)) result <- mkReg(0);
  Reg#(Bit#(32)) joltageResult <- mkReg(0);

  Vector#(NumLightSolver, Server#(SolverInput, Bit#(32))) light_solvers <-
    replicateM(mkLightsSolver);
  Vector#(NumLightSolver, Reg#(Bool)) light_solvers_ready <- replicateM(mkReg(True));

  JoltageSolver joltageSolver <- mkJoltageSolver;

  Bit#(TLog#(NumLightSolver)) next_solver = 0;
  for (Integer i=0; i < valueOf(NumLightSolver); i = i + 1) begin
    if (light_solvers_ready[i]) next_solver = fromInteger(i);
  end

  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule incr_cycle; cycle <= cycle+1; endrule

  Server#(void, Tuple2#(Ascii, Bit#(32))) parseInt <- mkIntegerParser(receive);

  Reg#(Bit#(15)) pos <- mkReg(0);

  Reg#(Bool) continue0 <- mkReg(True);
  Reg#(Bool) continue1 <- mkReg(True);

  for (Integer i=0; i < valueOf(NumLightSolver); i = i + 1) begin
    rule add_light_result;
      light_solvers_ready[i] <= True;
      let ret <- light_solvers[i].response.get;
      $display("increment result to %d at cycle %d", result + ret, cycle);
      transmit.put(ret[7:0]);
      result <= result + ret;
    endrule
  end

  rule add_joltage_result;
    let ret <- joltageSolver.getResult;
    joltageResult <= joltageResult + ret;
    $display("current solution for part 2: %d", joltageResult + ret);
    transmit.put(ret[7:0]);
  endrule

  Reg#(Machine) num_machine <- mkReg(?);

  let stmt = seq
    while (True) seq
      // Parse target pattern
      action
        num_machine <= 0;
        joltageSolver.reset;
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
            joltageSolver.setButton(truncate(idx), truncate(num_patterns));
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
        light_solvers_ready[next_solver] <= False;
        light_solvers[next_solver].request.put(SolverInput{
          num_patterns: num_patterns,
          patterns: patterns,
          target: target
        });
      endaction

      continue0 <= True;
      while (continue0) seq
        parseInt.request.put(?);

        action
          match {.ascii, .idx} <- parseInt.response.get;
          joltageSolver.setJoltage(num_machine, unpack(truncate(idx)));
          num_machine <= num_machine + 1;
          continue0 <= ascii == comma;
        endaction
      endseq

      action
        joltageSolver.call;
        let _ <- receive.get();
      endaction
    endseq
  endseq;

  mkAutoFSM(stmt);
endmodule

// Represent an intermediate state
// of the division
typedef struct {
  Bit#(size) index;
  Bit#(size) rem;
  Bit#(size) div;
  Bit#(size) num;
  Bit#(size) den;
} DivideUState#(numeric type size) deriving(Bits, FShow, Eq);

function DivideUState#(size) divideInit(Bit#(size) num, Bit#(size) den);
  Bool found = False;
  Bit#(size) index = 0;
  for (Integer i=valueOf(size)-1; i >= 0; i = i - 1) if (!found && num[i] == 1) begin
    index[i] = 1;
    found = True;
  end

  return DivideUState{
    index: index,//1 << (valueOf(size) - 1),
    num: num,
    den: den,
    rem: 0,
    div: 0
  };
endfunction

// Let a = b * (2^-(n+1) * q) + 1
//   2 * a = b * (2^-n * q) + 2*r
//   2 * a + 1 = b * (2^-n * q) + 2*r+1
//
// Then we remove b to the reminder if 2*r+1 or 2*r is greater than b
function DivideUState#(size) divideStep(DivideUState#(size) state);
  state.rem = (state.num & state.index) != 0 ? (state.rem << 1) | 1 : state.rem << 1;

  if (state.rem >= state.den) begin
    state.rem = state.rem - state.den;
    state.div = state.div | state.index;
  end

  state.index = state.index >> 1;

  return state;
endfunction

typedef 18 DivideSize;

typedef union tagged {
  void Idle;
  DivideUState#(DivideSize) Busy;
} DivideState deriving(Bits, FShow, Eq);

// For any input (a,b), return r == 0 ? Valid(q) : Invalid
module mkExactDivider(Server#(Tuple2#(Joltage, Joltage), Maybe#(Joltage)));
  Reg#(DivideState) state <- mkReg(Idle);
  Reg#(Tuple2#(Joltage, Joltage)) req <- mkReg(?);

  rule step if (state matches tagged Busy .st &&& st.index != 0);
    DivideUState#(DivideSize) newState = st;

    for (Integer i=0; i < 4; i = i + 1) begin
      if (newState.index != 0) newState = divideStep(newState);
    end

    state <= Busy(newState);
  endrule

  interface Put request;
    method Action put(Tuple2#(Joltage, Joltage) r) if (state matches Idle);
      let num = zeroExtend(pack(r.fst < 0 ? -r.fst : r.fst));
      let den = zeroExtend(pack(r.snd < 0 ? -r.snd : r.snd));
      state <= Busy(divideInit(num, den));
      req <= r;
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(Maybe#(Joltage)) get
      if (state matches tagged Busy .st &&& st.index == 0);
      // Euclidian division:
      //
      //   Let a = b * q
      //   -a = -b * q
      //   -a = b * (-q)
      //   a = (-b) * (-q)

      Joltage q = unpack(truncate(st.div));
      Joltage r = unpack(truncate(st.rem));
      state <= Idle;

      if (r != 0) return Invalid;
      else begin
        return Valid( ((req.fst < 0 && req.snd > 0) || (req.fst > 0 && req.snd < 0)) ? -q : q );
      end
    endmethod
  endinterface
endmodule


// Return (in[0] / gcd(in[0], in[1]), in[1] / gcd(in[0], in[1]))
module mkDivGcd(Server#(Tuple2#(Joltage, Joltage), Tuple2#(Joltage, Joltage)));
  Reg#(Joltage) x <- mkReg(?);
  Reg#(Joltage) y <- mkReg(?);

  // The following value:
  //    (x1 * (x / gcd(x,y)) + x2 * (y / gcd(x,y)), y1 * (x / gcd(x,y)) + y2 * (y / gcd(x,y)))
  // must be invariant during the computation, this allow to quickly find the expected value
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
    end else if (y > x) begin
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
