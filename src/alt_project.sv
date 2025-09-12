/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "pwl_synth.vh"

/*
// For pwls_channel_ALU_unit
module tt_um_toivoh_pwl_synth_ch #(parameter BITS=12, OCT_BITS=3) (
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
endmodule : tt_um_toivoh_pwl_synth
*/

/*
// For pwls_multichannel_ALU_unit
module tt_um_toivoh_pwl_synth_mc #(parameter BITS=12, OCT_BITS=3) (
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
endmodule : tt_um_toivoh_pwl_synth
*/

// For GL test of tqvp_toivoh_pwl_synth
module tt_um_toivoh_pwl_synth #(parameter BITS_E=13) (
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // always 1 when the design is powered, so you can ignore it
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	localparam CMD_SET_ADDR = 4;
	localparam CMD_SET_DATA = 5;
	localparam CMD_WRITE = 6;
	localparam CMD_READ  = 7;

	wire [2:0] cmd;
	wire [12:0] wdata;
	assign {cmd, wdata} = {uio_in, ui_in};

	wire write_en = (cmd == CMD_WRITE);
	wire read_en  = (cmd == CMD_READ);

	wire [1:0] data_write_n = write_en ? 2'b10 : 2'b11;
	wire [1:0] data_read_n  = read_en  ? 2'b10 : 2'b11;

	reg write_en_prev;
	reg [5:0] address;
	reg [BITS_E-1:0] data_in;

	always_ff @(posedge clk) begin
		write_en_prev <= write_en;

		if (cmd == CMD_SET_ADDR) address <= wdata;
		if (cmd == CMD_SET_DATA) data_in <= wdata;
`ifdef USE_P_LATCHES_ONLY
		else if (write_en_prev) data_in <= 'X;
`else
		else data_in <= 'X;
`endif
	end

	wire [7:0] periph_uo_out;
	wire [BITS_E+`INTERFACE_REGISTER_SHIFT-1:0] data_out0;
	wire [BITS_E-1:0] data_out = data_out0 >> `INTERFACE_REGISTER_SHIFT;
	wire data_ready;

	tqvp_toivoh_pwl_synth dut(
		.clk(clk), .rst_n(rst_n),
		.ui_in('X), .uo_out(periph_uo_out),
		.address(address), .data_in({data_in, {`INTERFACE_REGISTER_SHIFT{1'b0}}}), .data_write_n(data_write_n), .data_read_n(data_read_n),
		.data_out(data_out0), .data_ready(data_ready)
	);

	assign uo_out = periph_uo_out;
	assign {uio_oe, uio_out} = {data_ready, data_out};
endmodule : tt_um_toivoh_pwl_synth
