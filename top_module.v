module tft_top (
    input  wire clk,        // Tang Nano 20K 27 MHz

    input  wire btn1,       // sol
    input  wire btn2,       // sağ

    // TFT
    output wire tft_scl,
    output wire tft_sda,
    output wire tft_res,
    output wire tft_dc,
    output wire tft_blk,

    // SPI Flash
    output wire flash_cs,
    output wire flash_clk,
    output wire flash_mosi,
    input  wire flash_miso
);

    // ---------- Ayarlar ----------
    localparam [23:0] BASE_ADDR   = 24'h200000;
    localparam [23:0] FRAME_SIZE  = 24'h01C200;       // 240*240*2 = 115200
    localparam [26:0] HOLD_CLKS   = 27'd1_000_000;    // kareler arası bekleme (~37 ms)
    localparam [27:0] IDLE_TIMEOUT = 28'd135_000_000; // ~5 sn butona basılmazsa parlama
    localparam        BTN_ACTIVE_LOW = 0;             // 0: butonlar basılınca 1 verir, 1: basılınca 0 verir

    // Animasyonlar
    localparam A_IDLE  = 0;  // 9 10 11 12 (döngü)
    localparam A_LEFT  = 1;  // 7 8 8 7
    localparam A_RIGHT = 2;  // 13 14 15 15 14 13
    localparam A_BLINK = 3;  // 1 2 3 4 5 6 6 5 4 3 2 1
    localparam A_GLOW  = 4;  // 16 17 18 18 17 16

    // Animasyondaki son adım numarası (uzunluk-1)
    function [3:0] last_pos;
        input [2:0] a;
        case (a)
            A_IDLE:  last_pos = 4'd3;
            A_LEFT:  last_pos = 4'd3;
            A_RIGHT: last_pos = 4'd5;
            A_BLINK: last_pos = 4'd11;
            A_GLOW:  last_pos = 4'd5;
            default: last_pos = 4'd3;
        endcase
    endfunction

    // Animasyon + adım -> bin içindeki kare numarası (0 tabanlı; yazdığın numara - 1)
    function [4:0] frame_of;
        input [2:0] a;
        input [3:0] p;
        case (a)
            A_IDLE: case (p)
                0: frame_of = 5'd8;   // 9
                1: frame_of = 5'd9;   // 10
                2: frame_of = 5'd10;  // 11
                default: frame_of = 5'd11; // 12
            endcase
            A_LEFT: case (p)
                0: frame_of = 5'd6;   // 7
                1: frame_of = 5'd7;   // 8
                2: frame_of = 5'd7;   // 8
                default: frame_of = 5'd6;  // 7
            endcase
            A_RIGHT: case (p)
                0: frame_of = 5'd12;  // 13
                1: frame_of = 5'd13;  // 14
                2: frame_of = 5'd14;  // 15
                3: frame_of = 5'd14;  // 15
                4: frame_of = 5'd13;  // 14
                default: frame_of = 5'd12; // 13
            endcase
            A_BLINK: case (p)
                0:  frame_of = 5'd0;  // 1
                1:  frame_of = 5'd1;  // 2
                2:  frame_of = 5'd2;  // 3
                3:  frame_of = 5'd3;  // 4
                4:  frame_of = 5'd4;  // 5
                5:  frame_of = 5'd5;  // 6
                6:  frame_of = 5'd5;  // 6
                7:  frame_of = 5'd4;  // 5
                8:  frame_of = 5'd3;  // 4
                9:  frame_of = 5'd2;  // 3
                10: frame_of = 5'd1;  // 2
                default: frame_of = 5'd0; // 1
            endcase
            A_GLOW: case (p)
                0: frame_of = 5'd15;  // 16
                1: frame_of = 5'd16;  // 17
                2: frame_of = 5'd17;  // 18
                3: frame_of = 5'd17;  // 18
                4: frame_of = 5'd16;  // 17
                default: frame_of = 5'd15; // 16
            endcase
            default: frame_of = 5'd8;
        endcase
    endfunction

    // ---------- Butonlar ----------
    wire b1, b2;
    button_filter #(.ACTIVE_LOW(BTN_ACTIVE_LOW)) f1 (.clk(clk), .raw(btn1), .pressed(b1));
    button_filter #(.ACTIVE_LOW(BTN_ACTIVE_LOW)) f2 (.clk(clk), .raw(btn2), .pressed(b2));

    reg b1_d = 0, b2_d = 0;
    reg l1 = 0, l2 = 0;   // basış mandalları (kısa basışlar kaçmasın, iki butonun "aynı anda" basışı yakalansın)

    // ---------- İç sinyaller ----------
    wire        pixel_req, pixel_valid, flash_busy, frame_done;
    wire [15:0] pixel_data;

    reg [23:0] base_address = BASE_ADDR;
    reg        start_read   = 0;
    reg        src_ready    = 0;
    reg        next_frame   = 0;

    // ---------- Kare yöneticisi ----------
    localparam M_BOOT = 0, M_BUSY_HI = 1, M_BUSY_LO = 2, M_RUN = 3, M_HOLD = 4, M_DECIDE = 5;

    reg [2:0]  mstate    = M_BOOT;
    reg [7:0]  boot_cnt  = 0;
    reg [2:0]  cur_anim  = A_IDLE;
    reg [3:0]  seq_pos   = 0;
    reg [26:0] hold_cnt  = 0;
    reg [27:0] idle_cnt  = 0;

    reg [2:0]  n_anim;
    reg [3:0]  n_pos;
    reg        want1, want2, at_end;

    always @(posedge clk) begin
        start_read <= 0;
        next_frame <= 0;
        b1_d <= b1;
        b2_d <= b2;

        // Boşta animasyonundayken sayaç işler, başka animasyonda sıfırlanır
        if (cur_anim == A_IDLE) begin
            if (idle_cnt != 28'hFFFFFFF) idle_cnt <= idle_cnt + 1;
        end else idle_cnt <= 0;

        case (mstate)
            M_BOOT: begin
                base_address <= BASE_ADDR + ({19'd0, frame_of(cur_anim, seq_pos)} * FRAME_SIZE);
                boot_cnt <= boot_cnt + 1;
                if (boot_cnt == 100) begin
                    start_read <= 1;
                    mstate <= M_BUSY_HI;
                end
            end

            M_BUSY_HI: if (flash_busy) mstate <= M_BUSY_LO;

            M_BUSY_LO: if (!flash_busy) begin   // adres kurulumu bitti
                src_ready <= 1;
                mstate <= M_RUN;
            end

            M_RUN: if (frame_done) begin        // kare tamamen çizildi
                src_ready <= 0;
                hold_cnt  <= 0;
                mstate    <= M_HOLD;
            end

            M_HOLD: begin
                hold_cnt <= hold_cnt + 1;
                if (hold_cnt == HOLD_CLKS) mstate <= M_DECIDE;
            end

            M_DECIDE: begin
                want1  = l1 | b1;
                want2  = l2 | b2;
                at_end = (seq_pos == last_pos(cur_anim));
                n_anim = cur_anim;
                n_pos  = seq_pos + 1;

                if (cur_anim == A_IDLE || at_end) begin
                    // Karar noktası
                    if (want1 && want2) begin
                        n_anim = A_BLINK; n_pos = 0; l1 <= 0; l2 <= 0;
                    end else if (want1) begin
                        n_anim = A_LEFT;  n_pos = 0; l1 <= 0; l2 <= 0;
                    end else if (want2) begin
                        n_anim = A_RIGHT; n_pos = 0; l1 <= 0; l2 <= 0;
                    end else if (cur_anim == A_IDLE && idle_cnt >= IDLE_TIMEOUT) begin
                        n_anim = A_GLOW;  n_pos = 0;
                    end else if (cur_anim == A_IDLE) begin
                        n_anim = A_IDLE;
                        n_pos  = at_end ? 4'd0 : seq_pos + 1;   // 9 10 11 12 döngüsü
                    end else begin
                        n_anim = A_IDLE;  n_pos = 0;            // animasyon bitti, boşta'ya dön
                    end
                end

                cur_anim   <= n_anim;
                seq_pos    <= n_pos;
                boot_cnt   <= 0;
                next_frame <= 1;
                mstate     <= M_BOOT;   // 100 clk sonra yeni adresle start_read atılır
            end
        endcase

        // Basış kenarları (mandal) - temizlemeden sonra yazıldığı için kazanır
        if (b1 && !b1_d) l1 <= 1;
        if (b2 && !b2_d) l2 <= 1;
    end

    // ---------- TFT ----------
    tft_st7789_core my_tft (
        .clk(clk), .reset(1'b0),
        .tft_scl(tft_scl), .tft_sda(tft_sda),
        .tft_res(tft_res), .tft_dc(tft_dc), .tft_blk(tft_blk),
        .pixel_req(pixel_req), .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .src_ready(src_ready),
        .next_frame(next_frame), .frame_done(frame_done),
        .dbg_state(), .dbg_step()
    );

    // ---------- Flash ----------
    flash_reader my_flash (
        .clk(clk), .reset(1'b0),
        .start_read(start_read),
        .base_address(base_address),
        .busy(flash_busy),
        .pixel_req(pixel_req), .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .flash_cs(flash_cs), .flash_clk(flash_clk),
        .flash_mosi(flash_mosi), .flash_miso(flash_miso)
    );

endmodule

module button_filter #(
    parameter ACTIVE_LOW = 1,          
    parameter CNT_MAX    = 270000      
)(
    input  wire clk,
    input  wire raw,
    output wire pressed
);
    reg s0 = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg s1 = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg state = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg [18:0] cnt = 0;

    always @(posedge clk) begin
        s0 <= raw;
        s1 <= s0;
        if (s1 != state) begin
            if (cnt == CNT_MAX) begin
                state <= s1;
                cnt   <= 0;
            end else cnt <= cnt + 1;
        end else cnt <= 0;
    end

    assign pressed = ACTIVE_LOW ? ~state : state;
endmodule