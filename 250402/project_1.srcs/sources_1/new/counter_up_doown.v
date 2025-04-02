`timescale 1ns / 1ps

module top_counter_up_down (
    input        clk,
    input        reset,
    input        mode,
    input  [2:0] sw,
    output [3:0] fndCom,
    output [7:0] fndFont
);
    wire [13:0] fndData;
    wire [3:0] fndDot;
    
    wire sw_mode;
    wire run_stop_mode;
    wire clear_mode;
    wire [2:0] current_state;
    
    // cu 모듈 인스턴스
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
        .mode(mode),
        .run_stop(run_stop_mode),
        .en(1'b1),
        .clear(clear_mode),
        .count(fndData),
        .dot_data(fndDot)
    );
    
    // fndController 인터페이스 수정
    fndController U_FndController (
        .clk(clk),
        .reset(reset),
        .fndData(fndData),
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
    parameter STATE_0 = 3'b000;  // STOP 상태
    parameter STATE_1 = 3'b001;  // RUN 상태
    parameter STATE_2 = 3'b010;  // CLEAR 상태
    
    // 내부 상태 레지스터
    reg [2:0] state_reg;
    assign current_state = state_reg;
    
    // 스위치에 따른 모드 설정 - sw[0] 직접 연결로 수정
    always @(*) begin
        sw_mode = sw[0];  // 모드 (up/down) - 직접 연결로 수정
        
        // 상태에 따른 출력 설정
        case (state_reg)
            STATE_0: begin  // STOP 상태
                run_stop_mode = 1'b0;  // 정지 상태
                clear_mode = 1'b0;
            end
            
            STATE_1: begin  // RUN 상태
                run_stop_mode = 1'b1;  // 실행 상태
                clear_mode = 1'b0;
            end
            
            STATE_2: begin  // CLEAR 상태
                run_stop_mode = 1'b0;
                clear_mode = 1'b1;  // 클리어 활성화
            end
            
            default: begin
                run_stop_mode = 1'b0;
                clear_mode = 1'b0;
            end
        endcase
    end

    // 상태 전환 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_reg <= STATE_0;  // 리셋 시 STOP 상태로
        end
        else begin
            case (state_reg)
                STATE_0: begin  // STOP 상태에서
                    if (sw[1] == 1'b1) begin  // sw1이 1이면
                        state_reg <= STATE_1;  // RUN 상태로 전환
                    end
                    else if (sw[2] == 1'b1) begin  // sw2가 1이면
                        state_reg <= STATE_2;  // CLEAR 상태로 전환
                    end
                end
                
                STATE_1: begin  // RUN 상태에서
                    if (sw[1] == 1'b0) begin  // sw1이 0이면
                        state_reg <= STATE_0;  // STOP 상태로 전환
                    end
                    else if (sw[2] == 1'b1) begin  // sw2가 1이면
                        state_reg <= STATE_2;  // CLEAR 상태로 전환
                    end
                end
                
                STATE_2: begin  // CLEAR 상태에서
                    if (sw[2] == 1'b0) begin  // sw2가 0이 되면
                        if (sw[1] == 1'b1) begin  // sw1 상태에 따라
                            state_reg <= STATE_1;  // RUN 상태로
                        end
                        else begin
                            state_reg <= STATE_0;  // 아니면 STOP 상태로
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