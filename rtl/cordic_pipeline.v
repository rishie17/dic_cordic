`timescale 1ns/1ps

// Pipelined linear CORDIC divider.
// Output is approximately numerator_in / denominator_in.
module cordic_pipeline #(
    parameter N = 32,              // total input/output width
    parameter FRAC = 28,           // fractional bits in fixed point
    parameter ITER = 16            // number of pipeline stages
)(
    input clk,                     // clock
    input rst,                     // async reset
    input valid_in,                // input sample is valid
    input signed [N-1:0] numerator_in,   // dividend input
    input signed [N-1:0] denominator_in, // divisor input
    output valid_out,              // output sample is valid
    output signed [N-1:0] quotient_out   // quotient output
);

    integer i;                     // loop variable used in reset and pipeline update

    reg signed [N-1:0] x_pipe [0:ITER]; // denominator travels through the pipe
    reg signed [N-1:0] y_pipe [0:ITER]; // residual/error value travels through pipe
    reg signed [N-1:0] z_pipe [0:ITER]; // quotient estimate travels through pipe
    reg sign_pipe [0:ITER];        // final sign travels with the sample
    reg valid_pipe [0:ITER];       // valid bit travels with the sample

    reg signed [N-1:0] num_abs;    // absolute value of numerator
    reg signed [N-1:0] den_abs;    // absolute value of denominator
    wire signed [N-1:0] z_signed;  // quotient after sign correction

    assign z_signed = sign_pipe[ITER] ? -z_pipe[ITER] : z_pipe[ITER]; // restore sign
    assign quotient_out = z_signed;  // connect signed quotient to output
    assign valid_out = valid_pipe[ITER]; // output valid after pipeline latency

    // Convert inputs to magnitudes; quotient sign is saved separately.
    always @(*) begin
        num_abs = numerator_in;     // start with original numerator
        den_abs = denominator_in;   // start with original denominator

        if (num_abs < 0)            // check numerator sign
            num_abs = -num_abs;     // make numerator positive
        if (den_abs < 0)            // check denominator sign
            den_abs = -den_abs;     // make denominator positive
    end

    // One CORDIC division step is done in each pipeline stage.
    always @(posedge clk or posedge rst) begin
        if (rst) begin              // clear all registers on reset
            for (i = 0; i <= ITER; i = i + 1) begin // visit every pipe slot
                x_pipe[i] <= 0;     // clear denominator pipe
                y_pipe[i] <= 0;     // clear residual pipe
                z_pipe[i] <= 0;     // clear quotient pipe
                sign_pipe[i] <= 0;  // clear sign pipe
                valid_pipe[i] <= 0; // clear valid pipe
            end
        end else begin              // normal pipeline operation
            x_pipe[0] <= den_abs;   // load absolute denominator
            y_pipe[0] <= num_abs;   // load absolute numerator
            z_pipe[0] <= 0;         // quotient starts from zero
            sign_pipe[0] <= numerator_in[N-1] ^ denominator_in[N-1]; // quotient sign
            valid_pipe[0] <= valid_in; // load valid bit

            for (i = 0; i < ITER; i = i + 1) begin // update all stages
                x_pipe[i+1] <= x_pipe[i];          // pass denominator forward
                sign_pipe[i+1] <= sign_pipe[i];    // pass sign forward
                valid_pipe[i+1] <= valid_pipe[i];  // pass valid forward

                if (y_pipe[i] >= 0) begin          // residual is positive, subtract
                    y_pipe[i+1] <= y_pipe[i] - (x_pipe[i] >>> i); // update residual
                    z_pipe[i+1] <= z_pipe[i] + (32'sd1 <<< (FRAC - i)); // add quotient bit
                end else begin                     // residual is negative, add back
                    y_pipe[i+1] <= y_pipe[i] + (x_pipe[i] >>> i); // update residual
                    z_pipe[i+1] <= z_pipe[i] - (32'sd1 <<< (FRAC - i)); // subtract quotient bit
                end
            end
        end
    end

endmodule
