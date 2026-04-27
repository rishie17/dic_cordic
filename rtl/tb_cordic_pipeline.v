`timescale 1ns/1ps

module tb_cordic_pipeline;
    parameter N = 32;
    parameter FRAC = 28;

    reg clk, rst, valid_in;
    reg signed [N-1:0] numerator, denominator;
    wire valid_out;
    wire signed [N-1:0] quotient;

    integer fd;
    integer cycle;

    cordic_pipeline #(.N(N), .FRAC(FRAC), .ITER(16)) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .numerator_in(numerator),
        .denominator_in(denominator),
        .valid_out(valid_out),
        .quotient_out(quotient)
    );

    always #5 clk = ~clk;

    function signed [N-1:0] to_fixed;
        input real value;
        begin
            to_fixed = $rtoi(value * (1 << FRAC));
        end
    endfunction

    task send_case;
        input real n_real;
        input real d_real;
        begin
            @(negedge clk);
            numerator = to_fixed(n_real);
            denominator = to_fixed(d_real);
            valid_in = 1'b1;
            @(posedge clk);
            $fdisplay(fd, "IN,%0d,%f,%f,0", cycle, n_real, d_real);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        valid_in = 0;
        numerator = 0;
        denominator = 0;
        cycle = 0;

        fd = $fopen("pipeline_results.csv", "w");
        $fdisplay(fd, "type,cycle,numerator,denominator,quotient_int");

        repeat (3) @(posedge clk);
        rst = 0;

        send_case(0.50, 1.00);
        send_case(0.75, 1.25);
        send_case(1.00, 1.50);
        send_case(-0.60, 1.20);
        send_case(1.40, 1.00);
        send_case(0.20, 0.80);

        @(negedge clk);
        valid_in = 0;
        numerator = 0;
        denominator = to_fixed(1.0);

        repeat (45) @(posedge clk);
        $fclose(fd);
        $display("Q2 pipeline testbench done. CSV file written.");
        $finish;
    end

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (valid_out) begin
            $display("cycle=%0d quotient_int=%0d", cycle, quotient);
            $fdisplay(fd, "OUT,%0d,0,0,%0d", cycle, quotient);
        end
    end
endmodule
