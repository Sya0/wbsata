`timescale 1ns / 1ps

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

    reg     known_cmd;
    reg [2:0] cnt;
    reg [127:0] respond;

    reg     res_wr_en;
    wire    res_wr_full;
    wire [31:0] res_wr_data;

    wire    res_rd_last, res_rd_empty, res_rd_en;
    wire [31:0] res_rd_data;

    assign  s_full = 1'b0;
    assign  s_empty = 1'b0;

    always @(posedge i_tx_clk)
	begin
        if (s_valid) begin
            case(s_data[23:16])
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
    end

    // Move the RESPOND data to the PHY clock
	// {{{
	// afifo #(
	// 	.WIDTH(32), .LGFIFO(4)
	// ) u_res_afifo (
	// 	.i_wclk(i_tx_clk), .i_wr_reset_n(!i_reset),
	// 	.i_wr(res_wr_en), .i_wr_data(res_wr_data),
	// 	.o_wr_full(res_wr_full),
	// 	//
	// 	.i_rclk(i_phy_clk), .i_rd_reset_n(!i_phy_reset),    // !!!
	// 	.i_rd(res_rd_en), .o_rd_data(m_data),
	// 	.o_rd_empty(res_rd_empty)
	// );
    // }}}

    // m_valid
    always @(posedge i_tx_clk) begin
        if (i_reset)
            m_valid <= 1'b0;
        else if (s_valid && s_last && !s_abort)
            m_valid <= 1'b1;
        else if (m_valid && m_last)
            m_valid <= 1'b0;
    end

    // m_last, cnt, m_data, respond
    always @(posedge i_tx_clk) begin
        if (i_reset)
            cnt <= 0;
        else if (s_valid && s_last && !s_abort) begin
            cnt <= 1;
            respond <= COMMAND_RESPOND;
        end else if (cnt > 0) begin
            if (m_ready) begin
                cnt <= cnt + 1;
                if (cnt >= 4)
                    cnt <= 0;
                respond <= { COMMAND_RESPOND[95:0], 32'h0 };
            end
        end else begin
            cnt <= 0;
            respond <= COMMAND_RESPOND;
        end
    end
    assign  m_last = (cnt == 4) ? 1'b1 : 1'b0;
    assign  m_data = m_valid ? respond[127:96] : 32'h0;

endmodule
