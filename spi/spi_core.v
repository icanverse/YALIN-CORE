module spi_core (
    input wire clk,
    input wire reset,

    // ÜST MODÜL (TFT_Driver veya NRF_Driver) İLE HABERLEŞME
    input wire start_trigger,  // İşlemi başlat << Üst modülden gelir
    input wire [7:0] tx_data,  // Gönderilecek 8-bit veri << Üst modülden gelir
    
    output reg [7:0] rx_data,  // Okunan 8-bit veri >> Üst modüle verilir)
    output reg rx_valid,       // okuyabilirsin bayrağı << hazır veriyi al
    output reg busy,           // meşgul bayrağı >> veri almaz 

    // FİZİKSEL SPI PİNLERİ 
    output reg scl,            // SPI Saat Sinyali
    output reg mosi,           // Master Out Slave In (Eklentiye giden)
    input wire miso            // Master In Slave Out (Eklentiden gelen)
);

    parameter CLK_DIV = 2; 

    // SCL boşta seviyesi
    // 0 :: SCL boşta düşük (Mode 0)
    // 1 :: SCL boşta yüksek (Mode 3) << CS'siz ST7789 modülleri genelde bunu ister
    parameter IDLE_HIGH = 1'b0;

    reg [7:0] clk_count = 0;

    reg phase = 0;
    // 0 :: veriyi dışarıya it (SCL Low)
    // 1 :: veriyi içeriye al (SCL High)
    
    wire tick = (clk_count == CLK_DIV - 1);

    // FSM Durumları
    reg state = 0;
    localparam IDLE = 1'b0;
    localparam DATA = 1'b1;

    // Veri ve bit sayacı
    reg [7:0] shift_tx = 0;
    reg [2:0] bit_index = 7;

    initial begin
        scl = IDLE_HIGH;
        mosi = 0;
        busy = 0;
        rx_valid = 0;
        rx_data = 0;
    end

    always @(posedge clk) begin 
        if (reset) begin
            state <= IDLE;
            busy <= 0;
            rx_valid <= 0;
            scl <= IDLE_HIGH;
            clk_count <= 0;
            phase <= 0;
        end else begin
            clk_count <= clk_count + 1;

            if (tick) begin 
                clk_count <= 0;
                phase <= ~phase; 
            end

            if ( state == IDLE ) begin
                scl <= IDLE_HIGH;
                phase <= 0;
                rx_valid <= 0;

                if ( start_trigger == 1 ) begin
                    shift_tx <= tx_data;
                    bit_index <= 7;
                    state <= DATA;
                    busy <= 1;
                    clk_count <= 0;
                    phase <= 0;
                end else begin
                    busy <= 0;
                end 
            end else if ( state == DATA ) begin
                if (tick) begin 
                    if (phase == 0) begin
                        // Saati indir ve sıradaki biti dışarı it (MOSI)
                        scl <= 0;
                        mosi <= shift_tx[bit_index];
                    end else begin
                        // Saati kaldır ve gelen biti içeri al (MISO)
                        scl <= 1;
                        rx_data[bit_index] <= miso;
                        
                        // Bitleri kontrol et
                        if (bit_index == 0) begin
                            state <= IDLE;
                            busy <= 0;
                            rx_valid <= 1;
                        end else begin
                            // Henüz bitmedi, bir sonraki bite geç
                            bit_index <= bit_index - 1;
                        end
                    end

                end
            end
        end
    end


endmodule