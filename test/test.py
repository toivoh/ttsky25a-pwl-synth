# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

# When submitting your design, change this to the peripheral number
# in peripherals.v.  e.g. if your design is i_user_peri05, set this to 5.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 0

def read_pwm_out(dut):
	data = dut.uo_out.value.integer
	assert data == 0 or data == 255
	return data != 0

async def read_pwm_run(dut, level, max_len=56):
	n = 0
	while (read_pwm_out(dut) == level):
		await ClockCycles(dut.clk, 1)
		n += 1
		assert n <= max_len

	return n

async def read_pwm_duty(dut, aligned = False, max_period=56):
	if not aligned:
		await read_pwm_run(dut, False) # wait for PWM to go high
		await read_pwm_run(dut, True) # wait for falling edge

	n_low = await read_pwm_run(dut, False)
	n_high = await read_pwm_run(dut, True)

	return n_high, n_low + n_high


@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	# Set the clock period to 100 ns (10 MHz)
	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	# Interact with your design's registers through this TinyQV class.
	# This will allow the same test to be run when your design is integrated
	# with TinyQV - the implementation of this class will be replaces with a
	# different version that uses Risc-V instructions instead of the SPI test
	# harness interface to read and write the registers.
	tqv = TinyQV(dut, PERIPHERAL_NUM)

	# Reset
	await tqv.reset()

	dut._log.info("Test project behavior")

	nbits = [13, 6, 12, 16]


	await ClockCycles(dut.clk, 100)
	# Check that PWM output stays at zero level, at expected period
	n_high, n_total = await read_pwm_duty(dut)
	assert n_total == 56
	assert n_high == 24
	n_high_0, n_total_0 = n_high, n_total
	for i in range(9):
		n_high, n_total = await read_pwm_duty(dut, True)
		assert (n_high, n_total) == (n_high_0, n_total_0)

	# Test register write and read back
	for i in range(16):
		#print("i =", i)
		data_in = (0x1234 + i*0x1111)&0xffff
		await tqv.write_hword_reg(2*i, data_in)
		data_out = await tqv.read_hword_reg(2*i)
		expected = data_in & ((1 << nbits[i>>2]) - 1)
		#print("data_out =", hex(data_out), "expected =", hex(expected))
		assert data_out == expected
	# Test reading back the registers again
	for i in range(16):
		#print("i =", i)
		data_in = (0x1234 + i*0x1111)&0xffff
		data_out = await tqv.read_hword_reg(2*i)
		expected = data_in & ((1 << nbits[i>>2]) - 1)
		#print("data_out =", hex(data_out), "expected =", hex(expected))
		assert data_out == expected

	# Check that not all PWM output samples remain at the zero level now that the amp registers are nonzero
	ok = False
	for i in range(10):
		n_high, n_total = await read_pwm_duty(dut, i > 0)
		#print("n_high =", n_high)
		assert n_total == n_total_0
		if n_high != n_high_0: ok = True
	assert ok

	# Restore the amp registers to zero
	for i in range(4): await tqv.write_hword_reg(2*(4+i), 0)

	# Check that the PWM output samples are back at the zero level
	for i in range(10):
		n_high, n_total = await read_pwm_duty(dut, i > 0)
		assert (n_high, n_total) == (n_high_0, n_total_0)


	assert not await tqv.is_interrupt_asserted()
