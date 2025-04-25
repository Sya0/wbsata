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
    localparam MAX_STORAGE_SIZE  = 4096;      // Only 4KB of storage - enough for test cases
    localparam SECTOR_SIZE       = 16;        // Tiny 16-byte sectors for simulation speed
    localparam MAX_DATA_FIS_SIZE = SECTOR_SIZE/4;  // Size of Data FIS buffer in 32-bit words

    // Device Register Bit Definitions
    localparam DEVICE_LBA_MODE  = 8'h40;        // Bit 6 set for LBA mode in device register

	// Remember ... the SATA spec is listed with byte 0 in bits [7:0],
	// but we transmit big-endian, so byte 0 must be placed in the most
	// significant bits.  This will have the appearance of swapping byte
	// order in words.
	localparam [127:0] COMMAND_RESPONSE = {
		// FIS TYPE (0x34) | RIRR,PMPORT | STATUS | ERROR
		{8'h34, 4'h0, 4'h0, 8'h77, 8'h00 },
		{8'h00, 24'h000000},		// DEVICE | LBA[23:0]
		{8'h00, 24'h000000},		// FEATURES[15:8] | LBA[47:24]
		{8'h00 ,8'h00, 16'h0000}	// CONTROL | ICC | COUNT[15:0]
	};

    reg     known_cmd;
    reg [2:0] cnt;
    reg [127:0] response;
    reg [7:0] sector_storage[0:MAX_STORAGE_SIZE-1];

    // Command processing state
    reg [7:0] current_command;   // Current ATA command being processed
    reg [27:0] current_lba;      // Current LBA for the command (28-bit)
    reg [7:0] current_count;     // Sector count for the command (8-bit)

    // DMA data transfer state
    reg dma_write_active;        // Flag for active DMA write operation
    reg dma_read_active;         // Flag for active DMA read operation
    reg sending_dma_activate;    // Flag for active DMA Activate operation
    reg [31:0] dma_word_counter; // Count bytes received/sent in current DMA transfer
    reg [31:0] dma_sector_bytes; // Total bytes to transfer in current operation

    // Data FIS storage
    reg [31:0] data_fis_buffer[0:MAX_DATA_FIS_SIZE-1];  // Buffer for one Data FIS (up to 2KB)
    integer data_fis_index;             // Current index in data FIS buffer
    integer byte_offset;
    integer sector_offset;
    integer word_idx;                

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
            known_cmd <= 0;
            dma_write_active <= 0;
            dma_read_active <= 0;
            current_command <= 8'h00;
        end
        else if (s_valid) begin
            // Check if this is a Register FIS (Host to Device) containing a command
            if (s_data[31:24] == FIS_TYPE_REG_H2D) begin
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
                    known_cmd <= 1;
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
                    known_cmd <= 1;
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
                    known_cmd <= 1;
                    dma_write_active <= 0;
                    dma_read_active <= 0;
                    end
                    // }}}
                8'h25, 8'h2a, CMD_READ_DMA, 8'he9: begin // DMA read (from device)
                    // {{{
                    // Read DMA ext, read stream DMA ext,
                    // Read DMA, Read buffer DMA
                    known_cmd <= 1;
                    dma_write_active <= 0;
                    dma_read_active <= 1;

                    // For standard READ DMA (0xC8), this is the first word
                    // We'll get LBA and count in subsequent words
                    if (s_data[15:8] == CMD_READ_DMA) begin
                        // For standard commands, extract bits 0-3 of device reg for upper LBA bits
                        current_lba[27:24] <= s_data[23:16] & 4'hF;
                    end
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
                    dma_write_active <= 1;
                    dma_read_active <= 0;
                    data_fis_index <= 0;

                    // For standard WRITE DMA (0xCA), this is the first word
                    // We'll get LBA and count in subsequent words of the FIS
                    if (s_data[15:8] == CMD_WRITE_DMA) begin
                        // For standard commands, extract bits 0-3 of device reg for upper LBA bits
                        current_lba[27:24] <= s_data[23:16] & 4'hF;
                    end
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
                    dma_write_active <= 0;
                    dma_read_active <= 0;
                    end
                endcase
            end

            if (dma_write_active && s_data[31:24] == FIS_TYPE_DATA) begin // DATA FIS
                data_fis_index <= 0;
                $display("SATA MODEL: Receiving DATA FIS for Write DMA");
            end else if (dma_write_active && data_fis_index < MAX_DATA_FIS_SIZE) begin
                // Store the data word in our buffer
                data_fis_buffer[data_fis_index] <= s_data;
                data_fis_index <= data_fis_index + 1;
                dma_word_counter <= dma_word_counter + 4; // 4 bytes per word

                // Check if we've received a complete sector
                if ((dma_word_counter + 4) % SECTOR_SIZE == 0) begin
                    // Calculate which sector this is within the transfer
                    sector_offset = dma_word_counter / SECTOR_SIZE;

                    // Store the sector - copy from buffer to our storage
                    // We need to unpack the 32-bit words into bytes
                    for (word_idx = 0; word_idx < SECTOR_SIZE/4; word_idx = word_idx + 1) begin
                        byte_offset = word_idx * 4;
                        // Store byte by byte in big endian order
                        sector_storage[(current_lba + sector_offset) * SECTOR_SIZE + byte_offset]     = data_fis_buffer[word_idx][31:24];
                        sector_storage[(current_lba + sector_offset) * SECTOR_SIZE + byte_offset + 1] = data_fis_buffer[word_idx][23:16];
                        sector_storage[(current_lba + sector_offset) * SECTOR_SIZE + byte_offset + 2] = data_fis_buffer[word_idx][15:8];
                        sector_storage[(current_lba + sector_offset) * SECTOR_SIZE + byte_offset + 3] = data_fis_buffer[word_idx][7:0];
                    end

                    $display("SATA MODEL: Stored sector at LBA %h", current_lba + sector_offset);
                end

                // Check if we've received all expected data
                if (dma_word_counter >= dma_sector_bytes) begin
                    dma_write_active <= 0;
                    $display("SATA MODEL: Write DMA complete, stored %d sectors", current_count);
                end
            end

            // if (s_last) begin
            //     // Reset FIS processing state for the next FIS
            //     if (dma_write_active && s_data[31:24] == FIS_TYPE_DATA) begin
            //         // The last word wasn't part of a Data FIS, so this is end of command
            //         dma_write_active <= 0;
            //     end
            // end
        end
    end

    // m_valid
    always @(posedge i_tx_clk) begin
        if (i_reset)
            m_valid <= 1'b0;
        else if (s_valid && s_last && !s_abort)
            m_valid <= 1'b1;
        else if (m_valid && m_last)
            m_valid <= 1'b0;
        else if (sending_dma_activate)
            m_valid <= 1'b1;
    end

    // cnt, response, sending_dma_activate
    always @(posedge i_tx_clk) begin
        if (i_reset) begin
            sending_dma_activate <= 1'b0;
            cnt <= 0;
            response <= COMMAND_RESPONSE;
        end else if (s_valid && s_last && !s_abort) begin
            cnt <= 1;
            response <= COMMAND_RESPONSE;
        end else if (cnt > 0 && !sending_dma_activate) begin
            if (m_ready) begin
                cnt <= cnt + 1;
                if (cnt >= 4) begin
                    // if (current_command == CMD_READ_DMA && dma_read_active) begin
                    //     // Move to data FIS state
                    //     dma_read_active <= 0;
                    //     $display("SATA MODEL: READ DMA complete, would send %d sectors from LBA %h",
                    //             current_count, current_lba);
                    // end
                    
                    if (dma_write_active) begin
                        // We've finished sending Register FIS, now send DMA Activate
                        sending_dma_activate <= 1;
                        $display("SATA MODEL: Sending DMA Activate FIS for WRITE DMA");
                    end else begin
                        cnt <= 0;
                    end
                end
                response <= { response[95:0], 32'h0 };
            end
        end else if (sending_dma_activate && m_valid && m_last) begin
            sending_dma_activate <= 1'b0;
            cnt <= 0;
        end else begin
            cnt <= 0;
            response <= COMMAND_RESPONSE;
        end
    end

    // m_last
    always @(*) begin
        if (i_reset)
            m_last <= 0;
        else if (!sending_dma_activate && cnt == 4 && m_valid)
            m_last <= 1'b1;
        else if (sending_dma_activate && m_valid)
            m_last <= 1'b1;
        else
            m_last <= 1'b0;
    end

    // m_data
    always @(*) begin
        if (i_reset)
            m_data <= 0;
        else if (m_valid && !sending_dma_activate)
            m_data <= response[127:96];
        else if (sending_dma_activate)
            m_data <= { FIS_TYPE_DMA_ACT, 24'h0 };
        else
            m_data <= 32'h0;
    end

endmodule
