`timescale 1ns/1ps

module tb_cordic_q1;
    parameter N = 32;
    parameter FRAC = 28;

    reg signed [N-1:0] rot_x, rot_y, rot_angle;
    wire signed [N-1:0] rot_x_out, rot_y_out, rot_angle_left;

    reg signed [N-1:0] vec_x, vec_y;
    wire signed [N-1:0] vec_mag, vec_angle, vec_y_left;

    integer fd_rot, fd_vec;
    integer t;

    cordic_rotation #(.N(N), .FRAC(FRAC), .ITER(16)) dut_rot (
        .x_in(rot_x),
        .y_in(rot_y),
        .angle_in(rot_angle),
        .x_out(rot_x_out),
        .y_out(rot_y_out),
        .angle_left(rot_angle_left)
    );

    cordic_vectoring #(.N(N), .FRAC(FRAC), .ITER(16)) dut_vec (
        .x_in(vec_x),
        .y_in(vec_y),
        .mag_out(vec_mag),
        .angle_out(vec_angle),
        .y_left(vec_y_left)
    );

    function signed [N-1:0] to_fixed;
        input real value;
        begin
            to_fixed = $rtoi(value * (1 << FRAC));
        end
    endfunction

    task run_rotation_case;
        input real x_real;
        input real y_real;
        input real a_real;
        begin
            rot_x = to_fixed(x_real);
            rot_y = to_fixed(y_real);
            rot_angle = to_fixed(a_real);
            #2;
            $display("ROT x=%f y=%f ang=%f -> xo=%0d yo=%0d", x_real, y_real, a_real, rot_x_out, rot_y_out);
            $fdisplay(fd_rot, "%f,%f,%f,%0d,%0d,%0d", x_real, y_real, a_real,
                      rot_x_out, rot_y_out, rot_angle_left);
        end
    endtask

    task run_vector_case;
        input real x_real;
        input real y_real;
        begin
            vec_x = to_fixed(x_real);
            vec_y = to_fixed(y_real);
            #2;
            $display("VEC x=%f y=%f -> mag=%0d ang=%0d", x_real, y_real, vec_mag, vec_angle);
            $fdisplay(fd_vec, "%f,%f,%0d,%0d,%0d", x_real, y_real, vec_mag, vec_angle, vec_y_left);
        end
    endtask

    initial begin
        fd_rot = $fopen("rotation_results.csv", "w");
        fd_vec = $fopen("vectoring_results.csv", "w");

        $fdisplay(fd_rot, "x_in,y_in,angle_in,x_out,y_out,angle_left");
        $fdisplay(fd_vec, "x_in,y_in,mag_out,angle_out,y_left");

        run_rotation_case(1.0, 0.0, 0.000000);
        run_rotation_case(1.0, 0.0, 0.523599);
        run_rotation_case(1.0, 0.0, 0.785398);
        run_rotation_case(0.5, 0.5, -0.523599);
        run_rotation_case(0.8, -0.2, 0.349066);

        run_vector_case(1.0, 0.0);
        run_vector_case(0.866025, 0.5);
        run_vector_case(0.707107, 0.707107);
        run_vector_case(0.5, -0.5);
        run_vector_case(1.25, 0.75);

        $fclose(fd_rot);
        $fclose(fd_vec);
        $display("Q1 testbench done. CSV files written.");
        $finish;
    end
endmodule
