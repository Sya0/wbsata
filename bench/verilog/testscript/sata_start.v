`include "../testscript/satalib.v"


module sata_soft_reset (
    input wire clk,         // Clock sinyali
    input wire reset,       // Reset sinyali
    output reg [31:0] tx_data, // Gönderilecek veri (FIS verisi)
    output reg tx_ready,    // Komut gönderim sinyali
    input wire rx_ready     // Alıcı hazır sinyali
);

    // Durum makineleri için tanımlar
    localparam IDLE        = 3'b000;
    localparam SEND_FIS    = 3'b001;
    localparam WAIT_RESP   = 3'b010;

    // FIS tipleri
    localparam [7:0] FIS_TYPE_CONTROL = 8'hA1;  // Control FIS tipi

    reg [2:0] state;          // Durum makinesi durumu
    reg [7:0] control_field;  // Control FIS için kontrol alanı

    initial begin
        state = IDLE;
        tx_ready = 0;
        control_field = 8'h08; // Soft Reset komutunun Control alanı
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx_ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_ready <= 0;
                    if (!reset) begin
                        // Control FIS paketini hazırla
                        tx_data <= {FIS_TYPE_CONTROL, 24'h080000}; // Soft Reset için FIS
                        $display("Preparing Soft Reset FIS: %h", tx_data);
                        state <= SEND_FIS;
                    end
                end

                SEND_FIS: begin
                    tx_ready <= 1;  // Gönderim başlıyor
                    $display("Sending Soft Reset FIS...");
                    state <= WAIT_RESP;
                end

                WAIT_RESP: begin
                    if (rx_ready) begin
                        tx_ready <= 0;
                        $display("Soft Reset completed.");
                        state <= IDLE; // İşlem tamamlandı
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
