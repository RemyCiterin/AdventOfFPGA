import ClientServer::*;
import BRAMCore::*;
import StmtFSM::*;
import GetPut::*;
import Fifo::*;
import Ehr::*;

typedef Bit#(8) Ascii;

function Ascii charToAscii(Char c) = fromInteger(charToInteger(c));

function Bool asciiIsSpace(Ascii a) =
  a == charToAscii(" ") ||
  a == charToAscii("\t") ||
  a == charToAscii("\n");

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
