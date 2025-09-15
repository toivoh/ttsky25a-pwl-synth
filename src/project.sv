/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "pwl_synth.vh"

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

	wire [7:0] user_data_in = ui_in;
	wire read_sel = uio_in[4];
	wire [3:0] cmd0 = uio_in[3:0];

	reg [3:0] cmd1, cmd2, cmd3;
	always_ff @(posedge clk) begin
		if (!rst_n) begin
			cmd1 <= '1;
			cmd2 <= '1;
			cmd3 <= '1;
		end else begin
			cmd3 <= cmd2;
			cmd2 <= cmd1;
			cmd1 <= cmd0;
		end
	end

	wire [3:0] cmd = cmd2 & ~cmd3;

	wire cmd_read, cmd_write, cmd_data_high, cmd_data_low;
	assign {cmd_read, cmd_write, cmd_data_high, cmd_data_low} = cmd;



	reg [15:0] rdata, wdata0, wdata;
	reg [7:0] address;
	reg waiting_for_read;
	reg write_pending;

	wire data_ready;
	wire [31:0] data_out;
	wire reg_we_internal;

	always_ff @(posedge clk) begin
		if (!rst_n) begin
			address <= '0;
			wdata0 <= '0;
			wdata <= '0;
			rdata <= '0;
			waiting_for_read <= 0;
			write_pending <= 0;
		end else begin
			if (cmd_read || cmd_write) address <= user_data_in;
			if (cmd_data_low) wdata0[7:0] <= user_data_in;
			if (cmd_data_high) wdata0[15:8] <= user_data_in;
			if (cmd_write) wdata <= wdata0;

			if (cmd_read) waiting_for_read <= 1;
			else if (data_ready) waiting_for_read <= 0;

			write_pending <= cmd_write || (reg_we_internal && write_pending);

			if (waiting_for_read && data_ready) rdata <= data_out[15:0];
		end
	end

	wire do_write = write_pending && !reg_we_internal;
	wire [1:0] data_write_n = do_write ? 3'b10 : 3'b11;
	wire [1:0] data_read_n  = waiting_for_read ? 3'b10 : 3'b11;

	wire [7:0] synth_uo_out;
	tqvp_toivoh_pwl_synth user_peripheral(
		.clk(clk), .rst_n(rst_n),

		.address(address), .data_in(wdata), .data_write_n(data_write_n), .data_read_n(data_read_n), .ui_in(0),
		.uo_out(synth_uo_out), .data_out(data_out), .data_ready(data_ready), .reg_we_internal(reg_we_internal)
	);

	assign uo_out = read_sel ? rdata[15:8] : rdata[7:0];
	assign uio_out = {synth_uo_out[7:6], waiting_for_read, 5'd0};
	assign uio_oe = 8'b11100000;
endmodule : tt_um_toivoh_pwl_synth
