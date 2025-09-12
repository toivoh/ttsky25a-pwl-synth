/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module compare_top(
		input wire clk, rst_n,

		input wire [2:0] cmd_in,
		input wire [12:0] wdata_in,

		output wire [7:0] uo_out,
		output wire [12:0] data_out,
		output wire data_ready
	);

	reg [2:0] cmd;
	reg [12:0] wdata;
	always_ff @(posedge clk) begin
		if (!rst_n) cmd <= 0;
		else begin
			cmd <= cmd_in;
			wdata <= wdata_in;
		end
	end

	wire [7:0] ui_in;
	wire [7:0] uio_in;
	assign {uio_in, ui_in} = {cmd, wdata};

	wire [7:0] uio_out;
	wire [7:0] uio_oe;
	tt_um_toivoh_pwl_synth wrapper(
		.clk(clk), .rst_n(rst_n),
		.ui_in(ui_in), .uio_in(uio_in),
		.uo_out(uo_out), .uio_out(uio_out), .uio_oe(uio_oe)
	);

	assign {data_ready, data_out} = {uio_oe, uio_out};
endmodule : compare_top
