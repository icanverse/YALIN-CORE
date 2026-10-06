module top_module (
    input wire clk,          // Tang Nano 20K'nın kendi 27 MHz saati
    input wire btn,          // Kartın üzerindeki fiziksel buton (Tetikleyici)
    
    inout wire sda,          // AS5600'e giden SDA kablosu
    output wire scl,         // AS5600'e giden SCL kablosu
    
    output wire [5:0] led    // Kartın üzerindeki 6 adet LED (Görsel geri bildirim için)
);

    // =========================================================
    // 1. BUTON KENAR YAKALAYICI (Edge Detector)
    // Butona bastığımızda parmağımız milisaniyelerce basılı kalır. 
    // Ama FSM bizden sadece 1 saat vuruşu (1 nanosaniye) uzunluğunda bir "start_trigger" bekliyor.
    // Bu kod, butonun sadece 1'den 0'a DÜŞTÜĞÜ o tek anı yakalar.
    // =========================================================
    reg btn_sync1 = 1;
    reg btn_sync2 = 1;
    
    always @(posedge clk) begin
        btn_sync1 <= btn;        // Butonun o anki hali
        btn_sync2 <= btn_sync1;  // Butonun 1 vuruş önceki hali
    end
    
    // Buton bırakılmış (1) durumundan, basılmış (0) durumuna geçtiği o tek an!
    wire start_trigger = (btn_sync1 == 0 && btn_sync2 == 1);


    // =========================================================
    // 2. I2C ÇEKİRDEĞİNİ (IP CORE) ÇAĞIRMA VE KABLOLAMA
    // =========================================================
    wire i2c_error; // Çekirdekten gelecek hata sinyalini tutacağımız tel
    
    i2c_core my_i2c_master (
        .clk(clk),
        .reset(1'b0),
        .start_trigger(start_trigger),
        
        .dev_addr(7'h36),     // AS5600'ün I2C Donanım Adresi
        .rw_flag(1'b0),       // 0 = Sensöre Yazma yap (Write)
        .reg_addr(8'h07),     // Hedef Klasör: AS5600 CONF (Ayar) Register'ı
        .tx_data(8'h00),      // İçine yazılacak veri: Ayarları sıfırla
        
        .sda(sda),            // Fiziksel pinlere giden direkt yollar
        .scl(scl),
        .error_flag(i2c_error) // Hatayı okuyup telimize bağladık
    );


    // =========================================================
    // 3. LED BİLDİRİMLERİ (Tang Nano 20K'da LED'ler 0'da yanar, 1'de söner)
    // =========================================================
    // LED 5 (En sağdaki): HATA varsa KIRMIZI yanar
    // =========================================================
    // 3. LED BİLDİRİMLERİ (Tang Nano 20K'da LED'ler 0'da yanar)
    // =========================================================
    
    // Pin 16 (led[1]): HATA (NACK) varsa yanar
    assign led[1] = ~i2c_error; 
    
    // Pin 15 (led[0]): İşlem BAŞARILIYSA (ACK) yanar
    reg success_led = 1; 
    
    always @(posedge clk) begin
        if (start_trigger) begin
            success_led <= 1; 
        end else if (my_i2c_master.state == 4'd3 /*STOP*/) begin
            if (i2c_error == 0) begin
                success_led <= 0; 
            end
        end
    end
    
    assign led[0] = success_led;
    
    // Diğer kullanılmayan LED'leri (Pin 17, 18, 19, 20) sönük (1) bırak
    assign led[5:2] = 4'b1111;

endmodule