module mkTop (
  input CLK,
  input RST_N,

  output [7:0] led,
  output ftdi_rxd,
  input ftdi_txd
);

  mkSOC soc(
    .CLK(CLK),
    .RST_N(RST_N),

    .led(led),
    .ftdi_txd(ftdi_txd),
    .ftdi_rxd(ftdi_rxd)
  );

endmodule
