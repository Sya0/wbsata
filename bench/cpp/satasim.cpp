#include "satasim.h"
#include <iostream>
#include <cstring>
#include <cassert>
#include "wb_tb.h"

// Constructor
SATASIM::SATASIM() {
    m_busy = false;
    m_current_lba = 0;
    m_sector_count = 0;
    m_disk_size = 0;
    
    // Initialize interface signals
    m_rx_elecidle = true;
    m_cominit_detect = false;
    m_comwake_detect = false;
    m_cominit_finish = false;
    m_comwake_finish = false;
    m_ready = false;
    m_rxphy_valid = false;  
    m_rxphy_primitive = false;
    m_rxphy_data = 0;
    
    // Initialize memory and testbench
    m_memory = nullptr;
    m_tb = nullptr;
    
    // Initialize sector buffer
    m_sector_buffer.resize(SATA_SECTOR_SIZE);
}

// Destructor
SATASIM::~SATASIM() {
    // Close the disk file if it's open
    if (m_disk_file.is_open()) {
        m_disk_file.close();
    }
    
    // Note: We don't delete m_memory or m_tb because they're owned by the caller
}

// Set memory simulator
void SATASIM::set_memory(MEMSIM* memory) {
    m_memory = memory;
}

// Set testbench for Wishbone access
void SATASIM::set_testbench(WB_TB<Vsata_controller>* tb) {
    m_tb = tb;
}

// Wishbone register read
uint32_t SATASIM::wb_read_reg(uint32_t addr) {
    if (!m_tb) {
        std::cerr << "Cannot read register: Testbench not set" << std::endl;
        return 0;
    }
    
    return m_tb->wb_read(addr);
}

// Wishbone register write
void SATASIM::wb_write_reg(uint32_t addr, uint32_t data) {
    if (!m_tb) {
        std::cerr << "Cannot write register: Testbench not set" << std::endl;
        return;
    }
    
    m_tb->wb_write(addr, data);
}

// Load disk image
bool SATASIM::load(const char* filename) {
    // Close any previously open file
    if (m_disk_file.is_open()) {
        m_disk_file.close();
    }
    
    // Store the filename
    m_disk_filename = filename;
    
    // Open file for reading and writing in binary mode
    m_disk_file.open(filename, std::ios::in | std::ios::out | std::ios::binary);
    if (!m_disk_file.is_open()) {
        std::cerr << "Failed to open disk image file: " << filename << std::endl;
        return false;
    }
    
    // Get file size
    m_disk_file.seekg(0, std::ios::end);
    m_disk_size = m_disk_file.tellg();
    m_disk_file.seekg(0, std::ios::beg);
    
    std::cout << "Loaded disk image: " << filename << ", size: " << m_disk_size << " bytes" << std::endl;
    std::cout << "SATA disk has " << (m_disk_size / SATA_SECTOR_SIZE) << " sectors" << std::endl;
    
    return true;
}

// Save disk image changes to file
bool SATASIM::save() {
    if (!m_disk_file.is_open()) {
        std::cerr << "No disk image file is open" << std::endl;
        return false;
    }
    
    // Flush any pending writes
    m_disk_file.flush();
    
    return true;
}

// Reset the SATA interface
void SATASIM::reset() {
    m_busy = false;
    
    // Reset interface signals
    m_rx_elecidle = true;
    m_cominit_detect = false;
    m_comwake_detect = false;
    m_cominit_finish = false;
    m_comwake_finish = false;
    m_ready = false;
}

// Check if operation is in progress
bool SATASIM::is_busy() {
    return m_busy;
}

// Process signals from controller to PHY
void SATASIM::process_oob(bool tx_cominit, bool tx_comwake) {
    // Host sends COMRESET, wait for controller to finish
    while(!tx_cominit) {
        // When controller sends COMINIT, respond with COMINIT finish
        m_tb->m_core->i_txphy_comfinish = false;
        
        // Update tx_cominit from controller
        tx_cominit = m_tb->m_core->o_txphy_cominit;
        m_tb->tick();
    }
    m_tb->m_core->i_txphy_comfinish = true;
    for (int i = 0; i < 10; i++) {
        m_tb->tick();
    }
    printf("HOST: COMRESET sent\n");

    // Device sends COMINIT, wait for controller to finish
    m_tb->tick();
    m_cominit_detect = true;
    for (int i = 0; i < 10; i++) {
        m_tb->tick();
    }
    m_cominit_detect = false;
    printf("HOST: COMINIT detected\n");

    // Host sends COMWAKE, wait for controller to finish
    while(!tx_comwake) {
        // When controller sends COMWAKE, respond with COMWAKE detect
        m_tb->m_core->i_txphy_comfinish = false;
        m_tb->tick();
        
        // Update tx_comwake from controller
        tx_comwake = m_tb->m_core->o_txphy_comwake;
    }
    m_tb->m_core->i_txphy_comfinish = true;
    for (int i = 0; i < 10; i++) {
        m_tb->tick();
    }
    printf("HOST: COMWAKE sent\n");

    // Device sends COMWAKE, wait for controller to finish
    m_tb->tick();
    m_comwake_detect = true;
    for (int i = 0; i < 10; i++) {
        m_tb->tick();
    }
    m_comwake_detect = false;
    m_tb->tick();
    printf("HOST: COMWAKE detected\n");

    // Controller is ready
    m_rx_elecidle = false;
    m_ready = true;
    m_tb->tick();

    // Start sending ALIGN primitives - these are necessary for link initialization
    // This is a simplification, but should work for basic testing
    m_rxphy_valid = true;
    m_rxphy_primitive = true;
    m_rxphy_data = ALIGN_P;
    m_tb->tick();
    printf("HOST: Started sending ALIGN primitives (0x%08X)\n", m_rxphy_data);
}

// Send SYNC primitive
void SATASIM::send_sync() {
    m_rxphy_valid = true;
    m_rxphy_primitive = true;
    m_rxphy_data = SYNC_P;
}

// Generate input signals for the controller
void SATASIM::get_phy_inputs(
    bool& rx_elecidle, bool& rx_cominit, bool& rx_comwake,
    bool& rx_valid, uint64_t& rx_data) {
    
    // Simply provide the current state of interface signals
    rx_elecidle = m_rx_elecidle;
    rx_cominit = m_cominit_detect;
    rx_comwake = m_comwake_detect;
    
    // Return the data and valid signals
    rx_valid = m_rxphy_valid;
    // Construct 33-bit signal with primitive bit at MSB (bit 32)
	rx_data = (uint64_t)m_rxphy_data & 0xFFFFFFFF;  // 32-bit data
	if (m_rxphy_primitive)
		rx_data |= (1ULL << 32);  // Set bit 32 (primitive bit)
}

// Start SATA read operation
void SATASIM::start_read(uint64_t lba, uint32_t count, uint32_t dma_addr) {
    if (!m_disk_file.is_open()) {
        std::cerr << "Cannot read: No disk image file is open" << std::endl;
        return;
    }
    
    if (!m_memory) {
        std::cerr << "Cannot read: Memory simulator not set" << std::endl;
        return;
    }
    
    // Check if LBA is within range
    if (lba * SATA_SECTOR_SIZE >= m_disk_size) {
        std::cerr << "Read error: LBA " << lba << " out of range" << std::endl;
        return;
    }
    
    // Set up read operation
    m_current_lba = lba;
    m_sector_count = count;
    m_busy = true;
    
    std::cout << "SATA: Starting read from LBA " << lba << ", count " << count << std::endl;
    
    // Read data from disk image into memory buffer
    uint32_t total_bytes = count * 4; // 4 bytes per word
    uint32_t sectors_to_read = (total_bytes + SATA_SECTOR_SIZE - 1) / SATA_SECTOR_SIZE;
    
    std::vector<uint8_t> buffer(sectors_to_read * SATA_SECTOR_SIZE);
    
    // Seek to the LBA position
    m_disk_file.seekg(lba * SATA_SECTOR_SIZE);
    
    // Read data from disk
    m_disk_file.read(reinterpret_cast<char*>(buffer.data()), sectors_to_read * SATA_SECTOR_SIZE);
    
    // Transfer data to DMA memory
    for (uint32_t i = 0; i < count; i++) {
        uint32_t word = 0;
        if (i * 4 < buffer.size()) {
            // Read a 32-bit word from buffer
            word = (buffer[i * 4 + 0]) |
                   (buffer[i * 4 + 1] << 8) |
                   (buffer[i * 4 + 2] << 16) |
                   (buffer[i * 4 + 3] << 24);
        }
        
        // Write to memory at DMA address
        m_memory->operator[](dma_addr + i) = word;
    }
    
    // Operation complete
    std::cout << "SATA: Read completed, " << count << " words transferred to DMA address 0x" 
              << std::hex << dma_addr << std::dec << std::endl;
    m_busy = false;
}

// Start SATA write operation
void SATASIM::start_write(uint64_t lba, uint32_t count, uint32_t dma_addr) {
    if (!m_disk_file.is_open()) {
        std::cerr << "Cannot write: No disk image file is open" << std::endl;
        return;
    }
    
    if (!m_memory) {
        std::cerr << "Cannot write: Memory simulator not set" << std::endl;
        return;
    }
    
    // Check if LBA is within range
    if (lba * SATA_SECTOR_SIZE >= m_disk_size) {
        std::cerr << "Write error: LBA " << lba << " out of range" << std::endl;
        return;
    }
    
    // Set up write operation
    m_current_lba = lba;
    m_sector_count = count;
    m_busy = true;
    
    std::cout << "SATA: Starting write to LBA " << lba << ", count " << count << std::endl;
    
    // Calculate total bytes and sectors
    uint32_t total_bytes = count * 4; // 4 bytes per word
    uint32_t sectors_to_write = (total_bytes + SATA_SECTOR_SIZE - 1) / SATA_SECTOR_SIZE;
    
    std::vector<uint8_t> buffer(sectors_to_write * SATA_SECTOR_SIZE, 0);
    
    // Read data from DMA memory
    for (uint32_t i = 0; i < count; i++) {
        // Read from memory
        uint32_t word = m_memory->operator[](dma_addr + i);
        
        // Write to buffer as bytes
        if (i * 4 < buffer.size()) {
            buffer[i * 4 + 0] = (word & 0x000000FF);
            buffer[i * 4 + 1] = (word & 0x0000FF00) >> 8;
            buffer[i * 4 + 2] = (word & 0x00FF0000) >> 16;
            buffer[i * 4 + 3] = (word & 0xFF000000) >> 24;
        }
    }
    
    // Seek to the LBA position
    m_disk_file.seekp(lba * SATA_SECTOR_SIZE);
    
    // Write data to disk
    m_disk_file.write(reinterpret_cast<char*>(buffer.data()), sectors_to_write * SATA_SECTOR_SIZE);
    m_disk_file.flush();
    
    // Operation complete
    std::cout << "SATA: Write completed, " << count << " words transferred from DMA address 0x" 
              << std::hex << dma_addr << std::dec << std::endl;
    m_busy = false;
}
