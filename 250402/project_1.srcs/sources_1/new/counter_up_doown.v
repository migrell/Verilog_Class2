`timescale 1ns / 1ps

module top_uart_counter (
    input        clk,
    input        reset,
    input        rx,         // UART 수신 신호
    output       tx,         // UART 송신 신호
    output [3:0] fndCom,
    output [7:0] fndFont
);
    // 내부 신호
    wire [13:0] fndData;
    wire [3:0] fndDot;
    
    // 가상 스위치 신호 (UART로부터 생성)
    reg [2:0] virtual_sw;
    reg mode;  // reg로 선언
    
    // UART 수신 신호
    wire rx_done;
    wire [7:0] rx_data;
    
    // UART 송신 신호
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_done;
    wire [1:0] tx_state;
    
    // 디바운스 카운터 - 명령 안정화를 위한 타이머
    reg [19:0] debounce_counter;
    wire debounce_tick;
    
    // 디바운스 타이머 (약 1ms)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debounce_counter <= 0;
        end else begin
            debounce_counter <= debounce_counter + 1;
        end
    end
    
    // 디바운스 틱 신호 (1ms마다 생성)
    assign debounce_tick = (debounce_counter == 20'd0);
    
    // UART 수신 모듈 - 단순화된 버전 사용
    uart_rx_simple U_UART_RX(
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .rx_done(rx_done),
        .rx_data(rx_data)
    );
    
    // UART 송신 모듈 - 단순화된 버전 사용
    uart_simple U_UART(
        .clk(clk),
        .reset(reset),
        .tx_data_in(tx_data),
        .btn_start(tx_start),
        .o_tx_done(tx_done),
        .o_tx(tx),
        .state_out(tx_state)
    );
    
    // 명령 래치
    reg cmd_received;
    reg [7:0] cmd_buffer;
    
    // 명령 수신 및 래치
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cmd_received <= 0;
            cmd_buffer <= 0;
            virtual_sw <= 3'b000; // 스위치 초기화 추가
            mode <= 0;            // 모드 초기화 추가
        end else begin
            if (rx_done) begin
                cmd_received <= 1;
                cmd_buffer <= rx_data;
            end else if (debounce_tick && cmd_received) begin
                // 디바운스 처리 후 명령 실행
                case (cmd_buffer)
                    8'h72, 8'h52: begin // 'r', 'R' - Run
                        virtual_sw[1] <= 1'b1; // sw[1] = run_stop
                    end
                    8'h73, 8'h53: begin // 's', 'S' - Stop
                        virtual_sw[1] <= 1'b0; // sw[1] = run_stop
                    end
                    8'h63, 8'h43: begin // 'c', 'C' - Clear
                        virtual_sw[2] <= 1'b1; // sw[2] = clear
                    end
                    8'h6D, 8'h4D: begin // 'm', 'M' - Mode
                        mode <= ~mode; // mode 토글
                        virtual_sw[0] <= ~virtual_sw[0]; // sw[0] = mode toggle
                    end
                    default: ;
                endcase
                cmd_received <= 0;
            end
            
            // 클리어 버튼은 원샷으로 동작
            if (virtual_sw[2] && debounce_tick) begin
                virtual_sw[2] <= 1'b0;
            end
        end
    end
    
    // 기존 cu 모듈과 카운터 연결
    wire sw_mode;
    wire run_stop_mode;
    wire clear_mode;
    wire [2:0] current_state;
    
    // cu 모듈 인스턴스
    cu U_CU(
        .clk(clk),
        .reset(reset),
        .sw(virtual_sw),        // UART로부터 생성된 가상 스위치 입력
        .current_state(current_state),
        .sw_mode(sw_mode),
        .run_stop_mode(run_stop_mode),
        .clear_mode(clear_mode)
    );
    
    counter_up_down U_Counter (
        .clk(clk),
        .reset(reset),
        .mode(mode),            // 직접 mode를 연결
        .run_stop(run_stop_mode),
        .en(1'b1),
        .clear(clear_mode),
        .count(fndData),
        .dot_data(fndDot)
    );
    
    // 송신 응답 모듈 - 단순화된 버전
    uart_response_simple U_UART_RESPONSE(
        .clk(clk),
        .reset(reset),
        .rx_done(rx_done),
        .rx_data(rx_data),
        .tx_done(tx_done),
        .tx_data(tx_data),
        .tx_start(tx_start)
    );
    
    // fndController 인스턴스
    fndController U_FndController (
        .clk(clk),
        .reset(reset),
        .fndData(fndData),
        .fndCom(fndCom),
        .fndFont(fndFont)
    );
endmodule

// 단순화된 응답 모듈
module uart_response_simple(
    input clk,
    input reset,
    input rx_done,
    input [7:0] rx_data,
    input tx_done,
    output reg [7:0] tx_data,
    output reg tx_start
);
    // 상태 정의
    parameter IDLE = 2'b00;
    parameter PREPARE = 2'b01;
    parameter SEND = 2'b10;
    parameter WAIT = 2'b11;
    
    reg [1:0] state;
    reg send_pending; // 전송 대기 중 플래그
    reg [7:0] pending_data; // 대기 중인 데이터
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx_start <= 0;
            tx_data <= 0;
            send_pending <= 0;
            pending_data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_start <= 0;
                    
                    // 새 명령이 수신되었거나 대기 중인 전송이 있는 경우
                    if (rx_done || send_pending) begin
                        state <= PREPARE;
                        if (rx_done) begin
                            // 수신 데이터에 따라 응답 메시지 설정
                            case (rx_data)
                                8'h72, 8'h52: tx_data <= 8'h52; // 'R' (Run)
                                8'h73, 8'h53: tx_data <= 8'h53; // 'S' (Stop)
                                8'h63, 8'h43: tx_data <= 8'h43; // 'C' (Clear)
                                8'h6D, 8'h4D: tx_data <= 8'h4D; // 'M' (Mode)
                                default: tx_data <= 8'h3F;      // '?' (Unknown)
                            endcase
                            send_pending <= 0; // 새 명령을 직접 처리
                        end else begin
                            // 대기 중인 명령 처리
                            tx_data <= pending_data;
                            send_pending <= 0;
                        end
                    end
                end
                
                PREPARE: begin
                    state <= SEND;
                end
                
                SEND: begin
                    tx_start <= 1;
                    state <= WAIT;
                end
                
                WAIT: begin
                    tx_start <= 0;
                    
                    if (tx_done) begin
                        state <= IDLE;
                    end
                    
                    // 대기 중 새 명령이 왔을 때
                    if (rx_done) begin
                        // 현재 전송이 완료될 때까지 대기하고, 새 명령을 저장
                        case (rx_data)
                            8'h72, 8'h52: pending_data <= 8'h52; // 'R' (Run)
                            8'h73, 8'h53: pending_data <= 8'h53; // 'S' (Stop)
                            8'h63, 8'h43: pending_data <= 8'h43; // 'C' (Clear)
                            8'h6D, 8'h4D: pending_data <= 8'h4D; // 'M' (Mode)
                            default: pending_data <= 8'h3F;      // '?' (Unknown)
                        endcase
                        send_pending <= 1;
                    end
                end
            endcase
        end
    end
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