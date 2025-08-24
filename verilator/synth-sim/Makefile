
all: obj_dir/Vpwls_multichannel_ALU_unit

obj_dir/Vpwls_multichannel_ALU_unit: main.cpp ../../src/pwl_synth.sv ../../src/pwl_synth.vh ../../src/pwl_synth_memory.sv
	verilator -cc --trace -j 0 -I../../src -DPURE_RTL --exe --build  -CFLAGS "-g -O3" --top-module pwls_multichannel_ALU_unit main.cpp -Wno-widthexpand -Wno-widthtrunc -Wno-PINMISSING  ../../src/pwl_synth.sv ../../src/pwl_synth_memory.sv
