`timescale 1ns / 1ps

module mdl_oob (
        input   wire i_clk,
        input   wire i_rst,
        input   wire i_comfinish,
        input   wire i_comreset_det, i_comwake_dev,
        input   wire i_comwake_det,
        input   wire i_oob_done, i_link_layer_up,
        output  reg  o_done,
        output  wire o_tx_p, o_tx_n
    );

    // Parts of ALIGNP
    localparam P_BITS = 40;
    localparam [(P_BITS/4)-1:0] D21_4 = 10'b1010101101;
    localparam [(P_BITS/4)-1:0] K28_3 = 10'b0011110011;
    localparam [(P_BITS/4)-1:0] D21_5 = 10'b1010101010;
    localparam [(P_BITS/4)-1:0] K28_5 = 10'b0011111010;  // K28.5 chars (Inverts disparity)
    localparam [(P_BITS/4)-1:0] D10_2 = 10'b0101010101;  // D10.2 chars (Neutral)
    localparam [(P_BITS/4)-1:0] D27_3 = 10'b0010011100;  // D27.3 chars (Inverts disparity)

    localparam [P_BITS-1:0] SYNC_P = { D21_5, D21_5, D21_4, K28_3 };
    localparam [P_BITS-1:0] ALIGN_P = { D27_3, D10_2, D10_2, K28_5 };

    // Parameters
    localparam CLOCK_PERIOD = 0.667; // 1.5GHz = 667ps = 0.667ns
    localparam UIOOB = 160; // 160 UIOOB units
    localparam N_COMRESET_BURST = 6;    // Number of COMRESET Burst
    localparam N_COMWAKE_BURST = 6;    // Number of COMRESET Burst

    // Test timing ve burst/idle periods
    localparam realtime COMINIT_BURST_DURATION = UIOOB;  // Burst timing
    localparam realtime COMINIT_IDLE_DURATION  = UIOOB * 3;  // Idle timing
    localparam realtime COMWAKE_DURATION = UIOOB;  // Burst-Idle timing

    // State machine
    localparam	[2:0]	SEND_COMINIT = 0,
				WAIT_COMINIT = 1,
                SEND_COMWAKE = 2,
                WAIT_COMWAKE = 3,
                COMWAKE_DET = 4,
				SEND_ALIGN = 5,
                SEND_SYNC = 6;
    reg	[2:0]	fsm_state;

    // Testbench signals
    wire    tx_p, tx_n;
    reg     send_cominit, send_comwake, send_align, send_sync;
    reg [P_BITS-1:0]  data_burst;
    reg     burst_en;
    reg [12:0]   burst_cnt;
    reg [$clog2(COMINIT_BURST_DURATION):0]  burst_timeout;
    reg [$clog2(COMINIT_IDLE_DURATION):0]   idle_timeout;

    reg [16:0] wait_align;

    mdl_alignp_transmit alignp_inst (
        .clk(i_clk),
        .reset(i_rst),
        .burst_en(burst_en),
        .data_p(data_burst),
        .tx_p(tx_p),
        .tx_n(tx_n)
    );

    assign o_tx_p = tx_p;
    assign o_tx_n = tx_n;

    // initial begin
    // 	$dumpfile("waveform.vcd");
    // 	$dumpvars(0, tb_oob);
    // end

    always @(*)
        if (send_sync)
            data_burst <= SYNC_P;
        else
            data_burst <= ALIGN_P;
    
    // assign  data_burst = ALIGN_P;

    // OOB Test Sequence for COMRESET, COMINIT and COMWAKE
    initial send_cominit = 1'b0;
    initial send_comwake = 1'b0;
    initial send_align = 1'b0;
    initial send_sync = 1'b0;
    always @(posedge i_clk)
	if (i_rst) begin
		fsm_state    <= SEND_COMINIT;
		send_cominit <= 1'b0;
		send_comwake <= 1'b0;
		send_align   <= 1'b0;
        send_sync    <= 1'b0;
        o_done       <= 1'b0;
    end else begin
        case(fsm_state)
            SEND_COMINIT: begin
                if (i_comfinish && i_comreset_det) begin
                    $display("Host detects COMRESET");
                    $display("Starting COMINIT Sequence");
                    fsm_state    <= WAIT_COMINIT;
                    send_cominit <= 1'b1;
                end
            end
            WAIT_COMINIT: begin
                if (burst_cnt == N_COMRESET_BURST && send_cominit) begin
                    fsm_state    <= SEND_COMWAKE;
                    send_cominit <= 1'b0;
                end
            end
            SEND_COMWAKE: begin
                if (i_comfinish && i_comwake_dev) begin
                    $display("Host detects COMWAKE");
                    $display("Starting COMWAKE Sequence");
                    fsm_state    <= WAIT_COMWAKE;
                    send_comwake <= 1'b1;
                end
            end
            WAIT_COMWAKE: begin
                if (burst_cnt == N_COMRESET_BURST && send_comwake) begin
                    fsm_state    <= COMWAKE_DET;
                    send_comwake <= 1'b0;
                end
            end
            COMWAKE_DET: begin
                if (i_comwake_det) begin
                    fsm_state <= SEND_ALIGN;
                    send_align <= 1'b1;
                    o_done <= 1'b1;
                end
            end
            SEND_ALIGN: begin
                // fsm_state <= SEND_SYNC;
                send_align <= 1'b1;
                // if (burst_cnt == 2048) begin    // magic number (2048)
                    if (i_oob_done) begin
                        send_align <= 1'b0;
                        fsm_state  <= SEND_SYNC;
                        send_sync <= 1'b1;
                        $display("Starting SYNC Sequence");
                    end
                // end
            end
            SEND_SYNC: begin
                send_sync <= 1'b1;
            end
        endcase
    end

    initial burst_timeout = 0;
    initial idle_timeout = 0;
    always @(posedge i_clk) begin
        if (i_rst) begin
            burst_timeout <= 0;
            idle_timeout <= 0;
        end else if (send_cominit) begin
            if (burst_en) begin
                burst_timeout <= burst_timeout + 1;
                if (burst_timeout == COMINIT_BURST_DURATION-1)
                    idle_timeout <= idle_timeout + 1;
                else
                    idle_timeout <= 0;
            end else begin
                burst_timeout <= 0;
                if (idle_timeout == COMINIT_IDLE_DURATION-1)
                    idle_timeout <= 0;
                else
                    idle_timeout <= idle_timeout + 1;
            end
        end else if (send_comwake) begin
            if (burst_en) begin
                burst_timeout <= burst_timeout + 1;
                if (burst_timeout == COMWAKE_DURATION-1)
                    idle_timeout <= idle_timeout + 1;
                else
                    idle_timeout <= 0;
            end else begin
                burst_timeout <= 0;
                if (idle_timeout == COMWAKE_DURATION-1)
                    idle_timeout <= 0;
                else
                    idle_timeout <= idle_timeout + 1;
            end
        end else if (send_align) begin
            if (burst_en) begin
                if (burst_timeout == (P_BITS-1))
                    burst_timeout <= 0;
                else
                    burst_timeout <= burst_timeout + 1;
                idle_timeout <= 0;
            end
        end else if (send_sync) begin
            if (burst_en) begin
                if (burst_timeout == (P_BITS-1))
                    burst_timeout <= 0;
                else
                    burst_timeout <= burst_timeout + 1;
                idle_timeout  <= 0;
            end
        end else begin
            burst_timeout <= 0;
            idle_timeout  <= 0;
        end
    end

    initial burst_en = 0;
    initial burst_cnt = 0;
    always @(posedge i_clk) begin
        if (i_rst) begin
            burst_en  <= 1'b0;
            burst_cnt <= 0;
        end
        else if (send_cominit || send_comwake) begin
            if (burst_timeout == (UIOOB-1)) begin
                burst_en  <= 1'b0;
                burst_cnt <= burst_cnt + 1;
            end else if (idle_timeout == 0) begin
                burst_en <= 1'b1;
            end
        // after this stage burst_en should be always '1'
        end else if (send_align) begin  
            burst_en <= 1'b1;
            if (burst_timeout == 0) begin
                burst_cnt <= burst_cnt + 1;
            end
        end else if (send_sync) begin
            burst_en <= 1'b1;
            if (burst_cnt < 3)
                burst_cnt <= 0;
            if (burst_timeout == 0) begin
                burst_cnt <= burst_cnt + 1;
            end
        end else begin
            burst_en  <= 1'b0;
            burst_cnt <= 0;
        end
    end

endmodule
