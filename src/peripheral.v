/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "pwl_synth.vh"

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_toivoh_pwl_synth #(parameter BITS=12, OCT_BITS=3, DETUNE_EXP_BITS=3, SLOPE_EXP_BITS=4, NUM_CHANNELS=4) (
		input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
		input         rst_n,        // Reset_n - low to reset.

		input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
		                            // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

		output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
		                            // Note that uo_out[0] is normally used for UART TX.

		input [5:0]   address,      // Address within this peripheral's address space
		input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

		// Data read and write requests from the TinyQV core.
		input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
		input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

		output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
		output        data_ready,

		output        user_interrupt  // Dedicated interrupt request for this peripheral
	);

	wire reset = !rst_n;

	// Temporary cfg register for shared parameters
	reg [31:0] cfg;
	always @(posedge clk) begin
		if (data_write_n == 2'b10 && address == 60) cfg <= data_in;
	end

	wire [DETUNE_EXP_BITS-1:0] detune_exp;
	wire [BITS-1:0] tri_offset;
	wire [SLOPE_EXP_BITS-1:0] slope_exp;
	wire [BITS-3-1:0] slope_offset;
	wire [BITS-2-1:0] amp;

	assign {detune_exp, tri_offset[BITS-1 -: 10], slope_exp, slope_offset[BITS-3-1 -: 5], amp[BITS-2-1 -: 6]} = cfg;
	assign tri_offset[BITS-10-1:0] = '0;
	assign slope_offset[BITS-3-5-1:0] = '0;
	assign amp[BITS-2-6-1:0] = '0;


	// Read / write interface to pwls_multichannel_ALU_unit
	wire [$clog2(`REGS_PER_CHANNEL)+$clog2(NUM_CHANNELS)-1:0] reg_addr = address[5:1];
	//wire read_en = (data_read_n != 2'b11);

	reg read_en;
	//reg [5:0] reg_raddr;
	wire [5:0] reg_raddr = reg_addr;
	always_ff @(posedge clk) begin
		if (reset) read_en <= 0;
		else read_en <= (data_read_n != 2'b11);
		//reg_raddr <= reg_addr;
	end

	wire reg_we = (data_write_n == 2'b01) && (address[5] == 0); // Accept only 16 bit writes for now
	wire [`REG_BITS-1:0] reg_wdata = data_in;



	wire [BITS-1:0] out_acc;
	wire [`REG_BITS-1:0] reg_rdata;
	wire pwm_out;
	pwls_multichannel_ALU_unit #(.BITS(BITS), .OCT_BITS(OCT_BITS), .DETUNE_EXP_BITS(DETUNE_EXP_BITS), .SLOPE_EXP_BITS(SLOPE_EXP_BITS), .NUM_CHANNELS(NUM_CHANNELS)) mc_alu_unit(
		.clk(clk), .reset(reset), .en(!read_en),
		.reg_waddr(reg_addr), .reg_wdata(reg_wdata), .reg_we(reg_we),
		.reg_raddr_p(reg_raddr), .reg_rdata_p(reg_rdata),
		//.detune_exp(detune_exp),
		.tri_offset(tri_offset), .slope_exp (slope_exp), .slope_offset(slope_offset), //.amp(amp),
		.out_acc_out(out_acc), .pwm_out(pwm_out)
	);

	//assign uo_out = out_acc >> (BITS-8);
	assign uo_out = pwm_out ? '1 : 0;

	assign data_out = reg_rdata;
	assign data_ready = read_en;
	assign user_interrupt = 1'b0;
endmodule
