import ClientServer::*;
import BRAMCore::*;
import StmtFSM::*;
import Utils::*;
import GetPut::*;

Ascii comma = charToAscii(",");
Ascii lineFeed = charToAscii("\n");

typedef Bit#(48) Number;
typedef Bit#(10) Addr;

typedef struct {
  Number xmin;
  Number xmax;
  Number ymin;
  Number ymax;
} Box deriving(Bits, Eq, FShow);

typedef struct {
  Number x;
  Number ymin;
  Number ymax;
} VEdge deriving(Bits, FShow, Eq);

typedef struct {
  Number y;
  Number xmin;
  Number xmax;
} HEdge deriving(Bits, FShow, Eq);

function Box buildBox(Number x0, Number y0, Number x1, Number y1);
  return Box{
    xmin: min(x0,x1) + 1,
    xmax: max(x0,x1) - 1,
    ymin: min(y0,y1) + 1,
    ymax: max(y0,y1) - 1
  };
endfunction

function Number boxArea(Box box) =
  (box.xmax - box.xmin + 3) * (box.ymax - box.ymin + 3);

function Bool vintersect(Box b, VEdge e) = b.xmin <= e.x && e.x <= b.xmax && (
    (e.ymin <= b.ymin && b.ymin <= e.ymax) ||
    (e.ymin <= b.ymax && b.ymax <= e.ymax)
);

function Bool hintersect(Box b, HEdge e) = b.ymin <= e.y && e.y <= b.ymax && (
    (e.xmin <= b.xmin && b.xmin <= e.xmax) ||
    (e.xmin <= b.xmax && b.xmax <= e.xmax)
);

module mkSolveDay9#(Put#(Ascii) transmit, Get#(Ascii) receive) (Empty);
  BRAM_PORT#(Addr, Tuple2#(Number,Number)) points <- mkBRAMCore1(1024, False);
  BRAM_PORT#(Addr, VEdge) vedges <- mkBRAMCore1(1024, False);
  BRAM_PORT#(Addr, HEdge) hedges <- mkBRAMCore1(1024, False);

  let printer <- mkResultPrinter(transmit);

  Reg#(Bit#(32)) cycle <- mkReg(0);
  rule incr_cycle; cycle <= cycle+1; endrule

  Reg#(Addr) num_vedges <- mkReg(0);
  Reg#(Addr) num_hedges <- mkReg(0);
  Reg#(Addr) num_points <- mkReg(0);

  Reg#(Tuple2#(Number, Number)) first_point <- mkReg(?);
  Reg#(Maybe#(Tuple2#(Number, Number))) last_point <- mkReg(Invalid);

  Server#(void, Tuple2#(Ascii, Bit#(32))) parseInt <- mkIntegerParser(receive);

  Reg#(Number) last_int <- mkReg(0);

  Reg#(Bool) continue0 <- mkReg(True);
  Reg#(Bool) continue1 <- mkReg(True);

  Reg#(Addr) addr0 <- mkReg(0);
  Reg#(Addr) addr1 <- mkReg(0);
  Reg#(Addr) addr2 <- mkReg(0);
  Reg#(Addr) addr3 <- mkReg(0);

  // Point from the inner loop
  Reg#(Tuple2#(Number,Number)) point <- mkReg(?);
  Reg#(Box) box <- mkReg(?);

  Reg#(Number) best_area_part1 <- mkReg(1);
  Reg#(Number) best_area_part2 <- mkReg(1);
  Reg#(Bool) found_vintersection <- mkReg(?);
  Reg#(Bool) found_hintersection <- mkReg(?);
  Reg#(Bool) found_intersection <- mkReg(?);
  Reg#(Number) iter_count <- mkReg(?);

  mkAutoFSM(seq
    while (continue0) seq
      parseInt.request.put(?);

      action
        match {.ascii, .i} <- parseInt.response.get;
        continue0 <= ascii == comma;
        last_int <= zeroExtend(i);
      endaction

      parseInt.request.put(?);

      if (continue0) action
        let x = last_int;
        match {.ascii, .i} <- parseInt.response.get;
        Number y = zeroExtend(i);
        //$display(x,y,ascii);
        continue0 <= ascii == lineFeed;
        points.put(True, num_points, tuple2(x,y));
        num_points <= num_points + 1;

        if (last_point matches tagged Valid ({.last_x, .last_y})) begin
          if (last_x == x) begin
            vedges.put(True, num_vedges, VEdge{x: x, ymin: min(y,last_y), ymax: max(y,last_y)});
            num_vedges <= num_vedges + 1;
          end else begin
            hedges.put(True, num_hedges, HEdge{y: y, xmin: min(x,last_x), xmax: max(x,last_x)});
            num_hedges <= num_hedges + 1;
          end
        end else begin
          first_point <= tuple2(x,y);
        end

        last_point <= Valid(tuple2(x,y));
      endaction
    endseq

    action
      match {.x,.y} = unJust(last_point);

      if (x == first_point.fst) begin
        vedges.put(True, num_vedges,
          VEdge{x: x, ymin: min(y,first_point.snd), ymax: max(y,first_point.snd)});
        num_vedges <= num_vedges + 1;
      end else begin
        hedges.put(True, num_hedges,
          HEdge{y: y, xmin: min(x,first_point.fst), xmax: max(x,first_point.fst)});
        num_hedges <= num_hedges + 1;
      end
    endaction


    while (addr0 < num_points) seq
      points.put(False, addr0, ?);
      point <= points.read;

      while (addr1 < num_points) seq
        points.put(False, addr1, ?);

        action
          box <= buildBox(point.fst, point.snd, points.read.fst, points.read.snd);
          found_vintersection <= False;
          found_hintersection <= False;
          found_intersection <= False;
          iter_count <= 0;
          addr2 <= 0;
          addr3 <= 0;

          // read the first edges
          vedges.put(False, 0, ?);
          hedges.put(False, 0, ?);
        endaction

        best_area_part1 <= max(best_area_part1, boxArea(box));

        // Stop the search here if the area is bot large enough
        if (boxArea(box) > best_area_part2) seq
          // Test intersection with horizontal and vertical lines in parallel
          // I use two variables for intersections here (`found_hintersection` and
          // `found_vintersection`) to ensure that both searchs can be done in parallel,
          // otherwise the Bluespec scheduler can't perform the two search rules at
          // the same cycle. In addition if one of the search find an intersection,
          // then the other search is ended using an additional rule.
          par
            while (!found_vintersection && !found_intersection && addr2 < num_vedges) seq
              action
                let e = vedges.read;

                if (e.x > box.xmin && e.ymin <= box.ymin && box.ymin < e.ymax)
                  iter_count <= iter_count + 1;

                if (vintersect(box, e)) found_vintersection <= True;

                // read the next vertical edge
                vedges.put(False, addr2+1, ?);
                addr2 <= addr2 + 1;
              endaction

              if (found_vintersection) found_intersection <= True;
            endseq

            while (!found_hintersection && !found_intersection && addr3 < num_hedges) seq
              action
                let e = hedges.read;

                if (hintersect(box, e)) found_hintersection <= True;

                // read the next horizontal edge
                hedges.put(False, addr3+1, ?);
                addr3 <= addr3 + 1;
              endaction

              if (found_hintersection) found_intersection <= True;
            endseq
          endpar

          if (!found_intersection && iter_count[0] == 1) action
            best_area_part2 <= boxArea(box);
            $display(boxArea(box));
          endaction
        endseq

        addr1 <= addr1 + 1;
      endseq

      action
        addr1 <= addr0 + 2;
        addr0 <= addr0 + 1;
      endaction
    endseq

    $display("cycles: %d part1: %d part2: %d", cycle, best_area_part1, best_area_part2);
    printer.put(zeroExtend(best_area_part1));
    printer.put(zeroExtend(best_area_part2));

    while (True) noAction;

  endseq);
endmodule

