# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	channel_alu_unit = dut.channel_alu_unit
	alu_unit = channel_alu_unit.alu_unit

	LFSR_BITS = 3
	#LFSR_BITS = 11

	BITS = int(dut.BITS.value)
	PHASE_BITS = BITS
	NUM_STATES = int(alu_unit.STATE_LAST.value) + 1
	PIPELINE = int(alu_unit.PIPELINE.value)
	CHANNEL_MODE_BIT_NOISE = int(dut.CHANNEL_MODE_BIT_NOISE.value);
	LFSR_HIGHEST_OCT = int(dut.LFSR_HIGHEST_OCT.value);

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	# NOTE! pwls_channel_ALU_unit used in this test uses a full 11 bit mantissa, unlike pwls_multichannel_ALU_unit which uses a 10 bit one
	octave = 0
	mantissa = 0b10101010101
	#mantissa = 0

	#octave = 3
	#mantissa = 2047

	mantissa &= (-1 << (7-octave)) >> 3

	period0 = (1 << (PHASE_BITS - 1)) + mantissa
	period = (period0 << octave) >> 3

	dut.octave.value = octave
	dut.mantissa.value = mantissa
	dut.detune_exp.value = 0
	#dut.tri_offset.value = (1 << (BITS-1-2)) - (1 << (BITS-2))
	dut.tri_offset.value = -48
	dut.slope_exp.value = 5
	dut.slope_offset.value = 1 << (BITS - 4) # full range is 0 to 2^(BITS-3)-1

	#lfsr_on = False
	lfsr_on = True

	phase_mask = -1
	if lfsr_on:
		octave = 1
		dut.octave.value = octave

		dut.channel_mode.value = 1 << CHANNEL_MODE_BIT_NOISE
		mantissa = 0b1010101010
		#mantissa = 0
		#mantissa = 1024
		dut.mantissa.value = mantissa
		phase_mask = (1 << (LFSR_BITS + 1)) - 1
		#period = (8 + (mantissa>>8))
		period = (2048 + mantissa) >> (11 - LFSR_BITS)
		period <<= (octave + LFSR_HIGHEST_OCT + 1)

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	if lfsr_on:
		# The LFSR includes the zero state, ok to start at zero
		#channel_alu_unit.phase.value = 2
		channel_alu_unit.phase.value = 0

	await ClockCycles(dut.clk, 1 + PIPELINE)
	for i in range(period):
		await ClockCycles(dut.clk, NUM_STATES)
		print(channel_alu_unit.phase.value.integer & phase_mask, end=" ")
	print("\n")
	print("period =", period)
	print()
