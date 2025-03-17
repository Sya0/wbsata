`include "../testscript/satalib.v"

// Example timestamp value (48 bits)
localparam [47:0] TIMESTAMP = 48'h123456789ABC;  // Example timestamp in milliseconds

// Define DMA write test parameters
localparam [27:0] TEST_LBA = 28'h0000_100;       // Starting LBA for DMA write (sector 256)
localparam [7:0]  TEST_COUNT = 8'd1;             // Number of sectors to write

task testscript;
begin
	$display("Sending SET DATE & TIME EXT Command...");
	sata_set_time(TIMESTAMP);

	// Wait a bit before sending the next command
	#1000;
	
	$display("\n === Starting DMA WRITE/READ Test ===");
	test_dma_write_read(TEST_LBA, TEST_COUNT);

end endtask

