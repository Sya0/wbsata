#ifndef SATASIM_H
#define SATASIM_H

#include <stdint.h>
#include <string>
#include <vector>

// SATA sector size in bytes
#define SATA_SECTOR_SIZE 512

// SATA Addresses
#define	SATA_CMD_ADDR		0
#define	SATA_LBALO_ADDR		1
#define	SATA_LBAHI_ADDR		2
#define	SATA_COUNT_ADDR		3
#define	SATA_PHY_ADDR		5
#define SATA_DMA_ADDR_LO	6
#define SATA_DMA_ADDR_HI	7

// SATA Primitives
#define ALIGN_P     0xBC4A4A7B
#define SYNC_P      0x7C95B5B5
#define XRDY_P      0x7CB55757
#define RRDY_P      0x7C954A4A
#define OK_P        0x7CB53535
#define ERR_P       0x7CB55656
#define WTRM_P      0x7CB55858
#define SOF_P       0x7CB53737
#define EOF_P       0x7CB5D5D5
#define R_IP_P      0x7CB55555

// FIS Types
#define FIS_TYPE_REG_H2D       0x27
#define FIS_TYPE_REG_D2H       0x34
#define FIS_TYPE_DMA_READ      0xC8
#define FIS_TYPE_DMA_WRITE     0xCA
#define FIS_TYPE_DMA_ACT       0x39

// Link Layer State Machine States
enum LinkState {
    SEND_ALIGN,
    IDLE,
    SEND_CHKRDY,
    SEND_DATA,
    WAIT,
    RCV_CHKRDY,
    RCV_DATA,
    GOODEND,
    BADEND
};

// SATA Signal Definitions by Clock Domain
/*
 * RX Clock Domain Signals (Device to Controller):
 * - i_rxphy_cominit     : COMINIT signal from device (driven on RX clock)
 * - i_rxphy_comwake     : COMWAKE signal from device (driven on RX clock)
 * - i_rxphy_elecidle    : Indicates PHY is in electrical idle state (driven on RX clock)
 * - i_rxphy_valid       : Indicates valid data is present on RX data lines (driven on RX clock)
 * - i_rxphy_data        : 32-bit data received from device (driven on RX clock)
 * - i_rxphy_primitive   : When set, data should be interpreted as a primitive (driven on RX clock)
 * 
 * TX Clock Domain Signals (Controller to Device):
 * - o_txphy_cominit     : Controller sends COMINIT signal (observed on TX clock)
 * - o_txphy_comwake     : Controller sends COMWAKE signal (observed on TX clock)
 * - o_txphy_elecidle    : Controller puts PHY in electrical idle state (observed on TX clock)
 * - o_txphy_data        : 32-bit data transmitted to device (observed on TX clock)
 * - o_txphy_primitive   : When set, data should be interpreted as a primitive (observed on TX clock)
 * - i_txphy_comfinish   : Indicates completion of COM sequence by device (driven on TX clock)
 * 
 * Note: Signal prefixes follow the convention from the controller's perspective:
 * - 'i_' indicates input TO the controller
 * - 'o_' indicates output FROM the controller
 * 
 * Clock Domain Rules:
 * 1. RX signals should be driven/updated in sim_rx_clk_tick()
 * 2. TX signals should be observed/processed in sim_tx_clk_tick()
 * 3. Communication between clock domains requires proper synchronization
 *    - i_txphy_comfinish is detected in TX domain 
 *    - i_rxphy_cominit/comwake are driven in RX domain (typically one clock after detection)
 */

// SATA simulator class - provides simulation for SATA PHY interface
class SATASIM {
private:
    // Basic state tracking
    bool m_busy;
    bool m_reset;
    bool m_link_ready;
    
    // RX & TX Clock Domain State Variables
    // RX domain signals (device to controller)
    bool m_rxphy_cominit;     // COMINIT signal to send to controller (RX domain)
    bool m_rxphy_comwake;     // COMWAKE signal to send to controller (RX domain)
    bool m_rxphy_elecidle;    // Device electrical idle state
    bool m_rxphy_valid;       // Valid data on RX bus
    bool m_rxphy_primitive;   // Primitive indicator (bit 32) 
    uint32_t m_rxphy_data;    // 32-bit data to send to controller
    
    // TX domain signals (controller to device)
    bool m_txphy_cominit;      // Controller sent COMINIT (TX domain)
    bool m_txphy_comwake;      // Controller sent COMWAKE (TX domain)
    bool m_txphy_comfinish;    // Controller sent COMFINISH (TX domain)
    bool m_txphy_elecidle;     // Controller puts PHY in electrical idle state (TX domain)
    bool m_txphy_primitive;    // Primitive indicator (bit 32)
    uint32_t m_txphy_data;     // 32-bit data to send to device
    
    bool m_tx_cominit_detected;  // Controller sent COMINIT (detected in TX domain)
    bool m_tx_comwake_detected;  // Controller sent COMWAKE (detected in TX domain)
    bool m_tx_comfinish_active;  // COMFINISH signal status (TX domain)
    
    bool m_ready;                // Overall link ready status
    bool m_phy_ready;            // Physical layer ready status
    bool m_txphy_ready;          // TX PHY ready status
    
    // Link Layer State Machine
    LinkState m_link_state;      // Current state of the link layer

    // OOB processing
    bool m_oob_done;

    // DMA operations
    bool m_dma_write;
    bool m_dma_read;
    // SATA Scrambling and CRC constants
    const uint16_t SCRAMBLER_POLYNOMIAL = 0xa011;
    const uint16_t SCRAMBLER_INITIAL = 0xffff;
    const uint32_t CRC_POLYNOMIAL = 0x04c11db7;
    const uint32_t CRC_INITIAL = 0x52325032;
    
    // Scrambling and CRC state
    uint16_t m_scrambler_fill;
    uint32_t m_crc;
    
    // Scrambler and CRC functions based on RTL implementation
    uint32_t scramble_data(uint32_t data, bool init);
    uint32_t calculate_crc(uint32_t data);
    
    // Helper functions that implement the RTL counterparts
    uint64_t scramble_function(uint16_t prior);
    uint32_t advance_crc(uint32_t prior, uint32_t dword);
    
public:
    // Constructor/destructor
    SATASIM();
    ~SATASIM();
    
    // Byte swap function for endianness conversion
    uint32_t swap_endian(uint32_t data);
    
    // Interface with Verilog model
    void reset();

    // Check if operation is in progress
    bool is_busy();
    
    // Interface signals between controller and phy
    void set_oob_done(bool oob_done);
    void detect_coms();
    bool send_coms();
    bool process_oob();
    void device_sends(uint32_t data, bool primitive);
    
    // Process controller TX data
    bool wait_for_primitive(uint32_t primitive);
    void wait_for_command();
    
    // DMA operations
    void dma_activate();

    // Link layer model
    LinkState link_layer_model();

    // Get current link state
    LinkState get_link_state() const { return m_link_state; }
    
    // Debug functions
    void debug_fis_scramble_crc(uint32_t fis_data);
    
    // Update SATASIM's internal state from controller signals
    void process_tx_signals(bool reset,
                         bool txphy_cominit, 
                         bool txphy_comwake, 
                         bool txphy_elecidle, 
                         bool txphy_primitive, 
                         uint32_t txphy_data,
                         bool &txphy_comfinish,
                         bool &txphy_ready,
                         bool link_ready);
    
    // Get SATASIM's signals to apply to controller inputs    
    void process_rx_signals(bool &rxphy_cominit,
                         bool &rxphy_comwake,
                         bool &rxphy_elecidle,
                         bool &rxphy_valid,
                         bool &rxphy_primitive,
                         uint64_t &rxphy_data,
                         bool &phy_ready);
};

#endif // SATASIM_H 