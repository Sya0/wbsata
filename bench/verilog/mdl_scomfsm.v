////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/mdl_scomfsm.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Implements the SATA COM handshake, from the perspective of
//		the device.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2022-2025, Gisselquist Technology, LLC
// {{{
// This file is part of the WBSATA project.
//
// The WBSATA project is a free software (firmware) project: you may
// redistribute it and/or modify it under the terms of  the GNU General Public
// License as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  If not, please see <http://www.gnu.org/licenses/> for a
// copy.
// }}}
// License:	GPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/gpl.html
//
////////////////////////////////////////////////////////////////////////////////
//
`default_nettype	none
`timescale 1ns / 1ps
// }}}
module	mdl_scomfsm #(
		parameter realtime	CLOCK_SYM_NS = 1000.0 / 1500.0
	) (
		// {{{
		input	wire	i_txclk, i_reset,
		output	reg		o_reset,
		input	wire	i_comfinish,
		input	wire	i_cominit_det, i_comwake_det,
		input	wire	i_oob_done, i_link_layer_up,
		input	wire	i_rx_p, i_rx_n,
		input	wire	i_tx,
		output	wire	o_tx_p, o_tx_n
		// }}}
	);

	// Local decalarations
	// {{{
	localparam	[0:0]	OOB = 1'h0,
						ACTIVE_TRANSACTION = 1'h1;

	localparam P_BITS = 40;
    localparam [(P_BITS/4)-1:0] D21_4 = 10'b1010101101;
    localparam [(P_BITS/4)-1:0] K28_3 = 10'b0011110011;
    localparam [(P_BITS/4)-1:0] D21_5 = 10'b1010101010;

    localparam [P_BITS-1:0] SYNC_P = { D21_5, D21_5, D21_4, K28_3 };

	wire	oob_tx_p, oob_tx_n;
	reg	[0:0]	fsm_state;
	reg		r_tx, r_oob;
	wire	w_comwake, w_comreset;
	reg [39:0] oob_reg, link_reg;
	wire 	oob_sync_true, link_sync_true;
	wire	done;
	// }}}

	// OOB
	// {{{
	mdl_oob u_oob (
		.i_clk(i_txclk),
		.i_rst(i_reset),
    	.i_comfinish(i_comfinish),
		.i_comreset_det(w_comreset),
		.i_comwake_dev(w_comwake),
		.i_comwake_det(i_comwake_det),
		.i_oob_done(i_oob_done),
		.i_link_layer_up(i_link_layer_up),
		.o_done(done),
	    .o_tx_p(oob_tx_p),
        .o_tx_n(oob_tx_n)
    );
	// }}}

	mdl_srxcomsigs #(
		.OVERSAMPLE(4), .CLOCK_SYM_NS(CLOCK_SYM_NS)
	) u_comdet (
		.i_clk(i_txclk),
		.i_reset(i_reset),
		.i_rx_p(i_rx_p), .i_rx_n(i_rx_n),
		.i_cominit_det(i_cominit_det), .i_comwake_det(i_comwake_det),
		.o_comwake(w_comwake), .o_comreset(w_comreset)
	);

	always @(posedge i_txclk or i_reset)
	if (i_reset)
	begin
		fsm_state <= OOB;
		r_tx <= 1'bX;
		r_oob <= 1'b1;
		o_reset <= 1'b1;
	end else case(fsm_state)
		OOB: begin
		// {{{
			r_tx <= 1'bX;
			r_oob <= 1'b1;
			o_reset <= 1'b1;
			if (i_link_layer_up) begin
				fsm_state <= ACTIVE_TRANSACTION;
				r_tx <= i_tx;
				r_oob <= 1'b0;
				o_reset <= 1'b0;
			end
		end
		ACTIVE_TRANSACTION: begin
		// {{{
			r_tx <= i_tx;
			r_oob <= 1'b0;
			o_reset <= 1'b0;
		// }}}
		end
	endcase

	always @(posedge i_txclk or i_reset)
	if (i_reset) begin
		oob_reg <= 0;
		link_reg <= 0;	
	end else begin
		oob_reg <= { oob_reg[38:0], oob_tx_p };
		link_reg <= { link_reg[38:0], r_tx };
	end

	assign	oob_sync_true = (oob_reg == SYNC_P) ? 1 : 0;
	assign	link_sync_true = (link_reg == SYNC_P) ? 1 : 0;

	assign	o_tx_p = (r_oob) ? oob_tx_p :  r_tx;
	assign	o_tx_n = (r_oob) ? oob_tx_n : !r_tx;

endmodule
