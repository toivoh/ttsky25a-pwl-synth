`default_nettype none
`timescale 1ns / 1ps

`include "pwl_synth.vh"

module tb_peripheral #(parameter BITS=12, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4) ();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_peripheral.vcd");
		$dumpvars(0, tb_peripheral);
		#1;
	end

	reg clk;
	reg rst_n;

	reg [5:0]  address = 0;
	reg [31:0] data_in = 0;
	reg data_write = 0;
	reg data_read = 0;

	tqvp_toivoh_pwl_synth peripheral(
		.clk(clk), .rst_n(rst_n),
		.ui_in(0),
		.address(address), .data_in(data_in),
		.data_write_n(data_write ? 2'b01 : 11),
		.data_read_n( data_read  ? 2'b01 : 11)
	);

	wire [BITS-1:0] phase0 = peripheral.mc_alu_unit.phases[0];
	wire [BITS-1:0] phase1 = peripheral.mc_alu_unit.phases[1];
	wire [BITS-1:0] phase2 = peripheral.mc_alu_unit.phases[2];
	wire [BITS-1:0] phase3 = peripheral.mc_alu_unit.phases[3];

	wire [12:0] period0 = peripheral.mc_alu_unit.periods[0];
	wire [12:0] period1 = peripheral.mc_alu_unit.periods[1];
	wire [12:0] period2 = peripheral.mc_alu_unit.periods[2];
	wire [12:0] period3 = peripheral.mc_alu_unit.periods[3];

	wire [5:0] amp0 = peripheral.mc_alu_unit.amps[0];
	wire [5:0] amp1 = peripheral.mc_alu_unit.amps[1];
	wire [5:0] amp2 = peripheral.mc_alu_unit.amps[2];
	wire [5:0] amp3 = peripheral.mc_alu_unit.amps[3];

`ifndef USE_NEW_REGMAP
	wire [9:0] sweep0 = peripheral.mc_alu_unit.sweeps[0];
	wire [9:0] sweep1 = peripheral.mc_alu_unit.sweeps[1];
	wire [9:0] sweep2 = peripheral.mc_alu_unit.sweeps[2];
	wire [9:0] sweep3 = peripheral.mc_alu_unit.sweeps[3];
`endif

	wire [7:0] pwm_offset0 = peripheral.mc_alu_unit.pwm_offsets[0];
	wire [7:0] pwm_offset1 = peripheral.mc_alu_unit.pwm_offsets[1];
	wire [7:0] pwm_offset2 = peripheral.mc_alu_unit.pwm_offsets[2];
	wire [7:0] pwm_offset3 = peripheral.mc_alu_unit.pwm_offsets[3];

	wire [7:0] slope0_0 = peripheral.mc_alu_unit.slopes0[0];
	wire [7:0] slope0_1 = peripheral.mc_alu_unit.slopes0[1];
	wire [7:0] slope0_2 = peripheral.mc_alu_unit.slopes0[2];
	wire [7:0] slope0_3 = peripheral.mc_alu_unit.slopes0[3];

	wire [7:0] slope1_0 = peripheral.mc_alu_unit.slopes1[0];
	wire [7:0] slope1_1 = peripheral.mc_alu_unit.slopes1[1];
	wire [7:0] slope1_2 = peripheral.mc_alu_unit.slopes1[2];
	wire [7:0] slope1_3 = peripheral.mc_alu_unit.slopes1[3];

	wire [15:0] sweep0_0 = peripheral.mc_alu_unit.sweeps0[0];
	wire [15:0] sweep0_1 = peripheral.mc_alu_unit.sweeps0[1];
	wire [15:0] sweep0_2 = peripheral.mc_alu_unit.sweeps0[2];
	wire [15:0] sweep0_3 = peripheral.mc_alu_unit.sweeps0[3];

	wire [15:0] sweep1_0 = peripheral.mc_alu_unit.sweeps1[0];
	wire [15:0] sweep1_1 = peripheral.mc_alu_unit.sweeps1[1];
	wire [15:0] sweep1_2 = peripheral.mc_alu_unit.sweeps1[2];
	wire [15:0] sweep1_3 = peripheral.mc_alu_unit.sweeps1[3];

	int en_counter = 0;
	always_ff @(posedge clk) en_counter <= en_counter + (peripheral.mc_alu_unit.en_eff && rst_n);
endmodule
