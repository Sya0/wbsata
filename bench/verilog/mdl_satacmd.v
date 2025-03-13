////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/verilog/mdl_satacmd.v
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
`timescale 1ns / 1ps
`default_nettype none
// }}}
module mdl_satacmd (
        // {{{
		input	wire		i_tx_clk, i_phy_clk,
		input	wire		i_reset, i_phy_reset,
		input	wire		s_valid,
		// output wire		s_ready,
		output	wire		s_full,	// Will take some time to act
		output	wire		s_empty,
		input	wire [31:0]	s_data,
		input	wire		s_last,
		input	wire		s_abort,
		//
		output	reg		    m_valid,
		input	wire		m_ready,
		output	wire [31:0]	m_data,
		output	wire		m_last
		// output wire		m_abort	// TX aborts
        // }}}
    );

    localparam [127:0] COMMAND_RESPOND = {
        {8'h00, 8'h77, 4'h0, 4'h0, 8'h27},      // ERROR | STATUS | RIRR | PMPORT | FIS TYPE (0x34)
        {8'h00, 24'h000000},                    // DEVICE | LBA[23:0]
        {8'h00, 24'h000000},                    // FEATURES[15:8] | LBA[47:24]
        {8'h00 ,8'h00, 16'h0000}                // CONTROL | ICC | COUNT[15:0]
    };

    // request signals
    reg     known_cmd;
    wire     req_rd_en;
    wire [31:0] req_rd_data;

    // respond signals
    reg [127:0] respond;

    reg     res_wr_en;
    wire    res_wr_full;
    wire [31:0] res_wr_data;

    wire    res_rd_last, res_rd_empty;
    wire [31:0] res_rd_data;

    // Move the FIS data to the PHY clock
	// {{{
	afifo #(
		.WIDTH(32), .LGFIFO(4)
    ) u_req_afifo (
		.i_wclk(i_tx_clk), .i_wr_reset_n(!i_reset),
		.i_wr(s_valid), .i_wr_data(s_data),
		.o_wr_full(s_full),
		//
		.i_rclk(i_phy_clk), .i_rd_reset_n(!i_phy_reset),    // !!!
		.i_rd(req_rd_en), .o_rd_data(req_rd_data),
		.o_rd_empty(s_empty)
	);
    // }}}

    assign  req_rd_en = 1'b1;

    always @(posedge i_phy_clk)
	begin
        case(req_rd_data[23:16])
        8'h00, 8'h0b, 8'h40, 8'h42, 8'h44, 8'h45, 8'h51, 8'h63,
        8'h77, 8'h78, 8'hb0, 8'hb2, 8'hb4,
        8'he0, 8'he1, 8'he2, 8'he3, 8'he5, 8'he6, 8'he7, 8'hea,
        8'hef, 8'hf5: begin // Non-Data
            // {{{
                // NOOP, request sense data
                // Read verify sectors
                // Read verify sectors (EXT)
                // Zero EXT
                // Write uncorrectable EXT
                // Configure stream
                // NCQ data
                // Set date & time,
                // max address configuration
                // SMART, set secto config,
                // sanitize device
                // Standby immediate, idle immediate,
                // standby, idle, check power, sleep
                // Flush cache, flush cache ext
                // Set features, Security freeze lock
            known_cmd <= 1;
            end
            // }}}
        8'h20, 8'h24, 8'h2b, 8'h2f,
        8'h5c, 8'hec: begin // PIO Read
            // {{{
                // Read sectors, Read sectors EXT,
                // read stream ext, read log ext,
                // trusted rcv, read buffer,
                // identify device
            known_cmd <= 1;
            end
            // }}}
        8'h30, 8'h34, 8'h3b, 8'h3f, 8'h5e, 8'he8,
        8'hf1, 8'hf2, 8'hf4, 8'hf6: begin // PIO Write
            // {{{
                // Write sector(s) (ext),
                // write stream (ext), write log ext,
                // trusted send, write buffer,
                // security set password,
                // security unlock,
                // security erase unit,
                // security disable passwrd
            known_cmd <= 1;
            end
            // }}}
        8'h25, 8'h2a, 8'hc8, 8'he9: begin // DMA read (from device)
            // {{{
                // Read DMA ext, read stream DMA ext,
                // Read DMA, Read buffer DMA
            known_cmd <= 1;
            end
            // }}}
        8'h06, 8'h07, 8'h35, 8'h3a, 8'h3d, 8'h57, 8'hca,
        8'heb: begin // DMA write (to device)
            // {{{
                // Data set management,
                // data set mgt DMA,
                // Write DMA ext, write DMA stream Ext,
                // Write DMA FUA EXT, Write DMA,
                // write buffer DMA
            known_cmd <= 1;
            end
        // }}}
        default: begin
            // 8'h4a?? ZAC management?
            // 8'h5d?? Trusted receive data ? DMA
            // 8'h5f?? Trusted send data ? DMA
            // 8'h92?? Download microcode
            // 8'h93?? Download microcode (DMA)
            // 8'h4f?? ZAC management OUT (?)
            known_cmd <= 0;
            end
        endcase
    end

    // Move the RESPOND data to the PHY clock
	// {{{
	afifo #(
		.WIDTH(32), .LGFIFO(4)
	) u_res_afifo (
		.i_wclk(i_tx_clk), .i_wr_reset_n(!i_reset),
		.i_wr(res_wr_en), .i_wr_data(res_wr_data),
		.o_wr_full(res_wr_full),
		//
		.i_rclk(i_phy_clk), .i_rd_reset_n(!i_phy_reset),    // !!!
		.i_rd(m_ready), .o_rd_data(m_data),
		.o_rd_empty(res_rd_empty)
	);
    // }}}

    // res_wr_en
    always @(posedge i_tx_clk) begin
        if (i_reset)
            res_wr_en <= 1'b0;
        else if (s_valid && s_last && !s_abort)
            res_wr_en <= 1'b1;
        else if (res_wr_full)
            res_wr_en <= 1'b0;
    end

    // res_wr_data, respond
    always @(posedge i_tx_clk) begin
        if (res_wr_en)
            respond <= { 32'h0, COMMAND_RESPOND[127:32] };
        else
            respond <= COMMAND_RESPOND;
    end
    assign res_wr_data = res_wr_en ? respond[31:0] : 32'h0;

    // m_valid
    always @(posedge i_phy_clk || i_phy_reset) begin
        if (i_phy_reset)
            m_valid <= 1'b0;
        else if (!res_rd_empty)
            m_valid <= 1'b1;
    end

    // m_last
    assign  m_last = res_rd_empty;
    
endmodule
