`timescale 1ns/1ps

module tb_hist_eq_core;

    // -------------------------------------------------
    // Parameters
    // -------------------------------------------------
    localparam WIDTH  = 320;
    localparam HEIGHT = 240;
    localparam TOTAL_PIXELS = WIDTH * HEIGHT;

    // -------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------
    reg clk;
    reg rst_n;

    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------
    // DUT I/O
    // -------------------------------------------------
    reg         i_valid;
    reg  [7:0]  i_gray;
    reg         i_end;
    wire        o_in_ready;

    wire        o_valid;
    wire [7:0]  o_gray_eq;
    wire        o_done;
    reg         i_out_ready;

    // -------------------------------------------------
    // DUT Instance
    // -------------------------------------------------
    hist_eq_core #(
        .WIDTH (WIDTH),
        .HEIGHT(HEIGHT)
    ) dut (
        .i_clk       (clk),
        .i_rst_n     (rst_n),
        .i_valid     (i_valid),
        .i_gray      (i_gray),
        .i_end       (i_end),
        .o_in_ready  (o_in_ready),
        .i_out_ready (i_out_ready),
        .o_valid     (o_valid),
        .o_gray_eq   (o_gray_eq),
        .o_done      (o_done)
    );

    // -------------------------------------------------
    // Test Vectors
    // -------------------------------------------------
    reg [7:0] input_image   [0:TOTAL_PIXELS-1];
    reg [7:0] golden_output [0:TOTAL_PIXELS-1];

    integer in_idx;
    integer out_idx;

    // -------------------------------------------------
    // Clocked Ready (random back-pressure)
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            i_out_ready <= 1'b0;
        else
            i_out_ready <= $urandom_range(0,1);
    end

    // -------------------------------------------------
    // Input Driver
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            i_valid <= 0;
            i_gray  <= 0;
            i_end   <= 0;
            in_idx  <= 0;
        end
        else if (o_in_ready && in_idx < TOTAL_PIXELS) begin
            i_valid <= 1'b1;
            i_gray  <= input_image[in_idx];
            i_end   <= (in_idx == TOTAL_PIXELS-1);
            in_idx  <= in_idx + 1;
        end
        else begin
            i_valid <= 1'b0;
            i_end   <= 1'b0;
        end
    end

    // -------------------------------------------------
    // Output Checker (Self-Checking)
    // -------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            out_idx <= 0;
        end
        else if (o_valid && i_out_ready) begin
            if (o_gray_eq !== golden_output[out_idx]) begin
                $display("ERROR: Mismatch at pixel %0d", out_idx);
                $display("  Expected: %0d", golden_output[out_idx]);
                $display("  Got     : %0d", o_gray_eq);
                $fatal;
            end
            out_idx <= out_idx + 1;
        end
    end

    // -------------------------------------------------
    // Test Sequence
    // -------------------------------------------------
    initial begin
        clk = 0;
        rst_n = 0;

        $readmemh("input_image.hex",  input_image);
        $readmemh("golden_output.hex", golden_output);

        #50;
        rst_n = 1;

        wait(o_done);
        #50;

        $display("=================================");
        $display("TEST PASSED: All pixels matched");
        $display("=================================");
        $finish;
    end

endmodule
