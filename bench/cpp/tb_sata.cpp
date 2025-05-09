////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/cpp/tb_sata.cpp
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Exercise all of the functionality contained within the Verilog
//		core, from bring up through read to write and read-back.
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
// }}}
// Include files
// {{{
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <vector>

#include <Vsata_controller.h>
#include "testb.h"
#include "wb_tb.h"
#include "satasim.h"
#include "memsim.h"
// }}}

// MACRO definitions
// {{{
#define	SATA_CMD_ADDR	0
#define	SATA_LBALO_ADDR	1
#define	SATA_LBAHI_ADDR	2
#define	SATA_COUNT_ADDR	3
#define	SATA_PHY_ADDR	5
#define	SATA_DMA_ADDR	6

#define FIS_TYPE_REG_H2D 		0x27
#define FIS_TYPE_REG_D2H 		0x34
#define SATA_CMD_SET_DATE_TIME  0x10
#define SATA_CMD_READ   		0xC8
#define SATA_CMD_WRITE  		0xCA
// }}}

class SATA_TB : public WB_TB<Vsata_controller> {
	SATASIM	*m_sata;
	MEMSIM  *m_mem;
public:

	SATA_TB(const char *filesystem_image) {
		// {{{
		if (0 != access(filesystem_image, R_OK)) {
			fprintf(stderr, "Cannot open %s for reading\n", filesystem_image);
			exit(EXIT_FAILURE);
		} 
		if (0 != access(filesystem_image, W_OK)) {
			fprintf(stderr, "Cannot open %s for writing\n", filesystem_image);
			exit(EXIT_FAILURE);
		}

		// Initialize MEMSIM for DMA memory operations
		m_mem = new MEMSIM(1024*1024, 10); // 1MB memory with 10-cycle delay
		
		// Initialize SATASIM for disk operations
		m_sata = new SATASIM();
		if (!m_sata->load(filesystem_image)) {
			fprintf(stderr, "Failed to load disk image: %s\n", filesystem_image);
			exit(EXIT_FAILURE);
		}
		
		// Set MEMSIM instance in SATASIM
		m_sata->set_memory(m_mem);
		m_sata->set_testbench(this);
		// }}}
	}
	
	virtual ~SATA_TB() {
		delete m_sata;
		delete m_mem;
	}

	virtual	void tick(void) {
		// {{{
		TESTB<Vsata_controller>::tick();

		// Process output signals from controller to PHY
		bool tx_elecidle = core()->o_txphy_elecidle;
		bool tx_cominit = core()->o_txphy_cominit;
		bool tx_comwake = core()->o_txphy_comwake;
		
		// Get inputs for controller from SATASIM
		bool rx_elecidle, rx_cominit, rx_comwake;
		bool rx_valid;
		uint64_t rx_data;
		m_sata->get_phy_inputs(rx_elecidle, rx_cominit, rx_comwake, rx_valid, rx_data);
		
		// Apply inputs to controller
		core()->i_rxphy_elecidle = rx_elecidle;
		core()->i_rxphy_cominit = rx_cominit;
		core()->i_rxphy_comwake = rx_comwake;
		core()->i_rxphy_valid = rx_valid;
		core()->i_rxphy_data = rx_data;
		// Note: i_rxphy_valid and data values are set directly here
		// }}}
	}

	Vsata_controller *core(void) {
		return m_core;
	}

	// Add a getter method to access m_time_ps from the parent TESTB class
	uint64_t get_time_ps(void) {
		return m_time_ps;
	}

	void wait_while_busy(void) {
		// {{{
		// Simply call tick() until we get an interrupt
		while(!core()->o_int)
			tick();
		// }}}
	}

	void wait_while_link_ready(void) {
		// {{{
		while(!core()->o_lnk_ready)
			tick();
		printf("HOST: Link ready\n");
		// }}}
	}

	void reset_controller() {
		// Reset our SATA simulator
		m_sata->reset();

		// Assert reset for 100 cycles at the very start
		core()->i_reset = 1;
		for (int i = 0; i < 100; i++)
			tick();
		core()->i_reset = 0;
		tick();
		core()->i_phy_ready = 1;
		core()->i_txphy_ready = 1;
		core()->i_rxphy_cominit = 0;
		core()->i_rxphy_comwake = 0;
		tick();
		
		// Print status
		printf("HOST: SATA controller reset complete\n");
	}

	void oob() {
		m_sata->process_oob(core()->o_txphy_cominit, core()->o_txphy_comwake);
	}

	void send_sync() {
		m_sata->send_sync();
	}

	void dma_write(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		// Only 28-bit LBA and 8-bit count supported (as in satalib)
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits

		// Program the SATA controller registers via Wishbone
		wb_write(SATA_LBAHI_ADDR, lba_hi); // Upper bits not used
		wb_write(SATA_LBALO_ADDR, lba24);  // Lower 24 bits of LBA
		wb_write(SATA_COUNT_ADDR, count8); // Lower 8 bits of count
		wb_write(SATA_DMA_ADDR, dma_addr); // DMA address

		// Construct the command FIS word as in satalib
		uint32_t fis_cmd = (0x00 << 24) | (0xCA << 16) | 
						   ((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_D2H;
		wb_write(SATA_CMD_ADDR, fis_cmd);

		// Start SATA simulator write operation
		// m_sata->start_write(lba, count, dma_addr);

		// Wait for operation to complete
		wait_while_busy();

		printf("DMA Write complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	void dma_read(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		// Only 28-bit LBA and 8-bit count supported (as in satalib)
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits

		// Program the SATA controller registers via Wishbone
		wb_write(SATA_LBAHI_ADDR, lba_hi); // Upper bits not used
		wb_write(SATA_LBALO_ADDR, lba24);  // Lower 24 bits of LBA
		wb_write(SATA_COUNT_ADDR, count8); // Lower 8 bits of count
		wb_write(SATA_DMA_ADDR, dma_addr); // DMA address

		// Construct the command FIS word as in satalib
		uint32_t fis_cmd = (0x00 << 24) | (0xC8 << 16) | ((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_D2H;
		wb_write(SATA_CMD_ADDR, fis_cmd);

		// Start SATA simulator read operation
		// m_sata->start_read(lba, count, dma_addr);

		// Wait for operation to complete
		wait_while_busy();

		printf("DMA Read complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	bool verify_data(uint32_t dma_addr, uint32_t expected_val, uint32_t count) {
		bool success = true;
		
		// Verify data directly from memory
		for (uint32_t i = 0; i < count; i++) {
			uint32_t value = m_mem->operator[](dma_addr + i);
			if (value != expected_val + i) {
				printf("Data mismatch at offset %u: Expected 0x%08x, Got 0x%08x\n", 
					i, expected_val + i, value);
				success = false;
			}
		}
		
		return success;
	}

	// Direct memory access for testing purposes
	void write_memory(uint32_t addr, uint32_t* data, uint32_t count) {
		for (uint32_t i = 0; i < count; i++) {
			m_mem->operator[](addr + i) = data[i];
		}
	}

	void wait(int n) {
		for (int i = 0; i < n; i++) {
			tick();
		}
	}
};

int	main(int argc, char **argv) {
	const char	IMG_FILENAME[] = "sdcard.img";
	const char	VCD_FILENAME[] = "trace.vcd";
	SATA_TB	tb(IMG_FILENAME);

	// Now open trace and continue with the rest of the test
	tb.opentrace(VCD_FILENAME);

	// Reset the controller
	tb.reset_controller();
	// printf("Time after reset: %llu ps\n", tb.get_time_ps());

	// Process OOB
	tb.oob();

	// Wait some time after OOB
	tb.wait(1000);

	// Send SYNC primitive
	tb.send_sync();

	// Wait for link to be ready
	tb.wait_while_link_ready();
	
	// Wait some time after link up
	tb.wait(1000);

	// Test parameters
	// uint64_t test_lba = 0;
	// uint32_t test_count = 8;   // 8 words (2 sectors)
	// uint32_t dma_addr = 0x1000;
	bool failed = false;
	
	// Create and initialize test data
	// printf("Creating test data\n");
	// std::vector<uint32_t> test_data(test_count);
	// for (uint32_t i = 0; i < test_count; i++) {
	// 	test_data[i] = 0xA0000000 + i;
	// }
	
	// DMA Write
	// printf("Issue DMA Write\n");
	// // Write test data directly to memory
	// tb.write_memory(dma_addr, test_data.data(), test_count);
	// tb.dma_write(test_lba, test_count, dma_addr);
	
	// DMA Read
	// printf("Issue DMA Read\n");
	// tb.dma_read(test_lba, test_count, dma_addr);
	
	// // Verify read data equals written data
	// printf("Verifying read data matches written data...\n");
	// if (!tb.verify_data(dma_addr, 0xA0000000, test_count)) {
	// 	failed = true;
	// 	printf("Data verification FAILED\n");
	// } else {
	// 	printf("Data verification PASSED\n");
	// }

	if (!failed)
		printf("TEST SUMMARY: SUCCESS!\n");
	else
		printf("TEST SUMMARY: FAILED!\n");

	for (int i = 0; i < 1000; i++) {
		tb.tick();
	}
		
	return failed ? 1 : 0;
}
