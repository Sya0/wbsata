#include "satasim.h"
#include <iostream>
#include <cstring>
#include <cassert>
#include <iomanip>

// Constructor
SATASIM::SATASIM() {
    m_busy = false;
    
    // Initialize interface signals
    m_rxphy_elecidle = true;
    m_rxphy_cominit = false;
    m_rxphy_comwake = false;
    m_txphy_comfinish = false;
    m_ready = false;
    m_rxphy_valid = false;  
    m_rxphy_primitive = false;
    m_rxphy_data = 0;
    
    // Initialize reset and ready signals
    m_reset = false;
    m_link_ready = false;
    m_phy_ready = false;
    m_txphy_ready = false;
    
    // Initialize link layer state machine
    m_link_state = SEND_ALIGN;

    // Initialize OOB processing
    m_oob_done = false;

    // Initialize DMA operations
    m_dma_write = false;
    m_dma_read = false;
    
    // Initialize scrambler and CRC
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
}

// Destructor
SATASIM::~SATASIM() {
    // Nothing to clean up
}

// Byte swap function for endianness conversion
uint32_t SATASIM::swap_endian(uint32_t data) {
    return ((data & 0xFF000000) >> 24) |
            ((data & 0x00FF0000) >> 8) |
            ((data & 0x0000FF00) << 8) |
            ((data & 0x000000FF) << 24);
}

// Reset the SATA interface
void SATASIM::reset() {
    m_busy = false;
    
    // Reset interface signals
    m_rxphy_elecidle = true;
    m_rxphy_cominit = false;
    m_rxphy_comwake = false;
    m_txphy_comfinish = false;
    m_ready = false;
    m_rxphy_valid = false;
    m_rxphy_primitive = false;
    m_rxphy_data = 0;
    
    // Reset status signals
    m_phy_ready = false;
    m_txphy_ready = false;
    m_oob_done = false;
    
    // Reset scrambler and CRC state
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
}

// Check if operation is in progress
bool SATASIM::is_busy() {
    return m_busy;
}

void SATASIM::set_oob_done(bool oob_done) {
    m_oob_done = oob_done;
}

// Send COMINIT and COMWAKE responses
bool SATASIM::send_coms() {
    static bool cominit_sent = false;
    static bool comwake_sent = false;

    // Handle the COMINIT response
    if (m_txphy_comfinish && !cominit_sent) {
        // Drive COMINIT one clock after comfinish
        m_rxphy_cominit = true;
        printf("DEVICE: Sending COMINIT\n");
    } else {
        // After one clock, clear COMINIT
        if (m_rxphy_cominit) {
            cominit_sent = true;
            m_rxphy_cominit = false;
        }
    }

    // Handle the COMWAKE response (only after COMINIT was sent)
    if (m_txphy_comfinish && !comwake_sent && cominit_sent) {
        // Drive COMWAKE one clock after comfinish
        m_rxphy_comwake = true;
        printf("DEVICE: Sending COMWAKE\n");
    } else {
        // After one clock, clear COMWAKE
        if (m_rxphy_comwake) {
            comwake_sent = true;
            m_rxphy_comwake = false;
        }
    }

    return cominit_sent && comwake_sent;
}

// Detect COMINIT and COMWAKE signals from controller
void SATASIM::detect_coms() {
    if (m_txphy_cominit || m_txphy_comwake) {
        // Controller is sending COMINIT/COMWAKE - set comfinish in response
        m_txphy_comfinish = true;
        printf("DEVICE: Detecting COMINIT/COMWAKE\n");
    } else {
        m_txphy_comfinish = false;
    }
}

// Process OOB (Out-of-Band) signaling
bool SATASIM::process_oob() {
    bool coms_done = false;
    // bool sync_received = false;
    // static int align_cnt = 0;

    // Detect COMs and send responses
    detect_coms();
    coms_done = send_coms();

    if (coms_done) {
        // Controller is ready - exit electrical idle
        m_rxphy_elecidle = false;

        // Start sending ALIGN primitives (on RX clock domain)
        // device_sends(ALIGN_P, true);
        // align_cnt++;

        // Send SYNC primitive
        // sync_received = wait_for_primitive(SYNC_P);
        // if (sync_received && (align_cnt == 100))
        //     device_sends(SYNC_P, true);
    }

    return coms_done;
}

// Generate input signals for the controller (drives controller's inputs)
void SATASIM::process_rx_signals(bool &rxphy_cominit,
                             bool &rxphy_comwake,
                             bool &rxphy_elecidle,
                             bool &rxphy_valid,
                             bool &rxphy_primitive,
                             uint64_t &rxphy_data,
                             bool &phy_ready) {
    // Pass our internal RX signals to the output parameters
    rxphy_cominit = m_rxphy_cominit;
    rxphy_comwake = m_rxphy_comwake;
    rxphy_elecidle = m_rxphy_elecidle;
    rxphy_valid = m_rxphy_valid;
    
    // Construct 33-bit signal with primitive bit at MSB (bit 32)
    rxphy_data = (uint64_t)m_rxphy_data & 0xFFFFFFFF;  // 32-bit data
    if (m_rxphy_primitive)
        rxphy_data |= (1ULL << 32);  // Set bit 32 (primitive bit)
    
    rxphy_primitive = m_rxphy_primitive;
    
    // Pass other PHY status signals
    phy_ready = m_phy_ready;
}

// Update internal state from controller's outputs
void SATASIM::process_tx_signals(bool reset,
                              bool txphy_cominit, 
                              bool txphy_comwake, 
                              bool txphy_elecidle, 
                              bool txphy_primitive, 
                              uint32_t txphy_data,
                              bool &txphy_comfinish,
                              bool &txphy_ready,
                              bool link_ready) {
    // Update reset state
    m_reset = reset;
    m_link_ready = link_ready;
    
    // Set up PHY status based on reset
    if (m_reset) {
        m_txphy_ready = false;
        m_phy_ready = false;
    } else {
        m_txphy_ready = true;
        m_phy_ready = true;
    }

    txphy_comfinish = m_txphy_comfinish;
    txphy_ready = m_txphy_ready;

    // Capture TX signals from controller to our internal state
    m_txphy_cominit = txphy_cominit;
    m_txphy_comwake = txphy_comwake;
    m_txphy_elecidle = txphy_elecidle;
    m_txphy_primitive = txphy_primitive;
    m_txphy_data = txphy_data;
}

// Send data or primitive from device to host
void SATASIM::device_sends(uint32_t data, bool primitive) {
    // Set the data and primitive signals on RX clock domain
    m_rxphy_valid = true;
    m_rxphy_primitive = primitive;
    m_rxphy_data = data;
}

// Wait for a specific primitive from controller
bool SATASIM::wait_for_primitive(uint32_t primitive) {
    bool primitive_received = false;
    bool log_flag = false;
    
    // Wait for the specific primitive on the TX clock domain
    if((m_txphy_data == primitive) && (m_txphy_primitive)) {
        log_flag = true;
        primitive_received = true;
    }
    
    // Log which primitive was received
    if (log_flag) {
        log_flag = false;
        if (primitive == XRDY_P)
            printf("DEVICE: XRDY received\n");
        else if (primitive == RRDY_P)
            printf("DEVICE: RRDY received\n");
        else if (primitive == OK_P)
            printf("DEVICE: OK received\n");
        else if (primitive == WTRM_P)
            printf("DEVICE: WTRM received\n");
        else if (primitive == R_IP_P)
            printf("DEVICE: R_IP received\n");
        else if (primitive == EOF_P)
            printf("DEVICE: EOF received\n");
        else if (primitive == SYNC_P)
            printf("DEVICE: SYNC received\n");
        else if (primitive == SOF_P)
            printf("DEVICE: SOF received\n");
        else if (primitive == ALIGN_P)
            printf("DEVICE: ALIGN received\n");
    }
    
    return primitive_received;
}

// Wait for a specific command from controller
void SATASIM::wait_for_command() {
    uint32_t fis_type = 0;
    uint32_t cmd_type = 0;
    uint32_t scrambled_data = 0;
    
    // Extract FIS type from 32-bit data
    if (!m_txphy_primitive) {
        // Call scramble_data once and store the result
        scrambled_data = scramble_data(swap_endian(m_txphy_data), false);
        fis_type = (scrambled_data >> 16) & 0xFF;
        cmd_type = (scrambled_data & 0xFF);
        
        // printf("DEVICE: TX PHY data: 0x%08x\n", m_txphy_data);
        // printf("DEVICE: TX PHY data scrambled: 0x%08x\n", scrambled_data);
        // printf("DEVICE: FIS type: %x\n", fis_type);
    }

    if (fis_type == FIS_TYPE_DMA_WRITE && cmd_type == FIS_TYPE_REG_H2D) {
        m_dma_write = true;
        printf("DEVICE: DMA Write command received\n");
    } else if (fis_type == FIS_TYPE_DMA_READ && cmd_type == FIS_TYPE_REG_H2D) {
        m_dma_read = true;
        printf("DEVICE: DMA Read command received\n");
    }
}

// Helper function equivalent to the scramble function in satatx_scrambler.v
uint64_t SATASIM::scramble_function(uint16_t prior) {
    uint16_t s_fill = prior;
    uint32_t s_prn = 0;
    
    // Implement the Verilog scramble algorithm
    for (int k = 0; k < 32; k++) {
        // Get MSB bit
        s_prn |= ((s_fill >> 15) & 0x1) << k;
        
        // LFSR with polynomial
        if (s_fill & 0x8000) { // if MSB is 1
            s_fill = ((s_fill << 1) ^ SCRAMBLER_POLYNOMIAL) & 0xFFFF;
        } else {
            s_fill = (s_fill << 1) & 0xFFFF;
        }
    }
    
    // Return 48-bit result (32-bit PRN + 16-bit next state)
    return ((uint64_t)s_prn << 16) | s_fill;
}

// Main scrambling function 
uint32_t SATASIM::scramble_data(uint32_t data, bool init) {
    if (init)
        m_scrambler_fill = SCRAMBLER_INITIAL;
    uint64_t result = scramble_function(m_scrambler_fill);
    uint32_t prn = result >> 16;
    m_scrambler_fill = result & 0xFFFF;
    
    // XOR input data with generated PRN
    return data ^ prn;
}

// Helper function equivalent to the advance_crc function in satatx_crc.v
uint32_t SATASIM::advance_crc(uint32_t prior, uint32_t dword) {
    uint32_t sreg = prior;
    
    // Implement the Verilog CRC algorithm
    for (int k = 0; k < 32; k++) {
        bool bit = (sreg >> 31) & 0x1;
        bool data_bit = (dword >> (31-k)) & 0x1;
        
        if (bit ^ data_bit) {
            sreg = ((sreg << 1) ^ CRC_POLYNOMIAL) & 0xFFFFFFFF;
        } else {
            sreg = (sreg << 1) & 0xFFFFFFFF;
        }
    }
    
    return sreg;
}

// Main CRC calculation function
uint32_t SATASIM::calculate_crc(uint32_t data) {
    m_crc = advance_crc(m_crc, data);
    
    return m_crc;
}

// Activate DMA operation
void SATASIM::dma_activate() {
    // Send RRDY primitive (tells that device ready for data)
    wait_for_primitive(XRDY_P);
    device_sends(RRDY_P, true);
    
    // Send WTRM primitive (tells that device received data)
    wait_for_primitive(WTRM_P);
    device_sends(OK_P, true);
    
    // Send XRDY primitive (tells that device has something to send)
    wait_for_primitive(SYNC_P);
    device_sends(XRDY_P, true);
    
    // Send SOF primitive (tells that device detected the host is ready)
    wait_for_primitive(RRDY_P);
    device_sends(SOF_P, true);
    
    // Send Activate DMA (tells that DMA is activated)
    wait_for_primitive(R_IP_P);

    // Scrambled FIS command for DMA activate
    uint32_t fis_cmd = 0xB476D2C2;
    device_sends(fis_cmd, false);

    // CRC data for the FIS
    uint32_t crc_data = 0xE71B49DA;
    device_sends(crc_data, false);

    device_sends(EOF_P, true);
    
    // Send OK primitive (tells that transfer is complete)
    wait_for_primitive(OK_P);
    device_sends(SYNC_P, true);
}

// Link layer state machine for DMA activation
LinkState SATASIM::link_layer_model() {
    static int data_cnt = 0;
    static int align_cnt = 0;
    static int s_data = 0;
    static int dma_act_fis = (0x00 << 24) | (0x00 << 16) | (0x00 << 8) | 0x39; // DMA Activate FIS

    if (m_oob_done) {
        // Use a state machine to handle the link layer protocol
        switch (m_link_state) {
            case SEND_ALIGN:
                align_cnt++;    // Count the number of ALIGN primitives sent (100 is trivial)
                device_sends(ALIGN_P, true);
                // If OOB processing is done, transition to IDLE
                if (align_cnt == 100) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;

            case IDLE:
                device_sends(SYNC_P, true);
                // Host asks; if device is ready to accept data
                if (wait_for_primitive(XRDY_P)) {
                    m_link_state = RCV_CHKRDY;
                    printf("DEVICE: Link state -> RCV_CHKRDY\n");
                } else if  (m_dma_write) {
                    m_link_state = SEND_CHKRDY;
                    printf("DEVICE: Link state -> SEND_CHKRDY\n");
                }
                break;

            case SEND_CHKRDY:
                device_sends(XRDY_P, true);
                if (wait_for_primitive(RRDY_P)) {
                    m_link_state = SEND_DATA;
                    printf("DEVICE: Link state -> SEND_DATA\n");
                } else if (wait_for_primitive(XRDY_P)) {
                    m_link_state = RCV_CHKRDY;
                    printf("DEVICE: Link state -> RCV_CHKRDY\n");
                }
                break;

            case SEND_DATA:
                if (m_dma_write) {
                    if (data_cnt == 0) {
                        device_sends(SOF_P, true);
                        data_cnt++;
                    } else if (data_cnt == 1) {
                        s_data = swap_endian(scramble_data(dma_act_fis, true));    // Scrambled FIS command for DMA activate
                        device_sends(s_data, false);
                        data_cnt++;
                    } else if (data_cnt == 2) {
                        // !!! scramble_data(calculate_crc(swap_endian(dma_act_fis)), false)
                        s_data = 0xE71B49DA;    // CRC data for the FIS
                        device_sends(s_data, false);
                        data_cnt++;
                    } else if (data_cnt == 3) {
                        m_dma_write = false;
                        device_sends(EOF_P, true);
                        data_cnt++;
                        m_link_state = WAIT;
                        printf("DEVICE: Link state -> WAIT\n");
                    }
                }
                break;
            
            case RCV_CHKRDY:
                device_sends(RRDY_P, true);
                // Did we get the start of frame primitive?
                if (wait_for_primitive(SOF_P)) {
                    m_link_state = RCV_DATA;
                    printf("DEVICE: Link state -> RCV_DATA\n");
                }
                break;
            
            case RCV_DATA:
                device_sends(OK_P, true);
                // Receive data from host
                wait_for_command();
                if (wait_for_primitive(WTRM_P) && (m_dma_write || m_dma_read)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                break;
            
            case WAIT:
                device_sends(WTRM_P, true);
                //
                if (wait_for_primitive(SYNC_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                else if (wait_for_primitive(OK_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }
                else if (wait_for_primitive(ERR_P)) {
                    m_link_state = IDLE;
                    printf("DEVICE: Link state -> IDLE\n");
                }

                break;
            
            case GOODEND:
            //     // Send EOF primitive
            //     device_sends(EOF_P, true);
            //     m_link_state = LINK_WAIT_OK;
            //     printf("DEVICE: Link state -> LINK_WAIT_OK\n");
            //     break;
            
            case BADEND:
            //     // Wait for OK primitive
            //     primitive_detected = wait_for_primitive(OK_P);
            //     if (primitive_detected) {
            //         m_link_state = LINK_SEND_SYNC;
            //         printf("DEVICE: Link state -> LINK_SEND_SYNC\n");
            //     }
                break;
        }
    }

    return m_link_state;
}

// Debug function to show scrambling and CRC calculation for a given FIS
void SATASIM::debug_fis_scramble_crc(uint32_t fis_data) {
    // Reset the scrambler and CRC state
    m_scrambler_fill = SCRAMBLER_INITIAL;
    m_crc = CRC_INITIAL;
    
    // Calculate scrambled FIS
    uint32_t scrambled_fis = swap_endian(scramble_data(fis_data, true));
    
    // Calculate CRC
    uint32_t crc_data = swap_endian(scramble_data(calculate_crc(fis_data), false));
    
    // Print results
    std::cout << "FIS Debug Information:" << std::endl;
    std::cout << "  Original FIS: 0x" << std::hex << std::setw(8) << std::setfill('0') << fis_data << std::endl;
    std::cout << "  Scrambled FIS: 0x" << std::hex << std::setw(8) << std::setfill('0') << scrambled_fis << std::endl;
    std::cout << "  CRC: 0x" << std::hex << std::setw(8) << std::setfill('0') << crc_data << std::endl;
    std::cout << std::dec;
}
