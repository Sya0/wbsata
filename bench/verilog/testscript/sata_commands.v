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

task testscript; // send_set_date_time_ext;
	// input [47:0] timestamp;  // Timestamp in milliseconds
begin
	// Initialize command fields
	// feature = 16'h0000;       // Reserved for SET DATE & TIME EXT
	// count   = 16'h0000;       // Reserved for this command
	// lba     = timestamp;      // Timestamp provided as input
	// device  = 8'h00;          // Typically 0x00 for control commands
	// command = 8'h77;          // SET DATE & TIME EXT opcode

	$display("Sending SET DATE & TIME EXT Command...");
	sata_set_time(TIMESTAMP);
end endtask

