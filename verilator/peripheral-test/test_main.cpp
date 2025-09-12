/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <stdint.h>

#include "Vtqvp_toivoh_pwl_synth.h"
#include "verilated.h"
#include <verilated_vcd_c.h>


//#define TRACE_ON
//#define DEBUG_PRINTS
//#define DEBUG_OSC
//#define DEBUG_DETUNE
//#define DEBUG_TRI
//#define DEBUG_AMP_CLAMP
//#define DEBUG_ADD_COMMON_SAT


#define TEST_SLOPE
#define TEST_DETUNE
#define TEST_AMP_OUT
#define TEST_TRI_PWM_OFFSET
#define TEST_SWEEPS
#define TEST_LFSR
#define TEST_OCT_COUNTER_INC
#define TEST_OSC
#define TEST_PWL_OSC
#define TEST_SHORT_SEQS
#define TEST_LONG_SEQS


const int seq_extra_exp = 0;


//#define USE_P_LATCHES_ONLY
#define USE_NEW_READ
#define USE_ORION_WAVE
#define USE_ORION_WAVE_MASK
#define USE_ORION_WAVE_PWM
#define USE_OCT_COUNTER_LATCHES
#define USE_OSC_SYNC
#define USE_4_BIT_MODE
//#define USE_OSC_SYNC_ONLY_FOR_SOME_CHANNELS
#define USE_SWAPPED_DETUNE_SIGNS
#define USE_COMMON_SAT_STEREO
#define USE_DETUNE_FIFTH


const int INTERFACE_REGISTER_SHIFT = 0;

const int MAX_CYCLES_PER_SAMPLE = 64;
const int LOG2_NUM_CHANNELS = 2;
const int NUM_CHANNELS = 1 << LOG2_NUM_CHANNELS;

const int BITS = 12;
const int PHASE_BITS = BITS;
const int OCT_BITS = 3;
const int MANTISSA_BITS = 10;
const int PERIOD_BITS = OCT_BITS + MANTISSA_BITS;
const int OUT_ACC_FRAC_BITS = 4;
const int OUT_ACC_INITIAL_TOP = 512 >> OUT_ACC_FRAC_BITS;
const int OUT_ACC_INITIAL_TOP_STEREO = 768 >> OUT_ACC_FRAC_BITS;
const int OCT_COUNTER_BITS = 24;

const int OUT_RSHIFT = 4;
const int REV_PHASE_SHR = 0;


const int REG_PERIOD = 0;
const int REG_AMP = 1;
const int REG_SLOPE0 = 2;
const int REG_SLOPE1 = 3;
const int REG_PWM_OFFSET = 4;
const int REG_MODE = 5;
const int REG_SWEEP_PA = 6; // {period, amp} sweep
const int REG_SWEEP_WS = 7; // {pwm_offset, slope} sweep
const int REG_PHASE = 8;
#ifdef USE_OCT_COUNTER_LATCHES
const int REG_OCT_COUNTER = 9;
#endif
const int REGS_PER_CHANNEL = 9; // Keep at 9; Don't count oct_counter; it is still counted as a core register

const int num_reg_rand_bits[REGS_PER_CHANNEL] = {OCT_BITS + MANTISSA_BITS, 6, 8, 8, 8, 12, 16, 16, BITS};
const int reg_bits[] = {OCT_BITS + MANTISSA_BITS, 6, 8, 8, 8};
const int sweep_bits[] = {5, 7, 7, 7, 5};
const int pre_sweep[] = {0, 3, 5, 7, 1}; // Used to set oct_counter values that will activate the sweep for the corresponding parameter


const int MODE_BIT_DETUNE0 = 0;
const int MODE_BIT_NOISE = 3;
const int MODE_FLAG_NOISE = 1 << MODE_BIT_NOISE;
const int MODE_BIT_3X = 4;
const int MODE_FLAG_3X = 1 << MODE_BIT_3X;
const int MODE_BIT_X2N0 = 5;
const int MODE_BIT_X2N1 = 6;
const int MODE_FLAG_COMMON_SAT = 128;
const int MODE_FLAG_PWL_OSC = 256;
const int MODE_FLAG_OSC_SYNC_EN = 1 << 9;
const int MODE_FLAG_OSC_SYNC_SOFT = 1 << 10;
const int MODE_BIT_DETUNE_FIFTH = 11;
const int MODE_FLAG_DETUNE_FIFTH = 1 << MODE_BIT_DETUNE_FIFTH;


const int MODE_FLAGS_OSC_SYNC_MASK = MODE_FLAG_OSC_SYNC_EN | MODE_FLAG_OSC_SYNC_SOFT;


const int CFG_FLAG_STEREO_EN = 1;
const int CFG_FLAG_STEREO_POS_EN = 2;


const int STATE_CMP_REV_PHASE = 0;
const int STATE_UPDATE_PHASE = 1;
const int STATE_DETUNE = 2;
const int STATE_TRI = 3;
const int STATE_COMBINED_SLOPE_CMP = 4;
const int STATE_COMBINED_SLOPE_ADD = 5;
const int STATE_AMP_CMP = 6;
const int STATE_OUT_ACC = 7;
const int STATE_LAST = 7;

const int STATE_OCT_COUNTER_INC_LOW = 4;
const int STATE_OCT_COUNTER_INC_HIGH = 5;


const int TST_ADDR_NOTHING = -1;
const int TST_ADDR_ACC = 0;
const int TST_ADDR_OUT_ACC = 1;
const int TST_ADDR_PRED = 2;
const int TST_ADDR_PART = 3;
const int TST_ADDR_LFSR_EXTRA_BITS = 4;
const int TST_ADDR_OCT_COUNTER = 5;
const int TST_ADDR_OUT_ACC_ALT_FRAC = 6;
const int TST_ADDR_LAST_OSC_WRAPPED = 7;
const int TST_ADDR_NUM = 8;

const int core_reg_bits[TST_ADDR_NUM] = {BITS+1, BITS, 1, 1, 18-(BITS-1), 24, OUT_ACC_FRAC_BITS, 1};


// TODO
// - How to handle bit width/mask limitation of register banks? Need to mask the bits somewhere...


Vtqvp_toivoh_pwl_synth *top;
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


void write_reg_to_rtl(int channel, int reg, int data);

// assumes en_external = 0
void write_core_reg_to_rtl(int addr, int data) {
#ifdef USE_OCT_COUNTER_LATCHES
	if (addr == TST_ADDR_OCT_COUNTER) {
		write_reg_to_rtl(0, REG_OCT_COUNTER, data & 0xfff);
		write_reg_to_rtl(1, REG_OCT_COUNTER, (data >> 12) & 0xfff);
		return;
	}
#endif

	if (!(0 <= addr && addr < TST_ADDR_NUM)) return;
	top->ireg_waddr = addr;
	top->ireg_wdata = data & (((1 << core_reg_bits[addr])-1));
	timestep();
	top->ireg_waddr = -1;
}

// assumes en_external = 0
int read_core_reg_from_rtl(int addr) {
	top->ireg_raddr = addr;
	timestep();
	top->ireg_raddr = -1;
	int data = top->ireg_rdata;

	if (addr == TST_ADDR_ACC && data >= (1 << BITS)) data -= (1 << (BITS + 1));

	return data;
}
	
int read_acc12() {
	int data = read_core_reg_from_rtl(TST_ADDR_ACC) & ((1 << BITS) - 1);
	if (data >= (1 << (BITS-1))) data -= (1 << BITS);
	return data;
}

int get_reg_address(int channel, int reg) {
	//return reg*2 + channel*16;
	return (reg&7)*2 + channel*16 + ((reg>>3)&1);
}

int get_reg_address_p(int channel, int reg) {
	return (reg&15)*4 + (channel&3);
}

void write_reg_to_rtl(int channel, int reg, int data) {
	top->address = get_reg_address(channel, reg);
	top->data_in = data << INTERFACE_REGISTER_SHIFT;
	top->data_write_n = 1; // 16 bit write
	timestep();
	top->data_write_n = 3; // no write
}

int read_reg_from_rtl(int channel, int reg) {
#ifndef USE_NEW_READ
	top->address = get_reg_address(channel, reg);
	top->data_read_n = 1; // 16 bit read
	timestep();
	bool ok = false;
	for (int i = 0; i < 100; i++) {
		if (top->data_ready) {
			ok = true;
			break;
		}
		timestep();
	}
	top->data_read_n = 3; // no read

	return top->data_out >> INTERFACE_REGISTER_SHIFT;
#else
	top->reg_raddr_p = get_reg_address_p(channel, reg);
	top->reg_raddr_p_valid = 1;
	timestep();
	timestep();
	top->reg_raddr_p_valid = 0;

	return top->reg_rdata_p;
#endif
}


struct Model {
	int term_index;
	int acc, out_acc, out_acc_alt_frac, pred, part, lfsr_extra_bits, oct_counter, cfg;
	bool last_osc_wrapped;
	int regs[NUM_CHANNELS*REGS_PER_CHANNEL];

	Model() {
		term_index = 0;
		acc = out_acc = out_acc_alt_frac = pred = part = lfsr_extra_bits = oct_counter = cfg = 0;
		last_osc_wrapped = false;
		memset(regs, 0, sizeof(regs));
	}

	int get_reg(int channel, int reg) { return regs[channel + reg*NUM_CHANNELS]; }
	void set_reg(int channel, int reg, int data) {
		if (!(0 <= channel && channel < NUM_CHANNELS)) return;
		if (!(0 <= reg && reg < REGS_PER_CHANNEL)) return;
		regs[channel + reg*NUM_CHANNELS] = data;
	}
	void set_reg_both(int channel, int reg, int data) { set_reg(channel, reg, data); write_reg_to_rtl(channel, reg, data); }
	int get_channel() { return (term_index>>1) & (NUM_CHANNELS-1); }
	int get_channel_reg(int reg) { return get_reg(get_channel(), reg); }
	void set_channel_reg(int reg, int data) { set_reg(get_channel(), reg, data); }
	int get_subchannel() { return term_index&1; }
	bool stereo_en() { return (cfg & CFG_FLAG_STEREO_EN) != 0; }
	bool stereo_pos_en() { return (cfg & CFG_FLAG_STEREO_POS_EN) != 0; }
	int get_channel_stereo_pos() { return (get_channel_reg(REG_MODE) >> MODE_BIT_3X) & 7; }
	bool phase_factor_en() { return !stereo_pos_en(); }
	//bool common_sat() { return get_channel() == 0 && ((get_channel_reg(REG_MODE) & MODE_FLAG_COMMON_SAT) != 0) && !stereo_en(); }
#ifdef USE_COMMON_SAT_STEREO
	bool _common_sat() { return ((get_reg(0, REG_MODE) & MODE_FLAG_COMMON_SAT) != 0); }
	bool common_sat_store() {
		return _common_sat() && (stereo_en()
			? (get_channel() == 0)
			: (get_channel() == 0 && get_subchannel() == 0)
		);
	}
	bool common_sat_add() {
		return _common_sat() && (stereo_en()
			? (get_channel() == 1)
			: (get_channel() == 0 && get_subchannel() == 1)
		);
	}
#else
	bool _common_sat() { return ((get_channel_reg(REG_MODE) & MODE_FLAG_COMMON_SAT) != 0) && !stereo_en(); }
	bool common_sat_store() { return _common_sat() && get_channel() == 0 && get_subchannel() == 0; }
	bool common_sat_add() { return _common_sat() && get_channel() == 0 && get_subchannel() == 1; }
#endif
};

#ifdef USE_ORION_WAVE
const int MODE_FLAGS_WAVEFORM = MODE_FLAG_NOISE | MODE_FLAG_PWL_OSC;
const int MODE_FLAGS_ORION = MODE_FLAG_NOISE | MODE_FLAG_PWL_OSC;
bool get_lfsr_en(int mode) { return (mode & MODE_FLAGS_WAVEFORM ) == MODE_FLAG_NOISE; }
bool get_pwl_osc_en(int mode) { return (mode & MODE_FLAGS_WAVEFORM ) == MODE_FLAG_PWL_OSC; }
bool get_orion_en(int mode) { return (mode & MODE_FLAGS_WAVEFORM ) == MODE_FLAGS_ORION; }
#else
bool get_lfsr_en(int mode) { return (mode & MODE_FLAG_NOISE) != 0; }
bool get_pwl_osc_en(int mode) { return (mode & MODE_FLAG_PWL_OSC) != 0; }
bool get_orion_en(int mode) { return 0; }
#endif

int signed_wrap(int x) {
	x += 1 << (BITS - 1);
	x &= (1 << BITS) - 1;
	x -= 1 << (BITS - 1);
	return x;
}

int sat(int x) {
	if (x >= (1 << (BITS-2))) return (1 << (BITS-2))-1;
	else if (x < (-1 << (BITS-2))) return -(1 << (BITS-2));
	else return x;
}

static uint16_t bitreverse(uint16_t x, int num_bits) {
	int shift, mask;
	shift = 1; mask = 0x5555;
	x = ((x & mask) << shift) | ((x >> shift) & mask);
	shift = 2; mask = 0x3333;
	x = ((x & mask) << shift) | ((x >> shift) & mask);
	shift = 4; mask = 0x0f0f;
	x = ((x & mask) << shift) | ((x >> shift) & mask);
	shift = 8; mask = 0x00ff;
	x = ((x & mask) << shift) | ((x >> shift) & mask);

	return x >> (16 - num_bits);
}

// Depends on channel, period and phase for the channel, oct_counter
void model_oscillator(Model &m) {
	int phase = m.get_channel_reg(REG_PHASE);

	int mode = m.get_channel_reg(REG_MODE);
	bool osc_sync_en = (mode & MODE_FLAG_OSC_SYNC_EN) != 0;
	bool osc_sync_soft = (mode & MODE_FLAG_OSC_SYNC_SOFT) != 0;
	bool lfsr_en = get_lfsr_en(mode);
	bool pwl_osc_en = get_pwl_osc_en(mode);

#ifdef DEBUG_OSC
	printf("phase = 0x%x, osc_sync_en = %d, osc_sync_soft = %d, last_osc_wrapped = %d, lfsr_en = %d, pwl_osc_en = %d\n", phase, osc_sync_en, osc_sync_soft, m.last_osc_wrapped, lfsr_en, pwl_osc_en);
#endif

	bool do_osc_sync = false;
	int sync_phase = 0;
	if (osc_sync_en && m.last_osc_wrapped) {
		do_osc_sync = true;
		sync_phase = osc_sync_soft ? ~phase : -1;
		sync_phase &= ((1 << BITS) - 1);
		//m.acc = sync_phase & ((1 << BITS) - 1);
#ifdef DEBUG_OSC
		printf("sync_phase = 0x%x ", sync_phase);
#endif
		if (!lfsr_en) m.last_osc_wrapped = 1; // The inversion of src1 sets carry_out
	}


	int f_period = m.get_channel_reg(REG_PERIOD);
	int mantissa = f_period & ((1 << MANTISSA_BITS) - 1);
	int period_exp = f_period >> MANTISSA_BITS;

	//bool lfsr_18 = (m.get_channel() == NUM_CHANNELS - 1);
	bool lfsr_18 = (m.get_channel() == 0 || m.get_channel() == 3);

	int shift_count = 3 - period_exp - (lfsr_en ? 6 : 0); // TODO: is 6 the right offset?
	bool skip = false;
	if (shift_count < 0) {
		//int oct_enables = (m.oct_counter + 1) & ~m.oct_counter;
		int oct_enables = m.oct_counter & ~(m.oct_counter + 1);
		if (((oct_enables >> (-shift_count - 1)) & 1) == 0) skip = true;
		shift_count = 0;
	}

	bool delayed = (((phase >> shift_count) & 1) != 0);
	bool small_step;

	//if (pwl_osc_en) printf("delayed = %d, phase = 0x%x\n", delayed, phase);

#ifdef DEBUG_OSC
	printf("phase = 0x%x ", phase);
#endif
	if (delayed) small_step = true;
	else {
		//int mantissa_ext = (mantissa << (PHASE_BITS - 1 - MANTISSA_BITS));
		int mantissa_ext = (mantissa << (PHASE_BITS - 1 - MANTISSA_BITS - REV_PHASE_SHR));
		if (pwl_osc_en) {
			int phase_mod = phase & ((1 << (PHASE_BITS-1)) - 1); // remove msb
			phase_mod &= (-1 << (shift_count + 1)); // remove unused LSBs
			phase_mod |= ((phase >> (PHASE_BITS-1)) & 1) << shift_count; // put the removed msb back as lowest used bit

#ifdef DEBUG_OSC
			printf(("phase = 0x%x, phase_mod = 0x%x)\n"), phase, phase_mod);
#endif

			small_step = (phase_mod < mantissa_ext);
		} else {

			int rev_phase = bitreverse(phase >> 1, PHASE_BITS-1) >> REV_PHASE_SHR;
			int rev_phase_shifted = (rev_phase << shift_count) & ((1 << (PHASE_BITS-1)) - 1);

			//if (phase == 2048) printf("phase = 0x%x, mantissa_ext = 0x%x, rev_phase_shifted = 0x%x\n", phase, mantissa_ext, rev_phase_shifted);


			small_step = (rev_phase_shifted < mantissa_ext);
			//small_step = ((rev_phase_shifted >> REV_PHASE_SHR) < (mantissa_ext >> REV_PHASE_SHR));

#ifdef DEBUG_OSC
			printf("rev_phase_shifted = 0x%x, mantissa_ext = 0x%x ", rev_phase_shifted, mantissa_ext);
#endif
		}
	}

#ifdef DEBUG_OSC
	printf("delayed = %d, small_step = 0x%x, lfsr_en = %d\n", delayed, small_step, lfsr_en);
#endif

	if (lfsr_en) {
		if (!delayed && small_step) phase += 1;
		else {
			int x = ((phase >> 1)&((1<<BITS)-1)) | (m.lfsr_extra_bits << (BITS-1));

			int lfsr_bit;
			if (lfsr_18) {
#ifdef DEBUG_OSC
				printf("18 bit: lfsr_extra_bits = 0x%x, x = 0x%x\n", m.lfsr_extra_bits, x);
#endif

				// 18 bit LFSR
				bool bit17 = ((x>>17)&1);
				bool bit6 = ((x>>6)&1);
				bool zeros = ( (x & ((1<<17)-1) ) == 0);
				lfsr_bit = bit17 ^ (bit6 | zeros); // include zero state
			} else {
				// 11 bit LFSR
				bool bit10 = ((x>>10)&1);
				bool bit8 = ((x>>8)&1);
				bool zeros = ( (x & ((1<<10)-1) ) == 0);
				lfsr_bit = bit10 ^ (bit8 | zeros); // include zero state
			}
			x = (x << 1) | lfsr_bit;
			phase = (x & ((1<<BITS)-1)) << 1;
			if (!skip && lfsr_18) m.lfsr_extra_bits = (x >> (BITS-1)) & 127;
		}
	} else {
		int prev_phase = phase;
		phase = (phase + ((small_step ? 1 : 2) << shift_count)) & ((1 << PHASE_BITS) - 1);
		if (!do_osc_sync) m.last_osc_wrapped = !skip && ((phase & (1 << (BITS-1)))==0) && ((prev_phase & (1 << (BITS-1)))!=0);
	}

	if (do_osc_sync) {
		m.acc = sync_phase & ((1 << BITS) - 1);
		m.set_channel_reg(REG_PHASE, m.acc);
	} else {
		m.acc = phase & ((1 << BITS) - 1);
		if (!skip) m.set_channel_reg(REG_PHASE, m.acc);
	}
}


// Depends on channel, subchannel, detune_exp for channel, phase for channel
void model_detune(Model &m, int old_phase) {
	int detune_exp = m.get_channel_reg(REG_MODE) & 7;
	int subchannel = m.get_subchannel();

	int mode = m.get_channel_reg(REG_MODE);
	bool enable_3x = (subchannel == 0) && m.phase_factor_en() && ((mode & MODE_FLAG_3X) != 0);

#ifdef DEBUG_DETUNE
	printf("detune_exp_orig = 0x%x\n", detune_exp);
#endif
	//if ((mode & MODE_FLAG_DETUNE_FIFTH) != 0 && subchannel == 0 && detune_exp != 0) detune_exp++;
	if ((mode & MODE_FLAG_DETUNE_FIFTH) != 0 && subchannel == 0) detune_exp++;
#ifdef DEBUG_DETUNE
	printf("detune_exp_mod = 0x%x\n", detune_exp);
#endif

	bool detune_disable = (subchannel == 0 && m.phase_factor_en() && !enable_3x && ((mode & (3 << MODE_BIT_X2N0)) != 0));

	bool swap_detune_sign = false;
	int stereo_pos = m.get_channel_stereo_pos();
	if (m.stereo_pos_en() && stereo_pos <= 4) swap_detune_sign = (m.oct_counter & 1) != 0;

#ifdef USE_P_LATCHES_ONLY
	int x = m.get_channel_reg(REG_PHASE);
#else
	int x = old_phase;
#endif

#ifdef USE_SWAPPED_DETUNE_SIGNS
	swap_detune_sign = !swap_detune_sign;
#endif

#ifdef DEBUG_DETUNE
	printf("enable_3x = %d, detune_disable = %d, subchannel = %d, cfg = 0x%x, swap_detune_sign = %d, x = 0x%x\n", enable_3x, detune_disable, subchannel, m.cfg, swap_detune_sign, x);
#endif

	if (enable_3x) {
		x += m.acc << 1;
	} else {
		int detune = 0;
		if (detune_exp != 0 && !detune_disable) {
			//int detune_src = m.oct_counter >> 6;
			//detune = detune_src >> (7 - detune_exp);
			detune = m.oct_counter >> ((6+7) - detune_exp);

			if ((subchannel == 0) != swap_detune_sign) x += detune;
			else x -= detune;
		}

		x -= subchannel ^ swap_detune_sign;

#ifdef DEBUG_DETUNE
		printf("detune = 0x%x, x = 0x%x\n", detune, x);
#endif
	}


	m.acc = signed_wrap(x);
}

void model_detune(Model &m) {
	model_detune(m, m.get_channel_reg(REG_PHASE));
}

// Depends on acc, PWM offset for channel
void model_tri_pwm_offset(Model &m) {
	int mode = m.get_channel_reg(REG_MODE);
	int pwm_offset = (m.get_channel_reg(REG_PWM_OFFSET) << (BITS-2-8)) - (1 << (BITS-2));
	int lshift = (m.get_subchannel() == 1 && m.phase_factor_en()) ? (mode >> MODE_BIT_X2N0) & 3 : 0;

	int x = m.acc & ((1 << BITS) - 1);
#ifdef DEBUG_TRI
		printf("initial:\tpwm_offset = 0x%x, x = 0x%x\n", pwm_offset, x);
#endif

	if (get_orion_en(mode)) {
#ifdef USE_ORION_WAVE_PWM
		if (((m.acc << lshift)&(1 << (BITS-1))) != 0) pwm_offset = ~pwm_offset;
#endif

#ifdef DEBUG_TRI
		printf("orion:\tpwm_offset = 0x%x, x = 0x%x\n", pwm_offset, x);
#endif

		m.acc = signed_wrap((x << lshift) + pwm_offset);
		m.part = 0;
		return;
	}

	// Left shift
	x = (x << lshift) & ((1 << BITS)-1);

	bool part = (x >= (1 << (BITS-1)));

	// Triangle wave
	if (part) x = ~x;
	x &= ((1 << (BITS - 1)) - 1);
#ifdef DEBUG_TRI
	printf("x = 0x%x\n", x);
#endif

	// Apply PWM offset and saturate
	x += pwm_offset;
#ifdef DEBUG_TRI
	printf("x = 0x%x\n", x);
#endif
	if (x >= (1 << (BITS-2))) x = (1 << (BITS-2)) - 1;
#ifdef DEBUG_TRI
	printf("x = 0x%x\n", x);
#endif

	m.acc = x;
	m.part = part;
}

int bitshuffle(int x) {
	int y = 0;
#ifndef USE_ORION_WAVE_MASK
	// y |= ((x >> -1)&1) <<  0;
	y |= ((x >>  4)&1) <<  1;
	// y |= ((x >> -1)&1) <<  2;
	y |= ((x >>  7)&1) <<  3;
	y |= ((x >>  8)&1) <<  4;
	// y |= ((x >> -1)&1) <<  5;
	y |= ((x >> 10)&1) <<  6;
	// y |= ((x >> -1)&1) <<  7;
	// y |= ((x >> -1)&1) <<  8;
	y |= ((x >>  9)&1) <<  9;
	y |= ((x >> 11)&1) << 10;
	// y |= ((x >> -1)&1) << 11;
	// y |= ((x >> -1)&1) << 12;
#else
	//y |= ((x >> 11)&1) <<  0;
	y |= ((x >>  4)&1) <<  1;
	//y |= ((x >> 10)&1) <<  2;
	y |= ((x >>  7)&1) <<  3;
	y |= ((x >>  8)&1) <<  4;
	y |= ((x >> 6)&1) <<  5;
	y |= ((x >> 10)&1) <<  6;
	y |= ((x >> 11)&1) <<  7;
	y |= ((x >> 8)&1) <<  8;
	y |= ((x >>  9)&1) <<  9;
	y |= ((x >> 11)&1) << 10;
	// y |= ((x >> -1)&1) << 11;
	// y |= ((x >> -1)&1) << 12;
#endif
	return y;
}

// Depends on channel, part, slope for the channel and part, acc
void model_slope(Model &m) {
	int mode = m.get_channel_reg(REG_MODE);
	//printf("get_orion_en = %d\n", get_orion_en(mode));
	int y;
	if (get_orion_en(mode)) {
		//acc = (bitshuffle(acc) & mask) + offset
		int acc = bitshuffle(m.acc);
		//printf("orion: acc in = 0x%x, bitshuffle = 0x%x\n", m.acc, acc);

		int slope1 = m.get_channel_reg(REG_SLOPE1);
		int src2_mask = -1;
		src2_mask &= ~0xff << (BITS-1-8);
		if (slope1&1) src2_mask |= ~(-1 << (BITS-1-8)); // replicate the bottom mask bit
		src2_mask |= slope1 << (BITS-1-8);
		acc &= src2_mask;
		//printf("orion: src2_mask = 0x%x, acc = 0x%x\n", src2_mask, acc);

		acc += m.get_channel_reg(REG_SLOPE0) << (BITS-3-4);
		//printf("orion: offset: acc = 0x%x\n", acc);
		m.acc = acc;

		//acc = acc + (acc << 1)
		acc *= 3;
		//printf("orion: 3x: acc = 0x%x\n", acc);
		// acc = sext_wrap(acc)
		acc = acc & ((1 << (BITS-1))-1);
		acc |= ((acc >> (BITS-2))&1) << (BITS-1);
		//printf("orion: sext: acc = 0x%x\n", acc);

		y = signed_wrap(acc);
	} else {
		int slope = m.get_channel_reg(m.part ? REG_SLOPE1 : REG_SLOPE0);
		int slope_exp = slope >> 4;
		int slope_offset = (slope & 15) << (BITS-3-4);
		int x = m.acc;

		//printf("slope = 0x%x, part = %d, acc = 0x%x\n", slope, m.part, x);

		x <<= slope_exp;
		int x1 = 2*x;
		int x2 = x + (x >= 0 ? slope_offset : -slope_offset);

		y = x1;
		if ((x >= 0 && x2 < y) || (x < 0 && x2 > y)) y = x2;
		bool cmp = ((x1 - x2) < 0) ^ (x < 0);

		y = sat(y);
		m.pred = cmp;
	}

	if (m.common_sat_store()) { // store result to out_acc instead
		m.out_acc &= ((1 << OUT_ACC_FRAC_BITS) - 1);
		m.out_acc |= y & (-1 << OUT_ACC_FRAC_BITS);
	} else {
#ifdef USE_4_BIT_MODE
		if ((m.get_channel_reg(REG_MODE) & (MODE_FLAG_OSC_SYNC_EN | MODE_FLAG_OSC_SYNC_SOFT)) == MODE_FLAG_OSC_SYNC_SOFT) y &= -1 << (BITS-1-4);
#endif
		m.acc = y;
	}

	//printf("slope = %d, x = %d, x1 = %d, x2 = %d, y = %d\n", slope, x, x1, x2, y);
}

void model_add_common_sat(Model &m) {
	int out_acc = m.out_acc;
	out_acc &= -1 << OUT_ACC_FRAC_BITS;
#ifdef DEBUG_ADD_COMMON_SAT
	printf("add_common_sat:\tout_acc = 0x%x, out_acc_masked = 0x%x, acc = 0x%x\n", m.out_acc, out_acc, m.acc);
#endif
	m.acc = sat(m.acc + out_acc);
#ifdef DEBUG_ADD_COMMON_SAT
	printf("add_common_sat:\tacc = 0x%x\n", m.acc);
#endif
}

// Depends on channel, amp for channel, acc, out_acc. Special behavior for term_index == 0 (sigma-delta)
void model_amp_clamp_out(Model &m) {
	int x = m.acc;
	int amp = m.get_channel_reg(REG_AMP) << (BITS-2-6);

#ifdef DEBUG_AMP_CLAMP
	printf("initial:\tx = 0x%x, amp = 0x%x\n", x, amp);
#endif

	if (m.stereo_pos_en()) {
		int factor = 2;
		int stereo_pos = m.get_channel_stereo_pos();
		if (m.get_subchannel() == 0) {
			if ((stereo_pos&3) == 3) factor = 1;
			else if (stereo_pos == 4) factor = 0;
		} else {
			if ((stereo_pos&3) == 1) factor = 1;
			else if (stereo_pos == 0) factor = 0;
		}
		amp = (amp * factor) >> 1;
	}

	bool saturated_neg = false;
	if (x >= 0 && x >  amp) x = amp;
	if (x <  0 && x < -amp) { x = -amp; saturated_neg = true; }

#ifdef DEBUG_AMP_CLAMP
	printf("clamp:\tamp = 0x%x, x = 0x%x\n", amp, x);
#endif

	if (saturated_neg) x = -x; // amp is right shifted before negation, compensate
	if (m.common_sat_add()) x >>= (OUT_RSHIFT-1);
	else x >>= OUT_RSHIFT;
	if (saturated_neg) x = -x; // amp is right shifted before negation, compensate

	int y = m.out_acc;
#ifdef DEBUG_AMP_CLAMP
	printf("rshift:\tx = 0x%x, y = 0x%x\n", x, y);
#endif


	if (m.term_index == 0 || (m.term_index == 1 && m.stereo_en()) || m.common_sat_add()) {
		// Reset out_acc except the frac bits
		y &= (1 << OUT_ACC_FRAC_BITS) - 1;
		if (m.stereo_en()) {
			int old_alt_frac = m.out_acc_alt_frac;
			m.out_acc_alt_frac = y;
			y = old_alt_frac;
		}
		y |= (m.stereo_en() ? OUT_ACC_INITIAL_TOP_STEREO : OUT_ACC_INITIAL_TOP) << OUT_ACC_FRAC_BITS;
	}

#ifdef DEBUG_AMP_CLAMP
	printf("mask:\tx = 0x%x, y = 0x%x\n", x, y);
#endif

	y += x;
#ifdef DEBUG_AMP_CLAMP
	printf("add:\ty = 0x%x\n", y);
#endif

	m.out_acc = signed_wrap(y);
}

// Depends on oct_counter (oct_enables, sweep_channel, sweep_index), value and sweep value for swept parameter
int model_sweep(Model &m) {
	int sweep_channel = m.oct_counter & ((1 << LOG2_NUM_CHANNELS) - 1);

	int sweep_index;
	int pre_sweep_index = (m.oct_counter >> LOG2_NUM_CHANNELS) & 7;
	int sweep_oct_counter_term = 8;
	if ((pre_sweep_index & 1) == 0) sweep_index = 0;
	else {
		sweep_index = (pre_sweep_index >> 1) & 3;
		if (sweep_index == 0) sweep_index = 4;
		sweep_oct_counter_term = 32;
	}

	int sweep = 0;
	switch (sweep_index) {
		case REG_PERIOD: sweep = m.get_reg(sweep_channel, REG_SWEEP_PA) >> 8; break;
		case REG_AMP: sweep = m.get_reg(sweep_channel, REG_SWEEP_PA) & 255; break;
		case REG_SLOPE0: case REG_SLOPE1: sweep = m.get_reg(sweep_channel, REG_SWEEP_WS) & 255; break;
		case REG_PWM_OFFSET: sweep = m.get_reg(sweep_channel, REG_SWEEP_WS) >> 8; break;
	}

	int rate = sweep & 15;
	int sign = (sweep >> 4) & 1;

	int oct_enables = m.oct_counter & ~(m.oct_counter + sweep_oct_counter_term);
	bool enable;
	if (rate == 0) enable = false;
	else if (rate == 1) enable = true;
	else enable = (oct_enables >> rate) & 1;

	int value = m.get_reg(sweep_channel, sweep_index);

	if (sweep_index == REG_AMP) {
		int amp_target = ((sweep >> 4)&7)*9;
		sign = (value > amp_target);
		if (value == amp_target) enable = 0;
	} else if (sweep_index == REG_SLOPE0 || sweep_index == REG_SLOPE1) {
		int dir = (sweep >> 5) & 3;
		if (dir == 0 && sweep_index == REG_SLOPE1) sign = !sign;
		if (dir == 2 && sweep_index == REG_SLOPE0) enable = false;
		if (dir == 1 && sweep_index == REG_SLOPE1) enable = false;
	}

	if (sign && value == 0) enable = false;
	if (!sign && value == (1 << reg_bits[sweep_index]) - 1) enable = false;

	value += sign ? -1 : 1;
	m.acc = value;
	if (enable) m.set_reg(sweep_channel, sweep_index, value);

	return reg_bits[sweep_index];
}

void write_cfg_to_rtl(int cfg) { write_reg_to_rtl(2, REG_OCT_COUNTER, cfg);}


// assumes en_external = 0
void write_core_regs_to_rtl(Model &m) {
	write_core_reg_to_rtl(TST_ADDR_ACC, m.acc);
	write_core_reg_to_rtl(TST_ADDR_OUT_ACC, m.out_acc);
	write_core_reg_to_rtl(TST_ADDR_OUT_ACC_ALT_FRAC, m.out_acc_alt_frac);
	write_core_reg_to_rtl(TST_ADDR_PRED, m.pred);
	write_core_reg_to_rtl(TST_ADDR_PART, m.part);
	write_core_reg_to_rtl(TST_ADDR_LFSR_EXTRA_BITS, m.lfsr_extra_bits);
	write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, m.oct_counter);
	write_core_reg_to_rtl(TST_ADDR_LAST_OSC_WRAPPED, m.last_osc_wrapped);
	write_cfg_to_rtl(m.cfg);
}

void write_reg_array_to_rtl(Model &m) {
	for (int channel = 0; channel < NUM_CHANNELS; channel++) {
		for (int reg = 0; reg < REGS_PER_CHANNEL; reg++) {
			write_reg_to_rtl(channel, reg, m.get_reg(channel, reg));
		}
	}
}

void exec_step(int term_index, int state, int step_part_enables=7) {
	top->state_override = (term_index << 8) | state;
	top->en_external = 1;
	top->step_part_enables = step_part_enables;
	timestep();
	top->en_external = 0;
}

void print_reg_w_internal() {
	printf("reg_we_int = %d, reg_waddr_int = %d, reg_wdata_int = %d\n",
		top->reg_we_internal_out, top->reg_waddr_internal_out, top->reg_wdata_internal_out);
}

/*
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
void mode_write(int channel, int detune_exp, bool lfsr_en=false) { reg_write(MODE_ADDR, channel, ((detune_exp*DETUNE_ON)&7) | (lfsr_en<<3)); }



// 8 bit pwm_offset and slopes
void modeparams_write(int channel, int detune_exp, int pwm_offset, int slope0, int slope1) {
	reg_write(MODE_ADDR, channel, ((detune_exp*DETUNE_ON)&7)); // TODO: lfsr_en?
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

*/


bool run_step_tests() {
	Model m;

	write_core_regs_to_rtl(m);
	write_reg_array_to_rtl(m);

	bool ok;
	bool all_ok = true;
	int num_ok;
	int num_fail;


#ifdef TEST_SLOPE
	ok = true;
	num_ok = 0;
	num_fail = 0;

	printf("\nTesting slope step\n");
	for (int slope = 0; slope < 256; slope += 1) {
		//m.set_reg(0, REG_SLOPE0, slope);
		//write_reg_to_rtl(0, REG_SLOPE0, slope);
		m.set_reg_both(0, REG_SLOPE0, slope);

		for (int acc = -1024; acc < 1024; acc++) {
	//	for (int acc = -512; acc < 512; acc += 64) {
			write_core_reg_to_rtl(TST_ADDR_ACC, acc);
			m.acc = acc;

			exec_step(0, STATE_COMBINED_SLOPE_CMP);
			exec_step(0, STATE_COMBINED_SLOPE_ADD);

			model_slope(m);

			//int result = read_core_reg_from_rtl(TST_ADDR_ACC);
			int result = read_acc12();
			int expected = m.acc;
			//printf("%d %d %d\n", acc, result, expected);

			if (result != expected) {
				if (num_fail < 10) printf("ERROR: in = %d, result %d, expected = %d\n", acc, result, expected);
				num_fail++;
				ok = false;
				break;
			} else num_ok++;
		}
		if (!ok) {
			printf("tested with slope = %d\n", slope);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif

#ifdef TEST_DETUNE
	ok = true;
	num_ok = 0;
	num_fail = 0;

	printf("\nTesting detune step\n");
	for (int subchannel = 0; subchannel < 2; subchannel++) {
		m.term_index = subchannel;
#ifdef USE_DETUNE_FIFTH
		for (int detune_fifth = 0; detune_fifth < 2; detune_fifth++) {
#else
		int detune_fifth = 0;
#endif
		for (int detune_exp = 0; detune_exp <= 7; detune_exp++) {
//		for (int detune_exp = 7; detune_exp >= 0; detune_exp--) {
			if (detune_exp == 7 && detune_fifth == 1 && subchannel == 0) continue;
			m.set_reg_both(0, REG_MODE, detune_exp | (detune_fifth << MODE_BIT_DETUNE_FIFTH));
			//int detune_exp_eff = detune_exp + (detune_fifth && subchannel == 0);
			int detune_exp_eff = detune_exp + (detune_fifth && subchannel == 0 && detune_exp != 0);

			//for (int phase = 0; phase < 4096; phase++) {
			for (int detune = 0; detune < 4096; detune++) {
				int phase = (detune*0x2345) & ((1 << BITS) - 1);
				int oct_counter = (detune << (6 + 7 - detune_exp_eff)) & ((1<<24)-1);
				m.set_reg_both(0, REG_PHASE, phase);
				m.oct_counter = oct_counter;
				write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, oct_counter);

				exec_step(m.term_index, STATE_DETUNE, 3); // detune overwrites the phase with the value in acc if we run the post part
				model_detune(m);

				int result = read_acc12(); // & ((1 << BITS) - 1);
				int expected = m.acc;

				if (result != expected) {
					if (num_fail < 10) printf("ERROR: phase = 0x%x, oct_counter = 0x%x, result 0x%x, expected = 0x%x\n", phase, oct_counter, result, expected);
					num_fail++;
					ok = false;
					break;
				} else num_ok++;
			}
			if (!ok) {
				printf("tested with detune_exp = %d\n", detune_exp);
				break;
			}
		}
#ifdef USE_DETUNE_FIFTH // close the extra for loop
		if (!ok) {
			printf("tested with detune_fifth = %d\n", detune_fifth);
			break;
		}
		}
#endif
		if (!ok) {
			printf("tested with subchannel = %d\n", subchannel);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif

#ifdef TEST_AMP_OUT
	ok = true;
	num_ok = 0;
	num_fail = 0;

	// Depends on channel, amp for channel, acc, out_acc. Special behavior for term_index == 0 (sigma-delta)

	printf("\nTesting amp clamp+output step\n");
	m.term_index = 1;
	for (int amp = 0; amp < 64; amp++) {
		m.set_reg_both(0, REG_AMP, amp);

		for (int acc = -1024; acc < 1024; acc++) {
			int out_acc = (acc * 0x1234) & ((1 << BITS) - 1);
			//int out_acc = 0;

			m.acc = acc;
			write_core_reg_to_rtl(TST_ADDR_ACC, acc);
			m.out_acc = out_acc;
			write_core_reg_to_rtl(TST_ADDR_OUT_ACC, out_acc);

			exec_step(m.term_index, STATE_AMP_CMP);
			exec_step(m.term_index, STATE_OUT_ACC);
			model_amp_clamp_out(m);

			int result = read_core_reg_from_rtl(TST_ADDR_OUT_ACC) & ((1 << BITS) - 1);
			int expected = m.out_acc & ((1 << BITS) - 1);

			if (result != expected) {
				//if (num_fail < 10) printf("ERROR: in = %d, result %d, expected = %d\n", acc, result, expected);
				//if (num_fail < 100) printf("ERROR: amp = %d, in = %d, result %d, expected = %d\n", amp, acc, result, expected);
				if (num_fail < 100) printf("ERROR: amp = %d, in = %d, result %d, expected = %d, pred = %d\n", amp, acc, result, expected, read_core_reg_from_rtl(TST_ADDR_PRED));
				num_fail++;
				ok = false;
				break;
			} else num_ok++;
		}
		if (!ok) {
			printf("tested with amp = %d\n", amp);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif

#ifdef TEST_TRI_PWM_OFFSET

	ok = true;
	num_ok = 0;
	num_fail = 0;

	// Depends on acc, PWM offset for channel
	printf("\nTesting triangle + PWM offset\n");
	m.term_index = 0;

	for (int pwm_offset = 0; pwm_offset < 256; pwm_offset++) {
		m.set_reg_both(0, REG_PWM_OFFSET, pwm_offset);
		for (int acc = 0; acc < (1 << BITS); acc++) {
			m.acc = acc; write_core_reg_to_rtl(TST_ADDR_ACC, acc);

			exec_step(m.term_index, STATE_TRI);
			model_tri_pwm_offset(m);

			int result = read_core_reg_from_rtl(TST_ADDR_ACC) & ((1 << BITS) - 1);
			int expected = m.acc & ((1 << BITS) - 1);

			if (result != expected) {
				if (num_fail < 10) printf("ERROR: in = %d, result %d, expected = %d\n", acc, result, expected);
				num_fail++;
				ok = false;
				break;
			} else num_ok++;

			//if (pwm_offset == 64) printf("%d ", result);
		}
		if (!ok) {
			printf("tested with pwm_offset = %d\n", pwm_offset);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif

#ifdef TEST_SWEEPS

	ok = true;
	num_ok = 0;
	num_fail = 0;

	// Depends on oct_counter (oct_enables, sweep_channel, sweep_index), value and sweep value for swept parameter
	printf("\nTesting sweeps\n");
	m.term_index = 8;
	m.oct_counter = 0; write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, 0); // disable all oct_enables
	for (int sweep_index = 0; sweep_index <= REG_PWM_OFFSET; sweep_index++) {
//	for (int sweep_index = 1; sweep_index <= REG_PWM_OFFSET; sweep_index++) {
//	for (int sweep_index = 2; sweep_index <= REG_PWM_OFFSET; sweep_index++) {
//	for (int sweep_index = 4; sweep_index <= REG_PWM_OFFSET; sweep_index++) {
		printf("sweep_index = %d\n", sweep_index);
		int nbits = reg_bits[sweep_index];

		m.oct_counter = pre_sweep[sweep_index] << LOG2_NUM_CHANNELS;
		write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, m.oct_counter);

		// Test the case rate = 1.
		// The random tests should be enough to test that the other rates turn on/off updates as expected?
		for (int sweep = 1; sweep < (1 << sweep_bits[sweep_index]); sweep += 16) {
			//printf("sweep = 0x%x\n", sweep);
			int sweep_pa = 0;
			int sweep_ws = 0;

			switch (sweep_index) {
				case REG_PERIOD: sweep_pa = sweep << 8; break;
				case REG_AMP: sweep_pa = sweep; break;
				case REG_SLOPE0: case REG_SLOPE1: sweep_ws = sweep; break;
				case REG_PWM_OFFSET: sweep_ws = sweep << 8; break;
			}

			m.set_reg_both(0, REG_SWEEP_PA, sweep_pa);
			m.set_reg_both(0, REG_SWEEP_WS, sweep_ws);

			int num_changed = 0;
			for (int value = 0; value < (1 << (nbits)); value++) {
				m.set_reg_both(0, sweep_index, value);

				exec_step(0, STATE_OUT_ACC, 1); // Set part, also clears write collision
				for (int i = 0; i <= 3; i++) exec_step(m.term_index, i);
				exec_step(m.term_index, 4, 4);
				//printf("%d", top->reg_we_internal_out);
				model_sweep(m);

				int mask = (1 << nbits) - 1;
				int result = read_reg_from_rtl(0, sweep_index) & mask;
				int expected = m.get_reg(0, sweep_index) & mask;

				if (sweep_index == REG_PERIOD || sweep_index == REG_PWM_OFFSET) {
					int expected2 = value + ((sweep&16) ? -1 : 1);
					if (expected2 < 0) expected2 = 0;
					else if (expected2 > mask) expected2 = mask;

					if (expected != expected2) {
						if (num_fail < 10) printf("UNEXPECTED MODEL OUTPUT: in = %d, result %d, expected = %d\n", value, expected, expected2);
						num_fail++;
						ok = false;
						break;
					}
				}

				if (result != expected) {
					if (num_fail < 10) printf("ERROR: in = %d, result %d, expected = %d\n", value, result, expected);
					num_fail++;
					ok = false;
					break;
				} else num_ok++;

				if (result != value) num_changed++;
			}
			int num_changed_expected;
			if (sweep_index == REG_SLOPE0 && (sweep>>5) == 2) num_changed_expected = 0;
			else if (sweep_index == REG_SLOPE1 && (sweep>>5) == 1) num_changed_expected = 0;
			else num_changed_expected = (1 << nbits) - 1;
			if (num_changed != num_changed_expected) {
				if (num_fail < 10) printf("ERROR: num_changed = %d, expected = %d\n", num_changed, num_changed_expected);
				num_fail++;
				ok = false;
				break;
			}
			if (!ok) {
				printf("tested with sweep = %d\n", sweep);
				break;
			}
		}
		if (!ok) break;
	}
	m.set_reg_both(0, REG_SWEEP_PA, 0);
	m.set_reg_both(0, REG_SWEEP_WS, 0);

	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif

#ifdef TEST_LFSR
	ok = true;
	num_ok = 0;
	num_fail = 0;

	// Depends on channel, period and phase for the channel, oct_counter
	printf("\nTesting LFSR oscillator\n");

	int channel = 3;
	m.term_index = 2*channel;
	m.oct_counter = (1 << 24) - 1; // Force oct_enable on
	write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, m.oct_counter);

	for (int j = 0; j < 2; j++) {
//	for (int j = 1; j < 2; j++) {
		int f_period = j == 0 ? 0 : 0x155;
		int num_samples = (1024 + f_period) << 8;

		m.set_reg_both(channel, REG_PHASE, 0);
		m.set_reg_both(channel, REG_PERIOD, f_period); // Start without delay. TODO: Test with delay
		m.set_reg_both(channel, REG_MODE, MODE_FLAG_NOISE);
		int phase = 0;
		for (int i = 0; i < num_samples; i++) {
			exec_step(m.term_index, STATE_CMP_REV_PHASE);
			exec_step(m.term_index, STATE_UPDATE_PHASE);
			exec_step(m.term_index, STATE_DETUNE, 4);
			model_oscillator(m);

			//int result = read_reg_from_rtl(channel, REG_PHASE);
			//int expected = m.get_channel_reg(REG_PHASE);
			int result = read_reg_from_rtl(channel, REG_PHASE) | (read_core_reg_from_rtl(TST_ADDR_LFSR_EXTRA_BITS) << BITS);
			int expected = m.get_channel_reg(REG_PHASE) | (m.lfsr_extra_bits << BITS);

			if (result != expected) {
				if (num_fail < 10) printf("ERROR: i = %d, in = %d, result %d, expected = %d\n", i, phase, result, expected);
				num_fail++;
				ok = false;
				break;
			} else num_ok++;

			if ((result == 0) != (i == num_samples - 1)) {
				if (num_fail < 10) printf("LFSR zero too soon/late: i = %d, prev phase = %d, phase = %d\n", i, phase, result);
				num_fail++;
				ok = false;
				break;
			}

			phase = result;
			//printf("%d ", phase);
		}
		if (!ok) {
			printf("tested with f_period = %d\n", f_period);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
#endif


#ifdef TEST_OCT_COUNTER_INC
	m.set_reg_both(0, REG_SWEEP_PA, 257);
	m.set_reg_both(0, REG_SWEEP_WS, 257);

	ok = true;
	num_ok = 0;
	num_fail = 0;

	top->write_collision_en = 0; // turn off for now so that the external updates don't block the internal ones

	// Depends on oct_counter
	printf("\nTesting oct_counter incrementation\n");

	const int OC_DELTA = 4096;
	//const int OC_DELTA = 4;
	m.term_index = NUM_CHANNELS*2;
	for (int n = 0; n < OCT_COUNTER_BITS; n++) {
//	for (int n = 2; n < OCT_COUNTER_BITS; n++) {
		int center = 1 << n;
		for (int oc = center - OC_DELTA; oc <= center + OC_DELTA; oc++) {
			int oct_counter = oc & ((1 << OCT_COUNTER_BITS)-1);
			write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, oct_counter);

			exec_step(m.term_index, STATE_OCT_COUNTER_INC_LOW);
			exec_step(m.term_index, STATE_OCT_COUNTER_INC_HIGH);
			exec_step(m.term_index, STATE_OCT_COUNTER_INC_HIGH+1, 4);

			int result = read_core_reg_from_rtl(TST_ADDR_OCT_COUNTER);
			int expected = (oct_counter + 1) & ((1 << OCT_COUNTER_BITS)-1);

			if (result != expected) {
				if (num_fail < 10) printf("ERROR: in = 0x%x, result 0x%x, expected = 0x%x\n", oct_counter, result, expected);
				num_fail++;
				ok = false;
				break;
			} else num_ok++;
		}
		if (!ok) {
			printf("tested with n = %d\n", n);
			break;
		}
	}
	printf("\nNumber of cases tested ok: %d\n", num_ok);
	printf("Number of cases failed: %d\n\n", num_fail);
	if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }

	top->write_collision_en = 1;
	m.set_reg_both(0, REG_SWEEP_PA, 0);
	m.set_reg_both(0, REG_SWEEP_WS, 0);
#endif


	for (int osc_mode = 0; osc_mode < 2; osc_mode++) {
		bool pwl_osc_en = osc_mode;

#ifndef TEST_OSC
		if (pwl_osc_en == false) continue;
#endif
#ifndef TEST_PWL_OSC
		if (pwl_osc_en == true) continue;
#endif

		ok = true;
		num_ok = 0;
		num_fail = 0;

		// Depends on channel, period and phase for the channel, oct_counter
		if (pwl_osc_en) printf("\nTesting PWL oscillator\n");
		else printf("\nTesting oscillator\n");

		m.term_index = 0;
		m.oct_counter = 0;
		write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, m.oct_counter);
		m.set_reg_both(0, REG_MODE, pwl_osc_en ? MODE_FLAG_PWL_OSC : 0); // Disable LFSR, set pwl mode on/off
		for (int f_period = 0; f_period < (8 << MANTISSA_BITS); f_period++) {
//		for (int f_period = 4; f_period <= 4; f_period++) {
//		for (int f_period = 0; f_period < (5 << MANTISSA_BITS); f_period++) {
//		for (int f_period = 0; f_period < (4 << MANTISSA_BITS); f_period++) {
//		for (int f_period = 4; f_period < (4 << MANTISSA_BITS); f_period++) {
//		for (int f_period = 4; f_period < 5; f_period++) {
//		for (int f_period = 0; f_period < 3; f_period++) {
//		for (int f_period = (4 << MANTISSA_BITS); f_period < (5 << MANTISSA_BITS); f_period++) {
			bool do_print = (f_period & 255) == 0;
			//do_print = true;
			//if (do_print) printf("f_period = %d\n", f_period);
			int mantissa = f_period & ((1 << MANTISSA_BITS) - 1);
			int period_exp = f_period >> MANTISSA_BITS;
			int oct = 7 - period_exp;
			int shift_count = 3 - period_exp;

			int period = ((1 << MANTISSA_BITS) + mantissa) << (PHASE_BITS - MANTISSA_BITS);
			period <<= 3;
			if (((period >> oct) << oct) != period) continue; // TODO: test intermediate freqs
			period >>= oct;

			int num_samples = period;
			bool cut_short = (period_exp >= 5);
			if (cut_short) num_samples = 256;

			if (do_print) printf("f_period = %d, period = %d, num_samples = %d\n", f_period, period, num_samples);

			int phase = 0;
			m.set_reg_both(0, REG_PERIOD, f_period);
			m.set_reg_both(0, REG_PHASE, 0);
			bool nonzero = false;
			for (int i = 0; i < num_samples; i++) {
				m.oct_counter = i; write_core_reg_to_rtl(TST_ADDR_OCT_COUNTER, m.oct_counter);
				//printf("\n\ni = %d\n", i);
				exec_step(m.term_index, STATE_CMP_REV_PHASE);
				//print_reg_w_internal();
				exec_step(m.term_index, STATE_UPDATE_PHASE);
				//print_reg_w_internal();
				//int result = read_core_reg_from_rtl(TST_ADDR_ACC) & ((1 << PHASE_BITS) - 1);
				exec_step(m.term_index, STATE_DETUNE, 4);
				//print_reg_w_internal();
				model_oscillator(m);

				int result = read_reg_from_rtl(0, REG_PHASE);
				int expected = m.get_channel_reg(REG_PHASE);
				//if (pwl_osc_en) result = expected; // Ignore the RTL result for now for PWL oscillator. TODO: remove!

				if (result != expected) {
					if (num_fail < 10) printf("ERROR: in = %d, result %d, expected = %d\n", phase, result, expected);
					num_fail++;
					ok = false;
					break;
				} else num_ok++;

				if (result != 0) nonzero = true;

				if (result < phase && i*4 < period*3) {
					if (num_fail < 10) printf("ERROR: phase wrapped too soon: i = %d, period = %d, prev phase = %d, phase = %d\n", i, period, phase, result);
					num_fail++;
					ok = false;
					break;
				}

				phase = result;
				//printf("%d ", phase);
				//write_reg_to_rtl(0, REG_PHASE, phase); // !!!
			}
			if (ok && !cut_short && phase != 0) {
				if (num_fail < 10) printf("ERROR: phase didn't come back to zero, f_period = %d, period = %d, phase = %d\n", f_period, period, phase);
				num_fail++;
				ok = false;
			}
			if (!nonzero) {
				if (num_fail < 10) printf("ERROR: phase stayed at zero, f_period = %d, period = %d\n", f_period, period);
				num_fail++;
				ok = false;
			}

			if (!ok) {
				printf("tested with f_period = %d\n", f_period);
				break;
			}

		}

		printf("\nNumber of cases tested ok: %d\n", num_ok);
		printf("Number of cases failed: %d\n\n", num_fail);
		if (num_fail > 0) { printf("SOME CASES FAILED!\n"); all_ok = false; }
	}


	if (!all_ok) printf("\n\nSOME TESTS FAILED!\n\n");
	return all_ok;
}

int random(int range) {
	return rand() % range;
}

int rand_bits(int nbits) {
	return rand() & ((1 << nbits)-1);
}

void randomize(Model &m, int horizon) {
	m.acc = rand_bits(BITS+1);
	m.out_acc = rand_bits(BITS);
	m.pred = rand_bits(1);
	m.part = rand_bits(1);
	m.lfsr_extra_bits = rand_bits(7);
	m.last_osc_wrapped = rand_bits(1);
	m.cfg = rand_bits(2); // random stereo

	//m.oct_counter = rand_bits(24);
	// Weighted distribution to sample oct_counter_values with many lowest bits = 1, to trigger octave enables.
	int oct_counter = rand_bits(24);
	int n_ones = rand_bits(5);
	if (n_ones <= 16) oct_counter |= ((1 << n_ones) - 1);
	if (oct_counter > horizon) oct_counter -= horizon; // make the interesting case wait the horizon length
	m.oct_counter = oct_counter;
	//printf("n_ones = %d, oct_counter = 0x%x\n", n_ones, oct_counter);

	for (int channel = 0; channel < NUM_CHANNELS; channel++) {
		bool orion_en = false;
		for (int reg = 0; reg < REGS_PER_CHANNEL; reg++) {
			int data = rand_bits(num_reg_rand_bits[reg]);

			int flag_mask = (MODE_FLAG_NOISE | MODE_FLAG_PWL_OSC);
			if (reg == REG_MODE && ((data & flag_mask) == flag_mask)) {
#ifndef USE_ORION_WAVE
				// Don't allow LFSR and PWL_OSC at the same time.
				data &= ~MODE_FLAG_NOISE;
#else
				orion_en = true;
#endif
			}

#ifdef USE_OSC_SYNC
			if (reg == REG_PHASE && rand_bits(3) == 0) data = (1<<BITS)-1; // Try to trigger osc sync
#endif

#ifdef USE_OSC_SYNC_ONLY_FOR_SOME_CHANNELS
			//if (reg == REG_MODE && (channel == 1)) data &= ~MODE_FLAGS_OSC_SYNC_MASK;
			if (reg == REG_MODE && (channel == 1 || channel == 2)) data &= ~MODE_FLAGS_OSC_SYNC_MASK;
			if (reg == REG_MODE && (channel == 1 || channel == 3)) data &= ~MODE_FLAG_DETUNE_FIFTH;
#endif

#ifdef USE_DETUNE_FIFTH
			if (reg == REG_MODE && ((data&7)==7)) data &= ~MODE_FLAG_DETUNE_FIFTH;
#endif
#ifdef USE_DETUNE_FIFTH
			if (reg == REG_MODE && ((data&MODE_FLAG_3X)!=0)) data &= ~MODE_FLAG_DETUNE_FIFTH;
#endif

			m.set_reg(channel, reg, data);
		}

//		if (orion_en) m.set_reg(channel, REG_SLOPE1, 0xff);
	}
}

int check_match_counter = 0;

void check_match(const Model &m, bool &ok, const char *position, int nbits = BITS) {
	int mask = (1 << nbits) - 1;
	int acc = m.acc & mask;
	if (acc != (top->acc_out & mask)) {
		printf("%s: Mismatch in acc, model: 0x%x, RTL: 0x%x\n", position, acc, (top->acc_out & mask));
		ok = false;
	}
	mask = (1 << BITS) - 1;
	//int out_acc = (m.out_acc & (-1 << OUT_ACC_FRAC_BITS)) & mask;
	int out_acc = m.out_acc & mask;
	if (out_acc != top->out_acc_out) {
		printf("%s: Mismatch in out_acc, model: 0x%x, RTL: 0x%x\n", position, out_acc, top->out_acc_out);
		ok = false;
	}

	if (m.last_osc_wrapped != top->last_osc_wrapped) {
		printf("%s: Mismatch in last_osc_wrapped, model: %d, RTL: %d\n", position, m.last_osc_wrapped, top->last_osc_wrapped);
		ok = false;
	}
	check_match_counter++;
}

bool run_sequence_test(int num_samples, int horizon) {
	// No read, no write
	top->data_write_n = 3;
	top->data_read_n = 3;
	top->ireg_raddr = -1;
	top->ireg_waddr = -1;

	top->en_external = 0;
	top->state_override_en = 0;
	top->pipeline_curr_channel = 1; // How to make sure it starts out right for the first cycle? Rely on reset behavior?
	top->write_collision_en = 1;

	top->rst_n = 0; 
	for (int i = 0; i < 10; i++) timestep();
	top->rst_n = 1;

	bool all_ok = true;

	Model m;
	randomize(m, horizon);
	write_core_regs_to_rtl(m);
	write_reg_array_to_rtl(m);

	top->en_external = 1;
	top->step_part_enables = 7;

	int num_samples_ok = 0;
#ifdef DEBUG_PRINTS
	printf("\n");
#endif
	for (int sample_index = 0; sample_index < num_samples; sample_index++) {
#ifdef DEBUG_PRINTS
		printf("sample_index = %d, check_match_counter = %d, oct_counter = 0x%x\n", sample_index, check_match_counter, m.oct_counter);
#endif
		//printf("phases[0] = 0x%x\n", m.get_reg(0, REG_PHASE));
		// TODO: set state and term_index in the RTL? They are initialized to zero at reset.

		bool stereo_en = m.stereo_en();

		//for (int term_index = 0; term_index < 2*NUM_CHANNELS; term_index++) {
		for (int term_i = 0; term_i < 2*NUM_CHANNELS; term_i++) {
			int term_index;
			if (stereo_en) {
				term_index = ((term_i & 3) << 1) | ((term_i & 4) >> 2);
			} else term_index = term_i;

#ifdef DEBUG_PRINTS
			printf("term_index = %d\n", term_index);
#endif
			m.term_index = term_index; // TODO: keep updated!

			int old_phase = m.get_channel_reg(REG_PHASE);
			if ((term_index & 1) == 0) {
#ifdef DEBUG_PRINTS
				printf("model_oscillator\n");
#endif
				timestep(); // STATE_CMP_REV_PHASE
				timestep(); // STATE_UPDATE_PHASE
				model_oscillator(m);
				//printf("acc: 0x%x, 0x%x\n", m.acc, top->acc_out);
				check_match(m, all_ok, "oscillator    ");
			}
#ifdef DEBUG_PRINTS
			printf("model_detune\n");
#endif
			timestep(); // STATE_DETUNE
			model_detune(m, old_phase);
		//	printf("acc: 0x%x, 0x%x\n", m.acc, top->acc_out);
			check_match(m, all_ok, "detune        ");
			timestep(); // STATE_TRI
			model_tri_pwm_offset(m);
		//	printf("acc: 0x%x, 0x%x\n", m.acc, top->acc_out);
			check_match(m, all_ok, "tri_pwm_offset");

			timestep(); // STATE_COMBINED_SLOPE_CMP
			timestep(); // STATE_COMBINED_SLOPE_ADD
			model_slope(m);
		//	printf("acc: 0x%x, 0x%x\n", m.acc, top->acc_out);
			check_match(m, all_ok, "slope         ");

			if (m.common_sat_add()) {
				timestep(); // STATE_CMP_REV_PHASE as add
				model_add_common_sat(m);
				check_match(m, all_ok, "add_common_sat");
			}

			if (m.common_sat_store()) {
				timestep(); // STATE_AMP_CMP
			} else {
				timestep(); // STATE_AMP_CMP
				timestep(); // STATE_OUT_ACC
				model_amp_clamp_out(m);
			//	printf("out_acc: 0x%x, 0x%x\n", m.out_acc, top->out_acc_out);
				check_match(m, all_ok, "amp_clamp_out ");
			}
		}
		for (int i = 0; i < 4; i++) timestep();
		int nbits = model_sweep(m);
		check_match(m, all_ok, "sweep         ", nbits);
		for (int i = 0; i < 4; i++) timestep();
		m.acc = top->acc_out; // Read back current acc update to account for bits in acc that we ignored
		m.oct_counter++;

		if (all_ok) num_samples_ok = sample_index+1;

		if (!all_ok) break;
	}

//	printf("\n%d samples tested ok\n\n", num_samples_ok);

	return all_ok;
}

bool run_sequence_tests() {
	bool all_ok = true;

	for (int j = 0; j < 2; j++) {
//	for (int j = 0; j < 1; j++) {
		int num_samples, num_sequences, horizon;

#ifndef TEST_SHORT_SEQS
		if (j == 0) continue;
#endif
#ifndef TEST_LONG_SEQS
		if (j == 1) continue;
#endif

		if (j == 0) {
			num_samples = 4;
			num_sequences = 1 << (15 + seq_extra_exp);
			horizon = 1;
		} else {
			num_samples = 34;
			num_sequences = 1 << (12 + seq_extra_exp);
			horizon = 32;
		}

		printf("Testing sequences with random initial values: length = %d, horizon = %d\n", num_samples, horizon);

		int num_sequences_ok = 0;
		for (int i = 0; i < num_sequences; i++) {
			//printf("i = %d\n", i);
			int ns = num_samples;
			//if (i < 1) ns = 0;

			all_ok &= run_sequence_test(ns, horizon);
			if (all_ok) num_sequences_ok++;
			if (!all_ok) break;
		}

		printf("\n%d sequences tested ok\n\n", num_sequences_ok);
	}

	return all_ok;
}

int main(int argc, char** argv) {
	Verilated::commandArgs(argc, argv);

	top = new Vtqvp_toivoh_pwl_synth();

#ifdef TRACE_ON
	Verilated::traceEverOn(true);
	m_trace = new VerilatedVcdC;
	top->trace(m_trace, 5);
	m_trace->open("peripheral-test.vcd");
#endif

	// No read, no write
	top->data_write_n = 3;
	top->data_read_n = 3;
	top->ireg_raddr = -1;
	top->ireg_waddr = -1;

	top->pipeline_curr_channel = 0;
	top->write_collision_en = 1;

	top->en_external = 0;
	top->state_override_en = 1;

	top->rst_n = 0; 
	for (int i = 0; i < 10; i++) timestep();
	top->rst_n = 1;


	bool all_ok = true;
	all_ok &= run_step_tests();
	//all_ok &= run_sequence_test(256, 32);
	all_ok &= run_sequence_tests();
	if (!all_ok) printf("\n\nSOME TESTS FAILED!\n\n");

#ifdef TRACE_ON
	m_trace->close();
#endif

	// Cleanup
	delete top;
	return 0;
}
