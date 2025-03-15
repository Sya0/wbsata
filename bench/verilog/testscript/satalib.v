////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/testscript/satalib.v
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	A library of functions to be used as helpers when writing
//		test scripts.
//
// Creator:
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025, Gisselquist Technology, LLC
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
// }}}
localparam	[ADDRESS_WIDTH-1:0]
                ADDR_CMD      = SATA_ADDR + 0,
                ADDR_LBALO    = SATA_ADDR + 4,
                ADDR_LBAHI    = SATA_ADDR + 8,
                ADDR_COUNT    = SATA_ADDR + 12,
                ADDR_LO       = SATA_ADDR + 24,
                ADDR_HI       = SATA_ADDR + 28,
                ADDR_SATAPHY  = DRP_ADDR + 0;

localparam [7:0] FIS_TYPE_REG_H2D  = 8'h27,	// Host to Device Register
		FIS_TYPE_REG_D2H  = 8'h34,	// Device to Host Register
		FIS_TYPE_DMA_ACT  = 8'h39,	// DMA Activate
		FIS_TYPE_PIO      = 8'h5F,	// PIO Setup
		FIS_TYPE_DATA     = 8'h46,	// Data FIS
		FIS_TYPE_BIST     = 8'h58,	// BIST Activate
		FIS_TYPE_SETBITS  = 8'hA1,	// Set Device Bits
		FIS_TYPE_VENDOR   = 8'hC7;	// Vendor Specific

localparam [7:0] CMD_SET_DATETIME = 8'h77;

task wait_response();
begin
	$display("Waiting for response...");
	// #10;  // Simülasyon için bekleme süresi
	wait(sata_int);
	$display("Response received.");
end endtask

task	sata_set_time(input [47:0] timestamp);
	reg	[31:0]	status;
begin
	u_bfm.writeio(ADDR_COUNT, 32'h0);
	u_bfm.writeio(ADDR_LBAHI, { 8'h0, timestamp[47:24] });
	u_bfm.writeio(ADDR_LBALO, { 8'h0, timestamp[23: 0] });
	u_bfm.writeio(ADDR_CMD,   { 8'h0, CMD_SET_DATETIME, 8'h80,
			FIS_TYPE_REG_H2D });

	wait(sata_int);
	u_bfm.readio(ADDR_CMD, status);

	if (status !== 32'h00_77_00_34)
	begin
		error_flag = 1'b1;
		$display("SET DATE & TIME EXT command failed with status 0x%08x", status);
	end
end endtask
