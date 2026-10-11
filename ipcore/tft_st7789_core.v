module tft_st7789_core(
    input  wire        clk,
    input  wire        reset,

    output wire        tft_scl,
    output wire        tft_sda,        // MOSI
    output reg         tft_res = 1'b0,
    output reg         tft_dc  = 1'b0,
    output reg         tft_blk = 1'b1, // arka plan ışığı sürekli açık

    // Flash okuyucu ile el sıkışma
    output reg         pixel_req = 1'b0,
    input  wire        pixel_valid,
    input  wire [15:0] pixel_data,
    input  wire        src_ready,      // flash adres kurulumu bitti

    // Kare kontrolü
    input  wire        next_frame,     // yeni kare çizimini başlat (1 clk darbe)
    output wire        frame_done,

    // Hata ayıklama
    output wire [2:0]  dbg_state,
    output wire [5:0]  dbg_step
);

    // Durumlar
    reg [2:0] tft_state = 0;
    
    localparam STATE_RESET = 0;
    localparam STATE_INIT  = 1;
    localparam STATE_DRAW  = 2;
    localparam STATE_DONE  = 3;

    reg [23:0] delay_count = 0;
    reg [5:0]  step        = 0;
    reg [1:0]  wait_spi    = 0;   // 0: başlat, 1: busy yükselsin, 2: busy düşsün

    // SPI çekirdeği
    reg        spi_start   = 0;
    reg [7:0]  spi_tx_data = 0;
    wire       spi_busy;

    spi_core #(.IDLE_HIGH(1'b1), .CLK_DIV(2)) my_spi (
        .clk(clk),
        .reset(reset),
        .start_trigger(spi_start),
        .tx_data(spi_tx_data),
        .rx_data(),
        .rx_valid(),
        .busy(spi_busy),
        .scl(tft_scl),
        .mosi(tft_sda),
        .miso(1'b0)
    );

    assign dbg_state  = tft_state;
    assign dbg_step   = step;
    assign frame_done = (tft_state == STATE_DONE);

    reg [7:0]  delay_tour = 0;
    reg [15:0] pixel_cnt  = 0;
    reg [15:0] pixel_buf  = 0;

    always @(posedge clk) begin
        if (reset) begin
            tft_state   <= STATE_RESET;
            step        <= 0;
            wait_spi    <= 0;
            spi_start   <= 0;
            delay_count <= 0;
            delay_tour  <= 0;
            pixel_cnt   <= 0;
            pixel_buf   <= 0;
            pixel_req   <= 0;
            tft_res     <= 0;
            tft_dc      <= 0;
        end else begin
            case (tft_state)

                // ================= RESET =================
                STATE_RESET: begin
                    if (step == 0) begin
                        tft_res     <= 0;
                        delay_count <= delay_count + 1;
                        
                        if (delay_count == 27000) begin
                            delay_count <= 0;
                            delay_tour  <= delay_tour + 1;
                            
                            if (delay_tour == 20) begin
                                step       <= 1;
                                delay_tour <= 0;
                            end
                        end
                    end 
                    else if (step == 1) begin
                        tft_res     <= 1;
                        delay_count <= delay_count + 1;
                        
                        if (delay_count == 27000) begin
                            delay_count <= 0;
                            delay_tour  <= delay_tour + 1;
                            
                            if (delay_tour == 120) begin
                                step       <= 0;
                                delay_tour <= 0;
                                tft_state  <= STATE_INIT;
                            end
                        end
                    end
                end

                // ================= INIT =================
                STATE_INIT: begin
                    case (step)
                        0: begin // Sleep Out (0x11)
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h11; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        1: begin // 120 ms bekleme
                            delay_count <= delay_count + 1;
                            if (delay_count == 27000) begin
                                delay_count <= 0;
                                delay_tour  <= delay_tour + 1;
                                
                                if (delay_tour == 120) begin
                                    step       <= step + 1;
                                    delay_tour <= 0;
                                end
                            end
                        end

                        2: begin // COLMOD (0x3A)
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h3A; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        3: begin // RGB565
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h55; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        4: begin // MADCTL (0x36)
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h36; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        5: begin // MADCTL verisi
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        6: begin // INVON (0x21)
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h21; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        7: begin // Display ON (0x29)
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h29; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end
                        end

                        8: begin
                            step      <= 0;
                            tft_state <= STATE_DRAW;
                        end
                    endcase
                end

                // ================= DRAW =================
                STATE_DRAW: begin
                    case (step)
                        // --- Sütun adresi (0x2A): 0..239 ---
                        0: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h2A; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        1: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        2: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        3: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        4: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'hEF; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        // --- Satır adresi (0x2B): 0..239 ---
                        5: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h2B; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        6: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        7: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        8: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h00; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        9: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'hEF; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        // --- Memory Write (0x2C) ---
                        10: begin 
                            if (wait_spi == 0) begin 
                                spi_tx_data <= 8'h2C; 
                                tft_dc      <= 0; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= step + 1; 
                                end 
                            end 
                        end

                        // --- Piksel döngüsü (57.600 kez) ---
                        11: begin // Flash hazırsa piksel iste (1 clk darbe)
                            if (src_ready) begin
                                pixel_req <= 1;
                                step      <= 12;
                            end
                        end

                        12: begin
                            pixel_req <= 0;
                            step      <= 13;
                        end

                        13: begin // Pikselin gelmesini bekle
                            if (pixel_valid) begin
                                pixel_buf <= pixel_data;
                                step      <= 14;
                            end
                        end

                        14: begin // Üst bayt
                            if (wait_spi == 0) begin 
                                spi_tx_data <= pixel_buf[15:8]; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin 
                                if (!spi_busy) begin 
                                    wait_spi <= 0; 
                                    step     <= 15; 
                                end 
                            end
                        end

                        15: begin // Alt bayt + döngü kontrolü
                            if (wait_spi == 0) begin 
                                spi_tx_data <= pixel_buf[7:0]; 
                                tft_dc      <= 1; 
                                spi_start   <= 1; 
                                wait_spi    <= 1; 
                            end 
                            else if (wait_spi == 1) begin 
                                spi_start <= 0; 
                                if (spi_busy) begin
                                    wait_spi <= 2; 
                                end
                            end 
                            else begin
                                if (!spi_busy) begin
                                    wait_spi <= 0;
                                    
                                    if (pixel_cnt == 57599) begin
                                        step <= 16;
                                    end else begin
                                        pixel_cnt <= pixel_cnt + 1;
                                        step      <= 11;
                                    end
                                end
                            end
                        end

                        16: begin
                            tft_state <= STATE_DONE;
                        end
                    endcase
                end

                // ================= DONE =================
                STATE_DONE: begin
                    if (next_frame) begin
                        pixel_cnt <= 0;
                        step      <= 0;
                        wait_spi  <= 0;
                        tft_state <= STATE_DRAW;
                    end
                end

            endcase
        end
    end
endmodule