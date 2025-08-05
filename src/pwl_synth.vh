/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`define USE_SLOPE_EXP_REGS
`define USE_PARAMS_REGS

`define REGS_PER_CHANNEL 4

`ifdef USE_SLOPE_EXP_REGS
`define CHANNEL_MODE_BITS 12
`else
`define CHANNEL_MODE_BITS 4
`endif
// 0-2: detune_exp
`define CHANNEL_MODE_BIT_NOISE 3
// 4-7, 8-11: slope_exp


`define REG_BITS 16


`define SRC1_SEL_BITS 3
`define SRC1_SEL_PHASE        3'd0
`define SRC1_SEL_MANTISSA     3'd1
`define SRC1_SEL_TRI_OFFSET   3'd2
`define SRC1_SEL_SLOPE_OFFSET 3'd3
`define SRC1_SEL_AMP          3'd4
`define SRC1_SEL_OUT_ACC      3'd5
`define SRC1_SEL_ZERO         3'd6

`define SRC2_SEL_BITS 3
`define SRC2_SEL_ACC          3'd0
`define SRC2_SEL_REV_PHASE    3'd1
`define SRC2_SEL_PHASE_STEP   3'd2
`define SRC2_SEL_DETUNE       3'd3
`define SRC2_SEL_PHASE_MODIFIED 3'd4
`define SRC2_SEL_ZERO         3'd5

`define DEST_SEL_BITS 2
`define DEST_SEL_PHASE   2'd0
`define DEST_SEL_ACC     2'd1
`define DEST_SEL_OUT_ACC 2'd2
`define DEST_SEL_NOTHING 2'd3


`define STATE_CMP_REV_PHASE 0
`define STATE_UPDATE_PHASE 1
`define STATE_DETUNE 2
`define STATE_TRI 3
`define STATE_COMBINED_SLOPE_CMP 4
`define STATE_COMBINED_SLOPE_ADD 5
`define STATE_AMP_CMP 6
`define STATE_OUT_ACC 7
`define STATE_LAST 7
`define STATE_BITS ($clog2(`STATE_LAST + 1))


//`define PIPELINE

`ifdef PIPELINE // only applicable if PIPELINE enabled:
`define PIPELINE_SRC2
`define PIPELINE_SRC2_LSHIFT
`endif

`ifndef PURE_RTL
//`define NAMED_BUF_EN
`define USE_LATCHES
`endif
