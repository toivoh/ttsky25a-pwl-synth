/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <stdint.h>

#include "Vcompare_top.h"
#include "verilated.h"
#include <verilated_vcd_c.h>

const int compare_file_cycles = 1 << 16;
const char* compare_fname = "compare_data.txt";

#define TRACE_ON
//#define DEBUG_PRINTS



Vcompare_top *top;
VerilatedVcdC *m_trace;
int sim_time = 0;


inline void trace() {
#ifdef TRACE_ON
	m_trace->dump(sim_time); sim_time++;
#endif
}

//int pwm_acc;
//void timestep() { pwm_acc += top->pwm_out; top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
void timestep() {
/*
	top->clk = 0;
	top->eval();
	trace();
*/
	top->clk = 1;
	top->eval();
	trace();
	top->clk = 0;
	top->eval();
	trace();
//	top->clk = 0; top->eval(); top->clk = 1; top->eval();
}

int rand_bits(int nbits) {
	return rand() & ((1 << nbits)-1);
}

const int CMD_SET_ADDR = 4;
const int CMD_SET_DATA = 5;
const int CMD_WRITE = 6;
const int CMD_READ  = 7;

void cp_timestep(FILE* compare_fp, int &t, int cmd, int wdata) {
	top->cmd_in = cmd;
	top->wdata_in = wdata;

	timestep();
	t++;

	fprintf(compare_fp, "%d 0x%x  0x%x 0x%x %d\n", cmd, wdata, top->uo_out, top->data_out, top->data_ready);
}

int run_compare_sim() {
	top->cmd_in = 0;

	top->rst_n = 0; 
	for (int i = 0; i < 9; i++) timestep();
	top->rst_n = 1;

	FILE* compare_fp = fopen(compare_fname, "w+");
	if (!compare_fp) {
		printf("Failed to create output file: %s", compare_fname);
		return 1;
	}

	int t = 0;
	while (t < compare_file_cycles) {
		int choice = rand_bits(7);
		if (choice == 0) {
			// Random read
			cp_timestep(compare_fp, t, CMD_SET_ADDR, rand_bits(6));
			int i = 0;
			while (true) {
				cp_timestep(compare_fp, t, CMD_READ, 0);
				if (top->data_ready) break;
				i++;
				if (i > 64+4) {
					printf("ERROR: read failed to finish in %d cycles!\n", i);
					break;
				}
			}
		} else if (choice < 63) {
			// Idle
			cp_timestep(compare_fp, t, 0, 0);
		} else {
			// Random write
			cp_timestep(compare_fp, t, CMD_SET_ADDR, rand_bits(6));
			cp_timestep(compare_fp, t, CMD_SET_DATA, rand_bits(13));
			cp_timestep(compare_fp, t, CMD_WRITE, 0);
		}
	}

	fclose(compare_fp);
	printf("\nWrote compare data file\n\n");
	return 0;
}


int main(int argc, char** argv) {
	Verilated::commandArgs(argc, argv);

	top = new Vcompare_top();

#ifdef TRACE_ON
	Verilated::traceEverOn(true);
	m_trace = new VerilatedVcdC;
	top->trace(m_trace, 5);
	m_trace->open("peripheral-test.vcd");
#endif

	run_compare_sim();

#ifdef TRACE_ON
	m_trace->close();
#endif

	// Cleanup
	delete top;
	return 0;
}
