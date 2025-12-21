RTL = rtl
BSIM = bsim
BUILD = build
PACKAGES = ./src/:+
SIM_FILE = ./build/mkTop_sim
TOP = src/Soc.bsv

BSIM_MODULE = mkSOC_SIM
BUILD_MODULE = mkSOC

LIB = \
			$(BLUESPECDIR)/Verilog/SizedFIFO.v \
			$(BLUESPECDIR)/Verilog/FIFO1.v \
			$(BLUESPECDIR)/Verilog/FIFO2.v \
			$(BLUESPECDIR)/Verilog/FIFOL1.v \
			$(BLUESPECDIR)/Verilog/Counter.v \
			$(BLUESPECDIR)/Verilog/BRAM1.v \
			$(BLUESPECDIR)/Verilog/BRAM1Load.v \
			$(BLUESPECDIR)/Verilog/BRAM2.v \
			$(BLUESPECDIR)/Verilog/BRAM1BE.v \
			$(BLUESPECDIR)/Verilog/BRAM2BE.v \
			$(BLUESPECDIR)/Verilog/RevertReg.v \
			$(BLUESPECDIR)/Verilog/RegFile.v \
			$(BLUESPECDIR)/Verilog/RegFileLoad.v \
			src/Top.v
			#src/sdram_axi.v \
			#src/sd_card.v

DOT_FILES = $(shell ls ./build/*_combined_full.dot) \
	$(shell ls ./build/*_conflict.dot)

svg:
	$(foreach f, $(DOT_FILES), sed -i '/_init_register_file/d' $(f);)
	$(foreach f, $(DOT_FILES), sed -i '/_update_register_file/d' $(f);)
	$(foreach f, $(DOT_FILES), sed -i '/_ehr_canon/d' $(f);)
	$(foreach f, $(DOT_FILES), sed -i '/_block_ram_apply_read/d' $(f);)
	$(foreach f, $(DOT_FILES), sed -i '/_block_ram_apply_write/d' $(f);)
	$(foreach f, $(DOT_FILES), sed -i '/Sched /d' $(f);)
	$(foreach f, $(DOT_FILES), dot -Tsvg $(f) > $(f:.dot=.svg);)

BSIM_FLAGS =  -bdir $(BSIM) -vdir $(BSIM) -simdir $(BSIM) -info-dir $(BSIM) \
							-fdir $(BSIM) -l pthread -D BSIM -l SDL2

BSC_FLAGS = -keep-fires -aggressive-conditions \
						-check-assert -no-warn-action-shadowing

BUILD_FLAGS = -show-schedule -sched-dot -bdir $(BUILD) -vdir $(RTL) \
							-simdir $(BUILD) -info-dir $(BUILD) -fdir $(BUILD)


.PHONY: compile
compile:
	bsc $(BUILD_FLAGS) $(BSC_FLAGS) -cpp +RTS -K128M -RTS \
		-p $(PACKAGES) -verilog -u -g $(BUILD_MODULE) $(TOP)
#	bsc \
#		-verilog \
#		-vdir $(RTL) -bdir $(BUILD) -info-dir $(BUILD) \
#		-no-warn-action-shadowing -check-assert \
#		-keep-fires -aggressive-conditions -show-schedule -sched-dot \
#		-cpp +RTS -K128M -RTS  -show-range-conflict \
#		-p $(PACKAGES) -g $(BUILD_MODULE) -u $(TOP)

.PHONY: bsim
bsim:
	bsc $(BSC_FLAGS) $(BSIM_FLAGS) -p $(PACKAGES) -sim -u -g $(BSIM_MODULE) $(TOP)
	bsc $(BSC_FLAGS) $(BSIM_FLAGS) -sim -e $(BSIM_MODULE) -o \
		$(BSIM)/bsim $(BSIM)/*.ba
	./bsim/bsim -m 1000000000

.PHONY: yosys
yosys:
	yosys \
		-DULX3S -q -p "synth_ecp5 -abc9 -top mkTop -json ./build/mkTop.json; prep" \
		rtl/* $(LIB)

.PHONY: nextpnr
nextpnr:
	nextpnr-ecp5 --force --timing-allow-fail --json ./build/mkTop.json --lpf ulx3s.lpf \
		--textcfg ./build/mkTop_out.config --85k --package CABGA381

.PHONY: nextpnr_gui
nextpnr_gui:
	nextpnr-ecp5 --force --timing-allow-fail --json ./build/mkTop.json --lpf ulx3s.lpf \
		--textcfg ./build/mkTop_out.config --85k --freq 40 --package CABGA381 --gui

.PHONY: ecppack
ecppack:
	ecppack --compress --svf-rowsize 100000 --svf ./build/mkTop.svf \
		./build/mkTop_out.config ./build/mkTop.bit

.PHONY: prog
prog:
	sudo fujprog build/mkTop.bit

.PHONY: prog_t
prog_t:
	sudo fujprog build/mkTop.bit -t

.PHONY: clean
clean:
	rm -rf $(BUILD)/*
	rm -rf $(BSIM)/*
	rm -rf $(RTL)/*
