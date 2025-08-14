`default_nettype none
`timescale 1ns / 1ps

`include "pwl_synth.vh"

module tb_osc #(parameter BITS=12, OCT_BITS=3, MANTISSA_BITS=10, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, LFSR_HIGHEST_OCT=0) ();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_osc.vcd");
		$dumpvars(0, tb_osc);
		#1;
	end

	localparam CHANNEL_MODE_BIT_NOISE = `CHANNEL_MODE_BIT_NOISE;

	reg clk;
	reg rst_n;

	reg [OCT_BITS-1:0] octave = 0;
	reg [MANTISSA_BITS-1:0] mantissa = 0;
	reg [DETUNE_EXP_BITS-1:0] detune_exp = 0;
	reg [BITS-1:0] tri_offset = 0;
	reg [SLOPE_EXP_BITS-1:0] slope_exp = 0;
	reg [BITS-3-1:0] slope_offset = 0;
	reg [BITS-2-1:0] amp = '1;
	reg [`CHANNEL_MODE_BITS-1:0] channel_mode = 0;

	pwls_channel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .MANTISSA_BITS(MANTISSA_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .LFSR_HIGHEST_OCT(LFSR_HIGHEST_OCT)) channel_alu_unit(
		.clk(clk), .reset(!rst_n),
		.mantissa(mantissa), .octave(octave), .detune_exp(detune_exp), .tri_offset(tri_offset), .slope_exp(slope_exp), .slope_offset(slope_offset), .amp(amp), .channel_mode(channel_mode)
	);
endmodule
