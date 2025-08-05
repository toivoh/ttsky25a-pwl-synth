/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "pwl_synth.vh"


module named_buffer #(parameter BITS=1) (
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
`ifdef NAMED_BUF_EN
	genvar i;
	generate
		for (i = 0; i < BITS; i++) begin : bits
			(* keep *) (* dont_touch *) sky130_fd_sc_hd__buf_1 named_buf(.A(in[i]), .X(out[i]));
			//(* keep *) (* dont_touch *) buf named_buf(out[i], in[i]);
		end
	endgenerate
`else
	assign out = in;
`endif
endmodule


module pwls_shifter(
		input wire [15:0] shifter_in,
		input wire [3:0] shl_count,
		input wire do_shl, // mask out bits rotated into the bottom?

		output wire [15:0] shl_mask,
		output wire [15:0] shifter_out
	);

/*
	// CONSIDER: better with mux4? Does this become mux4?
	wire [15:0] x0 = shifter_in;
	wire [15:0] x1 = shl_count[3] ? {x0[ 7:0], x0[15: 8]} : x0;
	wire [15:0] x2 = shl_count[2] ? {x1[11:0], x1[15:12]} : x1;
	wire [15:0] x3 = shl_count[1] ? {x2[13:0], x2[15:14]} : x2;
	wire [15:0] x4 = shl_count[0] ? {x3[14:0], x3[15:15]} : x3;
	wire [15:0] x = x4;
*/
	wire [15:0] x = {{shifter_in, shifter_in} << shl_count} >> 16;

	assign shl_mask = '1 << shl_count;
	wire [15:0] mask = do_shl ? shl_mask : '1;

	assign shifter_out = x & mask;
endmodule : pwls_shifter


module pwls_ALU #(parameter BITS=12, SHIFT_COUNT_BITS=4, OUT_RSHIFT=3) (
		input wire clk, reset,

		input wire signed [BITS-1:0] src1_in,
		input wire signed [15:0] src2_in,
		input wire src2_rot, // rotate src2 instead of left shifting?
		input wire [SHIFT_COUNT_BITS-1:0] src2_lshift,
		input wire src2_sext,
		input wire inv_src1, inv_src2, src2_mask_msb, carry_in,
		input wire sat_en,

		output wire signed [BITS-1:0] result,
		output wire cmp_result, delayed
	);

	genvar i;

	wire signed [BITS-1:0] src2_shifted_0;
	wire signed [15:0] shl_mask;
	pwls_shifter src2_shifter(
		.shifter_in(src2_in), .shl_count(src2_lshift), .do_shl(!src2_rot),
		.shifter_out(src2_shifted_0), .shl_mask(shl_mask)
	);

	// not a register
	reg signed [BITS-1:0] src2_shifted;
	always_comb begin
		src2_shifted = src2_shifted_0;
		if (src2_sext) src2_shifted[BITS-1 -: OUT_RSHIFT] = src2_in[BITS-1] ? '1 : '0;
	end

	wire [15:0] rev_shl_mask;
	generate
		for (i = 0; i < 16; i++) assign rev_shl_mask[i] = shl_mask[15-i];
	endgenerate
	wire [BITS-1-1:0] shl_sat_mask = ~rev_shl_mask >> (15 - (BITS-2));

	wire do_sat_shl_plus  = (src2_in[BITS-1] == 0) && |( src2_in & shl_sat_mask);
	wire do_sat_shl_minus = (src2_in[BITS-1] == 1) && |(~src2_in & shl_sat_mask);
	wire do_sat_shl = do_sat_shl_plus || do_sat_shl_minus;
	wire sat_shl_sign = src2_in[BITS-1];


	wire signed [BITS-1:0] src2_1 = src2_shifted & {!src2_mask_msb, {(BITS-1){1'b1}}};

	//wire signed [BITS-1:0] src1 = (src1_en ? src1_in : '0) ^ (inv_src1 ? '1 : 0);
	wire signed [BITS-1:0] src1 = src1_in ^ (inv_src1 ? '1 : 0);
	wire signed [BITS-1:0] src2 = src2_1 ^ (inv_src2 ? '1 : 0);

	//wire signed [BITS-1:0] sum = src1 + src2 + $signed({1'b0, carry_in});
	// An additional result bit seems to be needed to saturate correctly, at least for the combined slope step
	wire signed [BITS+1-1:0] sum = src1 + src2 + $signed({1'b0, carry_in});

	// Saturate to one bit less than BITS if saturation enabled; only phases need the full bit width
	/*
	wire sat_sum_sign = sum[BITS-1];
	wire do_sat_sum = sum[BITS-2] != sat_sum_sign;
	*/
	wire sat_sum_sign = sum[BITS];
	wire do_sat_sum = sum[BITS-1 -: 2] != {2{sat_sum_sign}};

	// not registers
	reg sat_sign, do_sat;
	always_comb begin
		if (do_sat_shl) begin
			do_sat = 1;
			sat_sign = sat_shl_sign ^ inv_src2;
		end else if (do_sat_sum) begin
			do_sat = 1;
			sat_sign = sat_sum_sign;
		end else begin
			do_sat = 0;
			sat_sign = 'X;
		end
	end

	wire signed [BITS-1:0] sat_sum = (sat_en && do_sat) ? (sat_sign ? -1 << (BITS - 2) : (1 << (BITS - 2)) - 1) : sum;

	assign result = sat_sum;
	assign cmp_result = sum[BITS-1];
	assign delayed = src2_shifted[BITS-1];
endmodule : pwls_ALU


module pwls_state_decoder #(parameter SHIFT_COUNT_BITS=4, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, OUT_RSHIFT=3) (
		input wire [`STATE_BITS-1:0] state,

		input wire [SHIFT_COUNT_BITS-1:0] osc_shift,
		input wire oct_enable, acc_sign, pred, first_term, sub_channel,
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [`CHANNEL_MODE_BITS-1:0] channel_mode,

		output wire [`SRC1_SEL_BITS-1:0] src1_sel_out,
		output wire [`SRC2_SEL_BITS-1:0] src2_sel_out,
		output wire [SHIFT_COUNT_BITS-1:0] src2_lshift_out,
		output wire src2_lshift_extra_out, src2_rot_out, src2_mask_msb_out, mask_out_acc_top_out, src1_en_out, inv_src1_out, inv_src2_out, carry_in_out, sat_en_out,
		output wire pred_we_out, part_we_out,
		output wire [`DEST_SEL_BITS-1:0] dest_sel_out,
		output wire pred_next_use_cmp_out, pred_next_use_lfsr_out,
		output wire replace_src2_with_amp_out,
		output wire src2_sext_out
	);

	// not registers
	reg [`SRC1_SEL_BITS-1:0] src1_sel;
	reg [`SRC2_SEL_BITS-1:0] src2_sel;
	reg [SHIFT_COUNT_BITS-1:0] src2_lshift;
	reg src2_lshift_extra, src2_rot, src2_mask_msb, mask_out_acc_top, src1_en, inv_src1, inv_src2, carry_in, sat_en;
	reg pred_we, part_we;
	reg [`DEST_SEL_BITS-1:0] dest_sel;
	reg pred_next_use_cmp, pred_next_use_lfsr;
	reg replace_src2_with_amp;
	reg src2_sext;

	always_comb begin
		pred_next_use_cmp = 0;
		pred_next_use_lfsr = 0;
		part_we = 0;
		pred_we = 0;
		src2_rot = 0;
		src2_mask_msb = 0;
		replace_src2_with_amp = 0;
		src2_sext = 0;
		mask_out_acc_top = 0;
		src1_en = 1;
		src2_lshift_extra = 0;
		case (state)
			`STATE_CMP_REV_PHASE: begin
				src1_sel = `SRC1_SEL_MANTISSA;
				src2_sel = `SRC2_SEL_REV_PHASE;
				sat_en = 0;
				inv_src1 = 1; inv_src2 = 0; carry_in = 1;
				src2_lshift = channel_mode[`CHANNEL_MODE_BIT_NOISE] ? 0 : osc_shift;
				src2_mask_msb = 1;
				pred_we = 1;
				pred_next_use_lfsr = channel_mode[`CHANNEL_MODE_BIT_NOISE];
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_UPDATE_PHASE: begin
				if (channel_mode[`CHANNEL_MODE_BIT_NOISE]) begin
					// Update of lfsr_extra_bits is matched with this update
					if (pred) begin // small_step, just increase by one
						src1_sel = `SRC1_SEL_PHASE;
						src2_sel = `SRC2_SEL_PHASE_STEP;
						sat_en = 0;
						inv_src1 = 0; inv_src2 = 0; carry_in = 0;
						src2_lshift = 0;
						src2_lshift_extra = 0;
						dest_sel = oct_enable ? `DEST_SEL_PHASE : `DEST_SEL_NOTHING; // TODO: separate oct_enable for LFSR
					end else begin // LFSR step
						src1_sel = `SRC1_SEL_ZERO;
						src2_sel = `SRC2_SEL_PHASE_MODIFIED;
						sat_en = 0;
						inv_src1 = 0; inv_src2 = 0; carry_in = 0;
						src2_lshift = 1;
						src2_lshift_extra = 0;
						dest_sel = oct_enable ? `DEST_SEL_PHASE : `DEST_SEL_NOTHING;
					end
				end else begin
					src1_sel = `SRC1_SEL_PHASE;
					src2_sel = `SRC2_SEL_PHASE_STEP;
					sat_en = 0;
					inv_src1 = 0; inv_src2 = 0; carry_in = 0;
					src2_lshift = osc_shift;
					src2_lshift_extra = !pred;
					dest_sel = oct_enable ? `DEST_SEL_PHASE : `DEST_SEL_NOTHING;
				end
			end
			`STATE_DETUNE: begin
				src1_sel = `SRC1_SEL_PHASE;
				src2_sel = (detune_exp == 0) ? `SRC2_SEL_ZERO : `SRC2_SEL_DETUNE;
				src2_rot = 1; sat_en = 0;
				inv_src1 = 0; inv_src2 = sub_channel; carry_in = 0;
				src2_lshift = detune_exp;
				dest_sel = `DEST_SEL_ACC;
			end
			`STATE_TRI: begin
				src1_sel = `SRC1_SEL_TRI_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = 0; inv_src2 = acc_sign; carry_in = 0;
				src2_lshift = 0;
				part_we = 1;
				dest_sel = `DEST_SEL_ACC;
			end
/*
			`STATE_SLOPE: begin
				src1_sel = `SRC1_SEL_ZERO;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = 0; inv_src2 = 0; carry_in = 0;
				src2_lshift = slope_exp;
				dest_sel = `DEST_SEL_ACC;
			end
			`STATE_FINE_SLOPE_CMP: begin
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = 0;
				pred_we = 1;
				pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_FINE_SLOPE_ADD: begin
				src1_sel = pred ? `SRC1_SEL_ZERO : `SRC1_SEL_SLOPE_OFFSET; // TODO zero out later
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = pred; // TODO: modify src2_lshift later
				dest_sel = `DEST_SEL_ACC;
			end
*/
			`STATE_COMBINED_SLOPE_CMP: begin
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = slope_exp;
				pred_we = 1; pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
			`STATE_COMBINED_SLOPE_ADD: begin
				//src1_sel = pred ? `SRC1_SEL_ZERO : `SRC1_SEL_SLOPE_OFFSET; // TODO zero out later
				src1_sel = `SRC1_SEL_SLOPE_OFFSET;
				src1_en = !pred;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = acc_sign; inv_src2 = 0; carry_in = inv_src1;
				//src2_lshift = slope_exp + pred; // TODO: modify src2_lshift later
				src2_lshift = slope_exp;
				src2_lshift_extra = pred;
				dest_sel = `DEST_SEL_ACC;
			end
			`STATE_AMP_CMP: begin
				src1_sel = `SRC1_SEL_AMP;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;
				inv_src1 = !acc_sign; inv_src2 = 0; carry_in = inv_src1;
				src2_lshift = 0;
				pred_we = 1;
				pred_next_use_cmp = 1;
				dest_sel = `DEST_SEL_NOTHING;
			end
/*
			`STATE_AMP_CLAMP: begin
				//src1_sel = !pred ? `SRC1_SEL_AMP : `SRC1_SEL_ZERO;
				//src2_sel =  pred ? `SRC2_SEL_ACC : `SRC2_SEL_ZERO;

				src1_sel = `SRC1_SEL_ZERO;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 1;

				inv_src1 = 0; inv_src2 = 0;
				if (!pred) begin
					replace_src2_with_amp = 1;
					inv_src2 = acc_sign;
				end
				carry_in = inv_src1;

				src2_lshift = 16 - OUT_RSHIFT;
				src2_rot = 1;
				src2_sext = 1;
				dest_sel = `DEST_SEL_ACC;
			end
*/
			`STATE_OUT_ACC: begin
				//src1_sel = first_term ? `SRC1_SEL_ZERO : `SRC1_SEL_OUT_ACC; // TODO: mask out only the top bits
				src1_sel = `SRC1_SEL_OUT_ACC;
				mask_out_acc_top = first_term;
				src2_sel = `SRC2_SEL_ACC;
				sat_en = 0; // Saturation doesn't seem to play well with the right shift; would at least have to disable shl saturation to make it work.

				inv_src1 = 0; inv_src2 = 0;
				if (!pred) begin
					replace_src2_with_amp = 1;
					inv_src2 = acc_sign;
				end
				carry_in = inv_src2;

				src2_lshift = 16 - OUT_RSHIFT;
				src2_rot = 1;
				src2_sext = 1;
				dest_sel = `DEST_SEL_OUT_ACC;
			end

			default: begin
				src1_sel = 'X;
				src2_sel = 'X;
				src2_rot = 'X; sat_en = 'X;
				inv_src1 = 'X; inv_src2 = 'X; carry_in = 'X;
				src2_lshift = 'X;
				src2_mask_msb = 'X;
				pred_we = 'X;
				part_we = 'X;
				pred_next_use_cmp = 'X;
				dest_sel = 'X;
				replace_src2_with_amp = 'X;
				src2_sext = 'X;
				src1_en = 'X;
				src2_lshift_extra = 'X;
			end
		endcase
	end


	named_buffer #(.BITS(`SRC1_SEL_BITS)) nb_src1_sel(.in(src1_sel), .out(src1_sel_out));
	named_buffer #(.BITS(`SRC2_SEL_BITS)) nb_src2_sel(.in(src2_sel), .out(src2_sel_out));
	named_buffer #(.BITS(`DEST_SEL_BITS)) nb_dest_sel(.in(dest_sel), .out(dest_sel_out));
	named_buffer #(.BITS(SHIFT_COUNT_BITS)) nb_src2_lshift(.in(src2_lshift), .out(src2_lshift_out));

	named_buffer nb_src2_lshift_extra(.in(src2_lshift_extra), .out(src2_lshift_extra_out));
	named_buffer nb_src2_rot(.in(src2_rot), .out(src2_rot_out));
	named_buffer nb_src2_mask_msb(.in(src2_mask_msb), .out(src2_mask_msb_out));
	named_buffer nb_src1_en(.in(src1_en), .out(src1_en_out));
	named_buffer nb_mask_out_acc_top(.in(mask_out_acc_top), .out(mask_out_acc_top_out));
	named_buffer nb_inv_src1(.in(inv_src1), .out(inv_src1_out));
	named_buffer nb_inv_src2(.in(inv_src2), .out(inv_src2_out));
	named_buffer nb_carry_in(.in(carry_in), .out(carry_in_out));
	named_buffer nb_sat_en(.in(sat_en), .out(sat_en_out));
	named_buffer nb_pred_we(.in(pred_we), .out(pred_we_out));
	named_buffer nb_part_we(.in(part_we), .out(part_we_out));
	named_buffer nb_pred_next_use_cmp(.in(pred_next_use_cmp), .out(pred_next_use_cmp_out));
	named_buffer nb_pred_next_use_lfsr(.in(pred_next_use_lfsr), .out(pred_next_use_lfsr_out));
	named_buffer nb_replace_src2_with_amp(.in(replace_src2_with_amp), .out(replace_src2_with_amp_out));
	named_buffer nb_src2_sext(.in(src2_sext), .out(src2_sext_out));
endmodule


module pwls_ALU_unit #(parameter BITS=12, SHIFT_COUNT_BITS=4, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, OUT_RSHIFT=4, OUT_ACC_FRAC_BITS=4, LFSR_HIGHEST_OCT=3, LFSR_STATE_BITS=18, OUT_ACC_INITIAL_TOP=0) (
		input wire clk, reset, en,

		input wire [`STATE_BITS-1:0] state,
		input wire first_term, next_sample, sub_channel,

		input wire [OCT_BITS-1:0] octave,
		input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [`CHANNEL_MODE_BITS-1:0] channel_mode,

		output wire [`SRC1_SEL_BITS-1:0] src1_sel_out,
		output wire [`DEST_SEL_BITS-1:0] dest_sel_out,
		output wire part_out,
		output wire [BITS-1:0] result,
		input wire [BITS-1:0] src1_external,
		input wire [BITS-1:0] phase_external, // Only used for rev_phase, must be valid when src2 reads rev_phase (or delayed is used, which depends on it)
		input wire [BITS-2-1:0] amp_external,

		output wire [BITS-1:0] acc_out, out_acc_out
	);

	localparam HIGH_OCTAVES = 4;

	localparam PHASE_BITS = BITS;
	localparam STATE_LAST = `STATE_LAST;

	localparam LFSR_EXTRA_BITS = LFSR_STATE_BITS - (PHASE_BITS - 1);

`ifdef PIPELINE
	localparam PIPELINE = 1;
`else
	localparam PIPELINE = 0;
`endif

`ifdef PIPELINE_SRC2
	localparam ACC_BITS = 16;
`else
	localparam ACC_BITS = BITS;
`endif


	genvar i;

	reg pred, part;

	reg [ACC_BITS-1:0] acc;
	reg [BITS-1:0] out_acc;

	reg [LFSR_EXTRA_BITS-1:0] lfsr_extra_bits;

`ifdef PIPELINE
	reg [`STATE_BITS-1:0] state_late;
	always_ff @(posedge clk) if (en) state_late <= state; // TODO: do we need a reset value?
`else
	wire [`STATE_BITS-1:0] state_late = state;
`endif


	// Octave divider
	// ==============
	//localparam DIVIDER_BITS = 2**OCT_BITS - HIGH_OCTAVES;
	localparam DIVIDER_BITS = 24;

	wire oct_counter_we = next_sample;

	reg [DIVIDER_BITS-1:0] oct_counter;
	wire [DIVIDER_BITS-1:0] next_oct_counter = oct_counter + 1; // CONSIDER: Can we use the ALU's adder for this?

	wire [DIVIDER_BITS-1:0] all_oct_enables = next_oct_counter & ~oct_counter;

	wire [2**OCT_BITS-1:0] oct_enables = {all_oct_enables, {HIGH_OCTAVES{1'b1}}};
	//wire [2**OCT_BITS-1:0] oct_enables = {all_oct_enables, {HIGH_OCTAVES{1'b1}}} & 8'b01111111; // Disable octave 7

	wire [2**OCT_BITS-1:0] oct_enables_lfsr = all_oct_enables[2**OCT_BITS-1+LFSR_HIGHEST_OCT -: 2**OCT_BITS];


	always_ff @(posedge clk) begin
		if (reset) oct_counter <= 0;
		else if (oct_counter_we) oct_counter <= next_oct_counter;
	end

	wire oct_enable = channel_mode[`CHANNEL_MODE_BIT_NOISE] ? oct_enables_lfsr[octave] : oct_enables[octave];

	// ===================

	wire [PHASE_BITS-1:0] rev_phase;
	generate
		for (i = 0; i < PHASE_BITS; i++) assign rev_phase[i] = phase_external[PHASE_BITS-1 - i];
	endgenerate


	reg [SHIFT_COUNT_BITS-1:0] osc_shift; // not a register
	always_comb begin
		case (octave)
			0: osc_shift = 3;
			1: osc_shift = 2;
			2: osc_shift = 1;
			default: osc_shift = 0;
		endcase
	end


	// wire [BITS-1:0] osc_step = pred ? 1 : 2;
	wire [BITS-1:0] osc_step = 1; // handle using src2_lshift_extra instead

	wire cmp_result, delayed;


	wire [`SRC1_SEL_BITS-1:0] src1_sel;
	wire [`SRC2_SEL_BITS-1:0] src2_sel;
	wire [SHIFT_COUNT_BITS-1:0] src2_lshift_early;
	wire src2_lshift_extra, src2_rot, src2_mask_msb, mask_out_acc_top, src1_en, inv_src1, inv_src2, carry_in, sat_en;
	wire pred_we, part_we;
	wire [`DEST_SEL_BITS-1:0] dest_sel;
	wire pred_next_use_cmp, pred_next_use_lfsr, replace_src2_with_amp, src2_sext;

`ifdef PIPELINE
	pwls_state_decoder #(.SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .OUT_RSHIFT(OUT_RSHIFT)) state_decoder_early(
		.state(state),

		.src1_sel_out(src1_sel),
`ifdef PIPELINE_SRC2
		.src2_sel_out(src2_sel),
`endif
`ifdef PIPELINE_SRC2_LSHIFT
		.src2_lshift_out(src2_lshift_early),
`endif
/*
		.src2_lshift_extra(src2_lshift_extra), .src2_rot(src2_rot), .src2_mask_msb(src2_mask_msb), .src1_en(src1_en), .inv_src1(inv_src1), .inv_src2(inv_src2), .carry_in(carry_in), .sat_en(sat_en),
		.pred_we(pred_we), .part_we(part_we),
		.dest_sel(dest_sel),
		.pred_next_use_cmp(pred_next_use_cmp),
		.replace_src2_with_amp(replace_src2_with_amp), .src2_sext(src2_sext)
*/

		.osc_shift(osc_shift), .oct_enable(oct_enable), .acc_sign(acc[BITS-1]), .pred(pred), .first_term(first_term), .sub_channel(sub_channel),
		.detune_exp(detune_exp), .slope_exp(slope_exp), .channel_mode(channel_mode)
	);
`endif

	pwls_state_decoder #(.SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .OUT_RSHIFT(OUT_RSHIFT)) state_decoder_late(
		.state(state_late),

		.osc_shift(osc_shift), .oct_enable(oct_enable), .acc_sign(acc[BITS-1]), .pred(pred), .first_term(first_term), .sub_channel(sub_channel),
		.detune_exp(detune_exp), .slope_exp(slope_exp), .channel_mode(channel_mode),

`ifndef PIPELINE
		.src1_sel_out(src1_sel),
`endif
`ifndef PIPELINE_SRC2
		.src2_sel_out(src2_sel),
`endif
`ifndef PIPELINE_SRC2_LSHIFT
		.src2_lshift_out(src2_lshift_early),
`endif

		.src2_lshift_extra_out(src2_lshift_extra), .src2_rot_out(src2_rot), .src2_mask_msb_out(src2_mask_msb), .mask_out_acc_top_out(mask_out_acc_top),
		.src1_en_out(src1_en), .inv_src1_out(inv_src1), .inv_src2_out(inv_src2), .carry_in_out(carry_in), .sat_en_out(sat_en),
		.pred_we_out(pred_we), .part_we_out(part_we),
		.dest_sel_out(dest_sel),
		.pred_next_use_cmp_out(pred_next_use_cmp), .pred_next_use_lfsr_out(pred_next_use_lfsr),
		.replace_src2_with_amp_out(replace_src2_with_amp), .src2_sext_out(src2_sext)
	);


	wire [17:0] detune_src_full = oct_counter >> 6;
	wire [15:0] detune_src_16;
	assign detune_src_16[13:0] = detune_src_full >> 2;
	assign detune_src_16[15:14] = detune_exp[2] ? detune_src_full[1:0] : detune_src_full[17:16];
	wire [15:0] detune_src = {detune_src_16[4:0], detune_src_16[15:5]};

	wire [LFSR_STATE_BITS-1:0] lfsr_state = {lfsr_extra_bits, phase_external[BITS-1:1]};
	// left shift by one, just like the phase
	wire [LFSR_EXTRA_BITS-1:0] lfsr_extra_bits_next = lfsr_state[LFSR_STATE_BITS-1-1 -: LFSR_EXTRA_BITS];

	always_ff @(posedge clk) begin
		if (reset) begin
			lfsr_extra_bits <= 0; // Needed?
		end else begin
			// Update condition is matched with update condition for phase for LFSR
			if (en && dest_sel == `DEST_SEL_PHASE && !pred && channel_mode[`CHANNEL_MODE_BIT_NOISE]) lfsr_extra_bits <= lfsr_extra_bits_next;
		end
	end

	// 11 bit LFSR
	//wire lfsr_bit = lfsr_state[10] ^ lfsr_state[8];
	//wire lfsr_bit = lfsr_state[10] ^ lfsr_state[8] ^ !lfsr_state[9:0]; // include zero state
	//wire lfsr_bit = lfsr_state[10] ^ (lfsr_state[8] | !lfsr_state[9:0]); // include zero state

	// 3 bit LFSR
	//wire lfsr_bit = lfsr_state[2] ^ (lfsr_state[0] | !lfsr_state[1:0]); // include zero state

	// 15 bit LFSR
	//wire lfsr_bit = lfsr_state[14] ^ (lfsr_state[0] | !lfsr_state[13:0]); // include zero state

	// 18 bit LFSR
	wire lfsr_bit = lfsr_state[17] ^ (lfsr_state[6] | !lfsr_state[16:0]); // include zero state

	// Not registers
	reg signed [BITS-1:0] src1;
	reg signed [15:0] src2;
	always_comb begin
		case (src1_sel)
			//`SRC1_SEL_PHASE: src1 = phase;
			`SRC1_SEL_PHASE: src1 = src1_external;
			`SRC1_SEL_OUT_ACC: src1 = out_acc;
			
			/*
			`SRC1_SEL_MANTISSA: src1 = mantissa;
			`SRC1_SEL_TRI_OFFSET: src1 = tri_offset;
			`SRC1_SEL_SLOPE_OFFSET: src1 = slope_offset;
			`SRC1_SEL_AMP: src1 = amp;
			*/
			`SRC1_SEL_MANTISSA, `SRC1_SEL_TRI_OFFSET, `SRC1_SEL_SLOPE_OFFSET, `SRC1_SEL_AMP: src1 = src1_external;

			`SRC1_SEL_ZERO: src1 = 0;
			default: src1 = 'X;
		endcase
		case (src2_sel)
			//`SRC2_SEL_ACC: src2 = {{(16-BITS){1'bX}}, acc};
			`SRC2_SEL_ACC: begin
				src2 = {{(16-BITS){1'bX}}, acc};
/*
`ifdef PIPELINE_SRC2
				// Forward result
				// Note: This is the only way to write result into acc with src2 pipelining enabled, make sure to use src2_sel = `SRC2_SEL_ACC as default!
				if (dest_sel == `DEST_SEL_ACC) src2 = {{(16-BITS){1'bX}}, result};
`endif
*/
			end
			`SRC2_SEL_REV_PHASE: src2 = {{(16-BITS){1'bX}}, rev_phase};
			`SRC2_SEL_PHASE_STEP: src2 = {{(16-BITS){1'bX}}, osc_step};
			`SRC2_SEL_DETUNE: src2 = detune_src;
			`SRC2_SEL_PHASE_MODIFIED: src2 = {{(16-BITS){1'bX}}, 1'b0, phase_external[BITS-1-1:1], lfsr_bit};
			`SRC2_SEL_ZERO: src2 = 0;
			default: src2 = 'X;
		endcase

`ifdef PIPELINE_SRC2
		// Forward result
		// Note: This is the only way to write result into acc with src2 pipelining enabled, make sure to use src2_sel = `SRC2_SEL_ACC as default!
		if (dest_sel == `DEST_SEL_ACC && src2_sel == `SRC2_SEL_ACC) src2 = {{(16-BITS){1'bX}}, result};
`endif
	end

`ifdef PIPELINE
	// pipelining
	reg signed [BITS-1:0] src1_in0;
	always_ff @(posedge clk) if (en) src1_in0 <= src1;
`else
	wire signed [BITS-1:0] src1_in0 = src1;
`endif

`ifdef PIPELINE_SRC2
	wire signed [15:0] src2_in0 = acc;
`else
	wire signed [15:0] src2_in0 = src2;
`endif

`ifdef PIPELINE_SRC2_LSHIFT
	reg [SHIFT_COUNT_BITS-1:0] src2_lshift;
	always_ff @(posedge clk) if (en) src2_lshift <= src2_lshift_early;
`else
	wire [SHIFT_COUNT_BITS-1:0] src2_lshift = src2_lshift_early;
`endif

	//wire signed [BITS-1:0] src1_in = (src1_en && !mask_out_acc_top) ? src1_in0 : '0;
	reg signed [BITS-1:0] src1_in; // not a register
	always_comb begin
		src1_in = src1_in0;
		if (!src1_en) src1_in = '0;
		if (mask_out_acc_top) src1_in[BITS-1:OUT_ACC_FRAC_BITS] = OUT_ACC_INITIAL_TOP;
	end

	// wire [BITS-1:0] src2_in = replace_src2_with_amp ? amp : src2_in0;
	//wire [BITS-1:0] src2_in = replace_src2_with_amp ? src1_external : src2_in0; // Feed in amp through src1_external in this case
	wire [15:0] src2_in = replace_src2_with_amp ? amp_external : src2_in0;

	pwls_ALU #(.BITS(BITS), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .OUT_RSHIFT(OUT_RSHIFT)) alu(
		.clk(clk), .reset(reset),
		.src1_in(src1_in), .src2_in(src2_in), .src2_rot(src2_rot), .src2_lshift(src2_lshift + src2_lshift_extra), .src2_sext(src2_sext),
		.src2_mask_msb(src2_mask_msb), .inv_src1(inv_src1), .inv_src2(inv_src2), .carry_in(carry_in), .sat_en(sat_en),
		.result(result), .cmp_result(cmp_result), .delayed(delayed)
	);

	// delayed is based on rev_phase, which is based on phase_external
	wire pred_next_osc = cmp_result || delayed; // small_step
	wire pred_next_lfsr = cmp_result && !phase_external[0]; // small_step for LFSR
	wire pred_next_cmp = result[BITS-1] ^ acc[BITS-1]; // slope_out = pred_next_cmp ? 2*acc : acc +- slope_offset
	wire pred_next = pred_next_use_cmp ? pred_next_cmp : (pred_next_use_lfsr ? pred_next_lfsr : pred_next_osc);

	always_ff @(posedge clk) begin
		if (reset) begin
			//phase <= 0;

			// TODO: needed?
			acc <= 0;
			pred <= 0;
			part <= 0;
			out_acc <= 0;
		end else if (en) begin
`ifdef PIPELINE_SRC2
			acc <= src2; // Use acc as pipeline register for src2
`endif
			case (dest_sel)
				//`DEST_SEL_PHASE: phase <= result;
`ifndef PIPELINE_SRC2
				`DEST_SEL_ACC: acc <= result;
`endif
				`DEST_SEL_OUT_ACC: out_acc <= result;
				default: ;
			endcase
			if (pred_we) pred <= pred_next;
			if (part_we) part <= acc[BITS-1];
		end
	end

	assign src1_sel_out = src1_sel;
	assign dest_sel_out = dest_sel;

	assign acc_out = acc;
	
	//assign out_acc_out = out_acc;
	reg [BITS-1:0] out_acc_out0; // not a register
	always_comb begin
		out_acc_out0 = out_acc;
		if (OUT_ACC_FRAC_BITS > 0) out_acc_out0[OUT_ACC_FRAC_BITS-1:0] = '0;
	end
	assign out_acc_out = out_acc_out0;
	assign part_out = part;
endmodule : pwls_ALU_unit


// pwls_ALU_unit wrapped for multichannel use
module pwls_multichannel_ALU_unit #(parameter BITS=12, SHIFT_COUNT_BITS=4, OCT_BITS=3, MANTISSA_BITS=10, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4, DETUNE_ON=1, OUT_ACC_FRAC_BITS=4, LFSR_HIGHEST_OCT=2) (
		input wire clk, reset, en,

		input wire [$clog2(NUM_CHANNELS)+$clog2(`REGS_PER_CHANNEL)-1:0] reg_waddr,
		input wire [`REG_BITS-1:0] reg_wdata,
		input wire reg_we,

		input wire [5:0] reg_raddr_p,
		output wire [`REG_BITS-1:0] reg_rdata_p, // valid when `en` is low

		// temporary global controls
		//input wire [DETUNE_EXP_BITS-1:0] detune_exp,
		input wire [BITS-1:0] tri_offset, // includes offset to convert to signed
		input wire [SLOPE_EXP_BITS-1:0] slope_exp,
		input wire [BITS-3-1:0] slope_offset,
		//input wire [BITS-2-1:0] amp,

		// for debug
		output wire [$clog2(NUM_CHANNELS)-1:0] term_index_out,
		output wire [`STATE_BITS-1:0] state_out,
		output wire [BITS-1:0] tri_offset_eff_out,
		output wire [15:0] curr_params_out,

		output wire new_out_acc,
		output wire [BITS-1:0] phase_out, acc_out, out_acc_out,
		output wire pwm_out,
		output int pwm_offset
	);

	localparam AMP_BITS = 6;

	localparam OUT_ACC_INITIAL_TOP = 512 >> OUT_ACC_FRAC_BITS;
	assign pwm_offset = OUT_ACC_INITIAL_TOP;

	localparam CHANNEL_TIMES = DETUNE_ON ? 2 : 1;
	localparam OUT_RSHIFT = DETUNE_ON ? 4: 3;

	localparam LOG2_CHANNELS = $clog2(NUM_CHANNELS);
	localparam NUM_TERMS = NUM_CHANNELS * CHANNEL_TIMES;
	localparam LOG2_TERMS = $clog2(NUM_TERMS);

	localparam PERIOD_BITS = OCT_BITS + MANTISSA_BITS;


	genvar i;


	wire curr_sub_channel;
	wire [`SRC1_SEL_BITS-1:0] src1_sel;
	wire part;


	reg [LOG2_TERMS-1:0] term_index;
	reg [`STATE_BITS-1:0] state;

	(* mem2reg *) reg [BITS-1:0] phases[NUM_CHANNELS];

/*
	(* mem2reg *) reg [PERIOD_BITS-1:0] periods[NUM_CHANNELS];
	(* mem2reg *) reg [AMP_BITS-1:0] amps[NUM_CHANNELS];
	(* mem2reg *) reg [`CHANNEL_MODE_BITS-1:0] modes[NUM_CHANNELS];
`ifdef USE_PARAMS_REGS
	(* mem2reg *) reg [15:0] params[NUM_CHANNELS];
`endif
*/

	wire [PERIOD_BITS-1:0] periods[NUM_CHANNELS];
	wire [AMP_BITS-1:0] amps[NUM_CHANNELS];
	wire [`CHANNEL_MODE_BITS-1:0] modes[NUM_CHANNELS];
`ifdef USE_PARAMS_REGS
	wire [15:0] params[NUM_CHANNELS];
`endif

	wire [`REG_BITS-1:0] reg_wdata2;
	pwls_shared_data #(.BITS(`REG_BITS)) shared_data(.clk(clk), .reset(reset), .in(reg_wdata), .out(reg_wdata2));
	generate
		for (i = 0; i < NUM_CHANNELS; i++) begin
			// Allow register writes even when en is low
			pwls_register #(.BITS(PERIOD_BITS))        periods_reg(.clk(clk), .reset(reset), .we( 0+i == reg_waddr && reg_we), .wdata(reg_wdata2), .rdata(periods[i]));
			pwls_register #(.BITS(AMP_BITS))           amps_reg(   .clk(clk), .reset(reset), .we( 4+i == reg_waddr && reg_we), .wdata(reg_wdata2), .rdata(amps[i]));
			pwls_register #(.BITS(`CHANNEL_MODE_BITS)) modes_reg(  .clk(clk), .reset(reset), .we( 8+i == reg_waddr && reg_we), .wdata(reg_wdata2), .rdata(modes[i]));
`ifdef USE_PARAMS_REGS
			pwls_register #(.BITS(16))                 params_reg( .clk(clk), .reset(reset), .we(12+i == reg_waddr && reg_we), .wdata(reg_wdata2), .rdata(params[i]));
`endif
		end
	endgenerate

	// Sample out_acc on the first cycle of the new sample, then it should just have been update. CONSIDER: better time/condition to use?
	wire sample_out_acc = (state == '0 && term_index == '0) && en;


	wire [`STATE_BITS+1-1:0] state_inc = state + en;
	wire next_term = (state == `STATE_LAST) && en;
	wire next_sample = next_term && (term_index == NUM_TERMS - 1); // also gated by en
	always_ff @(posedge clk) begin
		if (reset || next_term) state <= !reset && DETUNE_ON && (curr_sub_channel == 0) ? `STATE_DETUNE : 0; // skip oscillator update second time
		else                    state <= state_inc;

		if (reset || next_sample) term_index <= 0;
		else                      term_index <= term_index + next_term;
	end


	wire [LOG2_CHANNELS-1:0] curr_channel = en ? term_index >> $clog2(CHANNEL_TIMES) : reg_raddr_p[1:0];
	assign curr_sub_channel = DETUNE_ON ? term_index[0] : 0;

	wire [BITS-1:0] curr_phase = phases[curr_channel];
	wire [PERIOD_BITS-1:0] curr_period = periods[curr_channel];

	//wire [AMP_BITS-1:0] amp = amps[curr_channel];
	wire [BITS-2-1:0] amp = {amps[curr_channel], {(BITS-2-6){1'b0}}};
	wire [`CHANNEL_MODE_BITS-1:0] channel_mode = modes[curr_channel];

	wire [DETUNE_EXP_BITS-1:0] detune_exp = channel_mode[2:0];
`ifdef USE_SLOPE_EXP_REGS
	wire [SLOPE_EXP_BITS-1:0] slope_exp_eff = part ? channel_mode[11:8] : channel_mode[7:4];
`else
	wire [SLOPE_EXP_BITS-1:0] slope_exp_eff = slope_exp;
`endif

`ifdef USE_PARAMS_REGS
	wire [15:0] curr_params = params[curr_channel];
	// TODO: handle tri_offset range/signedness offset
	wire [BITS-1:0] tri_offset_eff = {2'b11, curr_params[15:8], {(BITS-2-8){1'b0}}};
	wire [3:0] slope_offset_0 = part ? curr_params[7:4] : curr_params[3:0];
	wire [BITS-3-1:0] slope_offset_eff = {slope_offset_0, {(BITS-3-4){1'b0}}};
`else
	wire [BITS-1:0] tri_offset_eff = tri_offset;
	wire [BITS-3-1:0] slope_offset_eff = slope_offset;
`endif


	reg [`REG_BITS-1:0] rdata; // not a register
	always_comb begin
		rdata = 'X;
		case (reg_raddr_p[5:2])
			0: rdata = curr_period;
			1: rdata = amp >> (BITS-2-6);
			2: rdata = channel_mode;
			3: rdata = curr_params;
			default: rdata = 'X;
		endcase
	end
	assign reg_rdata_p = rdata;


	wire [OCT_BITS-1:0] octave;
	wire [MANTISSA_BITS-1:0] mantissa;
	wire [BITS-2:0] mantissa_ext;
	assign {octave, mantissa} = curr_period;
	assign mantissa_ext = {mantissa, {((BITS-1) - MANTISSA_BITS){1'b0}}};


	reg [BITS-1:0] src1; // not a register
	always_comb begin
		case (src1_sel)
			`SRC1_SEL_PHASE: src1 = curr_phase;
			`SRC1_SEL_MANTISSA: src1 = mantissa_ext;
			`SRC1_SEL_TRI_OFFSET: src1 = tri_offset_eff;
			`SRC1_SEL_SLOPE_OFFSET: src1 = slope_offset_eff;
//			`SRC1_SEL_AMP, `SRC1_SEL_OUT_ACC, `SRC1_SEL_ZERO: src1 = amp; // Feed in amp also for `SRC1_SEL_OUT_ACC, to handle replace_src2_with_amp
			`SRC1_SEL_AMP: src1 = amp;
			default: src1 = 'X;
		endcase
	end

/*
	// Pipeline octave
	// TODO: Is this ok? Can we use a multicycle constraint instead?
	reg [OCT_BITS-1:0] octave_reg;
	always_ff @(posedge clk) octave_reg <= octave;
*/

	wire [`DEST_SEL_BITS-1:0] dest_sel;
	wire [BITS-1:0] result;
	pwls_ALU_unit #(
		.BITS(BITS), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS),
		.OUT_RSHIFT(OUT_RSHIFT), .OUT_ACC_FRAC_BITS(OUT_ACC_FRAC_BITS), .LFSR_HIGHEST_OCT(LFSR_HIGHEST_OCT),
		.OUT_ACC_INITIAL_TOP(OUT_ACC_INITIAL_TOP)
	) alu_unit(
		.clk(clk), .reset(reset), .en(en),
		.state(state), .first_term(term_index == '0), .next_sample(next_sample), .sub_channel(curr_sub_channel),
		.octave(octave),
		//.octave(octave_reg),
		.detune_exp(detune_exp), .slope_exp(slope_exp_eff), .channel_mode(channel_mode),
		.src1_sel_out(src1_sel), .part_out(part),
		.src1_external(src1), .phase_external(curr_phase), .amp_external(amp),
		.dest_sel_out(dest_sel), .result(result),
		.acc_out(acc_out), .out_acc_out(out_acc_out)
	);


	generate
		for (i = 0; i < NUM_CHANNELS; i++) begin
			always_ff @(posedge clk) begin
				if (reset) begin
					phases[i] <= 0;

/*
					periods[i] <= 0; // not needed?
					amps[i] <= 0; // silent
					modes[i] = 0; // turn off LFSR, detune
`ifdef USE_PARAMS_REGS
					params[i] = 0;
`endif
*/
				end else begin
					if (i == curr_channel && dest_sel == `DEST_SEL_PHASE && en) phases[i] <= result;

/*
					if (i == reg_waddr && reg_we) periods[i] <= reg_wdata;
					if (4+i == reg_waddr && reg_we) amps[i] <= reg_wdata;
					if (8+i == reg_waddr && reg_we) modes[i] <= reg_wdata;
`ifdef USE_PARAMS_REGS
					if (12+i == reg_waddr && reg_we) params[i] <= reg_wdata;
`endif
*/
				end
			end
		end
	endgenerate


// PWM output
// ==========
	localparam PWM_BITS = 7;

	reg [PWM_BITS-1:0] pwm_counter;

	// Stop when we reach pwm_counter = 1 << (PWM_BITS - 1), but not when it has a small negative value
	wire pwm_inc = !(pwm_counter[PWM_BITS-1] && !pwm_counter[PWM_BITS-2]);
	assign pwm_out = !pwm_inc;

	always @(posedge clk) begin
		if (sample_out_acc) pwm_counter <= out_acc_out[PWM_BITS+OUT_ACC_FRAC_BITS-1 -: PWM_BITS]; // sample_out_acc is low when en is
		else pwm_counter <= pwm_counter + pwm_inc; // TODO: should it be paused when en is low?
	end


// Additional outputs
// ==================

	assign phase_out = curr_phase;
	assign new_out_acc = (term_index == 0) && (state == 1); // should allow time for out_acc to be computed even with one cycle of pipelining

	assign term_index_out = term_index;
	assign state_out = state;

	assign tri_offset_eff_out = tri_offset_eff;
`ifdef USE_PARAMS_REGS
	assign curr_params_out = curr_params;
`else
	assign curr_params_out = 'Z;
`endif
endmodule : pwls_multichannel_ALU_unit
