CFLAGS =	-march=rv32im_zicsr -mabi=ilp32 -fno-builtin \
					-ffreestanding -nostdlib -O2 -ggdb
CC = riscv32-none-elf-gcc
LD = riscv32-none-elf-ld

.PHONY: compile
compile:
	gcc -E -o build/kernel.lang -undef -P - < src/kernel.lang
	../3DRiscV/compiler-experiments/compiler kernel build build
	$(CC) $(CFLAGS) -Tsrc/linker.ld -Isrc \
		-o build/gpu_firmware.elf src/*.c src/*.s build/*.s -lgcc
	riscv32-none-elf-objcopy --strip-debug -O ihex \
		build/gpu_firmware.elf Mem.ihex
	../3DRiscV/ihex-to-img.py Mem.ihex hex 2147483648 4 32000 1 > Mem.hex
	../3DRiscV/ihex-to-img.py Mem.ihex hex 2147483648 4 32000 1 > GpuMem.hex

.PHONY: run
run: compile
	#cat example9.txt | stdbuf -o0 -i0 ../3DRiscV/sim
	python3 dump.py | stdbuf -o0 -i0 ../3DRiscV/sim

.PHONY: verilator
verilator: compile
	make -C .. test_gpu verilator
