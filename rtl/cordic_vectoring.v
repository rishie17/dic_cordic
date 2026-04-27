`timescale 1ns/1ps // simulation time unit is 1ns and precision is 1ps

// 16 iteration circular CORDIC in vectoring mode.
// Works directly for x >= 0, giving magnitude and angle atan(y/x).
module cordic_vectoring #(
    parameter N = 32, // total bit width for inputs and outputs
    parameter FRAC = 28, // fractional bit count for fixed-point arithmetic
    parameter ITER = 16 // number of CORDIC iterations
)(
    input  signed [N-1:0] x_in, // signed fixed-point x input
    input  signed [N-1:0] y_in, // signed fixed-point y input
    output signed [N-1:0] mag_out, // output magnitude after vectoring
    output signed [N-1:0] angle_out, // output angle after vectoring
    output signed [N-1:0] y_left // leftover y after convergence
);

    localparam W = N + 4; // working width with guard bits for operations

    integer i; // loop index for iteration
    reg signed [W-1:0] x_work, y_work, z_work; // current working values for x, y and accumulated angle
    reg signed [W-1:0] x_next, y_next, z_next; // next working values for the iteration
    wire signed [W-1:0] mag_scaled; // magnitude after gain compensation

    function signed [W-1:0] scale_by_k;
        input signed [W-1:0] value; // input value to apply gain compensation to
        begin
            scale_by_k = (value >>> 1) + (value >>> 3)
                       - (value >>> 6) - (value >>> 9)
                       - (value >>> 12) + (value >>> 14)
                       + (value >>> 15); // approximate the inverse CORDIC gain constant K
        end
    endfunction

    function signed [W-1:0] atan_lut;
        input integer index; // iteration index for atan lookup
        begin
            case (index)
                0:  atan_lut = 210828714; // atan(2^-0) scaled to Q3.28
                1:  atan_lut = 124459457; // atan(2^-1)
                2:  atan_lut = 65760959; // atan(2^-2)
                3:  atan_lut = 33381290; // atan(2^-3)
                4:  atan_lut = 16755422; // atan(2^-4)
                5:  atan_lut = 8385879; // atan(2^-5)
                6:  atan_lut = 4193963; // atan(2^-6)
                7:  atan_lut = 2097109; // atan(2^-7)
                8:  atan_lut = 1048571; // atan(2^-8)
                9:  atan_lut = 524287; // atan(2^-9)
                10: atan_lut = 262144; // atan(2^-10)
                11: atan_lut = 131072; // atan(2^-11)
                12: atan_lut = 65536; // atan(2^-12)
                13: atan_lut = 32768; // atan(2^-13)
                14: atan_lut = 16384; // atan(2^-14)
                15: atan_lut = 8192; // atan(2^-15)
                default: atan_lut = 0; // default fallback if index is out of range
            endcase
        end
    endfunction

    always @(*) begin
        x_work = {{4{x_in[N-1]}}, x_in}; // sign-extend x into working width
        y_work = {{4{y_in[N-1]}}, y_in}; // sign-extend y into working width
        z_work = 0; // initialize the accumulated angle to zero

        for (i = 0; i < ITER; i = i + 1) begin
            if (y_work >= 0) begin
                x_next = x_work + (y_work >>> i); // rotate toward the x-axis when y is non-negative
                y_next = y_work - (x_work >>> i); // reduce y magnitude using shifted x
                z_next = z_work + atan_lut(i); // accumulate positive angle
            end else begin
                x_next = x_work - (y_work >>> i); // rotate opposite direction when y is negative
                y_next = y_work + (x_work >>> i); // reduce y magnitude using shifted x
                z_next = z_work - atan_lut(i); // accumulate negative angle
            end

            x_work = x_next; // update x for next iteration
            y_work = y_next; // update y for next iteration
            z_work = z_next; // update z for next iteration
        end
    end

    // Vectoring mode magnitude has CORDIC gain, so scale it back by K.
    assign mag_scaled = scale_by_k(x_work); // apply inverse gain compensation to x_work
    assign mag_out = mag_scaled[N-1:0]; // output the lower N bits of magnitude
    assign angle_out = z_work[N-1:0]; // output the lower N bits of accumulated angle
    assign y_left = y_work[N-1:0]; // output any remaining y value after vectoring

endmodule
