`timescale 1ns / 1ps

module uart(
    input clk,
    input rst,
    input rx,             
    input btn_start,
    input [7:0] tx_data_in,
    output [7:0] rx_data_out,
    output rx_done,      
    output tx_done,
    output tx,
    output reg [2:0] sw     
);
    wire w_tick;
    wire rx_data_done;
    wire [7:0] rx_data;
    reg echo_start;
    reg [7:0] echo_data;
    reg [19:0] reset_counter;
    reg reset_completed;

    assign rx_data_out = rx_data;
    
    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tick(w_tick),
        .start_trigger(echo_start || btn_start),
        .data_in(echo_start ? echo_data : tx_data_in),
        .o_tx_done(tx_done),
        .o_tx(tx)
    );
   
    uart_rx U_UART_RX (
        .clk(clk),
        .rst(rst),
        .tick(w_tick),
        .rx(rx),
        .o_data(rx_data),
        .o_rx_done(rx_data_done)
    );

    baud_tick_gen U_BAUD_Tick_Gen (
        .clk(clk),
        .rst(rst),
        .baud_tick(w_tick)
    );
    
    assign rx_done = rx_data_done;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reset_counter <= 20'd0;
            reset_completed <= 1'b0;
        end else begin
            if (!reset_completed) begin
                if (reset_counter < 20'd1_000_000) begin
                    reset_counter <= reset_counter + 1;
                end else begin
                    reset_completed <= 1'b1;
                end
            end
        end
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sw <= 3'b000;
            echo_start <= 1'b0;
            echo_data <= 8'h00;
        end else if (reset_completed) begin
            if (echo_start) begin
                echo_start <= 1'b0;
            end
            
            if (sw[2]) sw[2] <= 1'b0;
            
            if (rx_data_done) begin
                echo_data <= rx_data;
                echo_start <= 1'b1;
                
                case (rx_data)
                    8'h52: begin  // 'R'
                        sw[1] <= 1'b1;
                    end
                    8'h53: begin  // 'S'
                        sw[1] <= 1'b0;
                    end
                    8'h43: begin  // 'C'
                        sw[2] <= 1'b1;
                    end
                    8'h4D: begin  // 'M'
                        sw[0] <= ~sw[0];
                    end
                    8'h55: begin  // 'U'
                        sw[0] <= 1'b0;
                    end
                    8'h44: begin  // 'D'
                        sw[0] <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule 


module uart_tx (
    input clk,
    input rst,
    input tick,
    input start_trigger,
    input [7:0] data_in,
    output o_tx_done,
    output o_tx
);
    parameter IDLE = 0, SEND = 1, START = 2, DATA = 3, STOP = 4;

    reg [3:0] state, next;
    reg tx_reg, tx_next;
    reg tx_done_reg, tx_done_next;
    reg [3:0] bit_count_reg, bit_count_next;
    reg [3:0] tick_count_reg, tick_count_next;
    reg [7:0] data_reg;
    
    assign o_tx_done = tx_done_reg;
    assign o_tx = tx_reg;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_reg <= 1'b1;
            tx_done_reg <= 0;
            bit_count_reg <= 0;
            tick_count_reg <= 0;
            data_reg <= 8'h00;
        end else begin
            state <= next;
            tx_reg <= tx_next;
            tx_done_reg <= tx_done_next;
            bit_count_reg <= bit_count_next;
            tick_count_reg <= tick_count_next;
            
            if (state == IDLE && start_trigger) begin
                data_reg <= data_in;
            end
        end
    end
    
    always @(*) begin
        next = state;
        tx_next = tx_reg;
        tx_done_next = 1'b0;
        bit_count_next = bit_count_reg;
        tick_count_next = tick_count_reg;

        case (state)
            IDLE: begin    
                tx_next = 1'b1;
                bit_count_next = 4'h0;
                tick_count_next = 4'h0;
                
                if(start_trigger) begin
                    next = SEND;
                end
            end
            
            SEND: begin
                if(tick == 1'b1) begin
                    next = START;
                end
            end
            
            START: begin
                tx_next = 1'b0;
                
                if(tick == 1'b1) begin 
                    if(tick_count_reg >= 15) begin
                        next = DATA;
                        bit_count_next = 4'h0;
                        tick_count_next = 4'h0;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end

            DATA: begin
                tx_next = data_reg[bit_count_reg];
                 
                if (tick) begin
                    if (tick_count_reg >= 15) begin
                        tick_count_next = 4'h0;
                        
                        if (bit_count_reg >= 7) begin
                            next = STOP;
                        end else begin
                            bit_count_next = bit_count_reg + 1;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                
                if (tick == 1'b1) begin
                    if (tick_count_reg >= 15) begin
                        next = IDLE;
                        tx_done_next = 1'b1;
                        tick_count_next = 4'h0;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            
            default: begin
                next = IDLE; 
                tx_next = 1'b1;  
                bit_count_next = 4'h0;
                tick_count_next = 4'h0;  
            end
        endcase
    end
endmodule


module uart_rx (
    input clk,
    input rst,
    input tick,
    input rx,
    output reg [7:0] o_data,
    output reg o_rx_done
);
    parameter IDLE = 0, START = 1, DATA = 2, STOP = 3;
    
    reg [1:0] state;
    reg [3:0] bit_count;
    reg [3:0] tick_count;
    reg [7:0] data_buf;
    reg rx_sync, rx_sync2;
    
    always @(posedge clk) begin
        rx_sync <= rx;
        rx_sync2 <= rx_sync;
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            o_data <= 8'h00;
            o_rx_done <= 1'b0;
            bit_count <= 0;
            tick_count <= 0;
            data_buf <= 8'h00;
        end else begin
            o_rx_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    bit_count <= 0;
                    data_buf <= 8'h00;
                    if (rx_sync2 == 1'b0) begin
                        state <= START;
                        tick_count <= 0;
                    end
                end
                
                START: begin
                    if (tick) begin
                        if (tick_count == 7) begin
                            if (rx_sync2 == 1'b0) begin
                                state <= DATA;
                                tick_count <= 0;
                                bit_count <= 0;
                            end else begin
                                state <= IDLE;
                            end
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end
                
                DATA: begin
                    if (tick) begin
                        if (tick_count == 15) begin
                            tick_count <= 0;
                            data_buf[bit_count] <= rx_sync2;
                            
                            if (bit_count == 7) begin
                                state <= STOP;
                            end else begin
                                bit_count <= bit_count + 1;
                            end
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end
                
                STOP: begin
                    if (tick) begin
                        if (tick_count == 15) begin
                            if (rx_sync2 == 1'b1) begin
                                o_data <= data_buf;
                                o_rx_done <= 1'b1;
                            end
                            state <= IDLE;
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule


module baud_tick_gen (
    input clk,
    input rst,
    output baud_tick
);
    parameter BAUD_RATE = 9600, BAUD_RATE_19200 = 19200;
    localparam BAUD_COUNT = 100_000_000 / BAUD_RATE;
    reg [$clog2(BAUD_COUNT) - 1 : 0] count_reg, count_next;
    reg tick_reg, tick_next;
    
    assign baud_tick = tick_reg;
    
    always @(posedge clk or posedge rst) begin
        if(rst == 1) begin
            count_reg <= 0;
            tick_reg <= 0;
        end else begin
            count_reg <= count_next;
            tick_reg <= tick_next;
        end
    end
    
    always @(*) begin
        count_next = count_reg;
        tick_next = 1'b0;
        
        if (count_reg == BAUD_COUNT - 1) begin
            count_next = 0;
            tick_next = 1'b1;
        end else begin
            count_next = count_reg + 1;
        end
    end
endmodule