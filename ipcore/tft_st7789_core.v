module tft_st7789_core(
    input wire clk,
    input wire reset,
    
    output wire tft_scl,
    output wire tft_sda, // MOSI
    output reg  tft_res = 1'b0,
    output reg  tft_dc  = 1'b0,
    output reg  tft_blk = 1'b1,  // _blk :: arka plan ışığı = 1 :: sürekli açık

    // HATA AYIKLAMA ÇIKIŞLARI (kullanmazsan boş bırakabilirsin)
    output wire [2:0] dbg_state,
    output wire [5:0] dbg_step
);
    
    // BAŞLATMA YÖNETİMİ
    reg [2:0] tft_state = 0;
    localparam STATE_RESET  = 0;
    localparam STATE_INIT = 1;
    localparam STATE_DRAW = 2;
    localparam STATE_DONE = 3;

    reg [23:0] delay_count = 0;

    reg [5:0] step = 0;

    // SPI el sıkışması (handshake) durumu
    // 0 :: veriyi hazırla ve start darbesi ver
    // 1 :: SPI çekirdeğinin busy'yi yükseltmesini bekle
    // 2 :: SPI çekirdeğinin busy'yi düşürmesini bekle (bayt bitti)
    reg [1:0] wait_spi = 0;

    // SPI Çekirdeği İle Haberleşmek İçin
    reg  spi_start = 0;
    reg  [7:0] spi_tx_data = 0;
    wire spi_busy;

    spi_core #(.IDLE_HIGH(1'b1), .CLK_DIV(8)) my_spi (
        .clk(clk),
        .reset(reset),
        
        .start_trigger(spi_start),  // İçerideki reg ile bağladık
        .tx_data(spi_tx_data),      // İçerideki reg ile bağladık
        
        .rx_data(),                 // Boş bıraktık
        .rx_valid(),                // Boş bıraktık
        .busy(spi_busy),            // İçerideki wire ile bağladık
        
        .scl(tft_scl),              // Doğrudan dışarı giden fiziksel pine bağladık
        .mosi(tft_sda),             // Doğrudan dışarı giden fiziksel pine bağladık
        .miso(1'b0)                 // Ekrandan okuma pini yok
    );

    assign dbg_state = tft_state;
    assign dbg_step  = step;

    reg [7:0] delay_tour = 0;
    reg [15:0] pixel_cnt = 0;

    always @(posedge clk) begin 
        if (reset) begin
            // spi_core ile aynı şekilde aktif-yüksek reset
            tft_state   <= STATE_RESET;
            step        <= 0;
            wait_spi    <= 0;
            spi_start   <= 0;
            delay_count <= 0;
            delay_tour  <= 0;
            pixel_cnt   <= 0;
            tft_res     <= 0;
            tft_dc      <= 0;
        end else begin
        case(tft_state)
            STATE_RESET: begin 
                if (step == 0) begin 
                    tft_res <= 0;
                    delay_count <= delay_count + 1;
        
                    if (delay_count == 27000) begin 
                        delay_count <= 0; 
                        delay_tour <= delay_tour + 1;

                        if (delay_tour == 20) begin 
                            step <= 1; 
                            delay_tour <= 0; 
                        end
                    end
                end else if (step == 1) begin 
                    tft_res <= 1;
                    delay_count <= delay_count + 1; 
        
                    if (delay_count == 27000) begin 
                        delay_count <= 0;
                        delay_tour <= delay_tour + 1;

                        if (delay_tour == 120) begin 
                            step <= 0;               
                            delay_tour <= 0;         
                            tft_state <= STATE_INIT; 
                        end
                    end
                end
            end
            
            STATE_INIT: begin 
                case (step)
                    // Uyandırma (Sleep Out) Komutu
                    0: begin 
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h11;
                            tft_dc <= 0; // Komut
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2; // SPI başladı
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1;
                            end
                        end
                    end
                    
                    // Uyandıktan Sonra 120ms Donanımsal Bekleme
                    1: begin 
                        delay_count <= delay_count + 1;
                        if (delay_count == 27000) begin 
                            delay_count <= 0;
                            delay_tour <= delay_tour + 1;
                            if (delay_tour == 120) begin 
                                step <= step + 1;
                                delay_tour <= 0;
                            end
                        end
                    end

                    // Renk Formatı (COLMOD) Komutu
                    2: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h3A;
                            tft_dc <= 0; // Komut
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Renk Formatı Verisi (RGB565 = 16 bit)
                    3: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h55;
                            tft_dc <= 1; // Veri
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Ekran Yönü (MADCTL) Komutu
                    4: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h36;
                            tft_dc <= 0; // Komut
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Ekran Yönü Verisi (Standart)
                    5: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h00;
                            tft_dc <= 1; // Veri
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Renkleri Ters Çevir (INVON) Komutu - çoğu 240x240 modül bunu ister
                    6: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h21;
                            tft_dc <= 0; // Komut
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Ekranı Aç (Display ON) Komutu
                    7: begin
                        if (wait_spi == 0) begin 
                            spi_tx_data <= 8'h29;
                            tft_dc <= 0; // Komut
                            spi_start <= 1;
                            wait_spi <= 1;
                        end else if (wait_spi == 1) begin
                            spi_start <= 0;
                            if (spi_busy == 1) wait_spi <= 2;
                        end else begin
                            if (spi_busy == 0) begin 
                                wait_spi <= 0;
                                step <= step + 1; 
                            end
                        end
                    end

                    // Başlatma Tamamlandı, Çizime Geç
                    8: begin
                        step <= 0;               // DRAW aşaması için sayacı sıfırla
                        tft_state <= STATE_DRAW; // Çizim fazına geç
                    end
                endcase
            end

            STATE_DRAW: begin 
                case (step)
                    // ==========================================
                    // 1. SÜTUN ADRESİ AYARI (0x2A) - X Koordinatı: 0'dan 239'a
                    // ==========================================
                    0: begin // Sütun Adres Komutu
                        if (wait_spi == 0) begin spi_tx_data <= 8'h2A; tft_dc <= 0; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    1: begin // Start X High (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    2: begin // Start X Low (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    3: begin // End X High (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    4: begin // End X Low (239 = 0xEF)
                        if (wait_spi == 0) begin spi_tx_data <= 8'hEF; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end

                    // ==========================================
                    // 2. SATIR ADRESİ AYARI (0x2B) - Y Koordinatı: 0'dan 239'a
                    // ==========================================
                    5: begin // Satır Adres Komutu
                        if (wait_spi == 0) begin spi_tx_data <= 8'h2B; tft_dc <= 0; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    6: begin // Start Y High (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    7: begin // Start Y Low (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    8: begin // End Y High (0)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    9: begin // End Y Low (239 = 0xEF)
                        if (wait_spi == 0) begin spi_tx_data <= 8'hEF; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end

                    // ==========================================
                    // 3. HAFIZAYA YAZMA BAŞLANGICI VE RENK DÖNGÜSÜ
                    // ==========================================
                    10: begin // Memory Write Komutu (0x2C)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h2C; tft_dc <= 0; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    
                    // -- DÖNGÜ BAŞLANGICI (57.600 Kez Çalışacak) --
                    11: begin // Kırmızı Renk Üst Bayt (0xF8)
                        if (wait_spi == 0) begin spi_tx_data <= 8'hF8; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin if (spi_busy == 0) begin wait_spi <= 0; step <= step + 1; end end
                    end
                    
                    12: begin // Kırmızı Renk Alt Bayt (0x00)
                        if (wait_spi == 0) begin spi_tx_data <= 8'h00; tft_dc <= 1; spi_start <= 1; wait_spi <= 1; end 
                        else if (wait_spi == 1) begin spi_start <= 0; if (spi_busy == 1) wait_spi <= 2; end
                        else begin 
                            if (spi_busy == 0) begin 
                                wait_spi <= 0; 
                                
                                // Piksel bitti, sayacı kontrol et
                                if (pixel_cnt == 57599) begin
                                    step <= step + 1; // Tüm ekran boyandı, döngüden çık
                                end else begin
                                    pixel_cnt <= pixel_cnt + 1; // Sonraki piksele geç
                                    step <= 11; // DÖNGÜYÜ BAŞA SAR (Üst bayt gönderimine dön)
                                end
                            end 
                        end
                    end
                    
                    13: begin // Çizim İşlemi Bitti
                        tft_state <= STATE_DONE;
                    end
                endcase
            end
            
            STATE_DONE: begin
                // Sistem boşta bekler. İleride görüntü değiştirmek istersen
                // state'i tekrar STATE_DRAW'a çekip pixel_cnt'yi 0'laman yeterli.
            end
        endcase
        end
    end
endmodule