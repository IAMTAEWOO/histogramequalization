module hist_eq_core #(
    parameter WIDTH   = 320,
    parameter HEIGHT  = 240
)(
    input               i_clk,
    input               i_rst_n,
    input               i_valid,
    input       [7:0]   i_gray,
    input               i_end,
    output reg          o_in_ready,
    input               i_out_ready,
    output reg          o_valid,
    output reg  [7:0]   o_gray_eq,
    output reg          o_done
);

    // 고정 프레임 크기 가정 (누적 total_pix 불필요)
    localparam integer TOTAL_PIXELS = WIDTH * HEIGHT;
    
// synopsys translate_off
// synopsys ramstyle = "block"
// synopsys translate_on
reg [15:0] hist [0:255];
reg [15:0] cdf  [0:255];
reg [7:0]  lut  [0:255];


    // ===== 제어 플래그/카운터 =====
    reg        lut_valid;         // LUT 존재 여부
    reg [4:0]  use_cnt;           // LUT 사용 프레임 카운트 (0~8 사용, 9번째 끝나면 재학습)
    reg [8:0]  idx;               // 0..255 루프 인덱스
    reg        phase_cdf;         // LUTC 단계 내부: 1=CDF, 0=LUT
    reg [15:0] cdf_acc;           // 누적합
    reg [15:0] cdf_min;           // 처음으로 비영(非0) CDF
    reg        cdf_min_found;

    // ===== FSM =====
    localparam S_IDLE   = 2'd0;   // 프레임 시작 대기
    localparam S_LEARN  = 2'd1;   // 첫/재학습 프레임: 히스토그램만 누적(출력 금지)
    localparam S_LUTC   = 2'd2;   // CDF→LUT 즉시 생성
    localparam S_STREAM = 2'd3;   // LUT 기반 스트리밍 매핑 출력
    reg [1:0] state, next_state;

    // ----------------- 상태 레지스터 -----------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) state <= S_IDLE;
        else          state <= next_state;
    end

    // --------------- 다음 상태 콤비 ------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE  : if (i_valid)                     next_state = (lut_valid ? S_STREAM : S_LEARN);
            S_LEARN : if (i_end)                       next_state = S_LUTC;
            S_LUTC  : if (!phase_cdf && (idx==9'd255)) next_state = S_IDLE;    // LUT 생성 끝 → IDLE
            S_STREAM: if (i_end)                       next_state = S_IDLE;    // 프레임 경계에서 IDLE
            default : next_state = S_IDLE;
        endcase
    end

    integer i;
    // ----------------- 순차 로직 ---------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_in_ready     <= 1'b0;
            o_valid        <= 1'b0;
            o_gray_eq      <= 8'd0;
            o_done         <= 1'b0;

            lut_valid      <= 1'b0;
            use_cnt        <= 3'd0;

            idx            <= 9'd0;
            phase_cdf      <= 1'b1;
            cdf_acc        <= 16'd0;
            cdf_min        <= 16'd0;
            cdf_min_found  <= 1'b0;

            for (i=0;i<256;i=i+1) begin
                hist[i] <= 16'd0;
                cdf[i]  <= 16'd0;
                lut[i]  <= i[7:0]; // 초기 항등 LUT (미사용이지만 초기화)
            end
        end else begin
            // 기본값
            o_valid <= 1'b0;
            o_done  <= 1'b0;

            case (state)
            // --------------------------- IDLE ---------------------------
            S_IDLE: begin
                // 입력 허용: 스트림 전체에 backpressure 주고 싶으면 여기서 제어
                // 요구사항: 첫 프레임/학습 프레임은 출력하지 않으므로 데이터는 항상 받아도 됨
                o_in_ready <= (lut_valid ? i_out_ready : 1'b1);

                // LUTC 막 끝난 직후에 한 사이클 o_done 펄스
                // (o_done은 LUTC에서 set됨, 여기선 건드리지 않음)

                // 상태 전이 자체는 next_state에서 처리
                // 전이 시 필요한 초기화는 각 상태 진입에서 수행
            end

            // -------------------------- LEARN --------------------------
            // 첫/재학습 프레임: 히스토그램 누적만 수행. 절대 출력하지 않음.
            S_LEARN: begin
                o_in_ready <= 1'b1; // 출력 안 하므로 백프레셔 불필요
                if (i_valid) begin
                    hist[i_gray] <= hist[i_gray] + 16'd1;
                end
                if (i_end) begin
                    // LUTC 준비
                    idx            <= 9'd0;
                    phase_cdf      <= 1'b1;   // 먼저 CDF
                    cdf_acc        <= 16'd0;
                    cdf_min        <= 16'd0;
                    cdf_min_found  <= 1'b0;
                end
            end

            // --------------------- LUTC (CDF → LUT) --------------------
            S_LUTC: begin
                o_in_ready <= 1'b0; // 입력 무시
                if (phase_cdf) begin
                    // CDF 단계: idx = 0..255
                    cdf_acc  <= cdf_acc + hist[idx];
                    cdf[idx] <= cdf_acc + hist[idx];

                    if (!cdf_min_found && (cdf_acc + hist[idx] != 16'd0)) begin
                        cdf_min       <= cdf_acc + hist[idx];
                        cdf_min_found <= 1'b1;
                    end

                    if (idx == 9'd255) begin
                        phase_cdf <= 1'b0;    // LUT 단계로 즉시 전환
                        idx       <= 9'd0;
                    end else begin
                        idx       <= idx + 1'b1;
                    end
                end else begin
                    // LUT 단계: idx = 0..255  (동시에 hist를 0으로 클리어해 다음 학습을 준비)
                    if (cdf_min_found && (TOTAL_PIXELS > cdf_min))
                        lut[idx] <= ((cdf[idx] - cdf_min) * 8'd255) / (TOTAL_PIXELS - cdf_min);
                    else
                        lut[idx] <= 8'd0;

                    hist[idx] <= 16'd0; // 다음 학습을 위해 사용한 bin은 즉시 0으로

                    if (idx == 9'd255) begin
                        lut_valid <= 1'b1;    // LUT 준비 완료
                        use_cnt   <= 3'd0;    // 이제 4프레임 동안 사용 예정
                        o_done    <= 1'b1;    // 완료 펄스
                        // 다음 상태 전이는 next_state에서 S_IDLE로
                    end else begin
                        idx       <= idx + 1'b1;
                    end
                end
            end

            // -------------------------- STREAM -------------------------
            // LUT 존재: 입력을 바로 매핑해 출력
            S_STREAM: begin
                // 출력 소비자가 막으면 입력도 막아 손실 방지 (rgb2gray에 backpressure 전달)
                o_in_ready <= i_out_ready;

                if (i_valid && i_out_ready) begin
                    o_gray_eq <= lut[i_gray];
                    o_valid   <= 1'b1;
                end

                if (i_end) begin
                    // 이 프레임을 LUT로 '사용' 완료
                    if (use_cnt == 8) begin
                        // 4프레임 사용을 채웠으므로 다음 프레임은 '학습 프레임'으로 전환
                        lut_valid <= 1'b0;   // 다음 IDLE에서 S_LEARN으로 빠짐
                        use_cnt   <= 3'd0;
                        // hist[]는 이전 LUTC에서 이미 0으로 되어 있음
                    end else begin
                        use_cnt   <= use_cnt + 1'b1; // 계속 사용
                    end
                end
            end

            endcase
        end
    end

endmodule
