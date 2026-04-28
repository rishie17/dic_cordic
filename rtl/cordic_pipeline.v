`timescale 1ns/1ps

// Pipelined circular CORDIC.
// First 16 stages rotate the input vector by angle_in.
// Next 16 stages vector the rotated result to get magnitude and angle.
// Final 16 stages run linear CORDIC division: quotient = y_rot / x_rot.
module cordic_pipeline #(
    parameter N = 32,                    // total input/output width
    parameter FRAC = 28,                 // fractional bits in fixed point
    parameter ITER = 16                  // CORDIC stages per mode
)(
    input clk,                           // clock
    input rst,                           // async reset
    input valid_in,                      // input sample is valid
    input signed [N-1:0] x_in,           // input x value
    input signed [N-1:0] y_in,           // input y value
    input signed [N-1:0] angle_in,       // rotation angle in radians
    output valid_out,                    // final outputs are valid
    output signed [N-1:0] x_rot_out,     // rotated x, delayed to match final outputs
    output signed [N-1:0] y_rot_out,     // rotated y, delayed to match final outputs
    output signed [N-1:0] magnitude_out, // vectoring magnitude output
    output signed [N-1:0] angle_out,     // vectoring angle output
    output signed [N-1:0] quotient_out   // linear CORDIC division output
);

    localparam W = N + 3;                // internal guard bits like the basic CORDIC modules

    integer i;                           // loop variable for reset and pipeline updates

    reg signed [W-1:0] rot_x [0:ITER];   // rotation pipeline x values
    reg signed [W-1:0] rot_y [0:ITER];   // rotation pipeline y values
    reg signed [W-1:0] rot_z [0:ITER];   // rotation pipeline angle values
    reg rot_valid [0:ITER];              // valid bits for rotation pipeline

    reg signed [W-1:0] vec_x [0:ITER];   // vectoring pipeline x values
    reg signed [W-1:0] vec_y [0:ITER];   // vectoring pipeline y values
    reg signed [W-1:0] vec_z [0:ITER];   // vectoring pipeline angle values
    reg vec_valid [0:ITER];              // valid bits for vectoring pipeline

    reg signed [W-1:0] rot_x_dly [0:ITER]; // rotated x delay for output alignment
    reg signed [W-1:0] rot_y_dly [0:ITER]; // rotated y delay for output alignment

    reg signed [W-1:0] div_x [0:ITER];   // division pipeline denominator
    reg signed [W-1:0] div_y [0:ITER];   // division pipeline residual/numerator
    reg signed [W-1:0] div_z [0:ITER];   // division pipeline quotient
    reg div_valid [0:ITER];              // valid bits for division pipeline

    reg signed [W-1:0] out_x_dly [0:ITER];   // x_rot delay through division pipe
    reg signed [W-1:0] out_y_dly [0:ITER];   // y_rot delay through division pipe
    reg signed [W-1:0] out_mag_dly [0:ITER]; // magnitude delay through division pipe
    reg signed [W-1:0] out_ang_dly [0:ITER]; // angle delay through division pipe

    wire signed [W-1:0] mag_fixed;       // magnitude after CORDIC gain correction

    assign mag_fixed = gain_fix(vec_x[ITER]); // vectoring x contains gain-scaled magnitude
    assign valid_out = div_valid[ITER];        // final valid comes from end of division pipe
    assign x_rot_out = out_x_dly[ITER][N-1:0]; // aligned rotated x output
    assign y_rot_out = out_y_dly[ITER][N-1:0]; // aligned rotated y output
    assign magnitude_out = out_mag_dly[ITER][N-1:0]; // aligned magnitude output
    assign angle_out = out_ang_dly[ITER][N-1:0];     // aligned vectoring angle output
    assign quotient_out = div_z[ITER][N-1:0];        // final linear CORDIC quotient

    // Reused atan table from the existing rotation/vectoring modules.
    function signed [W-1:0] atan_val;
        input integer k;                 // stage index
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
                default: atan_val = 0;    // safe default
            endcase
        end
    endfunction

    // Approximate K=0.60725 with shifts, same style as the other CORDIC files.
    function signed [W-1:0] gain_fix;
        input signed [W-1:0] a;          // value to scale
        begin
            gain_fix = (a >>> 1) + (a >>> 3)
                     - (a >>> 6) - (a >>> 9)
                     - (a >>> 12) + (a >>> 14)
                     + (a >>> 15);
        end
    endfunction

    // Registered rotation pipeline followed by registered vectoring pipeline.
    always @(posedge clk or posedge rst) begin
        if (rst) begin                   // clear every pipeline register
            for (i = 0; i <= ITER; i = i + 1) begin
                rot_x[i] <= 0;
                rot_y[i] <= 0;
                rot_z[i] <= 0;
                rot_valid[i] <= 0;
                vec_x[i] <= 0;
                vec_y[i] <= 0;
                vec_z[i] <= 0;
                vec_valid[i] <= 0;
                rot_x_dly[i] <= 0;
                rot_y_dly[i] <= 0;
                div_x[i] <= 0;
                div_y[i] <= 0;
                div_z[i] <= 0;
                div_valid[i] <= 0;
                out_x_dly[i] <= 0;
                out_y_dly[i] <= 0;
                out_mag_dly[i] <= 0;
                out_ang_dly[i] <= 0;
            end
        end else begin                   // normal pipeline operation
            rot_x[0] <= gain_fix({{3{x_in[N-1]}}, x_in});       // pre-scale x by K
            rot_y[0] <= gain_fix({{3{y_in[N-1]}}, y_in});       // pre-scale y by K
            rot_z[0] <= {{3{angle_in[N-1]}}, angle_in};         // load input angle
            rot_valid[0] <= valid_in;                           // load valid bit

            for (i = 0; i < ITER; i = i + 1) begin              // rotation stages
                if (rot_z[i] >= 0) begin                        // rotate one way
                    rot_x[i+1] <= rot_x[i] - (rot_y[i] >>> i);
                    rot_y[i+1] <= rot_y[i] + (rot_x[i] >>> i);
                    rot_z[i+1] <= rot_z[i] - atan_val(i);
                end else begin                                  // rotate opposite way
                    rot_x[i+1] <= rot_x[i] + (rot_y[i] >>> i);
                    rot_y[i+1] <= rot_y[i] - (rot_x[i] >>> i);
                    rot_z[i+1] <= rot_z[i] + atan_val(i);
                end
                rot_valid[i+1] <= rot_valid[i];                 // move valid forward
            end

            vec_x[0] <= rot_x[ITER];                            // vectoring starts after rotation
            vec_y[0] <= rot_y[ITER];                            // use rotated y
            vec_z[0] <= 0;                                      // vectoring angle starts at zero
            vec_valid[0] <= rot_valid[ITER];                    // valid crosses to vectoring pipe

            rot_x_dly[0] <= rot_x[ITER];                        // save rotated x for aligned output
            rot_y_dly[0] <= rot_y[ITER];                        // save rotated y for aligned output

            for (i = 0; i < ITER; i = i + 1) begin              // vectoring stages
                if (vec_y[i] >= 0) begin                        // reduce positive y
                    vec_x[i+1] <= vec_x[i] + (vec_y[i] >>> i);
                    vec_y[i+1] <= vec_y[i] - (vec_x[i] >>> i);
                    vec_z[i+1] <= vec_z[i] + atan_val(i);
                end else begin                                  // reduce negative y
                    vec_x[i+1] <= vec_x[i] - (vec_y[i] >>> i);
                    vec_y[i+1] <= vec_y[i] + (vec_x[i] >>> i);
                    vec_z[i+1] <= vec_z[i] - atan_val(i);
                end
                vec_valid[i+1] <= vec_valid[i];                 // move valid forward
                rot_x_dly[i+1] <= rot_x_dly[i];                 // delay rotated x with vectoring result
                rot_y_dly[i+1] <= rot_y_dly[i];                 // delay rotated y with vectoring result
            end

            if (rot_x_dly[ITER] < 0) begin                      // keep denominator positive
                div_x[0] <= -rot_x_dly[ITER];                   // denominator = abs(x_rot)
                div_y[0] <= -rot_y_dly[ITER];                   // flip numerator too, ratio is unchanged
            end else begin                                      // denominator already positive
                div_x[0] <= rot_x_dly[ITER];                    // denominator = x_rot
                div_y[0] <= rot_y_dly[ITER];                    // numerator = y_rot
            end
            div_z[0] <= 0;                                      // quotient starts at zero
            div_valid[0] <= vec_valid[ITER];                    // valid crosses to division pipe

            out_x_dly[0] <= rot_x_dly[ITER];                    // pass aligned rotated x into final delay
            out_y_dly[0] <= rot_y_dly[ITER];                    // pass aligned rotated y into final delay
            out_mag_dly[0] <= mag_fixed;                        // pass magnitude into final delay
            out_ang_dly[0] <= vec_z[ITER];                      // pass angle into final delay

            for (i = 0; i < ITER; i = i + 1) begin              // linear CORDIC division stages
                div_x[i+1] <= div_x[i];                         // x stays constant in linear mode
                div_valid[i+1] <= div_valid[i];                 // move valid forward
                out_x_dly[i+1] <= out_x_dly[i];                 // keep x_rot aligned to quotient
                out_y_dly[i+1] <= out_y_dly[i];                 // keep y_rot aligned to quotient
                out_mag_dly[i+1] <= out_mag_dly[i];             // keep magnitude aligned to quotient
                out_ang_dly[i+1] <= out_ang_dly[i];             // keep angle aligned to quotient

                if (div_y[i] >= 0) begin                        // residual positive: subtract
                    div_y[i+1] <= div_y[i] - (div_x[i] >>> i);
                    div_z[i+1] <= div_z[i] + ({{(W-1){1'b0}}, 1'b1} <<< (FRAC - i));
                end else begin                                  // residual negative: add back
                    div_y[i+1] <= div_y[i] + (div_x[i] >>> i);
                    div_z[i+1] <= div_z[i] - ({{(W-1){1'b0}}, 1'b1} <<< (FRAC - i));
                end
            end
        end
    end

endmodule
