/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
// For pwls_channel_ALU_unit
module tt_um_tqv_peripheral_harness_ch #(parameter BITS=12, OCT_BITS=3) (
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // always 1 when the design is powered, so you can ignore it
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	wire [OCT_BITS-1:0] octave;
	wire [BITS-2:0] mantissa;
	wire [2:0] detune_exp;
	wire [3:0] slope_exp;

	reg [15:0] in;
	always @(posedge clk) in <= {uio_in, ui_in};

	assign {detune_exp, octave, mantissa} = {in, 2'b00};
	assign slope_exp = {in[0], detune_exp};

	wire [BITS-1:0] tri_offset = in >> 1;
	wire [BITS-1:0] slope_offset = in >> 2;
	wire [BITS-1:0] amp = in >> 3;

	wire [BITS-1:0] phase, acc;
	pwls_channel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS)) channel_alu_unit(
		.clk(clk), .reset(!rst_n),
		.mantissa(mantissa), .octave(octave),
		.detune_exp(detune_exp), .tri_offset(tri_offset), .slope_exp (slope_exp), .slope_offset(slope_offset), .amp(amp),
		.phase_out(phase), .acc_out(acc)
	);

	assign {uio_out, uo_out} = acc;
	assign uio_oe = 0;
endmodule : tt_um_tqv_peripheral_harness
*/

// For pwls_multichannel_ALU_unit
module tt_um_tqv_peripheral_harness #(parameter BITS=12, OCT_BITS=3) (
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // always 1 when the design is powered, so you can ignore it
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	wire [OCT_BITS-1:0] octave;
	wire [BITS-2:0] mantissa;
	wire [2:0] detune_exp;
	wire [3:0] slope_exp;

	reg [15:0] in;
	always @(posedge clk) in <= {uio_in, ui_in};

	assign {detune_exp, octave, mantissa} = {in, 2'b00};
	assign slope_exp = {in[0], detune_exp};

	wire [BITS-1:0] tri_offset = in >> 1;
	wire [BITS-1:0] slope_offset = in >> 2;
	wire [BITS-1:0] amp = in >> 3;

	wire [BITS-1:0] phase, out_acc;
	pwls_multichannel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS)) mc_alu_unit(
		.clk(clk), .reset(!rst_n),
		.reg_waddr(in), .reg_wdata(in), .reg_we(in[15]),
		.detune_exp(detune_exp), .tri_offset(tri_offset), .slope_exp (slope_exp), .slope_offset(slope_offset), .amp(amp),
		.phase_out(phase), .out_acc_out(out_acc)
	);

	assign {uio_out, uo_out} = out_acc;
	assign uio_oe = 0;
endmodule : tt_um_tqv_peripheral_harness
