`timescale 1ns/1ps

// Vectoring mode CORDIC block.
// Finds magnitude and angle for x_in >= 0.
module cordic_vectoring #(
    parameter N = 32,              // total input/output width
    parameter FRAC = 28,           // number of fractional bits
    parameter ITER = 16            // number of CORDIC steps
)(
    input  signed [N-1:0] x_in,    // input x value
    input  signed [N-1:0] y_in,    // input y value
    output signed [N-1:0] mag_out, // approximate vector magnitude
    output signed [N-1:0] angle_out,// approximate atan(y/x)
    output signed [N-1:0] y_left   // leftover y after vectoring
);

    localparam W = N + 3;          // internal width with guard bits

    integer i;                     // loop variable for iterations
    reg signed [W-1:0] x_reg;      // working x value
    reg signed [W-1:0] y_reg;      // working y value
    reg signed [W-1:0] z_reg;      // accumulated angle
    reg signed [W-1:0] x_old;      // saved x before update
    reg signed [W-1:0] y_old;      // saved y before update
    wire signed [W-1:0] mag_fixed; // magnitude after gain correction

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

    // Approximate K=0.60725 using only shifts and adds.
    function signed [W-1:0] gain_fix;
        input signed [W-1:0] a;    // value to scale by K
        begin
            gain_fix = (a >>> 1) + (a >>> 3)   // 1/2 + 1/8
                     - (a >>> 6) - (a >>> 9)   // subtract small correction terms
                     - (a >>> 12) + (a >>> 14) // add another small correction
                     + (a >>> 15);             // final small correction
        end
    endfunction

    // Combinational 16-step CORDIC vectoring.
    always @(*) begin
        x_reg = {{3{x_in[N-1]}}, x_in};        // sign extend x
        y_reg = {{3{y_in[N-1]}}, y_in};        // sign extend y
        z_reg = 0;                             // start angle at zero

        for (i = 0; i < ITER; i = i + 1) begin // run each CORDIC iteration
            x_old = x_reg;                     // save old x
            y_old = y_reg;                     // save old y

            if (y_reg >= 0) begin              // choose direction to reduce positive y
                x_reg = x_old + (y_old >>> i); // x update using shifted y
                y_reg = y_old - (x_old >>> i); // y moves closer to zero
                z_reg = z_reg + atan_val(i);   // angle accumulates positive turn
            end else begin                     // choose direction to reduce negative y
                x_reg = x_old - (y_old >>> i); // x update for opposite direction
                y_reg = y_old + (x_old >>> i); // y moves closer to zero
                z_reg = z_reg - atan_val(i);   // angle accumulates negative turn
            end
        end
    end

    assign mag_fixed = gain_fix(x_reg);        // remove CORDIC gain from final x
    assign mag_out = mag_fixed[N-1:0];         // output corrected magnitude
    assign angle_out = z_reg[N-1:0];           // output accumulated angle
    assign y_left = y_reg[N-1:0];              // output remaining y error

endmodule
