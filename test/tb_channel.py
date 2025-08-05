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

	BITS = int(dut.BITS.value)
	PHASE_BITS = BITS
	NUM_STATES = int(alu_unit.STATE_LAST.value) + 1
	PIPELINE = int(alu_unit.PIPELINE.value)

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())



	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1


	octave = 4
	mantissa = 0

	dut.octave.value = octave
	dut.mantissa.value = mantissa

	period = 256 << octave

	dut.detune_exp.value = 0
	dut.tri_offset.value = (1 << (BITS-1-2)) - (1 << (BITS-2))
	dut.slope_exp.value = 2
	dut.slope_offset.value = 1 << (BITS - 4) # full range is 0 to 2^(BITS-3)-1
	dut.amp.value = 3 << (BITS - 4) # full range is 0 to 2^(BITS-2)-1


	with open("channel-data.txt", "w") as file:
		await ClockCycles(dut.clk, 1 + PIPELINE)

		for i in range(period):
			for j in range(NUM_STATES):
				if j <= 1: channel_alu_unit.phase.value = i # Hack: override the phase to check all phase values

				await ClockCycles(dut.clk, 1)

				if j == 0:              x = i # write out phase instead of acc for first step
				#elif j == NUM_STATES-1: x = alu_unit.out_acc.value.signed_integer # sample out_acc instead for last step
				elif j == NUM_STATES-1: x = alu_unit.out_acc_out.value.signed_integer # sample out_acc instead for last step
				else:                   x = alu_unit.acc.value.signed_integer

				pred = alu_unit.pred.value.integer
				part = alu_unit.part.value.integer
				flags = pred | (part << 1)
				file.write(hex(x) + " " + str(flags))
				if j < NUM_STATES - 1: file.write(" ")
			file.write("\n")
