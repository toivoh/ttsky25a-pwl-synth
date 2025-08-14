# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

async def reg_write(dut, addr, channel, value):
	dut.reg_waddr.value = addr*4 + channel
	dut.reg_wdata.value = value
	dut.reg_we.value = 1
	dut.en.value = 0
	await ClockCycles(dut.clk, 1)
	dut.reg_we.value = 0
	dut.en.value = 1


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

	dut.en.value = 1
	dut.next_en.value = 1


	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1


	await reg_write(dut, 1, 0, 63) # Set volume for channel 0
	await reg_write(dut, 2, 0, 7) # Set detune_exp for channel 0

	# Set tri_offset and slope_offset for channel 0
	#tri_offset = (1 << (BITS-1-2)) - (1 << (BITS-2))
	tri_offset = (1 << (BITS-1-2)) # full range is 0 to 2^(BITS-2)-1
	slope_offset = 1 << (BITS - 4) # full range is 0 to 2^(BITS-3)-1
	params = (((tri_offset >> (BITS-2-8))&255)<<8) | ((slope_offset >> (BITS-3-4))*17)
	print("params =", params)
	await reg_write(dut, 3, 0, params) # Set params for channel 0

	await reg_write(dut, 0, 0, (1 << 10) | 0b01010101) # set period for channel 0

	### await reg_write(dut, 4, 0, 16 | 2) # set sweep for channel 0
	await reg_write(dut, 0, 1, (3 << 10) | 0x3ff) # set period for channel 1
	### await reg_write(dut, 4, 1, 1) # set sweep for channel 1

	await reg_write(dut, 1, 2, 63) # set amp for channel 2
	# Set amp sweeps for channel 2 and 3. NOTE: will move...
	### await reg_write(dut, 4, 2, ((6<<4) | 1)<<5)
	### await reg_write(dut, 4, 3, ((1<<4) | 1)<<5)

	await reg_write(dut, 7, 0, (0 |1)<<8) # set pwm_offset sweep for channel 0
	await reg_write(dut, 7, 1, (16|1)<<8) # set pwm_offset sweep for channel 1

	await reg_write(dut, 2, 0, 0xfd) # set slope0 for channel 0
	await reg_write(dut, 3, 0, 0x18) # set slope1 for channel 0
	await reg_write(dut, 7, 0, ((0<<7)|1)) # set slope sweep for channel 0

	await reg_write(dut, 2, 1, 0x02) # set slope0 for channel 1
	await reg_write(dut, 3, 1, 0x38) # set slope1 for channel 1
	await reg_write(dut, 7, 1, ((1<<5)|16|1)) # set slope sweep for channel 1

	await reg_write(dut, 2, 2, 0xA0) # set slope0 for channel 2
	await reg_write(dut, 3, 2, 0xA8) # set slope1 for channel 2
	await reg_write(dut, 7, 2, ((2<<5)|1)) # set slope sweep for channel 2

	await reg_write(dut, 2, 3, 0xF0) # set slope0 for channel 3
	await reg_write(dut, 3, 3, 0xF8) # set slope1 for channel 3
	await reg_write(dut, 7, 3, ((3<<5)|1)) # set slope sweep for channel 3

	await reg_write(dut, 0, 2, 2) # set period for channel 2
	await reg_write(dut, 6, 2, (16 | 1) << 8) # set period sweep for channel 2
	await reg_write(dut, 0, 3, 8192-3) # set period for channel 3
	await reg_write(dut, 6, 3, (0 | 1) << 8) # set period sweep for channel 3


	if False:
		await ClockCycles(dut.clk, 1335) # no write collision - write not during extra_term
		#await ClockCycles(dut.clk, 1336) # no actual write collision but write still blocked
		#await ClockCycles(dut.clk, 1337) # earliest possible write collision
		#await ClockCycles(dut.clk, 1340) # latest possible write collision
		#await ClockCycles(dut.clk, 1341) # after write collision (no collision)
		await reg_write(dut, 2, 0, 0x20) # set slope0 for channel 0


	await ClockCycles(dut.clk, 1 + PIPELINE + 256*32)
