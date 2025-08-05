`default_nettype none
`timescale 1ns / 1ps

module tb_channel #(parameter BITS=12, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4) ();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_channel.vcd");
		$dumpvars(0, tb_channel);
		#1;
	end

	reg clk;
	reg rst_n;

	reg [OCT_BITS-1:0] octave = 0;
	reg [BITS-2:0] mantissa = 0;
	reg [DETUNE_EXP_BITS-1:0] detune_exp = 0;
	reg [BITS-1:0] tri_offset = 0;
	reg [SLOPE_EXP_BITS-1:0] slope_exp = 0;
	reg [BITS-3-1:0] slope_offset = 0;
	reg [BITS-2-1:0] amp = '1;
	reg [`CHANNEL_MODE_BITS-1:0] channel_mode = 0;

	pwls_channel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS)) channel_alu_unit(
		.clk(clk), .reset(!rst_n),
		.mantissa(mantissa), .octave(octave), .detune_exp(detune_exp), .tri_offset(tri_offset), .slope_exp(slope_exp), .slope_offset(slope_offset), .amp(amp), .channel_mode(channel_mode)
	);
endmodule
