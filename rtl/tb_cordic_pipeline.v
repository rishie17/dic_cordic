`timescale 1ns/1ps

// Testbench for the pipelined rotation + vectoring CORDIC.
module tb_cordic_pipeline;
    parameter N = 32;                    // data width used by DUT
    parameter FRAC = 28;                 // fractional bit count used by DUT

    reg clk;                             // testbench clock
    reg rst;                             // reset signal
    reg valid_in;                        // input valid flag
    reg signed [N-1:0] x_in;             // input x value
    reg signed [N-1:0] y_in;             // input y value
    reg signed [N-1:0] angle_in;         // input rotation angle
    wire valid_out;                      // output valid flag
    wire signed [N-1:0] x_rot_out;       // rotated x output
    wire signed [N-1:0] y_rot_out;       // rotated y output
    wire signed [N-1:0] magnitude_out;   // vectoring magnitude
    wire signed [N-1:0] angle_out;       // vectoring angle
    wire signed [N-1:0] quotient_out;    // linear CORDIC quotient

    integer fp;                          // CSV file handle
    integer cycle;                       // cycle counter

    cordic_pipeline dut (                // instantiate new pipeline DUT
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

    always #5 clk = ~clk;                // make a 10 ns clock

    function signed [N-1:0] fx;          // convert real to fixed point
        input real a;
        begin
            fx = $rtoi(a * (1 << FRAC));
        end
    endfunction

    task give_input;                     // send one sample into pipeline
        input real x_real;
        input real y_real;
        input real angle_real;
        begin
            @(negedge clk);              // change inputs away from posedge
            x_in = fx(x_real);
            y_in = fx(y_real);
            angle_in = fx(angle_real);
            valid_in = 1'b1;
            $fdisplay(fp, "IN,%0d,%f,%f,%f,0,0,0,0,0", cycle, x_real, y_real, angle_real);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        angle_in = 0;
        cycle = 0;

        fp = $fopen("results/pipeline_results.csv", "w");
        $fdisplay(fp, "type,cycle,x_in,y_in,angle_in,x_rot,y_rot,mag_out,angle_out,quotient_out");

        repeat (3) @(posedge clk);
        rst = 0;

        give_input(1.0, 0.0, 0.000000);   // quotient near 0/1 = 0
        give_input(1.0, 0.0, 0.244979);   // quotient near tan(14 deg) = 0.25
        give_input(1.0, 0.0, -0.244979);  // quotient near -0.25
        give_input(1.0, 0.0, 0.523599);   // quotient near tan(30 deg) = 0.577
        give_input(1.0, 0.0, 0.785398);   // quotient near tan(45 deg) = 1.0
        give_input(0.8, -0.2, 0.349066);  // general vector case
        give_input(0.5, 0.3, 0.000000);   // quotient = 0.3/0.5 = 3/5
        give_input(0.7, 0.6, 0.000000);   // quotient = 0.6/0.7 = 6/7

        @(negedge clk);
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        angle_in = 0;

        repeat (65) @(posedge clk);
        $fclose(fp);
        $display("pipeline rotation+vectoring tests finished");
        $finish;
    end

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (valid_out) begin
            $display("cycle=%0d x_rot=%0d y_rot=%0d mag=%0d angle=%0d quo=%0d",
                     cycle, x_rot_out, y_rot_out, magnitude_out, angle_out, quotient_out);
            $fdisplay(fp, "OUT,%0d,0,0,0,%0d,%0d,%0d,%0d,%0d",
                      cycle, x_rot_out, y_rot_out, magnitude_out, angle_out, quotient_out);
        end
    end
endmodule
