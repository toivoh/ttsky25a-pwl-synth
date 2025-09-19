`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb.vcd");
		$dumpvars(0, tb);
		#1;
	end

	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	reg ena;
	reg [7:0] ui_in;
	reg [7:0] uio_in;
	wire [7:0] uo_out;
	wire [7:0] uio_out;
	wire [7:0] uio_oe;
`ifdef GL_TEST
	wire VPWR = 1'b1;
	wire VGND = 1'b0;
`endif

	tt_um_tqv_peripheral_harness test_harness (

		// Include power ports for the Gate Level test:
`ifdef GL_TEST
		.VPWR(VPWR),
		.VGND(VGND),
`endif

		.ui_in  (ui_in),    // Dedicated inputs
		.uo_out (uo_out),   // Dedicated outputs
		.uio_in (uio_in),   // IOs: Input path
		.uio_out(uio_out),  // IOs: Output path
		.uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
		.ena    (ena),      // enable - goes high when design is selected
		.clk    (clk),      // clock
		.rst_n  (rst_n)     // not reset
	);

`ifndef GL_TEST
	wire [12:0] period0 = test_harness.user_peripheral.mc_alu_unit.periods[0];
	wire [12:0] period1 = test_harness.user_peripheral.mc_alu_unit.periods[1];
	wire [12:0] period2 = test_harness.user_peripheral.mc_alu_unit.periods[2];
	wire [12:0] period3 = test_harness.user_peripheral.mc_alu_unit.periods[3];

	wire [5:0] amp0 = test_harness.user_peripheral.mc_alu_unit.amps[0];
	wire [5:0] amp1 = test_harness.user_peripheral.mc_alu_unit.amps[1];
	wire [5:0] amp2 = test_harness.user_peripheral.mc_alu_unit.amps[2];
	wire [5:0] amp3 = test_harness.user_peripheral.mc_alu_unit.amps[3];

	wire [7:0] pwm_offset0 = test_harness.user_peripheral.mc_alu_unit.pwm_offsets[0];
	wire [7:0] pwm_offset1 = test_harness.user_peripheral.mc_alu_unit.pwm_offsets[1];
	wire [7:0] pwm_offset2 = test_harness.user_peripheral.mc_alu_unit.pwm_offsets[2];
	wire [7:0] pwm_offset3 = test_harness.user_peripheral.mc_alu_unit.pwm_offsets[3];

	wire [7:0] slope0_0 = test_harness.user_peripheral.mc_alu_unit.slopes0[0];
	wire [7:0] slope0_1 = test_harness.user_peripheral.mc_alu_unit.slopes0[1];
	wire [7:0] slope0_2 = test_harness.user_peripheral.mc_alu_unit.slopes0[2];
	wire [7:0] slope0_3 = test_harness.user_peripheral.mc_alu_unit.slopes0[3];

	wire [7:0] slope1_0 = test_harness.user_peripheral.mc_alu_unit.slopes1[0];
	wire [7:0] slope1_1 = test_harness.user_peripheral.mc_alu_unit.slopes1[1];
	wire [7:0] slope1_2 = test_harness.user_peripheral.mc_alu_unit.slopes1[2];
	wire [7:0] slope1_3 = test_harness.user_peripheral.mc_alu_unit.slopes1[3];

	wire [15:0] sweep0_0 = test_harness.user_peripheral.mc_alu_unit.sweeps0[0];
	wire [15:0] sweep0_1 = test_harness.user_peripheral.mc_alu_unit.sweeps0[1];
	wire [15:0] sweep0_2 = test_harness.user_peripheral.mc_alu_unit.sweeps0[2];
	wire [15:0] sweep0_3 = test_harness.user_peripheral.mc_alu_unit.sweeps0[3];

	wire [15:0] sweep1_0 = test_harness.user_peripheral.mc_alu_unit.sweeps1[0];
	wire [15:0] sweep1_1 = test_harness.user_peripheral.mc_alu_unit.sweeps1[1];
	wire [15:0] sweep1_2 = test_harness.user_peripheral.mc_alu_unit.sweeps1[2];
	wire [15:0] sweep1_3 = test_harness.user_peripheral.mc_alu_unit.sweeps1[3];

	wire [15:0] mode0 = test_harness.user_peripheral.mc_alu_unit.modes[0];
	wire [15:0] mode1 = test_harness.user_peripheral.mc_alu_unit.modes[1];
	wire [15:0] mode2 = test_harness.user_peripheral.mc_alu_unit.modes[2];
	wire [15:0] mode3 = test_harness.user_peripheral.mc_alu_unit.modes[3];
`endif

	int counter = 0;
	always_ff @(posedge clk) counter <= counter + 1;
endmodule
