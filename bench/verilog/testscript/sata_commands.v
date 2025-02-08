`include "../testscript/satalib.v"

// Example timestamp value (48 bits)
localparam [47:0] TIMESTAMP = 48'h123456789ABC;  // Example timestamp in milliseconds

// 5-word command definition
localparam [127:0] SET_DATE_TIME_EXT_CMD = {
    {8'h00, 8'h77, 8'h80, 8'h27},           // FEATURES[7:0] | COMMAND (0x77) | 0x80 | FIS TYPE (0x27)
    {8'h00, TIMESTAMP[23:0]},               // DEVICE | LBA[23:0]
    {8'h00, TIMESTAMP[47:24]},              // FEATURES[15:8] | LBA[47:24]
    {8'h00 ,8'h00, 16'h0000}                // CONTROL | ICC | COUNT[15:0]
};

// task sdio_wait_while_busy;
// 	reg	[31:0]	read_data;
// 	reg		prior_interrupt;
// begin

task testscript; // send_set_date_time_ext;
    // input [47:0] timestamp;  // Timestamp in milliseconds

    reg [7:0] status; // Status output to check command result
    reg [15:0] feature;  // FEATURE field
    reg [15:0] count;    // COUNT field
    reg [47:0] lba;      // LBA field
    reg [7:0] device;    // DEVICE field
    reg [7:0] command;   // COMMAND field
    reg [4:0] result;    // Result from BFM functions

    begin
        @(posedge wb_clk);
        while(wb_reset !== 1'b0)
            @(posedge wb_clk);
        @(posedge wb_clk);

        // Initialize command fields
        // feature = 16'h0000;       // Reserved for SET DATE & TIME EXT
        // count   = 16'h0000;       // Reserved for this command
        // lba     = timestamp;      // Timestamp provided as input
        // device  = 8'h00;          // Typically 0x00 for control commands
        // command = 8'h77;          // SET DATE & TIME EXT opcode

        $display("Sending SET DATE & TIME EXT Command...");

        // Send FEATURE field
        u_bfm.writeio(ADDR_COUNT, SET_DATE_TIME_EXT_CMD[31:0]);
        u_bfm.writeio(ADDR_LBAHI, SET_DATE_TIME_EXT_CMD[63:32]);
        u_bfm.writeio(ADDR_LBALO, SET_DATE_TIME_EXT_CMD[95:64]);
        u_bfm.write_f(ADDR_CMD, SET_DATE_TIME_EXT_CMD[127:96]);

        // Wait for command completion and check status
        $display("Waiting for command completion...");
        wait(sata_int);
        u_bfm.readio(ADDR_CMD, status);

        if (status == 8'h50)
            $display("SET DATE & TIME EXT command completed successfully.");
        else
            $display("SET DATE & TIME EXT command failed with status: %h", status);
    end
endtask

