module uart_rx(
    input wire clk,
    input wire rx_pin,

    output reg [7:0] rx_data,
    output reg data_ready
    
);

    parameter BIT_RATE_MAX = 8'd234;
    parameter HALF_BIT_RATE = 8'd117;
    
    reg [7:0] clk_count = 0;   // 234'e kadar sayacak zamanlayıcı
    reg [2:0] bit_index = 0;   

    reg [1:0] state = 0;
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    initial begin 
        data_ready = 0;
        rx_data = 0;
    end

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                data_ready <= 0;
                clk_count <= 0;
                bit_index <= 0;

                if ( rx_pin == 0 ) begin
                    state <= START;
                end
            end
            
            START: begin
                clk_count <= clk_count + 1;
        
                if ( clk_count == HALF_BIT_RATE - 1) begin
                    clk_count <= 0;
                      
                    if ( rx_pin == 0 ) begin 
                        state <= DATA;
                    end else begin 
                        state <= IDLE;
                    end
                end 
            end
            
            DATA: begin
                clk_count <= clk_count + 1;
    
                if ( clk_count == BIT_RATE_MAX - 1) begin
                    rx_data[bit_index] <= rx_pin;
                    bit_index <= bit_index + 1;
                    clk_count <= 0;
            
                    if ( bit_index == 7) begin
                        state <= STOP;
                    end
                end
            end
            
            STOP: begin
                clk_count <= clk_count + 1;
                if ( clk_count == BIT_RATE_MAX - 1) begin
                    data_ready <= 1;
                    state <= IDLE;
                end
            end
        endcase
    end



endmodule