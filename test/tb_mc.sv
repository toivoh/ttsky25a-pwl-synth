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

	pwls_multichannel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .NUM_CHANNELS(NUM_CHANNELS)) mc_alu_unit(
		.clk(clk), .reset(!rst_n), .en(1),
		.reg_waddr(reg_waddr), .reg_wdata(reg_wdata), .reg_we(reg_we),
		//.detune_exp(detune_exp),
		.tri_offset(tri_offset), .slope_exp(slope_exp), .slope_offset(slope_offset) //, .amp(amp)
	);
endmodule
