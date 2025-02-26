module mdl_alignp_transmit (
    input wire clk,
    input wire reset,
    input wire burst_en,
    input wire [39:0] data_p,
    output reg tx_p,
    output reg tx_n
);

    localparam ALIGNP_BIT = 40;

    reg [ALIGNP_BIT-1:0] shift_reg;
    reg [5:0] bit_count;

    always @(*) begin
        if (burst_en) begin
            tx_p <= shift_reg[39];   // Verinin en üst biti tx_p'ye atanır
            tx_n <= ~shift_reg[39];  // Diferansiyel sinyal, tx_n tx_p'nin tersi olur
        end else begin
            tx_p <= 1'bX;
            tx_n <= 1'bX;
        end
    end

    // Sinyal gönderme işlemi
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_reg <= data_p;  // ALIGNP verisini kaydırma register'ına yükle
            bit_count <= 0;
        end else begin
            if (burst_en) begin
                // Bir bit gönder ve veriyi kaydır
                if (bit_count == (ALIGNP_BIT-1)) begin
                    bit_count <= 0;
                    shift_reg <= data_p;
                end else begin
                    bit_count <= bit_count + 1;
                    shift_reg <= {shift_reg[38:0], 1'b0}; // Veriyi sola kaydır
                end
            end else begin
                // ALIGNP verisi bittiğinde tx_p ve tx_n'i idle seviyede tut
                shift_reg <= data_p;  // ALIGNP verisini kaydırma register'ına yükle
            end
        end
    end

endmodule

