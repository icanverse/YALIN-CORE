module uart_tx (
    input wire clk,         
    input wire tx_start,       
    input wire [7:0] tx_data,  
    
    output reg tx_pin,      
    output reg busy         // Modül veri gönderirken 1, boştayken 0 olmalı
);

    parameter BIT_RATE_MAX = 8'd234;
    
    reg [7:0] clk_count = 0;   // 234'e kadar sayacak zamanlayıcı
    reg [2:0] bit_index = 0;   
    reg [7:0] shift_data = 0;  
    
    reg [1:0] state = 0;
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    initial begin
        tx_pin = 1; 
        busy = 0;
    end

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                tx_pin = 1;
                busy = 0;
                if ( tx_start == 1 ) begin
                    shift_data <= tx_data;
                    bit_index <= 0;
                    clk_count <=0;
                    tx_pin <= 0;
                    busy <=1;
                    state <= START;
                end             
            end
            
            START: begin
                clk_count <= clk_count + 1;
                if ( clk_count == BIT_RATE_MAX - 1 ) begin
                    clk_count <= 0;

                    tx_pin <= shift_data[bit_index];
                    bit_index <= bit_index + 1;

                    state <= DATA;
                end                
            end
            
            DATA: begin
                clk_count <= clk_count + 1;
    
                if ( clk_count == BIT_RATE_MAX - 1 ) begin
                    tx_pin <= shift_data[bit_index];
                    bit_index <= bit_index + 1;
                    
                    clk_count <= 0;

                    if ( bit_index == 7) begin
                        state <= STOP;
                    end
                end                 
            end
            
            STOP: begin
                tx_pin <= 1;
                busy <= 0;
                clk_count <= clk_count + 1;
                if ( clk_count == BIT_RATE_MAX - 1 ) begin
                    state <= IDLE;
                end  
            end
        endcase
    end

endmodule