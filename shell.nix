{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.bluespec
    pkgs.verilator
    pkgs.verilog
    pkgs.gtkwave
    pkgs.openfpgaloader

    pkgs.yosys
    pkgs.zig_0_12
    pkgs.nextpnrWithGui
    pkgs.trellis
    pkgs.graphviz
    pkgs.fujprog

    pkgs.SDL2
  ];

  shellHook = ''
    export BLUESPECDIR=${pkgs.bluespec}/lib
    '';
}
