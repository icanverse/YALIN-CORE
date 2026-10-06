module i2c_core (
    input wire clk,
    input wire reset,

    input wire start_trigger,

    input wire [6:0] dev_addr, // 7-Bit Sensör Adresi (Örn: AS5600 için 0x36)
    input wire rw_flag,        // 0 ise Yazma (Write), 1 ise Okuma (Read)
    input wire [7:0] reg_addr,
    input wire [7:0] tx_data,

    inout wire sda,
    output reg scl,

    output reg error_flag
);

    // sda_dir = 1 :: Master konuşur
    // sda_dir = 0 :: Sensör dinleniyor
    reg sda_dir;

    // Basılacak değer
    reg sda_out;

    // Direkt bağlantı
    assign sda = (sda_dir == 1) ? sda_out : 1'bz;
    wire sda_in = sda;
    
    parameter BIT_RATE = 9'd270;
    parameter PHASE = BIT_RATE / 4 ;

    reg [6:0] clk_div = 0;
    reg [1:0] phase_count = 0;

    wire tick = (clk_div == PHASE - 1);

    // FSM
    reg [3:0] state = 0;
    localparam IDLE  = 4'd0;
    localparam START = 4'd1;
    localparam DATA = 4'd2;
    localparam STOP = 4'd3;

    // DATA
    reg [7:0] shift_data = 0; // Slave cihaz adresi + Yazma biti (0x36 << 1)
    reg [2:0] bit_index = 7;      // Geri sayım sayacımız (7'den 0'a)
    reg [1:0] byte_count = 0;

    // WAIT ACK
    localparam WAIT_ACK = 4'd4;

    initial begin
        scl = 1;
        error_flag = 0;
    end

    always @(posedge clk) begin 
        clk_div <= clk_div + 1;

        if (clk_div == PHASE - 1) begin
            clk_div <= 0;
            phase_count <= phase_count + 1;

            if ( phase_count == 3 ) begin 
                phase_count <= 0;
            end
        end

        if (state == IDLE) begin
            sda_dir <= 1; 
            sda_out <= 1; 
            scl <= 1;     
            
            if (start_trigger == 1) begin
                state <= START;

                shift_data <= {dev_addr, rw_flag};
                bit_index <= 7;
                byte_count <= 0;

                clk_div <= 0;
                phase_count <= 0;
            end
        end
        
        else if (tick == 1) begin 
            case (state)
                START: begin
                    if ( phase_count == 0 ) begin 
                        sda_out <= 1;
                        scl <= 1;
                    end else if ( phase_count == 1)begin
                        sda_out <= 0;
                    end else if ( phase_count == 2)begin
                        sda_out <= 0;
                    end else if ( phase_count == 3)begin
                        scl <= 0;
                        state <= DATA;
                    end                  
                end

                DATA: begin
                    if (phase_count == 0) begin
                        sda_out <= shift_data[bit_index];
                        scl <= 0;
                    end 
                    else if (phase_count == 1) begin
                        scl <= 1;
                    end 
                    else if (phase_count == 2) begin
                        scl <= 1;   
                    end 
                    else if (phase_count == 3) begin
                        scl <= 0;
                        
                        if ( bit_index == 0 ) begin 
                            state <= WAIT_ACK;
                        end else begin 
                            bit_index <= bit_index - 1;
                        end
                    end
                end

                WAIT_ACK: begin 
                    if (phase_count == 0) begin
                        sda_dir <= 0;
                        scl <= 0;
                    end
                    else if (phase_count == 1) begin
                        scl <= 1;
                    end
                    else if (phase_count == 2) begin
                        scl <= 1;

                        if ( sda_in == 1 ) begin
                            error_flag <= 1;
                        end else begin 
                            error_flag <= 0;
                        end
                    end
                    else if (phase_count == 3) begin
                        scl <= 0;
                        sda_dir <= 1;

                        if (error_flag == 1) begin
                            state <= STOP;
                        end else if (byte_count == 0) begin
                            shift_data <= reg_addr;
                            bit_index <= 7;
                            byte_count <= 1;
                            state <= DATA;
                        end 
                        else if (byte_count == 1) begin
                            shift_data <= tx_data;  
                            bit_index <= 7;
                            byte_count <= 2;
                            state <= DATA;
                        end 
                        else begin
                            state <= STOP; 
                        end
                    end
                end

                STOP: begin
                    if (phase_count == 0) begin
                        scl <= 0;
                        sda_out <= 0;
                    end
                    else if (phase_count == 1) begin
                        scl <= 1; 
                    end
                    else if (phase_count == 2) begin
                        scl <= 1; 
                        sda_out <= 1;
                    end
                    else if (phase_count == 3) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule