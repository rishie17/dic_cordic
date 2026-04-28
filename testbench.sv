`timescale 1ns/1ps

// Small direct testbench for cordic_pipeline.
module tb_cordic_pipeline_direct;
    parameter N = 32;                    // data width
    parameter FRAC = 28;                 // fractional bits
    parameter ITER = 16;                 // stages per CORDIC mode

    reg clk;                             // clock
    reg rst;                             // reset
    reg valid_in;                        // input valid
    reg signed [N-1:0] x_in;             // input x
    reg signed [N-1:0] y_in;             // input y
    reg signed [N-1:0] angle_in;         // rotation angle
    wire valid_out;                      // output valid
    wire signed [N-1:0] x_rot_out;       // rotated x
    wire signed [N-1:0] y_rot_out;       // rotated y
    wire signed [N-1:0] magnitude_out;   // final magnitude
    wire signed [N-1:0] angle_out;       // final vectoring angle
    wire signed [N-1:0] quotient_out;    // final linear CORDIC quotient

    cordic_pipeline #(
        .N(N),
        .FRAC(FRAC),
        .ITER(ITER)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x_in(x_in),
        .y_in(y_in),
        .angle_in(angle_in),
        .valid_out(valid_out),
        .x_rot_out(x_rot_out),
        .y_rot_out(y_rot_out),
        .magnitude_out(magnitude_out),
        .angle_out(angle_out),
        .quotient_out(quotient_out)
    );

    always #5 clk = ~clk;                // 10 ns clock

    function real to_real;               // fixed point to real
        input signed [N-1:0] value;
        begin
            to_real = value / real'(1 << FRAC);
        end
    endfunction

    initial begin
        $dumpfile("cordic_pipeline.vcd");
        $dumpvars(0, tb_cordic_pipeline_direct);

        clk = 0;
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        angle_in = 0;

        repeat (3) @(posedge clk);
        rst = 0;

        @(negedge clk);
        x_in = 32'sd268435456;           // 1.0 in Q3.28
        y_in = 32'sd0;                   // 0.0 in Q3.28
        angle_in = 32'sd210828714;       // 45 degrees, quotient should be near 1
        valid_in = 1'b1;

        @(negedge clk);
        valid_in = 1'b0;
        x_in = 0;
        y_in = 0;
        angle_in = 0;

        wait (valid_out == 1'b1);
        #1;

        $display("x_rot fixed   = %0d, real = %f", x_rot_out, to_real(x_rot_out));
        $display("y_rot fixed   = %0d, real = %f", y_rot_out, to_real(y_rot_out));
        $display("mag fixed     = %0d, real = %f", magnitude_out, to_real(magnitude_out));
        $display("angle fixed   = %0d, real = %f", angle_out, to_real(angle_out));
        $display("quot fixed    = %0d, real = %f", quotient_out, to_real(quotient_out));

        $finish;
    end
endmodule
