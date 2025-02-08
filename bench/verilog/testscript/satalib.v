////////////////////////////////////////////////////////////////////////////////
//
// Filename:
// {{{
// Project:
//
// Purpose:
//
// Creator:
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025-present, Gisselquist Technology, LLC
// {{{
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
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

localparam [7:0] FIS_TYPE_REG_H2D  = 8'h27;  // Host to Device Register
localparam [7:0] FIS_TYPE_REG_D2H  = 8'h34;  // Device to Host Register
localparam [7:0] FIS_TYPE_DMA_ACT  = 8'h39;  // DMA Activate
localparam [7:0] FIS_TYPE_PIO      = 8'h5F;  // PIO Setup
localparam [7:0] FIS_TYPE_DATA     = 8'h46;  // Data FIS
localparam [7:0] FIS_TYPE_BIST     = 8'h58;  // BIST Activate
localparam [7:0] FIS_TYPE_SETBITS  = 8'hA1;  // Set Device Bits
localparam [7:0] FIS_TYPE_VENDOR   = 8'hC7;  // Vendor Specific

task send_sata_command(input [7:0] command);
    begin
        $display("Sending SATA command: %h", command);
        // Burada komut gönderim mantığı implement edilir
    end
endtask

task send_data(input [31:0] data);
    begin
        $display("Sending data: %h", data);
        // Burada veri gönderim mantığı implement edilir
    end
endtask

task receive_data(output [31:0] data);
    begin
        $display("Receiving data...");
        // Burada veri alma mantığı implement edilir
        data = 32'hDEADBEEF; // Simülasyon için örnek veri
    end
endtask

task wait_response();
    begin
        $display("Waiting for response...");
        #10;  // Simülasyon için bekleme süresi
        $display("Response received.");
    end
endtask
