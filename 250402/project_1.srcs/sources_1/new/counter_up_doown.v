module top_counter_up_down (
    input        clk,
    input        reset,
    input        rx,
    output       tx,
    output [3:0] fndCom,
    output [7:0] fndFont
);
    wire [2:0] sw;
    wire [13:0] fndData;
    wire [3:0] fndDot;
    wire [2:0] current_state;
    wire sw_mode, run_stop_mode, clear_mode;

    wire [7:0] rx_data;
    wire rx_done;
    wire tx_done;
    reg btn_start = 0;
    reg [7:0] tx_data_in = 0;

    uart U_UART (
        .clk(clk),
        .rst(reset),
        .rx(rx),
        .btn_start(btn_start),
        .tx_data_in(tx_data_in),
        .rx_data_out(rx_data),
        .rx_done(rx_done),
        .tx_done(tx_done),
        .tx(tx),
        .sw(sw)
    );

    cu U_CU(
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .current_state(current_state),
        .sw_mode(sw_mode),
        .run_stop_mode(run_stop_mode),
        .clear_mode(clear_mode)
    );

    counter_up_down U_Counter (
        .clk(clk),
        .reset(reset),
        .mode(sw_mode),
        .run_stop(run_stop_mode),
        .en(1'b1),
        .clear(clear_mode),
        .count(fndData),
        .dot_data(fndDot)
    );

    fndController U_FndController (
        .clk(clk),
        .reset(reset),
        .fndData(fndData),
        .fndDot(fndDot),
        .fndCom(fndCom),
        .fndFont(fndFont)
    );
endmodule

module counter_up_down (
    input         clk,
    input         reset,
    input         mode,
    input         en,
    input         clear,
    input         run_stop,
    output [13:0] count,
    output [ 3:0] dot_data
);
    wire tick;
    
    clk_div_10hz U_Clk_Div_10Hz (
        .clk(clk),
        .reset(reset),
        .en(en),
        .clear(clear),
        .tick(tick)
    );
    
    counter U_Counter_Up_Down (
        .clk(clk),
        .reset(reset),
        .tick(tick & run_stop),
        .mode(mode),
        .clear(clear),
        .count(count)
    );
    
    comp_dot U_comp_dot (
        .count(count),
        .dot_data(dot_data)
    );
endmodule

module counter (
    input         clk,
    input         reset,
    input         tick,
    input         mode,
    input         clear,
    output [13:0] count
);
    reg [$clog2(10000)-1:0] counter;
    
    assign count = counter;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
        end else begin
            if(clear) begin
                counter <= 0;
            end else begin
                if (mode == 1'b0) begin
                    if (tick) begin
                        if (counter == 9999) begin
                            counter <= 0;
                        end else begin
                            counter <= counter + 1;
                        end
                    end
                end else begin
                    if (tick) begin
                        if (counter == 0) begin
                            counter <= 9999;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                end
            end
        end
    end
endmodule

module clk_div_10hz (
    input  wire clk,
    input  wire reset,
    input  wire en,
    input  wire clear,
    output reg  tick
);
    reg [$clog2(10_000_000)-1:0] div_counter;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            div_counter <= 0;
            tick <= 1'b0;
        end else begin
            if(clear) begin
                div_counter <= 0;
                tick <= 1'b0;
            end else if(en) begin
                if (div_counter == 10_000_000 - 1) begin
                    div_counter <= 0;
                    tick <= 1'b1;
                end else begin
                    div_counter <= div_counter + 1;
                    tick <= 1'b0;
                end
            end
        end
    end
endmodule

module comp_dot (
    input  [13:0] count,
    output [ 3:0] dot_data
);
    assign dot_data = ((count % 10) < 5) ? 4'b1101 : 4'b1111;
endmodule

module cu(
    input clk,
    input reset,
    input [2:0] sw,
    
    output [2:0] current_state,
    
    output reg sw_mode,
    output reg run_stop_mode,
    output reg clear_mode
);
    parameter STATE_0 = 3'b000;  
    parameter STATE_1 = 3'b001;  
    parameter STATE_2 = 3'b010;  
    
    reg [2:0] state_reg;
    assign current_state = state_reg;
    
    always @(*) begin
        sw_mode = sw[0];  
        
        case (state_reg)
            STATE_0: begin 
                run_stop_mode = 1'b0; 
                clear_mode = 1'b0;
            end
            
            STATE_1: begin  
                run_stop_mode = 1'b1;  
                clear_mode = 1'b0;
            end
            
            STATE_2: begin  
                run_stop_mode = 1'b0;
                clear_mode = 1'b1;  
            end
            
            default: begin
                run_stop_mode = 1'b0;
                clear_mode = 1'b0;
            end
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_reg <= STATE_0;  
        end
        else begin
            case (state_reg)
                STATE_0: begin  
                    if (sw[1] == 1'b1) begin 
                        state_reg <= STATE_1;  
                    end
                    else if (sw[2] == 1'b1) begin  
                        state_reg <= STATE_2; 
                    end
                end
                
                STATE_1: begin 
                    if (sw[1] == 1'b0) begin  
                        state_reg <= STATE_0; 
                    end
                    else if (sw[2] == 1'b1) begin  
                        state_reg <= STATE_2;  
                    end
                end
                
                STATE_2: begin 
                    if (sw[2] == 1'b0) begin  
                        if (sw[1] == 1'b1) begin  
                            state_reg <= STATE_1;  
                        end
                        else begin
                            state_reg <= STATE_0; 
                        end
                    end
                end
                
                default: begin
                    state_reg <= STATE_0;
                end
            endcase
        end
    end
endmodule