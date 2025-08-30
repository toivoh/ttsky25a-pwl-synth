# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

INTERFACE_REGISTER_SHIFT = 4

@cocotb.test()
async def test_project(dut):
	dut._log.info("Start")

	# Set the clock period to 100 ns (10 MHz)
	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut.ui_in.value  = 0
	dut.uio_in.value = 0

	await ClockCycles(dut.clk, 1)

	with open("../verilator/compare-test/compare_data.txt", "r") as file:
		t = 0
		while True:
		#for i in range(16):
			#print("i =", i, end="\t")
			line = file.readline()
			if line == "": break
			cmd_in, wdata_in, uo_out_expected, data_out_expected, data_ready_expected = [int(s, 0) for s in line.split()]

			u_in = (cmd_in << 13) | wdata_in
			dut.ui_in.value = u_in & 255
			dut.uio_in.value = u_in >> 8

			await ClockCycles(dut.clk, 1)

			#t += 1; continue

			if t >= 66: # compare results; a bit more than one sample time is needed to set the PWM counter
				uo_out = dut.uo_out.value.integer

				data_out = dut.data_out.value.integer
				data_ready = dut.data_ready.value.integer

				#print([(uo_out, uo_out_expected), (data_out, data_out_expected), (data_ready, data_ready_expected)])

				if not (uo_out == uo_out_expected and data_out == data_out_expected and data_ready == data_ready_expected):
					print("Mismatch")
					print("--------")
					print("t =", t)
					print("uo_out: ", hex(uo_out), "\texpected: ", hex(uo_out_expected))
					print("data_out: ", hex(data_out), "\texpected: ", hex(data_out_expected))
					print("data_ready: ", hex(data_ready), "\texpected: ", hex(data_ready_expected))

				if True:
					assert uo_out == uo_out_expected
					assert data_out == data_out_expected
					assert data_ready == data_ready_expected

			t += 1
