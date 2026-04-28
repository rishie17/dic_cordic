`timescale 1ns/1ps

// Rotation mode CORDIC block.
// Uses Q3.28 fixed point when N=32 and FRAC=28.
module cordic_rotation #(
    parameter N = 32,              // total input/output width
    parameter FRAC = 28,           // number of fractional bits
    parameter ITER = 16            // number of CORDIC steps
)(
    input  signed [N-1:0] x_in,    // input x value
    input  signed [N-1:0] y_in,    // input y value
    input  signed [N-1:0] angle_in,// input angle in radians, fixed point
    output signed [N-1:0] x_out,   // rotated x value
    output signed [N-1:0] y_out,   // rotated y value
    output signed [N-1:0] angle_left // remaining angle after iterations
);

    localparam W = N + 3;          // internal width with a few guard bits

    integer i;                     // loop variable for the CORDIC iterations
    reg signed [W-1:0] x_reg;      // working x value
    reg signed [W-1:0] y_reg;      // working y value
    reg signed [W-1:0] z_reg;      // working angle value
    reg signed [W-1:0] x_old;      // saved x before updating
    reg signed [W-1:0] y_old;      // saved y before updating

    // Lookup table for atan(2^-i), scaled by 2^28.
    function signed [W-1:0] atan_val;
        input integer k;           // table index
        begin
            case (k)
                0:  atan_val = 210828714; // atan(1)
                1:  atan_val = 124459457; // atan(1/2)
                2:  atan_val = 65760959;  // atan(1/4)
                3:  atan_val = 33381290;  // atan(1/8)
                4:  atan_val = 16755422;  // atan(1/16)
                5:  atan_val = 8385879;   // atan(1/32)
                6:  atan_val = 4193963;   // atan(1/64)
                7:  atan_val = 2097109;   // atan(1/128)
                8:  atan_val = 1048571;   // atan(1/256)
                9:  atan_val = 524287;    // atan(1/512)
                10: atan_val = 262144;    // atan(1/1024)
                11: atan_val = 131072;    // atan(1/2048)
                12: atan_val = 65536;     // atan(1/4096)
                13: atan_val = 32768;     // atan(1/8192)
                14: atan_val = 16384;     // atan(1/16384)
                15: atan_val = 8192;      // atan(1/32768)
                default: atan_val = 0;    // safe value for unused indexes
            endcase
        end
    endfunction

    // Approximate K=0.60725 using shifts, so no multiplier is used.
    function signed [W-1:0] gain_fix;
        input signed [W-1:0] a;    // value to scale by K
        begin
            gain_fix = (a >>> 1) + (a >>> 3)   // 1/2 + 1/8
                     - (a >>> 6) - (a >>> 9)   // subtract small correction terms
                     - (a >>> 12) + (a >>> 14) // add another small correction
                     + (a >>> 15);             // final small correction
        end
    endfunction

    // Combinational 16-step CORDIC rotation.
    always @(*) begin
        x_reg = gain_fix({{3{x_in[N-1]}}, x_in}); // sign extend x and pre-scale by K
        y_reg = gain_fix({{3{y_in[N-1]}}, y_in}); // sign extend y and pre-scale by K
        z_reg = {{3{angle_in[N-1]}}, angle_in};   // sign extend the angle

        for (i = 0; i < ITER; i = i + 1) begin    // run each CORDIC iteration
            x_old = x_reg;                        // save x before changing it
            y_old = y_reg;                        // save y before changing it

            if (z_reg >= 0) begin                 // rotate one way when angle is positive
                x_reg = x_old - (y_old >>> i);    // x update uses shifted y
                y_reg = y_old + (x_old >>> i);    // y update uses shifted x
                z_reg = z_reg - atan_val(i);      // reduce the remaining angle
            end else begin                        // rotate opposite way when angle is negative
                x_reg = x_old + (y_old >>> i);    // x update for opposite direction
                y_reg = y_old - (x_old >>> i);    // y update for opposite direction
                z_reg = z_reg + atan_val(i);      // bring angle back toward zero
            end
        end
    end

    assign x_out = x_reg[N-1:0];                  // send final x to output
    assign y_out = y_reg[N-1:0];                  // send final y to output
    assign angle_left = z_reg[N-1:0];             // send leftover angle to output

endmodule
