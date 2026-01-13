import ClientServer::*;
import StmtFSM::*;
import Utils::*;
import GetPut::*;

Ascii upperL = charToAscii("L");
Ascii upperR = charToAscii("R");

typedef Int#(16) Pos;

module mkSolveDay1#(Put#(Ascii) transmit, Get#(Ascii) receive) (Empty);
  Reg#(Pos) current_pos <- mkReg(50);
  Reg#(Bit#(32)) count <- mkReg(0);

  Reg#(Bool) is_left <- mkReg(?);
  Reg#(Bool) is_blank <- mkReg(True);

  Reg#(Pos) num <- mkReg(?);

  Server#(void,void) error0 <-
    mkStringPrinter("\nERROR 0: Invalid input for problem 1\n", transmit);
  Server#(void,void) error1 <-
    mkStringPrinter("\nERROR 1: Invalid input for problem 1\n", transmit);
  Reg#(Bool) stop <- mkReg(False);

  Put#(Bit#(64)) resultPrinter <- mkResultPrinter(transmit);

  rule stop0;
    error0.response.get;
  endrule

  rule stop1;
    error1.response.get;
  endrule

  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule incr_cycle; cycle <= cycle+1; endrule

  // I used a the Bluesec DSL for finite state machines for parsing, and also directly to solve the
  // problem because it can be done in one linear scan of the inputs
  let stmt = seq
    while (!stop) seq
      // Read L or R
      //while (is_blank && !stop) action
      //  Ascii ascii <- receive.get();

      //  is_blank <= asciiIsSpace(ascii);
      //  is_left <= ascii == upperL;
      //  num <= 0;

      //  if (!asciiIsSpace(ascii) && ascii != upperL && ascii != upperR) begin
      //    if (ascii != charToAscii("\n") && ascii != 0) error0.request.put(?);
      //    stop <= True;
      //  end
      //endaction
      action
        Ascii ascii <- receive.get();

        is_left <= ascii == upperL;
        is_blank <= False;
        num <= 0;

        if (ascii == charToAscii("\n") || ascii == 0) begin
          stop <= True;
        end else if (ascii != upperL && ascii != upperR) begin
          error0.request.put(?);
          stop <= True;
        end
      endaction

      // Read the size of the rotation
      while (!is_blank && !stop) action
        Ascii ascii <- receive.get();
        is_blank <= asciiIsSpace(ascii);

        if (ascii >= charToAscii("0") && ascii <= charToAscii("9")) begin
          num <= zeroExtend(unpack(ascii - charToAscii("0"))) + 10 * num;
        end else if (ascii != charToAscii("\n")) begin
          error1.request.put(?);
          stop <= True;
        end
      endaction

      if (!stop) seq
        // Update the state of the dial, and the conter of zeros
        action
          let new_pos = is_left ? current_pos - num : current_pos + num;
          current_pos <= new_pos;
        endaction

        // Compute `current_pos % 100` (high complexity but works well for small numbers)
        while (current_pos >= 100) action
          current_pos <= current_pos - 100;
        endaction

        while (current_pos < 0) action
          current_pos <= current_pos + 100;
        endaction

        count <= current_pos == 0 ? count + 1 : count;

        // Update the counter and display the current result
        action
          $display(
            "incr: %d current pos: %d zeros count: %d cycle: %d",
            is_left ? -num : num, current_pos, count, cycle
          );
        endaction
      endseq
    endseq

    resultPrinter.put(zeroExtend(pack(count)));

    while (True) noAction;
  endseq;

  mkAutoFSM(stmt);
endmodule
