
all: obj_dir/Vtqvp_toivoh_pwl_synth

obj_dir/Vtqvp_toivoh_pwl_synth: test_main.cpp ../../src/pwl_synth.sv ../../src/pwl_synth.vh ../../src/pwl_synth_memory.sv
	verilator --trace -cc -j 0 -I../../src -DPURE_RTL -DUSE_TEST_INTERFACE --exe --build  -CFLAGS "-g -O3" --top-module tqvp_toivoh_pwl_synth test_main.cpp -Wno-widthexpand -Wno-widthtrunc -Wno-PINMISSING  ../../src/pwl_synth.sv ../../src/pwl_synth_memory.sv
