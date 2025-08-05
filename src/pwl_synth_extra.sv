/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "pwl_synth.vh"

// pwls_ALU_unit wrapped for testing a single channel
module pwls_channel_ALU_unit #(parameter BITS=12, SHIFT_COUNT_BITS=4, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, OUT_RSHIFT=4, OUT_ACC_FRAC_BITS=4, LFSR_HIGHEST_OCT=3) (
		input wire clk, reset,

		input wire [OCT_BITS-1:0] octave,
		input wire [BITS-2:0] mantissa,
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [BITS-1:0] tri_offset, // includes offset to convert to signed
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [BITS-3-1:0] slope_offset,
		input wire [BITS-2-1:0] amp,
		input wire [`CHANNEL_MODE_BITS-1:0] channel_mode,

		output wire [BITS-1:0] phase_out, acc_out
	);

	reg [BITS-1:0] phase;

	wire [`SRC1_SEL_BITS-1:0] src1_sel;


	reg [`STATE_BITS-1:0] state;

	wire [`STATE_BITS+1-1:0] state_inc = state + 1;
	wire next_sample = (state == `STATE_LAST);
	always_ff @(posedge clk) begin
		if (reset || next_sample) begin
			state <= 0;
		end else begin
			state <= state_inc;
		end
	end


	reg [BITS-1:0] src1; // not a register
	always_comb begin
		case (src1_sel)
			`SRC1_SEL_PHASE: src1 = phase;
			`SRC1_SEL_MANTISSA: src1 = mantissa;
			`SRC1_SEL_TRI_OFFSET: src1 = tri_offset;
			`SRC1_SEL_SLOPE_OFFSET: src1 = slope_offset;
//			`SRC1_SEL_AMP, `SRC1_SEL_OUT_ACC, `SRC1_SEL_ZERO: src1 = amp; // Feed in amp also for `SRC1_SEL_OUT_ACC, to handle replace_src2_with_amp
			`SRC1_SEL_AMP: src1 = amp; // Feed in amp also for `SRC1_SEL_OUT_ACC, to handle replace_src2_with_amp
			default: src1 = 'X;
		endcase
	end


	wire [`DEST_SEL_BITS-1:0] dest_sel;
	wire [BITS-1:0] result;
	pwls_ALU_unit #(
		.BITS(BITS), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .OUT_RSHIFT(OUT_RSHIFT),
		.OUT_ACC_FRAC_BITS(OUT_ACC_FRAC_BITS), .LFSR_HIGHEST_OCT(LFSR_HIGHEST_OCT)
	) alu_unit(
		.clk(clk), .reset(reset),
		.state(state), .first_term(1'b1), .next_sample(next_sample), .sub_channel(0),
		.octave(octave),
		.detune_exp(detune_exp), .slope_exp(slope_exp), .channel_mode(channel_mode),
		.src1_sel_out(src1_sel), .src1_external(src1), .phase_external(phase), .amp_external(amp),
		.dest_sel_out(dest_sel), .result(result),
		.acc_out(acc_out)
	);

	always_ff @(posedge clk) begin
		if (reset) begin
			phase <= 0;
		end else begin
			if (dest_sel == `DEST_SEL_PHASE) phase <= result;
		end
	end

	assign phase_out = phase;
endmodule : pwls_channel_ALU_unit
