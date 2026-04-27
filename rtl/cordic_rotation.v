`timescale 1ns/1ps // simulation time unit is 1ns and precision is 1ps

// 16 iteration circular CORDIC in rotation mode.
// Default format is Q3.28 when N=32 and FRAC=28.
module cordic_rotation #(
    parameter N = 32, // total bit width for inputs and outputs
    parameter FRAC = 28, // fractional bit count for fixed-point arithmetic
    parameter ITER = 16 // number of CORDIC iterations
)(
    input  signed [N-1:0] x_in, // signed fixed-point x input
    input  signed [N-1:0] y_in, // signed fixed-point y input
    input  signed [N-1:0] angle_in, // signed fixed-point rotation angle input
    output signed [N-1:0] x_out, // signed fixed-point rotated x output
    output signed [N-1:0] y_out, // signed fixed-point rotated y output
    output signed [N-1:0] angle_left // remaining angle after rotation
);

    localparam W = N + 4; // working width with guard bits for shift/add safety

    integer i; // loop index for iteration
    reg signed [W-1:0] x_work, y_work, z_work; // current working values for x, y, and z
    reg signed [W-1:0] x_next, y_next, z_next; // next values computed each iteration

    // K = 0.607252935 approx using only shifts:
    // 1/2 + 1/8 - 1/64 - 1/512 - 1/4096 + 1/16384 + 1/32768
    function signed [W-1:0] scale_by_k;
        input signed [W-1:0] value; // input to scale by the CORDIC gain correction
        begin
            scale_by_k = (value >>> 1) + (value >>> 3)
                       - (value >>> 6) - (value >>> 9)
                       - (value >>> 12) + (value >>> 14)
                       + (value >>> 15); // approximate K using bit shifts and adds
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
        // Rotation mode gets K correction before the rotations.
        x_work = scale_by_k({{4{x_in[N-1]}}, x_in}); // sign-extend x and apply gain correction
        y_work = scale_by_k({{4{y_in[N-1]}}, y_in}); // sign-extend y and apply gain correction
        z_work = {{4{angle_in[N-1]}}, angle_in}; // sign-extend angle into working width

        for (i = 0; i < ITER; i = i + 1) begin
            if (z_work >= 0) begin
                x_next = x_work - (y_work >>> i); // rotate negatively when z is non-negative
                y_next = y_work + (x_work >>> i); // update y with shifted x
                z_next = z_work - atan_lut(i); // subtract current atan term from z
            end else begin
                x_next = x_work + (y_work >>> i); // rotate positively when z is negative
                y_next = y_work - (x_work >>> i); // update y with shifted x
                z_next = z_work + atan_lut(i); // add current atan term to z
            end

            x_work = x_next; // accept updated x for next iteration
            y_work = y_next; // accept updated y for next iteration
            z_work = z_next; // accept updated z for next iteration
        end
    end

    assign x_out = x_work[N-1:0]; // output the lower N bits of final x
    assign y_out = y_work[N-1:0]; // output the lower N bits of final y
    assign angle_left = z_work[N-1:0]; // output the lower N bits of final remaining angle

endmodule
