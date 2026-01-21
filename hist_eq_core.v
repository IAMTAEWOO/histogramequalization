module hist_eq_core #(
    parameter WIDTH   = 320,
    parameter HEIGHT  = 240
)(
    input               i_clk,
    input               i_rst_n,

    // input grayscale stream
    input               i_valid,
    input       [7:0]   i_gray,
    input               i_end,

    // input backpressure
    output reg          o_in_ready,

    // output grayscale stream
    input               i_out_ready,
    output reg          o_valid,
    output reg  [7:0]   o_gray_eq,
    output reg          o_done
);

    // ------------------------------------------------------------------
    // Frame configuration
    // 고정 해상도 프레임 가정 → total pixel 수는 상수
    // ------------------------------------------------------------------
    localparam integer TOTAL_PIXELS = WIDTH * HEIGHT;

    // ------------------------------------------------------------------
    // Histogram / CDF / LUT storage
    // ------------------------------------------------------------------
    // hist : 학습 프레임에서 grayscale histogram 누적
    // cdf  : LUT 생성 시 cumulative distribution function
    // lut  : histogram equalization mapping table
    // ------------------------------------------------------------------

// synopsys translate_off
// synopsys ramstyle = "block"
// synopsys translate_on
    reg [15:0] hist [0:255];
    reg [15:0] cdf  [0:255];
    reg [7:0]  lut  [0:255];

    // ------------------------------------------------------------------
    // Control registers
    // ------------------------------------------------------------------
    reg        lut_valid;        // LUT 유효 여부
    reg [4:0]  use_cnt;          // LUT 사용 프레임 카운트
    reg [8:0]  idx;              // 0~255 인덱스
    reg        phase_cdf;        // LUTC 내부 단계: 1=CDF, 0=LUT
    reg [15:0] cdf_acc;          // CDF 누적 합
    reg [15:0] cdf_min;          // 최초 non-zero CDF 값
    reg        cdf_min_found;

    // ------------------------------------------------------------------
    // FSM definition
    // ------------------------------------------------------------------
    // IDLE   : 프레임 시작 대기
    // LEARN  : histogram 누적 (출력 없음)
    // LUTC   : CDF 계산 후 LUT 생성
    // STREAM : LUT 기반 실시간 매핑
    // ------------------------------------------------------------------
    localparam S_IDLE   = 2'd0;
    localparam S_LEARN  = 2'd1;
    localparam S_LUTC   = 2'd2;
    localparam S_STREAM = 2'd3;

    reg [1:0] state, next_state;

    // ------------------------------------------------------------------
    // State register
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ------------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE  :
                if (i_valid)
                    next_state = (lut_valid ? S_STREAM : S_LEARN);

            S_LEARN :
                if (i_end)
                    next_state = S_LUTC;

            S_LUTC  :
                if (!phase_cdf && (idx == 9'd255))
                    next_state = S_IDLE;

            S_STREAM:
                if (i_end)
                    next_state = S_IDLE;

            default :
                next_state = S_IDLE;
        endcase
    end

    integer i;

    // ------------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // output control
            o_in_ready     <= 1'b0;
            o_valid        <= 1'b0;
            o_gray_eq      <= 8'd0;
            o_done         <= 1'b0;

            // LUT control
            lut_valid      <= 1'b0;
            use_cnt        <= 3'd0;

            // LUTC control
            idx            <= 9'd0;
            phase_cdf      <= 1'b1;
            cdf_acc        <= 16'd0;
            cdf_min        <= 16'd0;
            cdf_min_found  <= 1'b0;

            // memory init
            for (i = 0; i < 256; i = i + 1) begin
                hist[i] <= 16'd0;
                cdf[i]  <= 16'd0;
                lut[i]  <= i[7:0]; // default identity mapping
            end
        end else begin
            // default outputs
            o_valid <= 1'b0;
            o_done  <= 1'b0;

            case (state)

            // ----------------------------------------------------------
            // IDLE : 프레임 시작 대기
            // ----------------------------------------------------------
            S_IDLE: begin
                // LUT 사용 시 출력 ready에 따라 입력 제어
                o_in_ready <= (lut_valid ? i_out_ready : 1'b1);
            end

            // ----------------------------------------------------------
            // LEARN : histogram 누적 (출력 없음)
            // ----------------------------------------------------------
            S_LEARN: begin
                o_in_ready <= 1'b1;

                if (i_valid)
                    hist[i_gray] <= hist[i_gray] + 16'd1;

                if (i_end) begin
                    // LUTC 초기화
                    idx           <= 9'd0;
                    phase_cdf     <= 1'b1;
                    cdf_acc       <= 16'd0;
                    cdf_min       <= 16'd0;
                    cdf_min_found <= 1'b0;
                end
            end

            // ----------------------------------------------------------
            // LUTC : CDF 계산 → LUT 생성
            // ----------------------------------------------------------
            S_LUTC: begin
                o_in_ready <= 1'b0;

                if (phase_cdf) begin
                    // CDF accumulation
                    cdf_acc  <= cdf_acc + hist[idx];
                    cdf[idx] <= cdf_acc + hist[idx];

                    if (!cdf_min_found && (cdf_acc + hist[idx] != 16'd0)) begin
                        cdf_min       <= cdf_acc + hist[idx];
                        cdf_min_found <= 1'b1;
                    end

                    if (idx == 9'd255) begin
                        phase_cdf <= 1'b0;
                        idx       <= 9'd0;
                    end else
                        idx <= idx + 1'b1;

                end else begin
                    // LUT generation + histogram clear
                    if (cdf_min_found && (TOTAL_PIXELS > cdf_min))
                        lut[idx] <= ((cdf[idx] - cdf_min) * 8'd255)
                                     / (TOTAL_PIXELS - cdf_min);
                    else
                        lut[idx] <= 8'd0;

                    hist[idx] <= 16'd0;

                    if (idx == 9'd255) begin
                        lut_valid <= 1'b1;
                        use_cnt   <= 3'd0;
                        o_done    <= 1'b1;
                    end else
                        idx <= idx + 1'b1;
                end
            end

            // ----------------------------------------------------------
            // STREAM : LUT 기반 실시간 매핑
            // ----------------------------------------------------------
            S_STREAM: begin
                o_in_ready <= i_out_ready;

                if (i_valid && i_out_ready) begin
                    o_gray_eq <= lut[i_gray];
                    o_valid   <= 1'b1;
                end

                if (i_end) begin
                    if (use_cnt == 8) begin
                        // LUT 재학습 필요
                        lut_valid <= 1'b0;
                        use_cnt   <= 3'd0;
                    end else
                        use_cnt <= use_cnt + 1'b1;
                end
            end

            endcase
        end
    end

endmodule
