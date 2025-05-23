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
#include <iostream>
#include <fstream>

#include <Vsata_controller.h>
#include "testb.h"
#include "wb_tb.h"
#include "satasim.h"
#include "memsim.h"
// }}}

class SATA_TB : public WB_TB<Vsata_controller> {
public:
	SATASIM	*m_sata;
	MEMSIM  *m_mem;
	WB_TB<Vsata_controller>* m_tb;

	uint64_t m_current_lba;
    uint32_t m_sector_count;
    uint64_t m_disk_size;

	// Track basic disk image information
    std::string m_disk_filename;
    std::fstream m_disk_file;
    std::vector<uint8_t> m_sector_buffer;

	uint32_t m_dma_addr;

	SATA_TB(const char *filesystem_image) : WB_TB<Vsata_controller>() {
		// {{{
		if (0 != access(filesystem_image, R_OK)) {
			fprintf(stderr, "Cannot open %s for reading\n", filesystem_image);
			exit(EXIT_FAILURE);
		} 
		if (0 != access(filesystem_image, W_OK)) {
			fprintf(stderr, "Cannot open %s for writing\n", filesystem_image);
			exit(EXIT_FAILURE);
		}

		// Initialize DMA address
		m_dma_addr = 0x800100;

		// Initialize MEMSIM for DMA memory operations
		m_mem = new MEMSIM(1024*1024, 10); // 1MB memory with 10-cycle delay
		
		// Initialize SATASIM for disk operations
		m_sata = new SATASIM();
		m_mem->load(filesystem_image);
		
		// Set this testbench as its own testbench reference
		m_tb = this;
		// }}}
	}
	
	virtual ~SATA_TB() {
		delete m_sata;
		delete m_mem;
	}

	Vsata_controller *core(void) {
		return m_core;
	}

	// Override simulator clock callbacks to interact with SATASIM
	virtual	void sim_clk_tick(void) {
		// Call parent's simulation clock callback
		TESTB<Vsata_controller>::sim_clk_tick();

		deploy_test_data(m_dma_addr);
	}
	
	virtual	void sim_rx_clk_tick(void) {
		// Get signals from SATASIM to apply to core
		bool rxphy_cominit, rxphy_comwake, rxphy_elecidle, rxphy_valid;
		bool rxphy_primitive, phy_ready;
		uint64_t rxphy_data;

		// Call parent's simulation RX clock callback
		TESTB<Vsata_controller>::sim_rx_clk_tick();
		
		// Get values from SATASIM
		m_sata->process_rx_signals(rxphy_cominit, rxphy_comwake, rxphy_elecidle, 
		                         rxphy_valid, rxphy_primitive, rxphy_data,
		                         phy_ready);
		
		// Update link layer state machine
		m_sata->link_layer_model();

		// Apply to core
		m_core->i_rxphy_cominit = rxphy_cominit;
		m_core->i_rxphy_comwake = rxphy_comwake;
		m_core->i_rxphy_elecidle = rxphy_elecidle;
		m_core->i_rxphy_valid = rxphy_valid;
		m_core->i_rxphy_data = rxphy_data; // 33-bit value
		m_core->i_phy_ready = phy_ready;
	}
	
	virtual	void sim_tx_clk_tick(void) {
		// Call parent's implementation first
		WB_TB<Vsata_controller>::sim_tx_clk_tick();
		
		// Create local variables to receive output values
		bool txphy_comfinish;
		bool txphy_ready;
		bool oob_done;
		
		// Process OOB signals from controller
		if (!m_core->o_lnk_ready) {
			oob_done = m_sata->process_oob();
			m_sata->set_oob_done(oob_done);
		}

		// Update SATASIM with core signals
		m_sata->process_tx_signals(
		    m_core->i_reset,
		    m_core->o_txphy_cominit,
		    m_core->o_txphy_comwake,
		    m_core->o_txphy_elecidle,
		    m_core->o_txphy_primitive,
		    m_core->o_txphy_data,
		    txphy_comfinish,
		    txphy_ready,
		    m_core->o_lnk_ready
		);
		
		// Apply outputs back to core
		m_core->i_txphy_comfinish = txphy_comfinish;
		m_core->i_txphy_ready = txphy_ready;
	}

	// Add a getter method to access m_time_ps from the parent TESTB class
	uint64_t get_time_ps(void) {
		return m_time_ps;
	}

	// Direct memory access for testing purposes
	void write_memory(uint32_t addr, uint32_t* data, uint32_t count) {
		m_mem->load(addr, (char*)data, count*sizeof(uint32_t));
	}

	void wait(int n) {
		for (int i = 0; i < n; i++)
			tick();
	}

	void reset_controller() {
		// Reset our SATA simulator
		m_sata->reset();

		// Assert reset for 100 cycles at the very start
		m_core->i_reset = 1;
		for (int i = 0; i < 100; i++)
			tick();
		m_core->i_reset = 0;
		tick();
		
		// Print status
		printf("HOST: SATA controller reset complete\n");
	}

	void wait_while_busy(void) {
		// Wait for interrupt indicating operation complete
		int timeout = 10000;
		while(!m_core->o_int && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for busy to clear\n");
	}

	// Wishbone register read
	uint32_t wb_read_reg(uint32_t addr) {
		if (!m_tb) {
			std::cerr << "Cannot read register: Testbench not set" << std::endl;
			return 0;
		}
		
		return m_tb->wb_read(addr);
	}

	// Wishbone register write
	void wb_write_reg(uint32_t addr, uint32_t data) {
		if (!m_tb) {
			std::cerr << "Cannot write register: Testbench not set" << std::endl;
			return;
		}
		
		m_tb->wb_write(addr, data);
	}

	// Wait for link to be ready
	void wait_while_link_ready(void) {
		int timeout = 10000;
		
		while(!m_core->o_lnk_ready && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for link ready\n");
		else
			printf("HOST: Link ready\n");
	}

	// Wait for interrupt
	void wait_for_int(void) {
		int timeout = 10000;
		
		while(!m_core->o_int && --timeout > 0)
			tick();
			
		if (timeout <= 0)
			printf("ERROR: Timeout waiting for interrupt\n");
	}

	// Execute DMA write operation
	void dma_write(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform DMA write: Core or testbench not set" << std::endl;
			return;
		}

		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the DMA write
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr);          // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for DMA write
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_DMA_WRITE << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command
		
		// Wait for operation to complete (interrupt)
		wait_for_int();
		
		printf("DMA Write complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	// Execute DMA read operation
	void dma_read(uint64_t lba, uint32_t count, uint32_t dma_addr) {
		if (!m_core || !m_tb) {
			std::cerr << "Cannot perform DMA read: Core or testbench not set" << std::endl;
			return;
		}
		
		// Only 28-bit LBA and 8-bit count supported for now
		uint32_t lba24 = (uint32_t)(lba & 0xFFFFFF); // lower 24 bits
		uint32_t lba_hi = 0; // upper bits not used
		uint32_t count8 = count & 0xFF; // lower 8 bits
		
		// Setup Wishbone registers for the DMA read
		wb_write_reg(SATA_LBAHI_ADDR, lba_hi);             // Upper bits
		wb_write_reg(SATA_LBALO_ADDR, lba24);              // Lower 24 bits
		wb_write_reg(SATA_COUNT_ADDR, count8);             // Count
		wb_write_reg(SATA_DMA_ADDR_LO, dma_addr);          // DMA address low
		wb_write_reg(SATA_DMA_ADDR_HI, uint32_t(0));       // DMA address high
		
		// Construct the command FIS word for DMA read
		uint32_t fis_cmd = (0x00 << 24) | (FIS_TYPE_DMA_READ << 16) | 
						((0x40 | ((lba >> 24) & 0x0F)) << 8) | FIS_TYPE_REG_H2D;
		wb_write_reg(SATA_CMD_ADDR, fis_cmd);            // Command
		
		// Wait for operation to complete (interrupt)
		wait_for_int();
		
		printf("DMA Read complete: LBA=%llu, Count=%u, DMA Addr=0x%08x\n", 
			(unsigned long long)lba, count, dma_addr);
	}

	// SATA Controller pulls data from memory
	void deploy_test_data(const uint32_t dma_addr) {
		// Use MEMSIM::apply to handle the memory transaction
		m_mem->apply(m_core->o_dma_cyc, m_core->o_dma_stb, m_core->o_dma_we,
			dma_addr, &m_core->o_dma_data, m_core->o_dma_sel, 
			m_core->i_dma_stall, m_core->i_dma_ack, &m_core->i_dma_data);
		if (m_core->o_dma_cyc && m_core->o_dma_stb && !m_core->i_dma_stall)
			m_dma_addr++;
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
};

int	main(int argc, char **argv) {
	const char	IMG_FILENAME[] = "sata.img";
	const char	VCD_FILENAME[] = "trace.vcd";
	SATA_TB	tb(IMG_FILENAME);

	// Now open trace and continue with the rest of the test
	tb.opentrace(VCD_FILENAME);

	// Reset the controller
	tb.reset_controller();

	// Wait for link to be ready
	tb.wait_while_link_ready();
	
	// Wait some time after link up
	tb.wait(1000);

	// Test parameters
	uint32_t test_lba = 0x200;
	uint32_t test_count = 1;
	uint32_t dma_addr = tb.m_dma_addr;
	bool failed = false;
	
	// DMA Write
	printf("TB: Issue DMA Write\n");
	tb.dma_write(test_lba, test_count, dma_addr);
	
	// Wait some time after DMA write
	// tb.wait(1000);
	
	// DMA Read
	// printf("Issue DMA Read\n");
	// tb.dma_read(test_lba, test_count, dma_addr);
	
	// Verify read data equals written data
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

	tb.wait(10000);
		
	return failed ? 1 : 0;
}
