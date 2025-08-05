/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <stdint.h>

#include "Vpwls_multichannel_ALU_unit.h"
#include "verilated.h"


#define SAVE_AUDIO

const char* audio_fname = "audio.raw";


#define DOWNSAMPLE
const int log2_downsampling = 4;


// 0: Mono: C - G - B - C
// 1: Fading in chord one note at a time: D3 - G3 - C4 - Eb4  // C3 - E4 - G4 - Bb4
// 2: falling noise frequency
const int tune = 1;


//const bool DETUNE_ON = false;
const bool DETUNE_ON = true;


const int PERIOD_ADDR = 0;
const int AMP_ADDR = 1;
const int MODE_ADDR = 2;
const int PARAMS_ADDR = 3;

const int MODE_BIT_DETUNE0 = 0;
const int MODE_BIT_NOISE = 3;


#ifdef DOWNSAMPLE
const int LOG2_DOWNSAMPLING = log2_downsampling;
#else
const int LOG2_DOWNSAMPLING = 0;
#endif


const int MAX_CYCLES_PER_SAMPLE = 64;
const int NUM_CHANNELS = 4;

const int BITS = 12;
const int OCT_BITS = 3;
const int MANTISSA_BITS = 10;
const int PERIOD_BITS = OCT_BITS + MANTISSA_BITS;

const int FILTER_OUT_TAPS = 8;
const int LOG2_FILTER_DOWNSAMPLING = 4;
const int FILTER_DOWNSAMPLING = 1 << LOG2_FILTER_DOWNSAMPLING;
const int FILTER_SIZE = FILTER_OUT_TAPS * FILTER_DOWNSAMPLING;

// sum = 1
const float filter_kernel[FILTER_SIZE] = {1.9704187094300935e-5, 1.672124152367472e-5, 2.2091120095941078e-5, 2.685891825533267e-5, 2.986240567308994e-5, 2.9534150836547966e-5, 2.383946150169849e-5, 1.021951780838429e-5, -1.4411480429666529e-5, -5.36959988669223e-5, -0.00011180932123201447, -0.00019337588931160458, -0.00030342804910631955, -0.0004472782832528414, -0.0006303462676022846, -0.0008579957004840749, -0.001135309212249831, -0.0014667842276546196, -0.0018561320074222429, -0.002305912685078532, -0.002817258691731319, -0.0033895263704930615, -0.004020051222580581, -0.004703836003274322, -0.005433308142276695, -0.006198184498962297, -0.006985310407430402, -0.007778614246666663, -0.008559181086983851, -0.009305396042280256, -0.009993152391113985, -0.01059623243525253, -0.011086746809076363, -0.011435691266594215, -0.011613589672186135, -0.011591213583084728, -0.01134036359811593, -0.01083472103358854, -0.010050661114540156, -0.008968128717767905, -0.007571458653177024, -0.005850114301831013, -0.0037993853835723837, -0.0014209444872459675, 0.0012766983496119864, 0.00427794488352387, 0.007559983645916518, 0.011092860474231525, 0.014839750460875892, 0.018757433256881124, 0.022796916419864335, 0.026904280440575086, 0.031021680252996835, 0.03508844165879476, 0.03904232782324128, 0.0428208684017619, 0.04636270832694564, 0.04960900440934792, 0.05250477911818976, 0.05500018257543565, 0.05705170155105929, 0.05862317927162731, 0.059686702941030734, 0.060223274017816915, 0.060223274017816915, 0.059686702941030734, 0.05862317927162731, 0.05705170155105929, 0.05500018257543565, 0.05250477911818976, 0.04960900440934792, 0.04636270832694564, 0.0428208684017619, 0.03904232782324128, 0.03508844165879476, 0.031021680252996835, 0.026904280440575086, 0.022796916419864335, 0.018757433256881124, 0.014839750460875892, 0.011092860474231525, 0.007559983645916518, 0.00427794488352387, 0.0012766983496119864, -0.0014209444872459675, -0.0037993853835723837, -0.005850114301831013, -0.007571458653177024, -0.008968128717767905, -0.010050661114540156, -0.01083472103358854, -0.01134036359811593, -0.011591213583084728, -0.011613589672186135, -0.011435691266594215, -0.011086746809076363, -0.01059623243525253, -0.009993152391113985, -0.009305396042280256, -0.008559181086983851, -0.007778614246666663, -0.006985310407430402, -0.006198184498962297, -0.005433308142276695, -0.004703836003274322, -0.004020051222580581, -0.0033895263704930615, -0.002817258691731319, -0.002305912685078532, -0.0018561320074222429, -0.0014667842276546196, -0.001135309212249831, -0.0008579957004840749, -0.0006303462676022846, -0.0004472782832528414, -0.00030342804910631955, -0.00019337588931160458, -0.00011180932123201447, -5.36959988669223e-5, -1.4411480429666529e-5, 1.021951780838429e-5, 2.383946150169849e-5, 2.9534150836547966e-5, 2.986240567308994e-5, 2.685891825533267e-5, 2.2091120095941078e-5, 1.672124152367472e-5, 1.9704187094300935e-5};


const int note_mantissas[12] = {909, 801, 698, 601, 510, 424, 343, 266, 194, 125, 61, 0};



Vpwls_multichannel_ALU_unit *top;

int pwm_acc;

void timestep() { pwm_acc += top->pwm_out; top->clk = 0; top->eval(); top->clk = 1; top->eval(); }



void reg_write(int addr, int channel, int data) {
	top->reg_waddr = addr*4 + channel;
	top->reg_wdata = data & 0xffff;
	top->reg_we = 1;
	timestep();
	top->reg_we = 0;
}

void period_write(int channel, int period) { reg_write(PERIOD_ADDR, channel, period); }
void period_write(int channel, int octave, int mantissa) { period_write(channel, (octave << MANTISSA_BITS) | mantissa); }



int main(int argc, char** argv) {
	Verilated::commandArgs(argc, argv);

	top = new Vpwls_multichannel_ALU_unit();

	top->en = 1;

	top->reset = 1; 
	for (int i = 0; i < 10; i++) timestep();
	top->reset = 0;

	int output_offset = top->pwm_offset;
	int pwm_offset = output_offset - (64-56);
	printf("output_offset = %d\n", output_offset);

/*
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [BITS-1:0] tri_offset, // includes offset to convert to signed
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [BITS-3-1:0] slope_offset,
		input wire [BITS-2-1:0] amp,
*/
	//top->detune_exp = 0; // off
	//top->detune_exp = 7; // max
	//top->detune_exp = 6;
	top->tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2));
	top->slope_exp = 2;
	top->slope_offset = 1 << (BITS - 4); // full range is 0 to 2^(BITS-3)-1
	//top->amp = 3 << (BITS - 4); // full range is 0 to 2^(BITS-2)-1

	//int num_samples = 512;// / FILTER_DOWNSAMPLING;
	//int num_samples = 2;// / FILTER_DOWNSAMPLING;

	const int NUM_NOTES = 4;
	const int LOG2_SAMPLES_PER_NOTE = 15;

	int num_samples = NUM_NOTES << LOG2_SAMPLES_PER_NOTE;



#ifdef SAVE_AUDIO
	FILE* audio_fp = fopen(audio_fname, "w+");
	if (!audio_fp) {
		printf("Failed to create audio output file: %s", audio_fname);
		return 1;
	}
#endif


// Tune setup
// ==========


	for (int channel = 0; channel < NUM_CHANNELS; channel++) {
		reg_write(AMP_ADDR, channel, 0); // Silence all channels
		//reg_write(MODE_ADDR, channel, 6*DETUNE_ON);

		//int tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2));
		//int tri_offset = (1 << (BITS-2-2)) - (1 << (BITS-2));
		int tri_offset = (1 << (BITS-2-2)); // full range is 0 to 2^(BITS-2)-1
		int slope_offset = 1 << (BITS - 4); // full range is 0 to 2^(BITS-3)-1
		int params = (((tri_offset >> (BITS-2-8))&255)<<8) | ((slope_offset >> (BITS-3-4))*17);
		//printf("params = %d\n", params);
		reg_write(PARAMS_ADDR, channel, params);
	}

	if (tune == 0) {
		reg_write(AMP_ADDR, 0, 63);
		reg_write(MODE_ADDR, 0, 5*DETUNE_ON);
	}
	if (tune == 1) {
		//top->tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2));
		top->tri_offset = -(1 << (BITS-2));

		//static int notes[4] = {0+16, 4, 7, 10}; // C3 - E4 - G4 - Bb4
		static int notes[4] = {2+16, 7+16, 0, 3}; // D3 - G3 - C4 - Eb4
		// Set periods, notes silent
		for (int channel = 0; channel < NUM_CHANNELS; channel++) {
			int note = notes[channel];
			period_write(channel, 3 + (note>>4), note_mantissas[note&15]);
			int detune_exp = 5*DETUNE_ON; //(5 - (note>>4))*DETUNE_ON;
			int slope_exp0 = channel*2;
			int slope_exp1 = channel + 3;
			reg_write(MODE_ADDR, channel, detune_exp | (slope_exp0 << 4) | (slope_exp1 << 8));
		}
	}
	if (tune == 2) {
		// Try to preserve the noise
		top->tri_offset = -(1 << (BITS-2));
		top->slope_exp = 0;
		top->slope_offset = 0;

		reg_write(AMP_ADDR, 0, 63);
		reg_write(MODE_ADDR, 0, 1 << MODE_BIT_NOISE);
		period_write(0, 1, 0);
	}


// Main loop
// =========

	float accs[FILTER_OUT_TAPS];
	memset(accs, 0, sizeof(accs));

	int sample = -(1 << 15);
	int prev_sample = sample;
	int prev_pwm_acc = -1;
	int sample_print_counter = 0;

	bool run = true;
	for (int i = 0; i < num_samples; i++) {
		if (!run) break;

#ifdef DOWNSAMPLE
		float filtered_sample = accs[FILTER_OUT_TAPS - 1];
		memmove(accs + 1, accs, sizeof(float)*(FILTER_OUT_TAPS - 1));
		accs[0] = 0;
#endif

		for (int subsample = 0; subsample < (1<<LOG2_DOWNSAMPLING); subsample++) {
			bool ok = false;
			for (int k = (i > 0); k < 2; k++) { // wait for two samples the first time; first one is uninitialized
				for (int j = 0; j < MAX_CYCLES_PER_SAMPLE; j++) {

					//printf("tri_offset_eff = %d, curr_params = %d\n", top->tri_offset_eff_out, top->curr_params_out);

					timestep();
					//printf("term_index = %d\tstate = %d\n", top->term_index_out, top->state_out);
					if (top->new_out_acc) { ok = true; break; }
				}
				//run = false; break; // !!!
				if (!ok) {
					printf("No new_out_acc in %d cycles, aborting!\n", MAX_CYCLES_PER_SAMPLE);
					run = false;
					break;
				}
			}

/*
			if (sample != prev_sample || pwm_acc != prev_pwm_acc) {
				prev_sample = sample;
				prev_pwm_acc = pwm_acc;

				printf("(%d, %d): sample = %d, pwm_acc = %d\n", i, subsample, sample, pwm_acc);
				sample_print_counter++;

				if (sample_print_counter > 25) run = false;
			}
*/
			int pwm_adj = pwm_acc - pwm_offset;
			if (i > 0 && pwm_acc > 0 && pwm_adj*16 != sample) {
				printf("(%d, %d): sample = %d, pwm_adj = %d\n", i, subsample, sample, pwm_adj);
				run = false;
			}

			pwm_acc = 0;


			sample = top->out_acc_out - (output_offset << 4);
			if (sample >= (1 << (BITS - 1))) sample -= (1 << BITS);
			//printf("%d ", sample);

#ifdef DOWNSAMPLE
			for (int j = 0; j < FILTER_OUT_TAPS; j++) accs[j] += sample * (1.0f * FILTER_OUT_TAPS / (1 << BITS)) * filter_kernel[j*FILTER_DOWNSAMPLING + (subsample << (LOG2_FILTER_DOWNSAMPLING - LOG2_DOWNSAMPLING))];
#endif
		}

#ifdef SAVE_AUDIO
#ifdef DOWNSAMPLE
		int int_sample = filtered_sample * (16384 << (LOG2_FILTER_DOWNSAMPLING - LOG2_DOWNSAMPLING));
#else
		int int_sample = sample << 16-BITS;
#endif
		fwrite(&int_sample, 2, 1, audio_fp);
#endif

// Tune update
// ===========

		if (tune == 0) {
			// Play a melody on channel 0
			if ((i & ((1 << LOG2_SAMPLES_PER_NOTE) - 1)) == 0) {
				int t = i >> LOG2_SAMPLES_PER_NOTE;
				int octave = 3;
				int mantissa = 0;
				if (t == 0) octave++;
				else if (t == 1) mantissa = 344;
				else if (t == 2) mantissa = 60;

				for (int channel = 0; channel < 1; channel++) {
	//			for (int channel = 0; channel < 2; channel++) {
					reg_write(PERIOD_ADDR, channel, (octave << MANTISSA_BITS) | mantissa);
					mantissa += 1;
				}
			}
		} else if (tune == 1) {
			int amp = (i >> (LOG2_SAMPLES_PER_NOTE - 6)) & 63;
			int channel = i >> LOG2_SAMPLES_PER_NOTE;
			reg_write(AMP_ADDR, channel, amp);
		} else if (tune == 2) {
			int period = (i >> (2+LOG2_SAMPLES_PER_NOTE - 13));
			period_write(0, period);
		}
	}

	printf("\n\nDone!");

#ifdef SAVE_AUDIO
	fclose(audio_fp);
#endif

	// Cleanup
	delete top;
	return 0;
}
