#ifndef SATASIM_H
#define SATASIM_H

#include <stdint.h>
#include <string>
#include <vector>
#include <fstream>
#include "memsim.h"  // Include MEMSIM for memory operations

// Include the Verilator generated header
#include "obj-pc/Vsata_controller.h"

// Forward declaration for Wishbone testbench
template <class VA> class WB_TB;
template <class VA> class TESTB;

// SATA sector size in bytes
#define SATA_SECTOR_SIZE 512

#define ALIGN_P 0xBC4A4A7B
#define SYNC_P 0x7C95B5B5

// SATA simulator class - provides simulation for SATA PHY interface
class SATASIM {
private:
    // Track basic disk image information
    std::string m_disk_filename;
    std::fstream m_disk_file;
    uint64_t m_disk_size;
    std::vector<uint8_t> m_sector_buffer;

    // Basic state tracking
    bool m_busy;
    uint64_t m_current_lba;
    uint32_t m_sector_count;
    
    // Simplistic RX/TX state - for interface only
    bool m_rx_elecidle;
    bool m_cominit_detect;
    bool m_comwake_detect;
    bool m_cominit_finish;
    bool m_comwake_finish;
    bool m_ready;
    bool m_rxphy_valid;
    bool m_rxphy_primitive;   // Bit 32 (primitive bit)
    uint32_t m_rxphy_data;
    
    // Memory simulator for DMA operations
    MEMSIM* m_memory;
    
    // Wishbone interface access
    WB_TB<Vsata_controller>* m_tb;

public:
    // Constructor/destructor
    SATASIM();
    ~SATASIM();

    // Disk operations
    bool load(const char* filename);
    bool save();
    
    // Memory operations
    void set_memory(MEMSIM* memory);
    
    // Set testbench for Wishbone access
    void set_testbench(WB_TB<Vsata_controller>* tb);
    
    // Wishbone register access
    uint32_t wb_read_reg(uint32_t addr);
    void wb_write_reg(uint32_t addr, uint32_t data);
    
    // Interface with Verilog model - simplified to just match the interface
    void reset();

    // Check if operation is in progress
    bool is_busy();
    
    // Interface signals between controller and phy
    void process_oob(bool tx_cominit, bool tx_comwake);

    // Send SYNC primitive
    void send_sync();
    
    // Generate input signals for the controller
    void get_phy_inputs(
        bool& rx_elecidle, bool& rx_cominit, bool& rx_comwake,
        bool& rx_valid, uint64_t& rx_data);
    
    // SATA operations - simplified to just track state
    void start_read(uint64_t lba, uint32_t count, uint32_t dma_addr);
    void start_write(uint64_t lba, uint32_t count, uint32_t dma_addr);
};

#endif // SATASIM_H 