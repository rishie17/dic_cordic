`timescale 1ns/1ps // simulation time unit is 1ns and time precision is 1ps

// Doubly pipelined linear CORDIC divider.
// quotient_out ~= numerator_in / denominator_in.
// Best for denominator > 0 and |numerator/denominator| < 2.
module cordic_pipeline #(
    parameter N = 32, // total bit width for inputs and outputs
    parameter FRAC = 28, // number of fractional bits in fixed-point format
    parameter ITER = 16 // number of pipeline iterations / CORDIC steps
)(
    input clk, // clock input
    input rst, // synchronous reset input
    input valid_in, // input valid signal for pipelining
    input signed [N-1:0] numerator_in, // signed numerator input
    input signed [N-1:0] denominator_in, // signed denominator input
    output valid_out, // output valid signal after pipeline latency
    output signed [N-1:0] quotient_out // signed quotient output
);

    localparam W = N + 4; // internal working width with guard bits for shifts and adds

    reg signed [W-1:0] x_mid [0:ITER-1]; // first pipeline stage x values
    reg signed [W-1:0] y_mid [0:ITER-1]; // first pipeline stage y values
    reg signed [W-1:0] z_mid [0:ITER-1]; // first pipeline stage z/angle values
    reg signed [W-1:0] shift_mid [0:ITER-1]; // stored shifted value for stage updates
    reg d_mid [0:ITER-1]; // decision bits for each stage
    reg sign_mid [0:ITER-1]; // sign bit pipeline for output correction
    reg valid_mid [0:ITER-1]; // intermediate valid pipeline bits

    reg signed [W-1:0] x_pipe [0:ITER-1]; // second half pipeline x values
    reg signed [W-1:0] y_pipe [0:ITER-1]; // second half pipeline y values
    reg signed [W-1:0] z_pipe [0:ITER-1]; // second half pipeline z/angle values
    reg sign_pipe [0:ITER-1]; // second half sign bit pipeline
    reg valid_pipe [0:ITER-1]; // second half valid pipeline bits

    integer i; // loop index for initialization and pipeline updates
    reg signed [W-1:0] num_abs; // absolute value of numerator with guard bits
    reg signed [W-1:0] den_abs; // absolute value of denominator with guard bits
    reg signed [W-1:0] term; // current angle term for z updates
    wire out_negative; // flag whether output sign is negative
    wire signed [W-1:0] z_signed; // signed output after sign correction

    assign out_negative = sign_pipe[ITER-1]; // final sign is stored at last pipeline stage
    assign z_signed = out_negative ? -z_pipe[ITER-1] : z_pipe[ITER-1]; // negate final result if output sign is negative
    assign quotient_out = z_signed[N-1:0]; // truncate or wrap the final result to N bits
    assign valid_out = valid_pipe[ITER-1]; // final valid output after pipeline latency

    always @(*) begin
        num_abs = {{4{numerator_in[N-1]}}, numerator_in}; // sign-extend numerator into working width
        den_abs = {{4{denominator_in[N-1]}}, denominator_in}; // sign-extend denominator into working width

        if (num_abs < 0)
            num_abs = -num_abs; // take absolute value of numerator
        if (den_abs < 0)
            den_abs = -den_abs; // take absolute value of denominator
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ITER; i = i + 1) begin
                x_mid[i] <= 0; // reset intermediate x values
                y_mid[i] <= 0; // reset intermediate y values
                z_mid[i] <= 0; // reset intermediate z values
                shift_mid[i] <= 0; // reset shift values
                d_mid[i] <= 0; // reset decision bits
                sign_mid[i] <= 0; // reset sign bits
                valid_mid[i] <= 0; // reset valid bits
                x_pipe[i] <= 0; // reset second half x pipeline
                y_pipe[i] <= 0; // reset second half y pipeline
                z_pipe[i] <= 0; // reset second half z pipeline
                sign_pipe[i] <= 0; // reset second half sign pipeline
                valid_pipe[i] <= 0; // reset second half valid pipeline
            end
        end else begin
            // First half of stage 0: prepare absolute numerator and denominator and decide rotation direction.
            x_mid[0] <= den_abs; // store absolute denominator for stage 0
            y_mid[0] <= num_abs; // store absolute numerator for stage 0
            z_mid[0] <= 0; // initial z value starts at zero
            shift_mid[0] <= den_abs; // initial shift value is denominator itself
            d_mid[0] <= (num_abs >= 0); // decide sign based on numerator absolute value
            sign_mid[0] <= numerator_in[N-1] ^ denominator_in[N-1]; // remember sign of quotient from input signs
            valid_mid[0] <= valid_in; // propagate input valid through pipeline

            // Second half of stage 0: perform the first add/subtract update.
            term = ({{(W-1){1'b0}}, 1'b1} <<< FRAC); // compute scaling term shifted by FRAC to align fixed-point magnitude
            x_pipe[0] <= x_mid[0]; // propagate x through second half pipeline
            if (d_mid[0]) begin
                y_pipe[0] <= y_mid[0] - shift_mid[0]; // subtract shift when decision bit is true
                z_pipe[0] <= z_mid[0] + term; // add term to z when decision bit is true
            end else begin
                y_pipe[0] <= y_mid[0] + shift_mid[0]; // add shift when decision bit is false
                z_pipe[0] <= z_mid[0] - term; // subtract term from z when decision bit is false
            end
            sign_pipe[0] <= sign_mid[0]; // propagate sign bit through second-stage pipeline
            valid_pipe[0] <= valid_mid[0]; // propagate valid bit through second-stage pipeline

            for (i = 1; i < ITER; i = i + 1) begin
                // Half A of stage i: latch previous pipeline outputs and compute the next shift.
                x_mid[i] <= x_pipe[i-1]; // take previous stage x into current stage midpoint
                y_mid[i] <= y_pipe[i-1]; // take previous stage y into current stage midpoint
                z_mid[i] <= z_pipe[i-1]; // take previous stage z into current stage midpoint
                shift_mid[i] <= x_pipe[i-1] >>> i; // compute x shifted by i bits arithmetically
                d_mid[i] <= (y_pipe[i-1] >= 0); // decide next direction based on current y value sign
                sign_mid[i] <= sign_pipe[i-1]; // propagate sign bit forward
                valid_mid[i] <= valid_pipe[i-1]; // propagate valid bit forward

                // Half B of stage i: perform add/subtract update based on decision bit.
                term = ({{(W-1){1'b0}}, 1'b1} <<< (FRAC - i)); // compute scaled angle term for stage i
                x_pipe[i] <= x_mid[i]; // propagate x midpoint into second half pipeline
                if (d_mid[i]) begin
                    y_pipe[i] <= y_mid[i] - shift_mid[i]; // subtract shifted x from y when y is non-negative
                    z_pipe[i] <= z_mid[i] + term; // add term to z when direction is positive
                end else begin
                    y_pipe[i] <= y_mid[i] + shift_mid[i]; // add shifted x to y when y is negative
                    z_pipe[i] <= z_mid[i] - term; // subtract term from z when direction is negative
                end
                sign_pipe[i] <= sign_mid[i]; // propagate sign through second half
                valid_pipe[i] <= valid_mid[i]; // propagate valid through second half
            end
        end
    end

endmodule
