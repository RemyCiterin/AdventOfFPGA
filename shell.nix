{ pkgs ? import <nixpkgs> {} }:

let
  pkgsCross = import pkgs.path {
    localSystem = pkgs.stdenv.buildPlatform.system;
    crossSystem = {
      config = "riscv32-none-elf";
      libc = "newlib-nano";
      #libc = "newlib";
      gcc.arch = "rv32ima";
    };
  };
in

pkgs.mkShell {
  buildInputs = [
    pkgs.bluespec
    pkgs.verilator
    pkgs.verilog
    pkgs.gtkwave
    pkgs.openfpgaloader

    pkgsCross.buildPackages.gcc

    pkgs.yosys
    pkgs.zig_0_12
    pkgs.nextpnrWithGui
    pkgs.trellis
    pkgs.graphviz
    pkgs.fujprog

    pkgs.SDL2

    pkgs.python313
    pkgs.python313Packages.matplotlib
    pkgs.python313Packages.numpy
  ];

  shellHook = ''
    export BLUESPECDIR=${pkgs.bluespec}/lib
    '';
}
