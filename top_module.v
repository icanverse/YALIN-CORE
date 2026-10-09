module tft_top (
    input  wire clk,        // Tang Nano 20K'nın 27 MHz saati
    output wire tft_scl,    // 73
    output wire tft_sda,    // 74  (MOSI)
    output wire tft_res,    // 75
    output wire tft_dc,     // 85
    output wire tft_blk     // 77
);

    tft_st7789_core my_tft (
        .clk(clk),
        .reset(1'b0),

        .tft_scl(tft_scl),
        .tft_sda(tft_sda),
        .tft_res(tft_res),
        .tft_dc(tft_dc),
        .tft_blk(tft_blk),

        .dbg_state(),       // Kullanılmıyor
        .dbg_step()         // Kullanılmıyor
    );

endmodule