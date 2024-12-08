`timescale 1ns / 1ps

module mdl_oob (
        input   wire i_clk,
        input   wire i_rst,
        input   wire i_comfinish,
        input   wire i_comreset_det, i_comwake_dev,
        input   wire i_comwake_det,
        output  wire o_tx_p, o_tx_n
    );
   
    // Parts of ALIGNP  4 + 4
    localparam [9:0] K28_5 = 10'b0011111010;  // K28.5 chars (Inverts disparity)
    localparam [9:0] D10_2 = 10'b0101010101;  // D10.2 chars (Neutral)
    localparam [9:0] D27_3 = 10'b0010011100;  // D27.3 chars (Inverts disparity)
    localparam ALIGNP_BIT = 40;
    localparam [ALIGNP_BIT-1:0] ALIGN_P = { D27_3, D10_2, D10_2, K28_5 };

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
				COMWAKE_RELEASE = 5,
				SEND_ALIGN = 6,
                WAIT_ALIGN = 7;
    reg	[2:0]	fsm_state;

    // Testbench signals
    wire    tx_p, tx_n;
    reg     send_cominit, send_comwake, send_align;
    reg     next_align;
    wire [39:0]  alignp_burst;
    reg     burst_en;
    reg [3:0]   burst_cnt;
    reg [$clog2(COMINIT_BURST_DURATION):0]  burst_timeout;
    reg [$clog2(COMINIT_IDLE_DURATION):0]   idle_timeout;

    reg [16:0] wait_align;
   
    mdl_alignp_transmit alignp_inst (
        .clk(i_clk),
        .reset(i_rst),
        .burst_en(burst_en),
        .align_p(alignp_burst),
        .tx_p(tx_p),
        .tx_n(tx_n)
    );

    assign o_tx_p = tx_p;
    assign o_tx_n = tx_n;

    assign alignp_burst = ALIGN_P;

    // initial begin
    // 	$dumpfile("waveform.vcd");
    // 	$dumpvars(0, tb_oob);
    // end

    // COMRESET, COMINIT ve COMWAKE için OOB Test Sequence
    initial send_cominit = 1'b0;
    initial send_comwake = 1'b0;
    initial send_align = 1'b0;
    always @(posedge i_clk)
	if (i_rst) begin
		fsm_state    <= SEND_COMINIT;
		send_cominit <= 1'b0;
		send_comwake <= 1'b0;
		send_align   <= 1'b0;
        wait_align   <= 0;
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
                if (i_comwake_det)
                    fsm_state <= COMWAKE_RELEASE;
            end
            COMWAKE_RELEASE: begin
                if (!i_comwake_det) begin
                    wait_align <= wait_align + 1;
                    if (wait_align[10] == 1'b1) begin
                        fsm_state <= SEND_ALIGN;
                        wait_align <= 0;
                    end
                end
            end
            SEND_ALIGN: begin
                $display("Starting ALIGN Sequence");
                fsm_state  <= WAIT_ALIGN;
                send_align <= 1'b1;
            end
            WAIT_ALIGN: begin
                wait_align <= wait_align + 1;
                if ((wait_align[16] == 1'b1) && (wait_align[14] == 1'b1)) begin
                    fsm_state  <= SEND_COMINIT;
                    wait_align <= 0;
                    // send_align <= 1'b0;
                end
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
                burst_timeout <= burst_timeout + 1;
                if (burst_timeout == ALIGNP_BIT-1)
                    idle_timeout <= idle_timeout + 1;
                else
                    idle_timeout <= 0;
            // end else begin
            //     burst_timeout <= 0;
            //     if (idle_timeout == (COMWAKE_DURATION/2)-1)
            //         idle_timeout <= 0;
            //     else
            //         idle_timeout <= idle_timeout + 1;
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
            burst_en <= 1'b0;
            burst_cnt <= 0;
        end
        else if (send_cominit || send_comwake) begin
            if (burst_timeout == (UIOOB-1)) begin
                burst_en <= 1'b0;
                burst_cnt <= burst_cnt + 1;                
            end else if (idle_timeout == 0) begin
                burst_en <= 1'b1;
            end
        end else if (send_align) begin
            if (burst_timeout == (ALIGNP_BIT-1)) begin
                burst_en <= 1'b1;   // !!! 1'b0
                burst_cnt <= burst_cnt + 1;                
            end else if (idle_timeout == 0) begin
                burst_en <= 1'b1;
            end
        end else begin
            burst_en <= 1'b0;
            burst_cnt <= 0;
        end
    end
   
endmodule
