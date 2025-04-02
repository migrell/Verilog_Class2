`timescale 1ns / 1ps

module uart_rx_simple(
    input clk,
    input reset,
    input rx,
    output reg rx_done,
    output reg [7:0] rx_data
);
    // 상태 정의 - 패리티 없는 단순 8N1 형식
    parameter IDLE = 2'b00;
    parameter START = 2'b01;
    parameter DATA = 2'b10;
    parameter STOP = 2'b11;
    
    reg [1:0] state;
    reg [2:0] bit_idx; // 비트 인덱스 (0-7)
    reg [7:0] rx_reg;  // 수신 데이터 레지스터
    reg [1:0] rx_sync; // RX 신호 동기화
    
    wire baud_tick;
    wire rx_filtered;
    
    // RX 신호 동기화 (메타스테이빌리티 방지)
    always @(posedge clk) begin
        rx_sync <= {rx_sync[0], rx};
    end
    
    assign rx_filtered = rx_sync[1]; // 동기화된 RX 신호
    
    // 보레이트 생성기
    baud_tick_gen U_BAUD_TICK_GEN(
        .clk(clk),
        .rst(reset),
        .baud_tick(baud_tick)
    );
    
    // 상태 머신 구현
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            bit_idx <= 0;
            rx_reg <= 0;
            rx_data <= 0;
            rx_done <= 0;
            rx_sync <= 2'b11; // High 초기화
        end else begin
            rx_done <= 0; // 기본값은 0
            
            case (state)
                IDLE: begin
                    // 시작 비트 감지 (Low)
                    if (rx_filtered == 0) begin
                        state <= START;
                    end
                end
                
                START: begin
                    // 보레이트 틱에서 시작 비트 중간점 샘플링
                    if (baud_tick) begin
                        // 시작 비트가 여전히 Low인지 확인
                        if (rx_filtered == 0) begin
                            state <= DATA;
                            bit_idx <= 0;
                        end else begin
                            state <= IDLE; // 잘못된 시작 비트
                        end
                    end
                end
                
                DATA: begin
                    // 각 데이터 비트 샘플링
                    if (baud_tick) begin
                        // LSB first: 데이터를 오른쪽으로 시프트, 새 비트는 MSB로
                        rx_reg <= {rx_filtered, rx_reg[7:1]};
                        
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end
                
                STOP: begin
                    // 스톱 비트 확인
                    if (baud_tick) begin
                        // 스톱 비트는 High여야 함
                        if (rx_filtered == 1) begin
                            rx_data <= rx_reg; // 데이터 출력 업데이트
                            rx_done <= 1;      // 수신 완료 신호
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule

module uart_tx_simple(
    input clk,
    input reset,
    input tick,
    input start_trigger,
    input [15:0] data_in,
    output reg o_tx_done,
    output reg o_tx,
    output [15:0] state_out
);
    // FSM 상태 정의 - 패리티 없는 단순 8N1 형식
    parameter IDLE = 2'b00;
    parameter START = 2'b01;
    parameter DATA = 2'b10;
    parameter STOP = 2'b11;
    
    reg [1:0] state;
    reg [7:0] bit_idx; // 비트 인덱스 (0-7)
    reg [10:0] data_reg; // 전송 데이터 레지스터
    
    assign state_out = state;
    
    // 상태 머신 구현
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            o_tx <= 1;        // UART idle 상태는 High
            o_tx_done <= 1;   // 초기 상태는 준비 완료
            bit_idx <= 0;
            data_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    o_tx <= 1;         // idle은 High
                    o_tx_done <= 1;    // 전송 준비 완료
                    bit_idx <= 0;
                    
                    if (start_trigger) begin
                        state <= START;
                        data_reg <= data_in;  // 데이터 래치
                        o_tx_done <= 0;       // 전송 시작
                    end
                end
                
                START: begin
                    if (tick) begin
                        o_tx <= 0;     // 시작 비트는 Low
                        state <= DATA;
                    end
                end
                
                DATA: begin
                    if (tick) begin
                        // LSB first 전송
                        o_tx <= data_reg[bit_idx];
                        
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end
                
                STOP: begin
                    if (tick) begin
                        o_tx <= 1;       // 스톱 비트는 High
                        state <= IDLE;
                        o_tx_done <= 1;  // 전송 완료
                    end
                end
            endcase
        end
    end
endmodule

module uart_simple(
    input clk,
    input reset,
    input [16:0] tx_data_in,
    input btn_start,
    output o_tx_done,
    output o_tx,
    output [17:0] state_out
);
    wire baud_tick;
    
    // 보레이트 생성기
    baud_tick_gen U_BAUD_TICK_GEN(
        .clk(clk),
        .rst(reset),
        .baud_tick(baud_tick)
    );
    
    // 송신기
    uart_tx_simple U_UART_TX(
        .clk(clk),
        .reset(reset),
        .tick(baud_tick),
        .start_trigger(btn_start),
        .data_in(tx_data_in),
        .o_tx_done(o_tx_done),
        .o_tx(o_tx),
        .state_out(state_out)
    );
endmodule


`timescale 1ns / 1ps

module baud_tick_gen (
    input clk,
    input rst,
    output baud_tick
);
    // 9600 baud rate 설정
    parameter BAUD_RATE = 9600;
    localparam BAUD_COUNT = 100_000_000 / BAUD_RATE;
    
    reg [$clog2(BAUD_COUNT) - 1 : 0] count_reg, count_next;
    reg tick_reg, tick_next;
    
    // 출력 할당
    assign baud_tick = tick_reg;
    
    always @(posedge clk, posedge rst) begin
        if(rst == 1) begin
            count_reg <= 0;
            tick_reg <= 0;
        end else begin
            count_reg <= count_next;
            tick_reg <= tick_next;
        end
    end
    
    // 다음 상태 로직
    always @(*) begin
        count_next = count_reg;
        tick_next = tick_reg;
        
        if (count_reg == BAUD_COUNT - 1) begin
            count_next = 0;
            tick_next = 1'b1;
        end else begin
            count_next = count_reg + 1;
            tick_next = 1'b0;
        end
    end
endmodule

// `timescale 1ns / 1ps

// module uart(
//     input clk,
//     input rst,
//     input btn_start,
//     input [7:0] tx_data_in,
//     output tx_done,
//     output tx,
//     output [1:0] state_out
// );
//     // 내부 신호 선언
//     wire w_tick;
    
//     // UART 송신기 인스턴스화
//     uart_tx U_UART_TX (
//         .clk(clk),
//         .rst(rst),
//         .tick(w_tick),
//         .start_trigger(btn_start),
//         .data_in(tx_data_in),
//         .o_tx_done(tx_done),
//         .o_tx(tx),
//         .state_out(state_out)
//     );
    
//     // 보드레이트 생성기 인스턴스화
//     baud_tick_gen U_BAUD_Tick_Gen (
//         .clk(clk),
//         .rst(rst),
//         .baud_tick(w_tick)
//     );
// endmodule

// module uart_tx (
//     input clk,
//     input rst,
//     input tick,
//     input start_trigger,
//     input [7:0] data_in,
//     output o_tx_done,
//     output o_tx,
//     output [1:0] state_out
// );
//     // FSM 상태 정의 - 4-state Mealy model
//     parameter IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;
    
//     reg [1:0] state, next;
//     reg tx_reg, tx_next;
//     reg tx_done_reg, tx_done_next;
    
//     assign state_out = state;  // state_out으로 현재 상태 출력
    
//     // 데이터 카운터 추가 (0-7)
//     reg [2:0] data_count, data_count_next;
    
//     // 출력 할당
//     assign o_tx = tx_reg;
//     assign o_tx_done = tx_done_reg;
    
//     // 상태 레지스터 및 출력 레지스터
//     always @(posedge clk, posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tx_reg <= 1'b1;        // UART의 기본 idle 상태는 high
//             tx_done_reg <= 1'b1;   // 초기 상태는 준비 완료
//             data_count <= 3'b000;  // 데이터 카운터 초기화
//         end else begin
//             state <= next;
//             tx_reg <= tx_next;
//             tx_done_reg <= tx_done_next;
//             data_count <= data_count_next;
//         end
//     end
    
//     // 다음 상태 및 출력 로직
//     always @(*) begin
//         // 기본값 유지
//         next = state;
//         tx_next = tx_reg;
//         tx_done_next = tx_done_reg;
//         data_count_next = data_count;
        
//         case (state)
//             IDLE: begin
//                 tx_next = 1'b1;        // idle 상태에서는 high
//                 tx_done_next = 1'b1;   // 전송 준비 완료
//                 data_count_next = 3'b000; // 데이터 카운터 초기화
                
//                 if (start_trigger) begin
//                     next = START;      // 시작 트리거가 있으면 START 상태로 전환
//                     tx_done_next = 1'b0; // 전송 시작, 준비 상태 해제
//                 end
//             end
            
//             START: begin
//                 if (tick) begin
//                     tx_next = 1'b0;    // 시작 비트는 항상 0
//                     next = DATA;       // 다음은 데이터 비트 전송
//                 end
//             end
            
//             DATA: begin
//                 if (tick) begin
//                     // 현재 데이터 비트 전송
//                     tx_next = data_in[data_count];
                    
//                     // 모든 데이터 비트를 전송했는지 확인
//                     if (data_count == 3'b111) begin
//                         next = STOP;           // 마지막 비트 후 STOP으로 전환
//                         data_count_next = 3'b000; // 카운터 초기화
//                     end else begin
//                         data_count_next = data_count + 1'b1; // 다음 비트로
//                     end
//                 end
//             end
            
//             STOP: begin
//                 if (tick) begin
//                     tx_next = 1'b1;    // 정지 비트는 항상 1
//                     tx_done_next = 1'b1;    // 전송 완료 신호를 1로 변경
//                     next = IDLE;       // 전송 완료, IDLE로 돌아감
//                 end
//             end
            
//             default: begin
//                 next = IDLE;
//                 tx_next = 1'b1;
//                 data_count_next = 3'b000;
//             end
//         endcase
//     end
// endmodule


// `timescale 1ns / 1ps

// module baud_tick_gen (
//     input clk,
//     input rst,
//     output baud_tick
// );
//     // 9600 baud rate 설정
//     parameter BAUD_RATE = 9600;
//     localparam BAUD_COUNT = 100_000_000 / BAUD_RATE;
    
//     reg [$clog2(BAUD_COUNT) - 1 : 0] count_reg, count_next;
//     reg tick_reg, tick_next;
    
//     // 출력 할당
//     assign baud_tick = tick_reg;
    
//     always @(posedge clk, posedge rst) begin
//         if(rst == 1) begin
//             count_reg <= 0;
//             tick_reg <= 0;
//         end else begin
//             count_reg <= count_next;
//             tick_reg <= tick_next;
//         end
//     end
    
//     // 다음 상태 로직
//     always @(*) begin
//         count_next = count_reg;
//         tick_next = tick_reg;
        
//         if (count_reg == BAUD_COUNT - 1) begin
//             count_next = 0;
//             tick_next = 1'b1;
//         end else begin
//             count_next = count_reg + 1;
//             tick_next = 1'b0;
//         end
//     end
// endmodule