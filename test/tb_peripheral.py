# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

INTERFACE_REGISTER_SHIFT = 4

def map_addr(addr, channel):
	return (channel<<4) | ((addr&7)<<1) | ((addr&8)>>3)

async def reg_write(dut, addr, channel, value):
	address = map_addr(addr, channel)

	dut.address.value = address
	dut.data_in.value = value << INTERFACE_REGISTER_SHIFT
	dut.data_write.value = 1
	await ClockCycles(dut.clk, 1)
	dut.data_write.value = 0


#@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	# write pwm_offset[0]
	dut.address.value = 0x08
	dut.data_in.value = 0xcd
	dut.data_write.value = 1
	await ClockCycles(dut.clk, 1)
	dut.data_write.value = 0

	dut.data_read.value = 1
	await ClockCycles(dut.clk, 128)


#@cocotb.test()
async def test_slope_192_m1(dut):
	dut._log.info("Start")

	peripheral = dut.peripheral
	mc_alu_unit = peripheral.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	for slope in (176, 192):
		mc_alu_unit.genblk1[0].slope0_reg.data.value = slope
		for acc in (-2, -1, 0):
			mc_alu_unit.term_index.value = 0
			mc_alu_unit.state.value = 4
			alu_unit.acc.value = acc

			await ClockCycles(dut.clk, 4)
			#for i in range(4): alu_unit.pred.value = 0; await ClockCycles(dut.clk, 1)


#@cocotb.test()
async def test_slope_amp_clamp_out_acc_0(dut):
	dut._log.info("Start")

	peripheral = dut.peripheral
	mc_alu_unit = peripheral.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	mc_alu_unit.term_index.value = 1
	mc_alu_unit.state.value = 6

	alu_unit.acc.value = 0
	alu_unit.out_acc.value = 0
	mc_alu_unit.genblk1[0].amps_reg.data.value = 1

	await ClockCycles(dut.clk, 4)

#@cocotb.test()
async def test_new_read(dut):
	dut._log.info("Start")

	peripheral = dut.peripheral
	mc_alu_unit = peripheral.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut.address.value = 1
	dut.data_read.value = 1

	for i in range(128):
		await ClockCycles(dut.clk, 1)
		if peripheral.data_ready.value == 1: break

	dut.data_read.value = 0
	await ClockCycles(dut.clk, 80)

#@cocotb.test()
async def test_stereo(dut):
	dut._log.info("Start")

	peripheral = dut.peripheral
	mc_alu_unit = peripheral.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	alu_unit.out_acc.value = 5
	alu_unit.out_acc_alt_frac.value = 9

	await reg_write(dut, 9, 2, 1) # turn on stereo

	await ClockCycles(dut.clk, 128+16)


@cocotb.test()
async def test_read_oct_counter(dut):
	dut._log.info("Start")

	peripheral = dut.peripheral
	mc_alu_unit = peripheral.mc_alu_unit
	alu_unit = mc_alu_unit.alu_unit

	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	await reg_write(dut, 9, 0, 0x321)
	await reg_write(dut, 9, 1, 0x765)

	for i in range(2):
		dut.address.value = map_addr(9, i)
		dut.data_read.value = 1

		while (dut.data_ready.value.integer != 1):
			await ClockCycles(dut.clk, 1)
		value = peripheral.data_out.value.integer >> INTERFACE_REGISTER_SHIFT
		print("oct_counter", i, " = ", hex(value), sep="")

		assert value == (0x322 if i == 0 else 0x765)

		dut.data_read.value = 0
		await ClockCycles(dut.clk, 4)


