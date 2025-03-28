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
		output	reg [31:0]	m_data,
		output	reg 		m_last
		// output wire		m_abort	// TX aborts
        // }}}
    );

    // FIS (Frame Information Structure) Types
    localparam [7:0] FIS_TYPE_REG_H2D  = 8'h27;  // Host to Device Register FIS
    localparam [7:0] FIS_TYPE_REG_D2H  = 8'h34;  // Device to Host Register FIS
    localparam [7:0] FIS_TYPE_DATA     = 8'h46;  // Data FIS
    localparam [7:0] FIS_TYPE_DMA_ACT  = 8'h39;  // DMA Activate FIS

    // ATA Commands
    localparam [7:0] CMD_READ_DMA      = 8'hC8;  // Read DMA
    localparam [7:0] CMD_WRITE_DMA     = 8'hCA;  // Write DMA

    // Storage & Buffer Parameters
    localparam BYTES_PER_SECTOR = 512;
    localparam MAX_STORAGE_SIZE  = 4096;      // Only 4KB of storage - enough for test cases

    localparam	[1:0]	FIRST	= 2'h0,
                        SECOND  = 2'h1,
                        THIRD   = 2'h2,
                        FOURTH	= 2'h3;

    localparam	[3:0]	IDLE		 = 4'h0,
                        D2H_REG_FIS  = 4'h1,
                        DMA_ACTIVATE = 4'h2,
                        DMA_WRITE	 = 4'h3,
                        DMA_READ	 = 4'h4;

	// Remember ... the SATA spec is listed with byte 0 in bits [7:0],
	// but we transmit big-endian, so byte 0 must be placed in the most
	// significant bits.  This will have the appearance of swapping byte
	// order in words.
	localparam [127:0] D2H_REG_FIS_RESPONSE = {
		// FIS TYPE (0x34) | RIRR,PMPORT | STATUS | ERROR
		{8'h34, 4'h0, 4'h0, 8'h77, 8'h00 },
		{8'h00, 24'h000000},		// DEVICE | LBA[23:0]
		{8'h00, 24'h000000},		// FEATURES[15:8] | LBA[47:24]
		{8'h00 ,8'h00, 16'h0000}	// CONTROL | ICC | COUNT[15:0]
	};

    reg [1:0] fis_state;
    reg [3:0] state;
    reg [2:0] cnt;
    reg [127:0] response;
    reg [31:0] sector_storage[0:MAX_STORAGE_SIZE-1];

    // Command processing state
    reg [7:0] current_command;   // Current ATA command being processed
    reg [47:0] current_lba;      // Current LBA for the command (28-bit)
    reg [15:0] current_count;     // Sector count for the command (8-bit)

    // DMA data transfer state
    reg fis_sent;             // Send first word for FIS data
    reg send_d2h_fis;         // Flag for Device to Host register
    reg incoming_data_fis;    // Flag for valid data FIS (H2D)
    reg send_data_fis;        // Flag for valid data FIS (D2H)
    reg dma_write_active;     // Flag for active DMA write operation
    reg dma_read_active;      // Flag for active DMA read operation
    reg send_dma_activate;    // Flag for active DMA Activate operation

    // Data FIS storage
    integer write_index;             // Current index in data FIS buffer
    integer read_index;              // Current index in data FIS buffer

    // Initialize storage
    integer i;
    initial begin
        for (i = 0; i < MAX_STORAGE_SIZE; i = i + 1) begin
            sector_storage[i] = 0;
        end
    end

    assign  s_full = 1'b0;
    assign  s_empty = 1'b0;

    // Process incoming FIS to detect commands and extract parameters
    always @(posedge i_tx_clk)
	begin
        if (i_reset) begin
            fis_state <= FIRST;
            incoming_data_fis <= 0;
            dma_write_active <= 0;
            dma_read_active <= 0;
            current_command <= 8'h00;
            current_lba <= 0;
            current_count <= 0;
        end
        else if (s_valid) begin
            case (fis_state)
                FIRST: begin
                    // Check if this is a Register FIS (Host to Device) containing a command
                    if (s_data[31:24] == FIS_TYPE_REG_H2D) begin
                        fis_state <= SECOND;
                        // Extract command from the register FIS
                        current_command <= s_data[15:8];

                        case(s_data[15:8])
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
                            dma_write_active <= 0;
                            dma_read_active <= 0;
                            end
                            // }}}
                        8'h20, 8'h24, 8'h2b, 8'h2f,
                        8'h5c, 8'hec: begin // PIO Read
                            // {{{
                            // Read sectors, Read sectors EXT,
                            // read stream ext, read log ext,
                            // trusted rcv, read buffer,
                            // identify device
                            dma_write_active <= 0;
                            dma_read_active <= 0;
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
                            dma_write_active <= 0;
                            dma_read_active <= 0;
                            end
                            // }}}
                        8'h25, 8'h2a, 8'hc8, 8'he9: begin // DMA read (from device)
                            // {{{
                            // Read DMA ext, read stream DMA ext,
                            // Read DMA, Read buffer DMA
                            dma_write_active <= 0;
                            dma_read_active <= 1;
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
                            dma_write_active <= 1;
                            dma_read_active <= 0;
                            write_index <= 0;
                            end
                        // }}}
                        default: begin
                            // 8'h4a?? ZAC management?
                            // 8'h5d?? Trusted receive data ? DMA
                            // 8'h5f?? Trusted send data ? DMA
                            // 8'h92?? Download microcode
                            // 8'h93?? Download microcode (DMA)
                            // 8'h4f?? ZAC management OUT (?)
                            dma_write_active <= 0;
                            dma_read_active <= 0;
                            end
                        endcase
                    end else if (s_data[31:24] == FIS_TYPE_DATA)
                        incoming_data_fis <= 1'b1;
                end
                SECOND: begin
                    fis_state <= THIRD;
                    // We'll get LBA and count in subsequent words of the FIS
                    if (current_command == CMD_WRITE_DMA || current_command == CMD_READ_DMA)
                        // For standard commands, extract bits 0-3 of device reg for upper LBA bits
                        current_lba[15:0] <= { s_data[23:16], s_data[31:24] };
                end
                THIRD: begin
                    fis_state <= FOURTH;
                end
                FOURTH: begin
                    fis_state <= FIRST;
                    current_count <= { s_data[23:16], s_data[31:24]};
                end
            endcase

            if (s_last) begin
                dma_read_active <= 0;
                incoming_data_fis <= 0;
                dma_write_active <= 0;
                write_index <= 0;
            end

            if (incoming_data_fis && write_index < BYTES_PER_SECTOR) begin
                // Store the data word in our buffer
                write_index <= write_index + 1;
                sector_storage[write_index] <= { s_data[7:0], s_data[15:8], s_data[23:16], s_data[31:24] };
                $display("SATA MODEL: Stored sector at LBA %h", write_index);

                // Check if we've received all expected data
                if (s_last) begin
                    $display("SATA MODEL: Write DMA complete, stored %d sectors", write_index);
                end
            end

        end
    end

    // cnt, response, send_dma_activate, send_data_fis
    always @(posedge i_tx_clk) begin
        if (i_reset) begin
            fis_sent <= 1'b0;
            send_d2h_fis <= 1'b0;
            send_data_fis <= 1'b0;
            send_dma_activate <= 1'b0;
            cnt <= 0;
            response <= D2H_REG_FIS_RESPONSE;
            read_index <= 0;
        end else if (s_valid && s_last && !s_abort) begin
            response <= D2H_REG_FIS_RESPONSE;

            if (!dma_write_active)
                send_d2h_fis <= 1'b1;
            else
                send_dma_activate <= 1'b1;

            if (dma_read_active) begin
                // Move to data FIS state
                send_data_fis <= 1'b1;
                $display("SATA MODEL: READ DMA detected, will send %0h sectors from LBA %0h",
                        current_count, current_lba);
            end
        end else if (m_ready && m_valid) begin
            if (send_d2h_fis && !send_dma_activate && !send_data_fis) begin
                if (dma_write_active) begin
                    // Send DMA Activate
                    send_dma_activate <= 1;
                    $display("SATA MODEL: Sending DMA Activate FIS for WRITE DMA");
                end else begin
                    if (cnt >= 4) begin
                        send_d2h_fis <= 1'b0;
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                response <= { response[95:0], 32'h0 };
            end else if (send_dma_activate && m_last) begin
                send_d2h_fis <= 1'b0;
                send_dma_activate <= 1'b0;
                cnt <= 0;
            end else if (send_data_fis) begin
                if (!fis_sent)
                    fis_sent <= 1'b1;
                else
                    read_index <= read_index + 1;

                if (m_last) begin
                    fis_sent <= 1'b0;
                    send_data_fis <= 1'b0;
                    read_index <= 0;
                end
            end
        end else begin
            cnt <= 0;
            response <= D2H_REG_FIS_RESPONSE;
        end
    end

    // m_valid
    always @(posedge i_tx_clk) begin
        if (i_reset)
            m_valid <= 1'b0;
        else if (m_valid && m_last)
            m_valid <= 1'b0;
        else if (send_d2h_fis || send_dma_activate || send_data_fis || incoming_data_fis)
            m_valid <= 1'b1;
    end

    // m_last
    always @(*) begin
        if (i_reset)
            m_last = 0;
        else if (m_valid && m_ready) begin
            if (send_d2h_fis && cnt == 4)
                m_last = 1'b1;
            else if (send_dma_activate)
                m_last = 1'b1;
            else if (send_data_fis && (read_index == (current_lba[23:2] - 1)))
                m_last = 1'b1;
        end else begin
            m_last = 1'b0;
        end
    end

    // m_data
    always @(*) begin
        if (i_reset)
            m_data = 0;
        else if (m_valid && !send_dma_activate && !send_data_fis)
            m_data = response[127:96];
        else if (send_dma_activate)
            m_data = { FIS_TYPE_DMA_ACT, 24'h0 };
        else if (send_data_fis)
            if (!fis_sent)
                m_data = { FIS_TYPE_DATA, 24'h0 };
            else
                m_data = sector_storage[read_index];
        else
            m_data = 32'h0;
    end

endmodule
