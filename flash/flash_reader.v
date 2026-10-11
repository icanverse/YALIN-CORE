module flash_reader (
    input wire clk,
    input wire reset,

    // Üst kontrolcü sinyalleri
    input wire start_read,
    input wire [23:0] base_address,
    output reg busy,

    // TFT core ile haberleşme
    input wire pixel_req,
    output reg pixel_valid,
    output reg [15:0] pixel_data,

    // Fiziksel SPI Flash pinleri
    output reg flash_cs,
    output wire flash_clk,
    output wire flash_mosi,
    input wire flash_miso
);

    // --- Alt modül: SPI çekirdeği ---
    reg spi_start = 0;
    reg [7:0] spi_tx = 0;
    wire [7:0] spi_rx;
    wire spi_busy_flag;

    // Flash bellekler genellikle Mode 0 (IDLE_HIGH=0) ile çalışır
    spi_core #(.IDLE_HIGH(1'b0), .CLK_DIV(2)) flash_spi (
        .clk(clk),
        .reset(reset),
        .start_trigger(spi_start),
        .tx_data(spi_tx),
        .rx_data(spi_rx),
        .rx_valid(),
        .busy(spi_busy_flag),
        .scl(flash_clk),
        .mosi(flash_mosi),
        .miso(flash_miso)
    );

    // --- Durum makinesi ---
    reg [3:0] state = 0;
    
    localparam S_IDLE       = 0;
    localparam S_CMD        = 1;
    localparam S_ADDR_2     = 2;
    localparam S_ADDR_1     = 3;
    localparam S_ADDR_0     = 4;
    localparam S_WAIT_REQ   = 5;
    localparam S_READ_HIGH  = 6;
    localparam S_READ_LOW   = 7;
    localparam S_DONE_PIXEL = 8;
    localparam S_RESTART    = 9;
    localparam S_RESTART2   = 10;

    reg [1:0] wait_spi = 0;

    always @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            flash_cs    <= 1;
            busy        <= 0;
            pixel_valid <= 0;
            spi_start   <= 0;
            wait_spi    <= 0;
        end else begin
            pixel_valid <= 0;

            case (state)
                S_IDLE: begin
                    flash_cs <= 1;
                    busy     <= 0;
                    
                    if (start_read) begin
                        flash_cs <= 0;
                        busy     <= 1;
                        state    <= S_CMD;
                    end
                end

                // 0x03 Okuma komutu
                S_CMD: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= 8'h03; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin 
                        if (!spi_busy_flag) begin 
                            wait_spi <= 0; 
                            state    <= S_ADDR_2; 
                        end 
                    end
                end

                S_ADDR_2: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= base_address[23:16]; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin 
                        if (!spi_busy_flag) begin 
                            wait_spi <= 0; 
                            state    <= S_ADDR_1; 
                        end 
                    end
                end

                S_ADDR_1: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= base_address[15:8]; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin 
                        if (!spi_busy_flag) begin 
                            wait_spi <= 0; 
                            state    <= S_ADDR_0; 
                        end 
                    end
                end

                S_ADDR_0: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= base_address[7:0]; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin
                        if (!spi_busy_flag) begin
                            wait_spi <= 0;
                            state    <= S_WAIT_REQ;
                            busy     <= 0; // kurulum bitti, TFT'den piksel isteği bekleniyor
                        end
                    end
                end

                // TFT'den istek bekle
                S_WAIT_REQ: begin
                    if (start_read) begin
                        flash_cs <= 1;       // CS'yi bırak, yeni adresle baştan başla
                        busy     <= 1;
                        state    <= S_RESTART;
                    end else if (pixel_req) begin
                        state    <= S_READ_HIGH;
                    end
                end

                S_RESTART: begin
                    state <= S_RESTART2; // CS birkaç clk yüksek kalsın
                end

                S_RESTART2: begin
                    flash_cs <= 0;
                    state    <= S_CMD;
                end

                // Üst bayt
                S_READ_HIGH: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= 8'h00; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin
                        if (!spi_busy_flag) begin
                            wait_spi         <= 0;
                            pixel_data[15:8] <= spi_rx;
                            state            <= S_READ_LOW;
                        end
                    end
                end

                // Alt bayt
                S_READ_LOW: begin
                    if (wait_spi == 0) begin 
                        spi_tx    <= 8'h00; 
                        spi_start <= 1; 
                        wait_spi  <= 1; 
                    end 
                    else if (wait_spi == 1) begin 
                        spi_start <= 0; 
                        if (spi_busy_flag) begin
                            wait_spi <= 2; 
                        end
                    end 
                    else begin
                        if (!spi_busy_flag) begin
                            wait_spi        <= 0;
                            pixel_data[7:0] <= spi_rx;
                            state           <= S_DONE_PIXEL;
                        end
                    end
                end

                S_DONE_PIXEL: begin
                    pixel_valid <= 1;
                    state       <= S_WAIT_REQ; // CS açık kalır, flash adresi otomatik artırır
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule