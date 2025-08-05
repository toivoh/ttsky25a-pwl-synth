# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

async def reg_write(dut, addr, channel, value):
	dut.reg_waddr.value = addr*4 + channel
	dut.reg_wdata.value = value
	dut.reg_we.value = 1
	await ClockCycles(dut.clk, 1)
	dut.reg_we.value = 0


@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	mc_alu_unit = dut.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	BITS = int(dut.BITS.value)
	PHASE_BITS = BITS
	NUM_STATES = int(alu_unit.STATE_LAST.value) + 1
	PIPELINE = int(alu_unit.PIPELINE.value)

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

#	dut.detune_exp.value = 7
	dut.tri_offset.value = (1 << (BITS-1-2)) - (1 << (BITS-2))
	dut.slope_exp.value = 2
	dut.slope_offset.value = 1 << (BITS - 4) # full range is 0 to 2^(BITS-3)-1
	#dut.amp.value = 3 << (BITS - 4) # full range is 0 to 2^(BITS-2)-1

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 1)
	dut.rst_n.value = 1


	await reg_write(dut, 1, 0, 63) # Set volume for channel 0
	await reg_write(dut, 2, 0, 7) # Set detune_exp for channel 0

	# Set tri_offset and slope_offset for channel 0
	#tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2))
	tri_offset = (1 << (BITS-1-2)) # full range is 0 to 2^(BITS-2)-1
	slope_offset = 1 << (BITS - 4) # full range is 0 to 2^(BITS-3)-1
	params = (((tri_offset >> (BITS-2-8))&255)<<8) | ((slope_offset >> (BITS-3-4))*17)
	print("params =", params)
	await reg_write(dut, 3, 0, params) # Set detune_exp for channel 0



	await ClockCycles(dut.clk, 1 + PIPELINE + 256*32)
