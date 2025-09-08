
all: obj_dir/Vcompare_top

obj_dir/Vcompare_top: compare_main.cpp compare_top.sv ../../src/pwl_synth.sv ../../src/pwl_synth.vh ../../src/pwl_synth_memory.sv ../../src/alt_project.sv 
	verilator --trace -cc -j 0 -I../../src -DPURE_RTL --exe --build  -CFLAGS "-g -O3" --top-module compare_top compare_main.cpp -Wno-widthexpand -Wno-widthtrunc -Wno-PINMISSING  compare_top.sv ../../src/pwl_synth.sv ../../src/pwl_synth_memory.sv ../../src/alt_project.sv
