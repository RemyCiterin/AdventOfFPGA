import ClientServer::*;
import BRAMCore::*;
import StmtFSM::*;
import Vector::*;
import GetPut::*;
import Fifo::*;
import Ehr::*;

typedef Bit#(8) Ascii;

function Ascii charToAscii(Char c) = fromInteger(charToInteger(c));

function Bool asciiIsSpace(Ascii a) =
  a == charToAscii(" ") ||
  a == charToAscii("\t") ||
  a == charToAscii("\n");

// Return an integer and the first input that is not a digit
module mkIntegerParser#(Get#(Ascii) receive) (Server#(void, Tuple2#(Ascii, Bit#(32))));
  Fifo#(2, Tuple2#(Ascii, Bit#(32))) outputQ <- mkFifo;
  Fifo#(2, void) inputQ <- mkFifo;

  Reg#(Bit#(32)) acc <- mkReg(0);
  Reg#(Bool) valid <- mkReg(False);

  rule start if (!valid);
    let _ <- toGet(inputQ).get;
    valid <= True;
    acc <= 0;
  endrule

  rule step if (valid);
    Ascii ascii <- receive.get();

    if (ascii >= charToAscii("0") && ascii <= charToAscii("9")) begin
      acc <= zeroExtend(unpack(ascii - charToAscii("0"))) + 10 * acc;
    end else begin
      outputQ.enq(tuple2(ascii, acc));
      valid <= False;
    end
  endrule

  interface request = toPut(inputQ);
  interface response = toGet(outputQ);
endmodule

module mkStringPrinter#(String str, Put#(Ascii) transmit) (Server#(void,void));
  Reg#(Maybe#(Bit#(16))) pointer <- mkReg(Invalid);
  let chars = stringToCharList(str);

  rule print_char if (pointer matches tagged Valid .ptr &&& ptr < fromInteger(stringLength(str)));
    let ascii = charToAscii(chars[ptr]);
    pointer <= Valid(ptr+1);
    transmit.put(ascii);
  endrule

  interface Put request;
    method Action put(_) if (pointer matches Invalid);
      pointer <= Valid(0);
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(void) get if (pointer == Valid(fromInteger(stringLength(str))));
      pointer <= Invalid;
      return ?;
    endmethod
  endinterface
endmodule

typedef enum {
  Idle,
  Division,
  Printing,
  PrintBracket,
  PrintSpace,
  PrintEndline
} ResultPrinterState deriving(Bits, Eq);

module mkResultPrinter#(Put#(Ascii) transmit) (Put#(Bit#(64)));
  Reg#(Bit#(64)) index <- mkReg(0);
  Reg#(Bit#(64)) num <- mkReg(0);
  Reg#(Bit#(64)) div <- mkReg(0);
  Reg#(Bit#(64)) rem <- mkReg(0);

  Vector#(16, Reg#(Bit#(8))) buffer <- replicateM(mkReg(0));
  Reg#(Bit#(5)) num_digits <- mkReg(0);

  Reg#(ResultPrinterState) state <- mkReg(Idle);

  rule print_bracket if (state == PrintBracket);
    transmit.put(charToAscii(">"));
    state <= PrintSpace;
  endrule

  rule print_space if (state == PrintSpace);
    transmit.put(charToAscii(" "));
    state <= Division;
  endrule

  rule div_step if (index != 0);
    let newRem = (num & index) != 0 ? (rem << 1) | 1 : rem << 1;

    if (newRem >= 10) begin
      newRem = newRem - 10;
      div <= div | index;
    end

    rem <= newRem;
    index <= index >> 1;
  endrule

  rule new_div if (state == Division && index == 0);
    index <= 1 << 63;
    num <= div;
    div <= 0;
    rem <= 0;

    if (div == 0) state <= Printing;
    buffer[num_digits] <= truncate(rem);
    num_digits <= num_digits + 1;
  endrule

  rule print_digit if (state == Printing);
    transmit.put(buffer[num_digits - 1] + charToAscii("0"));

    num_digits <= num_digits - 1;
    if (num_digits == 1) state <= PrintEndline;
  endrule

  rule print_endline if (state == PrintEndline);
    transmit.put(charToAscii("\n"));
    state <= Idle;
  endrule

  method Action put(Bit#(64) number) if (state == Idle);
    index <= 1 << 63;
    num <= number;

    state <= PrintBracket;
  endmethod
endmodule


interface Stack#(type alpha, numeric type logSize);
  (* always_ready *)
  method alpha top();

  (* always_ready *)
  method Bool empty;

  (* always_ready *)
  method Bool full;

  method Action pop();

  method Action push(alpha x);
endinterface

module mkStack(Stack#(alpha, logSize)) provisos(Bits#(alpha, alphaW));
  BRAM_PORT#(Bit#(logSize), alpha) ram <- mkBRAMCore1(valueOf(TExp#(logSize)), False);

  Ehr#(2, Bit#(logSize)) next <- mkEhr(0);
  Wire#(Bool) doPop <- mkDWire(False);
  RWire#(alpha) doPush <- mkRWire;

  (* no_implicit_conditions, fire_when_enabled *)
  rule canon;
    if (doPush.wget matches tagged Valid .x)
      ram.put(True, next[1]-1, x);
    else
      ram.put(False, next[1]-1, ?);
  endrule

  method empty = next[0] == 0;
  method full = next[0]+1 == 0;
  method top = ram.read;

  method Action pop() if (next[0] != 0);
    next[0] <= next[0] - 1;
    doPop <= True;
  endmethod

  method Action push(alpha x) if (next[0] + 1 != 0);
    next[0] <= next[0] + 1;
    doPush.wset(x);
  endmethod
endmodule
