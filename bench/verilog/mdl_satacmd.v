`timescale 1ns / 1ps

module mdl_satacmd (
        input   wire i_clk,
        input   wire i_rst,
        input   wire i_link_layer_up,
        output  wire o_tx_p, o_tx_n
    );

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
    localparam	[3:0]	SEND_COMINIT = 0,
				WAIT_COMINIT = 1,
                SEND_COMWAKE = 2,
                WAIT_COMWAKE = 3,
                COMWAKE_DET = 4,
				COMWAKE_RELEASE = 5,
				SEND_ALIGN = 6,
                SEND_SYNC = 7;
    reg	[3:0]	fsm_state;

    // Testbench signals
    wire    tx_p, tx_n;
    reg     send_cominit, send_comwake, send_align, send_sync;
    reg     next_align;
    reg [P_BITS-1:0]  data_burst;
    reg     burst_en;
    reg [12:0]   burst_cnt;
    reg [$clog2(COMINIT_BURST_DURATION):0]  burst_timeout;
    reg [$clog2(COMINIT_IDLE_DURATION):0]   idle_timeout;

    reg [16:0] wait_align;

    always @(*) begin
        if (i_link_layer_up)
            $display("OOB sequence is done!");
    end

endmodule
