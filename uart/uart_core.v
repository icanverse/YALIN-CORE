module uart_core(
    input wire clk, 
    
    // PİNLER
    input wire rx_pin,
    output wire tx_pin,
    
    /// SİNYALLER
    // TX
    input wire [7:0] tx_data,
    input wire tx_start,
    output wire tx_busy,
    
    // RX
    output wire [7:0] rx_data,
    output wire rx_ready
);

    parameter BAUD_TIMER_MAX = 8'd234;     
    parameter BAUD_TIMER_HALF = 8'd117;

    // VERİCİ NESNESİ :: Transmitter Instance
    uart_tx #(
        .BIT_RATE_MAX(BAUD_TIMER_MAX) 
    ) my_transmitter (
        .clk(clk),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_pin(tx_pin),     
        .busy(tx_busy)       
    );

    // ALICI NESNESİ :: Receiver Instance
    uart_rx #(
        .BIT_RATE_MAX(BAUD_TIMER_MAX),
        .HALF_BIT_RATE(BAUD_TIMER_HALF)
    ) my_receiver (
        .clk(clk),
        .rx_pin(rx_pin),         
        .rx_data(rx_data),       
        .data_ready(rx_ready)    
    );

endmodule