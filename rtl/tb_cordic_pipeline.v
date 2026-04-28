`timescale 1ns/1ps

// Testbench for pipelined CORDIC divider.
module tb_cordic_pipeline;
    parameter N = 32;              // data width used by DUT
    parameter FRAC = 28;           // fractional bit count used by DUT

    reg clk;                       // testbench clock
    reg rst;                       // reset signal
    reg valid_in;                  // marks input as valid
    reg signed [N-1:0] num;        // numerator input
    reg signed [N-1:0] den;        // denominator input
    wire valid_out;                // output valid signal
    wire signed [N-1:0] quo;       // quotient output

    integer fp;                    // CSV file handle
    integer cycle;                 // simple cycle counter

    cordic_pipeline div1 (         // instantiate divider DUT
        .clk(clk),                 // connect clock
        .rst(rst),                 // connect reset
        .valid_in(valid_in),       // connect input valid
        .numerator_in(num),        // connect numerator
        .denominator_in(den),      // connect denominator
        .valid_out(valid_out),     // connect output valid
        .quotient_out(quo)         // connect quotient
    );

    always #5 clk = ~clk;          // make a 10 ns clock

    // Convert real number to fixed-point integer.
    function signed [N-1:0] fx;
        input real a;              // real input value
        begin
            fx = $rtoi(a * (1 << FRAC)); // scale real value by 2^FRAC
        end
    endfunction

    // Send one division sample into the pipeline.
    task give_input;
        input real n;              // numerator as real
        input real d;              // denominator as real
        begin
            @(negedge clk);        // change inputs away from active edge
            num = fx(n);           // drive fixed-point numerator
            den = fx(d);           // drive fixed-point denominator
            valid_in = 1'b1;       // mark this input as valid
            $fdisplay(fp, "IN,%0d,%f,%f,0", cycle, n, d); // save input row
        end
    endtask

    initial begin
        clk = 0;                   // start clock low
        rst = 1;                   // start in reset
        valid_in = 0;              // no valid input during reset
        num = 0;                   // clear numerator
        den = 0;                   // clear denominator
        cycle = 0;                 // clear cycle counter

        fp = $fopen("results/pipeline_results.csv", "w"); // open CSV file
        $fdisplay(fp, "type,cycle,numerator,denominator,quotient_int"); // header

        repeat (3) @(posedge clk); // hold reset for a few clocks
        rst = 0;                   // release reset

        give_input(0.50, 1.00);    // expected result about 0.5
        give_input(0.75, 1.25);    // expected result about 0.6
        give_input(1.00, 1.50);    // expected result about 0.6667
        give_input(-0.60, 1.20);   // expected result about -0.5
        give_input(1.40, 1.00);    // expected result about 1.4
        give_input(0.20, 0.80);    // expected result about 0.25

        @(negedge clk);            // wait before turning off valid
        valid_in = 0;              // stop sending new inputs
        num = 0;                   // clear numerator
        den = fx(1.0);             // keep denominator nonzero

        repeat (30) @(posedge clk);// wait for all outputs
        $fclose(fp);               // close CSV file
        $display("pipeline tests finished"); // print completion message
        $finish;                   // stop simulation
    end

    always @(posedge clk) begin
        cycle <= cycle + 1;        // count clock cycles
        if (valid_out) begin       // save only valid outputs
            $display("cycle=%0d quotient_int=%0d", cycle, quo); // print result
            $fdisplay(fp, "OUT,%0d,0,0,%0d", cycle, quo);       // save output row
        end
    end
endmodule
