`default_nettype none
`timescale 1ns / 1ps

`include "pwl_synth.vh"

module tb_mc #(parameter BITS=12, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4) ();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_mc.vcd");
		$dumpvars(0, tb_mc);
		#1;
	end

	reg clk;
	reg rst_n;

	reg [5:0] reg_waddr = 0;
	reg [`REG_BITS-1:0] reg_wdata = 0;
	reg reg_we = 0;

	//reg [DETUNE_EXP_BITS-1:0] detune_exp = 0;
	reg [BITS-1:0] tri_offset = 0;
	reg [SLOPE_EXP_BITS-1:0] slope_exp = 0;
	reg [BITS-3-1:0] slope_offset = 0;
	//reg [BITS-2-1:0] amp = '1;

	reg en = 1;
	reg next_en = 1;

	pwls_multichannel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .NUM_CHANNELS(NUM_CHANNELS)) mc_alu_unit(
		.clk(clk), .rst_n(rst_n), .en(en), .next_en(next_en),
		.control_reg_write(1), .state_reg_write(1),
		.reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_we(reg_we),
		.reg_raddr('1), .reg_raddr_valid(0),
		//.detune_exp(detune_exp),
		.tri_offset(tri_offset), .slope_exp(slope_exp), .slope_offset(slope_offset) //, .amp(amp)
	);

	wire [BITS-1:0] phase0 = mc_alu_unit.phases[0];
	wire [BITS-1:0] phase1 = mc_alu_unit.phases[1];
	wire [BITS-1:0] phase2 = mc_alu_unit.phases[2];
	wire [BITS-1:0] phase3 = mc_alu_unit.phases[3];

	wire [12:0] period0 = mc_alu_unit.periods[0];
	wire [12:0] period1 = mc_alu_unit.periods[1];
	wire [12:0] period2 = mc_alu_unit.periods[2];
	wire [12:0] period3 = mc_alu_unit.periods[3];

	wire [5:0] amp0 = mc_alu_unit.amps[0];
	wire [5:0] amp1 = mc_alu_unit.amps[1];
	wire [5:0] amp2 = mc_alu_unit.amps[2];
	wire [5:0] amp3 = mc_alu_unit.amps[3];

`ifndef USE_NEW_REGMAP
	wire [9:0] sweep0 = mc_alu_unit.sweeps[0];
	wire [9:0] sweep1 = mc_alu_unit.sweeps[1];
	wire [9:0] sweep2 = mc_alu_unit.sweeps[2];
	wire [9:0] sweep3 = mc_alu_unit.sweeps[3];
`endif

	wire [7:0] pwm_offset0 = mc_alu_unit.pwm_offsets[0];
	wire [7:0] pwm_offset1 = mc_alu_unit.pwm_offsets[1];
	wire [7:0] pwm_offset2 = mc_alu_unit.pwm_offsets[2];
	wire [7:0] pwm_offset3 = mc_alu_unit.pwm_offsets[3];

	wire [7:0] slope0_0 = mc_alu_unit.slopes0[0];
	wire [7:0] slope0_1 = mc_alu_unit.slopes0[1];
	wire [7:0] slope0_2 = mc_alu_unit.slopes0[2];
	wire [7:0] slope0_3 = mc_alu_unit.slopes0[3];

	wire [7:0] slope1_0 = mc_alu_unit.slopes1[0];
	wire [7:0] slope1_1 = mc_alu_unit.slopes1[1];
	wire [7:0] slope1_2 = mc_alu_unit.slopes1[2];
	wire [7:0] slope1_3 = mc_alu_unit.slopes1[3];

	wire [15:0] sweep0_0 = mc_alu_unit.sweeps0[0];
	wire [15:0] sweep0_1 = mc_alu_unit.sweeps0[1];
	wire [15:0] sweep0_2 = mc_alu_unit.sweeps0[2];
	wire [15:0] sweep0_3 = mc_alu_unit.sweeps0[3];

	wire [15:0] sweep1_0 = mc_alu_unit.sweeps1[0];
	wire [15:0] sweep1_1 = mc_alu_unit.sweeps1[1];
	wire [15:0] sweep1_2 = mc_alu_unit.sweeps1[2];
	wire [15:0] sweep1_3 = mc_alu_unit.sweeps1[3];

	int en_counter = 0;
	always_ff @(posedge clk) en_counter <= en_counter + (en && rst_n);
endmodule
