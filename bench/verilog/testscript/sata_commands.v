////////////////////////////////////////////////////////////////////////////////
//
// Filename:	sata_commands.txt
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
`include "../testscript/satalib.v"

// Example timestamp value (48 bits)
localparam [47:0] TIMESTAMP = 48'h123456789ABC;  // Example timestamp in milliseconds

// Define DMA write test parameters
localparam [27:0] TEST_LBA = 28'h0000_100;       // Starting LBA for DMA write (sector 256)
localparam [7:0]  TEST_COUNT = 8'd1;             // Number of sectors to write

task testscript;
begin
	$display("Sending SET DATE & TIME EXT Command...");
	sata_set_time(TIMESTAMP);

	// Wait a bit before sending the next command
	#1000;
	
	$display("\n === Starting DMA WRITE/READ Test ===");
	test_dma_write_read(TEST_LBA, TEST_COUNT);

end endtask

