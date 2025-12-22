import Connectable :: *;
import UART :: *;

import BRAMCore :: *;

import ClientServer :: *;
import GetPut :: *;
import Fifo :: *;
import Real :: *;
import Ehr :: *;

import Vector :: *;
import BuildVector :: *;

import FixedPoint :: *;

import StmtFSM :: *;

import Utils::*;

import Day1::*;
import Day10::*;
import Day11::*;

interface Soc_Ifc;
  (* always_ready, always_enabled *)
  method Bit#(8) led;

  (* always_ready, always_enabled *)
  method Bit#(1) ftdi_rxd;

  (* always_ready, always_enabled, prefix="" *)
  method Action ftdi_txd((* port="ftdi_txd" *) Bit#(1) value);
endinterface

(* synthesize *)
module mkSOC(Soc_Ifc);
  TxUART tx_uart <- mkTxUART(217);
  RxUART rx_uart <- mkRxUART(217);
  Reg#(Bit#(8)) led_state <- mkReg(0);

  mkSolveDay10(
    interface Put;
      method Action put(Ascii x);
        tx_uart.put(x);
      endmethod
    endinterface,
    interface Get;
      method ActionValue#(Ascii) get if (rx_uart.valid);
        rx_uart.ack();
        return rx_uart.data;
      endmethod
    endinterface
  );

  method led = led_state;
  method ftdi_rxd = tx_uart.transmit;
  method ftdi_txd = rx_uart.receive;
endmodule


(* synthesize *)
module mkSOC_SIM(Empty);
  mkSolveDay1(
    interface Put;
      method Action put(Ascii x);
        $write("%c", x);
      endmethod
    endinterface,
    interface Get;
      method ActionValue#(Ascii) get;
        let char <- $fgetc(stdin);
        return char == -1 ? 0 : pack(char)[7:0];
      endmethod
    endinterface
  );
endmodule
