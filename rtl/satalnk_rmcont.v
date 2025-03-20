////////////////////////////////////////////////////////////////////////////////
//
// Filename:	rtl/satalnk_rmcont.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2021-2025, Gisselquist Technology, LLC
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
`default_nettype none
`timescale	1ns/1ps
// }}}
module	satalnk_rmcont (
		// {{{
		input	wire		i_clk, i_reset,
		//
		input	wire		i_valid,
					i_primitive,
		input	wire	[31:0]	i_data,
		//
		output	reg		o_valid,
					o_primitive,
		output	reg	[31:0]	o_data
		// }}}
	);

	// Local declarations
	// {{{
`include "sata_primitives.vh"
	reg		r_active; // r_align;
	reg	[31:0]	r_last;
	// }}}

	always @(posedge i_clk)
	begin
		o_valid     <= i_valid;
		o_primitive <= r_active || i_primitive;
		o_data      <= i_data;

		if (i_valid && { i_primitive, i_data } == P_ALIGN)
			o_valid <= 0;
		if (i_valid && !i_primitive && r_active)
			o_valid <= 0;

		if (i_valid && i_primitive)
		begin
			r_active <= 1'b0;
			if (i_data[31:0] == P_CONT[31:0]) begin
				r_active <= 1'b1;
				o_data 	 <= r_last;
				o_valid	 <= 1'b0;
			end else begin
				r_last   <= i_data;
				// r_align  <= (i_data == P_ALIGN[31:0]);
				r_active <= 1'b0;
				// Always pass primitives forward
				o_data 	 <= i_data;
			end
		end else if (i_valid && r_active)
		begin
			// On any data, while P_CONT is active, repeat the
			// last primitive -- save that we'll drop o_valid,
			// to make it easier to cross clock domains
			o_data <= r_last;
		end

		if (i_reset)
		begin
			r_active <= 0;
			o_valid  <= 0;
		end
	end
endmodule
