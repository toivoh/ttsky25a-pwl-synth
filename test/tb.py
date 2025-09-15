# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

def read_pwm_out(dut):
	data = dut.uio_out.value.integer & 0xc0
	assert data == 0 or data == 0xc0
	return data != 0

async def read_pwm_run(dut, level, max_len=64):
	n = 0
	while (read_pwm_out(dut) == level):
		await ClockCycles(dut.clk, 1)
		n += 1
		assert n <= max_len

	return n

async def read_pwm_duty(dut, aligned = False, max_period=64):
	if not aligned:
		await read_pwm_run(dut, False) # wait for PWM to go high
		await read_pwm_run(dut, True) # wait for falling edge

	n_low = await read_pwm_run(dut, False)
	n_high = await read_pwm_run(dut, True)

	return n_high, n_low + n_high

def remap_addr(addr):
	channel = addr & 3
	field = addr >> 2
	return (((channel << 3) | (field&7)) << 1) | ((field&8)>>3)

READ_SEL_HIGH = 16
CMD_READ = 8
CMD_WRITE = 4
CMD_DATA_HIGH = 2
CMD_DATA_LOW = 1

READ_WAITING = 32

reg_bits = [13, 6, 8, 8, 8, 16, 13, 13, 12, 13, 16]

async def reg_write(dut, addr, value):
	bits = reg_bits[addr>>2]

	dut.ui_in.value = value & 0xff
	dut.uio_in.value = CMD_DATA_LOW
	await ClockCycles(dut.clk, 3)

	if bits > 8:
		dut.ui_in.value = (value >> 8) & 0xff
		dut.uio_in.value = CMD_DATA_HIGH
		await ClockCycles(dut.clk, 3)

	dut.ui_in.value = remap_addr(addr)
	dut.uio_in.value = CMD_WRITE
	await ClockCycles(dut.clk, 3)

	# wait for the write to take effect
	await ClockCycles(dut.clk, 4)


async def reg_read(dut, addr):
	bits = reg_bits[addr>>2]

	dut.ui_in.value = remap_addr(addr)
	dut.uio_in.value = CMD_READ
	await ClockCycles(dut.clk, 4)

	wait_counter = 0
	while (dut.uio_out.value.integer & READ_WAITING) != 0:
		await ClockCycles(dut.clk, 1)
		wait_counter += 1
		assert wait_counter < 70

	data = dut.uo_out.value.integer
	dut.uio_in.value = READ_SEL_HIGH
	await ClockCycles(dut.clk, 1)
	data |= dut.uo_out.value.integer << 8

	return data

@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	# Set the clock period to 100 ns (10 MHz)
	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.uio_in.value = 0
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut._log.info("Test project behavior: PWL Synth")

	nbits = [13, 6, 8, 8, 8, 16]

	dut._log.info("Check initial PWM output")
	await ClockCycles(dut.clk, 100)
	# Check that PWM output stays at zero level, at expected period
	n_high, n_total = await read_pwm_duty(dut)
	assert n_total == 64
	assert n_high == 32
	n_high_0, n_total_0 = n_high, n_total
	for i in range(9):
		n_high, n_total = await read_pwm_duty(dut, True)
		assert (n_high, n_total) == (n_high_0, n_total_0)

	# Test register write and read back
	dut._log.info("Test register write and read back")
	await ClockCycles(dut.clk, 4)
	for i in range(24):
		#print("i =", i)
		data_in = (0x1234 + i*0x1111)&0xffff
		await reg_write(dut, i, data_in)
		if i < 20:
			data_out = await reg_read(dut, i)
			expected = data_in & ((1 << nbits[i>>2]) - 1)
			#print("data_out =", hex(data_out), "expected =", hex(expected))
			assert data_out == expected

	# Test reading back the registers again
	dut._log.info("Test reading back the registers again")
	for i in range(20):
		#print("i =", i)
		data_in = (0x1234 + i*0x1111)&0xffff
		data_out = await reg_read(dut, i)
		expected = data_in & ((1 << nbits[i>>2]) - 1)
		#print("data_out =", hex(data_out), "expected =", hex(expected))
		assert data_out == expected

	# Check that not all PWM output samples remain at the zero level now that the amp registers are nonzero
	dut._log.info("Check PWM output when synth is running")
	ok = False
	for i in range(10):
		n_high, n_total = await read_pwm_duty(dut, i > 0)
		#print("n_high =", n_high)
		assert n_total == n_total_0
		if n_high != n_high_0: ok = True
	assert ok

	# Apply sweep values
	dut._log.info("Apply sweeps")
	sweeps = [
		# Period and amplitude sweeps
		((16|1)<<8) | ((7 << 4)|1),
		(( 0|0)<<8) | ((0 << 4)|1),
		((16|1)<<8) | ((0 << 4)|0),
		(( 0|1)<<8) | ((7 << 4)|1),
		# PWM offset and slope sweeps
		(( 0|1)<<8) | ((3<<5)| 0|1),
		(( 0|1)<<8) | ((2<<5)|16|1),
		((16|0)<<8) | ((1<<5)| 0|1),
		((16|1)<<8) | ((0<<5)| 0|1),
	]
	sweep_dirs = [
		-1,  0, -1,  1,
		 1, -1,  0,  1,
		 1,  0,  1,  1,
		 1, -1,  0, -1,
		 1,  1,  0, -1
	]
	for (i, sweep) in enumerate(sweeps):
		await reg_write(dut, 24+i, sweep)

	# Check that not all PWM output samples remain at the zero level now that the amp registers are nonzero
	dut._log.info("Check PWM output again and wait for sweeps to take effect")
	ok = False
	for i in range(32):
		n_high, n_total = await read_pwm_duty(dut, i > 0)
		#print("n_high =", n_high)
		assert n_total == n_total_0
		if n_high != n_high_0: ok = True
	assert ok

	dut._log.info("Check effect of sweeps")
	for (i, dir) in enumerate(sweep_dirs):
		data_in = (0x1234 + i*0x1111)&0xffff
		data_out = await reg_read(dut, i)
		expected = data_in & ((1 << nbits[i>>2]) - 1)
		if   dir == 0: assert data_out == expected
		elif dir  < 0: assert data_out  < expected
		elif dir  > 0: assert data_out  > expected

	# restore sweeps to zero
	for (i, sweep) in enumerate(sweeps):
		await reg_write(dut, 24+i, 0)

	dut._log.info("Check PWM output when all amplitudes are zero")

	# Restore the amp registers to zero
	for i in range(4): await reg_write(dut, 4+i, 0)
	await ClockCycles(dut.clk, 64) # wait for amps to take effect

	# Check that the PWM output samples are back at the zero level
	for i in range(10):
		n_high, n_total = await read_pwm_duty(dut, i > 0)
		assert (n_high, n_total) == (n_high_0, n_total_0)

	dut._log.info("Write and read back detune_counter")
	detune_counter = 0x98765432
	for i in range(2):
		if i == 1:
			dut._log.info("Turn off detune_counter incrementation")
			await reg_write(dut, 4*9+2, 0) # cfg

		await reg_write(dut, 4*10, detune_counter & 0xffff)
		await reg_write(dut, 4*10+1, (detune_counter>>16) & 0xffff)
		dut._log.info("Wrote detune_counter = " + hex(detune_counter))
		dc_read = (await reg_read(dut, 4*10)) | ((await reg_read(dut, 4*10+1))<<16)
		dut._log.info("Read detune_counter = " + hex(dc_read))

		if i == 1: assert dc_read == detune_counter
