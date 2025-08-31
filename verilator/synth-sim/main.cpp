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
#include <verilated_vcd_c.h>

//#define STEREO_ON
//#define STEREO_POS_ON // might have an effect even if stereo is off, affecting the subchannels

//#define TRACE_ON

#ifndef TRACE_ON
#define SAVE_AUDIO
#endif

const char* audio_fname = "audio.raw";


#define USE_NEW_REGMAP_B


#define DOWNSAMPLE
const int log2_downsampling = 4;


// 0: Mono: C - G - B - C
// 14: like 0 but with PWL oscillators
// 1: Fading in chord one note at a time: D3 - G3 - C4 - Eb4  // C3 - E4 - G4 - Bb4
// 2: falling noise frequency (manual period update)
// 10: fixed noise frequency
// 3: falling oscillator frequency (manual period update)
// 4: period sweep
// 5: slow period sweep
// 6: slow period sweep + amp sweep
// 9: like 6, but starting at lowest period
// 7: manual sweep slope, pwm_offset
// 8: sweep slope, pwm_offset
// 11: phase multipliers: (3, 2^n)
// 12: phase multipliers: (1, 2^n)
// 13: common_sat
// 15: orion pedal
// 16: oscillator sync
const int tune = 16;

//const bool DETUNE_ON = false;
const bool DETUNE_ON = true;


const int fastest_sweep = 2;
const int fastest_sweep_supported = 2;


const int PERIOD_ADDR = 0;
const int AMP_ADDR = 1;

#ifdef USE_NEW_REGMAP_B
const int SLOPE0_ADDR = 2;
const int SLOPE1_ADDR = 3;
const int PWM_OFFSET_ADDR = 4;
const int MODE_ADDR = 5;
const int SWEEP_PA_ADDR = 6; // {period, amp} sweep
const int SWEEP_WS_ADDR = 7; // {pwm_offset, slope} sweep
const int PHASE_ADDR = 8;
const int OC_ADDR = 9;
#else
const int MODE_ADDR = 2;
const int PARAMS_ADDR = 3;
const int SWEEP_ADDR = 4;
#endif

const int MODE_BIT_DETUNE0 = 0;
const int MODE_BIT_NOISE = 3;
const int MODE_FLAG_NOISE = 1 << MODE_BIT_NOISE;
const int MODE_BIT_3X = 4;
const int MODE_FLAG_3X = 1 << MODE_BIT_3X;
const int MODE_BIT_X2N0 = 5;
const int MODE_BIT_X2N1 = 6;
const int MODE_FLAG_COMMON_SAT = 128;
const int MODE_FLAG_PWL_OSC = 256;
const int MODE_FLAGS_ORION = MODE_FLAG_NOISE | MODE_FLAG_PWL_OSC;
const int MODE_FLAG_OSC_SYNC_EN = 1 << 9;
const int MODE_FLAG_OSC_SYNC_SOFT = 1 << 10;


const int CFG_FLAG_STEREO_EN = 1;
const int CFG_FLAG_STEREO_POS_EN = 2;


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
const int OUT_ACC_FRAC_BITS = 4;

const int FILTER_OUT_TAPS = 8;
const int LOG2_FILTER_DOWNSAMPLING = 4;
const int FILTER_DOWNSAMPLING = 1 << LOG2_FILTER_DOWNSAMPLING;
const int FILTER_SIZE = FILTER_OUT_TAPS * FILTER_DOWNSAMPLING;

// sum = 1
const float filter_kernel[FILTER_SIZE] = {1.9704187094300935e-5, 1.672124152367472e-5, 2.2091120095941078e-5, 2.685891825533267e-5, 2.986240567308994e-5, 2.9534150836547966e-5, 2.383946150169849e-5, 1.021951780838429e-5, -1.4411480429666529e-5, -5.36959988669223e-5, -0.00011180932123201447, -0.00019337588931160458, -0.00030342804910631955, -0.0004472782832528414, -0.0006303462676022846, -0.0008579957004840749, -0.001135309212249831, -0.0014667842276546196, -0.0018561320074222429, -0.002305912685078532, -0.002817258691731319, -0.0033895263704930615, -0.004020051222580581, -0.004703836003274322, -0.005433308142276695, -0.006198184498962297, -0.006985310407430402, -0.007778614246666663, -0.008559181086983851, -0.009305396042280256, -0.009993152391113985, -0.01059623243525253, -0.011086746809076363, -0.011435691266594215, -0.011613589672186135, -0.011591213583084728, -0.01134036359811593, -0.01083472103358854, -0.010050661114540156, -0.008968128717767905, -0.007571458653177024, -0.005850114301831013, -0.0037993853835723837, -0.0014209444872459675, 0.0012766983496119864, 0.00427794488352387, 0.007559983645916518, 0.011092860474231525, 0.014839750460875892, 0.018757433256881124, 0.022796916419864335, 0.026904280440575086, 0.031021680252996835, 0.03508844165879476, 0.03904232782324128, 0.0428208684017619, 0.04636270832694564, 0.04960900440934792, 0.05250477911818976, 0.05500018257543565, 0.05705170155105929, 0.05862317927162731, 0.059686702941030734, 0.060223274017816915, 0.060223274017816915, 0.059686702941030734, 0.05862317927162731, 0.05705170155105929, 0.05500018257543565, 0.05250477911818976, 0.04960900440934792, 0.04636270832694564, 0.0428208684017619, 0.03904232782324128, 0.03508844165879476, 0.031021680252996835, 0.026904280440575086, 0.022796916419864335, 0.018757433256881124, 0.014839750460875892, 0.011092860474231525, 0.007559983645916518, 0.00427794488352387, 0.0012766983496119864, -0.0014209444872459675, -0.0037993853835723837, -0.005850114301831013, -0.007571458653177024, -0.008968128717767905, -0.010050661114540156, -0.01083472103358854, -0.01134036359811593, -0.011591213583084728, -0.011613589672186135, -0.011435691266594215, -0.011086746809076363, -0.01059623243525253, -0.009993152391113985, -0.009305396042280256, -0.008559181086983851, -0.007778614246666663, -0.006985310407430402, -0.006198184498962297, -0.005433308142276695, -0.004703836003274322, -0.004020051222580581, -0.0033895263704930615, -0.002817258691731319, -0.002305912685078532, -0.0018561320074222429, -0.0014667842276546196, -0.001135309212249831, -0.0008579957004840749, -0.0006303462676022846, -0.0004472782832528414, -0.00030342804910631955, -0.00019337588931160458, -0.00011180932123201447, -5.36959988669223e-5, -1.4411480429666529e-5, 1.021951780838429e-5, 2.383946150169849e-5, 2.9534150836547966e-5, 2.986240567308994e-5, 2.685891825533267e-5, 2.2091120095941078e-5, 1.672124152367472e-5, 1.9704187094300935e-5};


const int note_mantissas[12] = {909, 801, 698, 601, 510, 424, 343, 266, 194, 125, 61, 0};



Vpwls_multichannel_ALU_unit *top;
VerilatedVcdC *m_trace;
int sim_time = 0;


inline void trace() {
#ifdef TRACE_ON
	m_trace->dump(sim_time); sim_time++;
#endif
}

int pwm_acc;

void timestep() {
	pwm_acc += top->pwm_out;

	top->clk = 0;
	top->eval();
	trace();
	top->clk = 1;
	top->eval();
	trace();
}



void reg_write(int addr, int channel, int data) {
	top->reg_waddr = addr*4 + channel;
	top->reg_wdata = data & 0xffff;
	top->reg_we = 1;
	top->en = 0; // pause the synth to avoid chaning the timing
	timestep();
	pwm_acc--; // the PWM output is not paused and the total will be increased by one, compensate
	top->reg_we = 0;
	top->en = 1;
}

int encode_sweep_rate(int sweep_rate) {
	if (sweep_rate != 0 && sweep_rate <= fastest_sweep) {
		if (fastest_sweep == fastest_sweep_supported) return 1;
		else return fastest_sweep;
	}
	else return sweep_rate;
}

void period_write(int channel, int period) { reg_write(PERIOD_ADDR, channel, period); }
void period_write(int channel, int octave, int mantissa) { period_write(channel, (octave << MANTISSA_BITS) | mantissa); }

void amp_write(int channel, int amp) { reg_write(AMP_ADDR, channel, amp); }
void mode_write(int channel, int detune_exp, int flags=0, int phase_factors=0) { reg_write(MODE_ADDR, channel, (((phase_factors&7)<<4)|(detune_exp*DETUNE_ON)&7) | flags); }

void cfg_write(int cfg) { reg_write(OC_ADDR, 2, cfg); }


#ifdef USE_NEW_REGMAP_B

// 8 bit pwm_offset and slopes
void modeparams_write(int channel, int detune_exp, int pwm_offset, int slope0, int slope1, int flags=0) {
	reg_write(MODE_ADDR, channel, ((detune_exp*DETUNE_ON)&7) | flags); // TODO: lfsr_en?
	reg_write(PWM_OFFSET_ADDR, channel, pwm_offset);
	reg_write(SLOPE0_ADDR, channel, slope0);
	reg_write(SLOPE1_ADDR, channel, slope1);
}

void sweep_period_amp_write(int channel, int period_sweep_rate, int period_sign, int amp_sweep_rate=0, int amp_target=0) {
	reg_write(SWEEP_PA_ADDR, channel, ((encode_sweep_rate(period_sweep_rate) | (period_sign<<4)) << 8) | (amp_sweep_rate|(amp_target << 4)));
}

void sweep_pwmoffs_slope_write(int channel, int pwmoffs_sweep_rate, int pwmoffs_sign, int slope_sweep_rate=0, int slope_sign=0, int slope_cfg=0) {
	reg_write(SWEEP_WS_ADDR, channel, ((encode_sweep_rate(pwmoffs_sweep_rate) | (pwmoffs_sign<<4)) << 8) | (slope_sweep_rate|(slope_sign << 4)|(slope_cfg<<5)));
}

#else // old regmap

// 8 bit pwm_offset and slopes
void modeparams_write(int channel, int detune_exp, int pwm_offset, int slope0, int slope1) {
	int params = (pwm_offset<<8) | ((slope1&15)<<4) | ((slope0&15));
	int mode = (detune_exp&7) | (((slope0>>4)&15)<<4) | (((slope1>>4)&15)<<8);
	//printf("mpw: params = %d\n", params);
	//printf("mpw: mode = %d\n", mode);
	reg_write(PARAMS_ADDR, channel, params);
	reg_write(MODE_ADDR, channel, mode);
}

void sweep_period_amp_write(int channel, int period_sweep_rate, int period_sign, int amp_sweep_rate=0, int amp_target=0) {
	reg_write(SWEEP_ADDR, channel, (encode_sweep_rate(period_sweep_rate) | (period_sign<<4)) | ((amp_sweep_rate|(amp_target << 4)) << 5));
}

#endif



int main(int argc, char** argv) {
	Verilated::commandArgs(argc, argv);

	top = new Vpwls_multichannel_ALU_unit();

#ifdef TRACE_ON
	Verilated::traceEverOn(true);
	m_trace = new VerilatedVcdC;
	top->trace(m_trace, 5);
	m_trace->open("synth-sim.vcd");
#endif

	top->en = 1;
	top->next_en = 1;
	top->control_reg_write = 1;
	top->state_reg_write = 1;

	//top->reset = 1; 
	top->rst_n = 0;
	for (int i = 0; i < 10; i++) timestep();
	top->rst_n = 1;
	//top->reset = 0;

	int output_offset = top->pwm_out_offset;
#ifdef STEREO_ON
	output_offset = 48;
#endif
	//int pwm_offset = output_offset - (64-56);
	int pwm_out_offset = output_offset - (64-64);
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
#ifdef TRACE_ON
	num_samples = 16;
#endif

#ifdef SAVE_AUDIO
	FILE* audio_fp = fopen(audio_fname, "w+");
	if (!audio_fp) {
		printf("Failed to create audio output file: %s", audio_fname);
		return 1;
	}
#endif


// Tune setup
// ==========

	int cfg = 0;
#ifdef STEREO_ON
	cfg |= CFG_FLAG_STEREO_EN;
#endif
#ifdef STEREO_POS_ON
	cfg |= CFG_FLAG_STEREO_POS_EN;
#endif
	if (cfg != 0) cfg_write(cfg);

	int tri_offset = (1 << (BITS-2-2)); // full range is 0 to 2^(BITS-2)-1
	int slope_offset = 1 << (BITS - 4); // full range is 0 to 2^(BITS-3)-1
	int pwm_offset_default = tri_offset >> (BITS-2-8);
	int slope_default = slope_offset >> (BITS-3-4);

	if (tune != 7) {
		for (int channel = 0; channel < NUM_CHANNELS; channel++) {
			amp_write(channel, 0); // Silence all channels
			//mode_write(channel, 6);

			if (tune != 11 && tune != 13 && tune != 14 && tune != 15 && tune != 16) {
				//int tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2));
				//int tri_offset = (1 << (BITS-2-2)) - (1 << (BITS-2));
				int params = (((tri_offset >> (BITS-2-8))&255)<<8) | ((slope_offset >> (BITS-3-4))*17);
				//printf("params = %d\n", params);

				//reg_write(PARAMS_ADDR, channel, params);
				//reg_write(MODE_ADDR, channel, 0);
				modeparams_write(channel, 0, pwm_offset_default, slope_default, slope_default);
			}
		}
	}

	int main_channel = 0;

	if (tune == 0 || tune == 14) {
		amp_write(0, 63);
		mode_write(0, 5*DETUNE_ON, MODE_FLAG_PWL_OSC);
	} else if (tune == 1) {
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

			int flags = 0;
#ifdef STEREO_POS_ON
			const int stereo_pos[] = {0,4,1,3};
			flags |= stereo_pos[channel] << MODE_BIT_3X;
#endif

			//reg_write(MODE_ADDR, channel, detune_exp | (slope_exp0 << 4) | (slope_exp1 << 8));
			modeparams_write(channel, detune_exp, pwm_offset_default, (slope_exp0 << 4) | (slope_default&15), (slope_exp1 << 4) | (slope_default&15), flags);
		}
	} else if (tune == 2 || tune == 10) {
		main_channel = 3;
		// Try to preserve the noise
		top->tri_offset = -(1 << (BITS-2));
		top->slope_exp = 0;
		top->slope_offset = 0;

		amp_write(main_channel, 63);
		mode_write(main_channel, 0, true);
		period_write(main_channel, 1, tune == 10 ? (1 << OCT_BITS) : 0);
		//period_write(main_channel, 1, 0);
	} else if (tune == 3 || tune == 4) {
		amp_write(0, 63);
		period_write(0, 0);
		//if (tune == 4) reg_write(SWEEP_ADDR, 0, 16 | 1);
		//if (tune == 4) reg_write(SWEEP_ADDR, 0, 2);
	} else if (tune == 5 || tune == 6 || tune == 9) {
		amp_write(0, 63);
		if (tune == 9) period_write(0, 7, 1023); // lowest note
		else period_write(0, 3, note_mantissas[0]); // C4
	} else if (tune == 7 || tune == 8) {
		amp_write(0, 63);
		period_write(0, 4, 0); // B3
/*
		int pwm_offset = 0;
		slope0 = 0;
		slope1 = 255;
		int detune_exp = 4*DETUNE_ON;

		modeparams_write(0, detune_exp, pwm_offset, slope0, slope1);
*/
	} else if (tune == 11 || tune == 12 || tune == 13) {
		amp_write(0, 63);
		period_write(0, 4, note_mantissas[0]); // C4

		if (tune == 13) {
			mode_write(0, 4, MODE_FLAG_COMMON_SAT, 1 | (1 << 1));
			reg_write(SLOPE0_ADDR, 0, 128);
			int slope_sweep_rate = 2+LOG2_SAMPLES_PER_NOTE-1+4-8 + 1;
			sweep_pwmoffs_slope_write(0, 0, 0, slope_sweep_rate, 1, 1); // sweep down slope0
		}
	} else if (tune == 15) {
		amp_write(0, 63);
		period_write(0, 4, note_mantissas[0]); // C4
		int detune_exp = 0;
		//int detune_exp = 4;
		mode_write(0, detune_exp, MODE_FLAGS_ORION);
		reg_write(SLOPE1_ADDR, 0, 0b11001010);
		reg_write(PWM_OFFSET_ADDR, 0, 0xff); // To defeat the PWM offset, -1 is as close to zero as we get
	} else if (tune == 16) {
		amp_write(0, 63);
		amp_write(1, 63);
		period_write(0, 4, note_mantissas[0]); // C4
	}

// Main loop
// =========

	float accs_l[FILTER_OUT_TAPS], accs_r[FILTER_OUT_TAPS];
	memset(accs_l, 0, sizeof(accs_l));
	memset(accs_r, 0, sizeof(accs_r));

	int sample = -(1 << 15);
	int prev_sample = sample;
	int prev_pwm_acc = -1;
	int sample_print_counter = 0;

	int next_sweep_update_time = 0;
	int sweep_rate = fastest_sweep;

	bool run = true;
	for (int i = 0; i < num_samples; i++) {
		if (!run) break;

#ifdef DOWNSAMPLE
		float filtered_sample_l = accs_l[FILTER_OUT_TAPS - 1];
		memmove(accs_l + 1, accs_l, sizeof(float)*(FILTER_OUT_TAPS - 1));
		accs_l[0] = 0;
#ifdef STEREO_ON
		float filtered_sample_r = accs_r[FILTER_OUT_TAPS - 1];
		memmove(accs_r + 1, accs_r, sizeof(float)*(FILTER_OUT_TAPS - 1));
		accs_r[0] = 0;
#endif
#endif

		for (int subsample = 0; subsample < (1<<LOG2_DOWNSAMPLING); subsample++) {
#ifdef STEREO_ON
		  for (int side = 0; side < 2; side++) {
#endif
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

#ifdef STEREO_ON
			int curr_pwm_offset = side ? 37-12 : 37-21;
#else
			int curr_pwm_offset = pwm_out_offset;
#endif

#ifndef STEREO_ON // TODO: test even with stereo
			int pwm_adj = pwm_acc - curr_pwm_offset;
			if (i > 0 && pwm_acc > 0 && pwm_adj*16 != sample) {
#ifdef STEREO_ON
				printf("side = %d: ", side);
#endif
				printf("(%d, %d): sample = %d, pwm_adj = %d, error = pwm_adj - (sample>>4) = %d\n", i, subsample, sample, pwm_adj, pwm_adj - (sample>>4));
				run = false;
			}
#endif

			pwm_acc = 0;

			sample = (top->out_acc_out & (-1 << OUT_ACC_FRAC_BITS)) - (output_offset << 4);
			if (sample >= (1 << (BITS - 1))) sample -= (1 << BITS);
			//printf("%d ", sample);
			//if (subsample == 0 && i > ((1<<15) - 256)) printf("%d ", sample); //!!!!

#ifdef DOWNSAMPLE
#ifdef STEREO_ON
			float *accs = side ? accs_r : accs_l;
#else
			float *accs = accs_l;
#endif
			for (int j = 0; j < FILTER_OUT_TAPS; j++) accs[j] += sample * (1.0f * FILTER_OUT_TAPS / (1 << BITS)) * filter_kernel[j*FILTER_DOWNSAMPLING + (subsample << (LOG2_FILTER_DOWNSAMPLING - LOG2_DOWNSAMPLING))];
#endif

#ifdef STEREO_ON
		  } // side loop
#endif
		}
		//if (i > (1<<15)) break; //!!!!

#ifdef SAVE_AUDIO
#ifdef DOWNSAMPLE
		int int_sample = filtered_sample_l * (16384 << (LOG2_FILTER_DOWNSAMPLING - LOG2_DOWNSAMPLING));
#ifdef STEREO_ON
		int int_sample_r = filtered_sample_r * (16384 << (LOG2_FILTER_DOWNSAMPLING - LOG2_DOWNSAMPLING));
#endif
#else
		int int_sample = sample << 16-BITS;
#endif

		fwrite(&int_sample, 2, 1, audio_fp);
#ifdef STEREO_ON
		fwrite(&int_sample_r, 2, 1, audio_fp);
#endif
#endif

// Tune update
// ===========

		if (tune == 0 || tune == 14) {
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
					period_write(channel, octave, mantissa);
					mantissa += 1;
				}
			}
		} else if (tune == 1) {
			int amp = (i >> (LOG2_SAMPLES_PER_NOTE - 6)) & 63;
			int channel = i >> LOG2_SAMPLES_PER_NOTE;
			amp_write(channel, amp);
		} else if (tune == 2) {
			int period = (i >> (2+LOG2_SAMPLES_PER_NOTE - 13));
			period_write(main_channel, period);
		} else if (tune == 3) {
			int period = (i >> (2+LOG2_SAMPLES_PER_NOTE - 13));
			//int period = (i<<1) & 8191;
			period_write(0, period);
		} else if (tune == 4) {
			int t = i << LOG2_DOWNSAMPLING;

			int sign = i >= (num_samples >> 1);
			if (i == num_samples >> 1) { // Restart with opposite sign
				sweep_rate = fastest_sweep;
				next_sweep_update_time = t;
			}

			if (t >= next_sweep_update_time) {
				period_write(0, 0);
				//reg_write(SWEEP_ADDR, 0, encode_sweep_rate(sweep_rate) | (sign ? 16 : 0));
				sweep_period_amp_write(0, sweep_rate, sign);
				next_sweep_update_time += 16384 << sweep_rate;
				sweep_rate += 1;
			}
		} else if (tune == 5 || tune == 6 || tune == 9) {
			int sweep_rate = 15 - ((i >> (2+LOG2_SAMPLES_PER_NOTE - 4)));
			int amp_target = ((i >> (2+LOG2_SAMPLES_PER_NOTE - 5)))&1;
			amp_target = amp_target ? 6 : 1;
			int amp_sweep_rate = 0;

			if (tune == 6 || tune == 9) {
				// Match the sweep rate so that period and amplitude sweep at the same rate
				amp_sweep_rate = sweep_rate + 7;
				if (amp_sweep_rate > 15) amp_sweep_rate = 15;
			}

			//reg_write(SWEEP_ADDR, 0, (encode_sweep_rate(sweep_rate) | 16) | ((amp_sweep_rate|(amp_target << 4)) << 5));
			sweep_period_amp_write(0, sweep_rate, 1, amp_sweep_rate, amp_target);
		} else if (tune == 7 || tune == 8) {
			int detune_exp = 4*DETUNE_ON;
			int shr0 = (2+LOG2_SAMPLES_PER_NOTE);
			int t = i >> (shr0 - 9);
			bool first = (i & ((1 << (shr0-1)) - 1)) == 0;
			if (t < 256) {
				if (tune == 7 || first) {
					int slope = 255 - t;
					int pwm_offset = 0;
					int slope0 = slope;
					int slope1 = 0;
					modeparams_write(0, detune_exp, pwm_offset, slope0, slope1);
				}
				if (tune == 8 && first) {
					printf("first: i = %d\n", i);
					int slope_sweep_rate = 2+LOG2_SAMPLES_PER_NOTE-1+4-8 - 1;
					sweep_pwmoffs_slope_write(0, 0, 0, slope_sweep_rate, 1, 0);
				}
			} else {
				if (tune == 7 || first) {
					int slope = 128;
					int pwm_offset = t&255;
					int slope0 = slope;
					int slope1 = slope;
					modeparams_write(0, detune_exp, pwm_offset, slope0, slope1);
				}
				if (tune == 8 && first) {
					printf("first: i = %d\n", i);
					int pwmoffs_sweep_rate = 2+LOG2_SAMPLES_PER_NOTE-1+4-8-1 - 1;
					sweep_pwmoffs_slope_write(0, pwmoffs_sweep_rate, 0);
				}
			}
		} else if (tune == 11 || tune == 12) {
			int shr0 = LOG2_SAMPLES_PER_NOTE;
			int t = (i >> shr0) & 3;
			bool first = (i & ((1 << shr0) - 1)) == 0;
			if (first) {
				if (tune == 11) mode_write(0, 5, 0, 1 | (t<<1));
				else if (tune == 12) mode_write(0, 4 + (t>0), 0, 0 | (t<<1));
			}
		} else if (tune == 15) {
			int shr0 = 1+LOG2_SAMPLES_PER_NOTE - 16;
			int t = i >> shr0;
			if (t >= (3<<15)) t &= ~0x4000;

			int offset = 0;
			offset += ((t >> 13)&1) << 8;
			offset += ((t >> 14)&1) << 7;
			offset += ((t >> 12)&1) << 5;
			offset += ((t >> 15)&1) << 2;
			offset += ((t >>  9)&1) << 0;
			int slope = offset >> 5;
			reg_write(SLOPE0_ADDR, 0, slope);
		} else if (tune == 16) {
			int shr0 = LOG2_SAMPLES_PER_NOTE+1;
			int t = (i >> shr0) & 1;
			bool first = (i & ((1 << shr0) - 1)) == 0;

			if (first) {
				period_write(1, 5, note_mantissas[5]); // F3
				int detune_exp = 0;
				//int detune_exp = 4;

				int flags0 = 0;
				int flags1 = 0;
#ifdef STEREO_POS_ON
				flags0 |= 0 << MODE_BIT_3X;
				flags1 |= 4 << MODE_BIT_3X;
#endif

				mode_write(0, detune_exp, flags0);
				mode_write(1, detune_exp, flags1 | MODE_FLAG_OSC_SYNC_EN | (t == 0 ? MODE_FLAG_OSC_SYNC_SOFT : 0));

				int sweep_rate = 2+LOG2_SAMPLES_PER_NOTE-1+4-12 - 1;
				sweep_period_amp_write(1, sweep_rate, 1);
			}
		}
	}

	printf("\n\nDone!");

#ifdef SAVE_AUDIO
	fclose(audio_fp);
#endif

#ifdef TRACE_ON
	m_trace->close();
#endif

	// Cleanup
	delete top;
	return 0;
}
