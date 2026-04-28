`timescale 1ns/1ps

// Testbench for rotation and vectoring CORDIC modules.
module tb_cordic_q1;
    parameter N = 32;              // data width used by DUTs
    parameter FRAC = 28;           // fractional bits used by DUTs

    reg signed [N-1:0] rx;         // rotation test x input
    reg signed [N-1:0] ry;         // rotation test y input
    reg signed [N-1:0] rang;       // rotation test angle input
    wire signed [N-1:0] rx_out;    // rotation x output
    wire signed [N-1:0] ry_out;    // rotation y output
    wire signed [N-1:0] rleft;     // rotation leftover angle

    reg signed [N-1:0] vx;         // vectoring test x input
    reg signed [N-1:0] vy;         // vectoring test y input
    wire signed [N-1:0] vmag;      // vectoring magnitude output
    wire signed [N-1:0] vang;      // vectoring angle output
    wire signed [N-1:0] vy_left;   // vectoring leftover y

    integer frot;                  // file handle for rotation CSV
    integer fvec;                  // file handle for vectoring CSV

    cordic_rotation rot1 (         // instantiate rotation DUT
        .x_in(rx),                 // connect rotation x input
        .y_in(ry),                 // connect rotation y input
        .angle_in(rang),           // connect rotation angle input
        .x_out(rx_out),            // connect rotation x output
        .y_out(ry_out),            // connect rotation y output
        .angle_left(rleft)         // connect rotation leftover angle
    );

    cordic_vectoring vec1 (        // instantiate vectoring DUT
        .x_in(vx),                 // connect vectoring x input
        .y_in(vy),                 // connect vectoring y input
        .mag_out(vmag),            // connect magnitude output
        .angle_out(vang),          // connect angle output
        .y_left(vy_left)           // connect leftover y output
    );

    // Convert a real number to Q3.28 style fixed point.
    function signed [N-1:0] fx;
        input real a;              // real value from the test case
        begin
            fx = $rtoi(a * (1 << FRAC)); // scale and convert to integer
        end
    endfunction

    // Apply one rotation test case and save the result.
    task test_rot;
        input real x;              // real x input
        input real y;              // real y input
        input real ang;            // real angle input in radians
        begin
            rx = fx(x);            // drive fixed-point x
            ry = fx(y);            // drive fixed-point y
            rang = fx(ang);        // drive fixed-point angle
            #5;                    // wait for combinational output
            $display("ROT  x=%f y=%f ang=%f  ->  xout=%0d yout=%0d", x, y, ang, rx_out, ry_out);
            $fdisplay(frot, "%f,%f,%f,%0d,%0d,%0d", x, y, ang, rx_out, ry_out, rleft);
        end
    endtask

    // Apply one vectoring test case and save the result.
    task test_vec;
        input real x;              // real x input
        input real y;              // real y input
        begin
            vx = fx(x);            // drive fixed-point x
            vy = fx(y);            // drive fixed-point y
            #5;                    // wait for combinational output
            $display("VEC  x=%f y=%f  ->  mag=%0d angle=%0d", x, y, vmag, vang);
            $fdisplay(fvec, "%f,%f,%0d,%0d,%0d", x, y, vmag, vang, vy_left);
        end
    endtask

    initial begin
        frot = $fopen("results/rotation_results.csv", "w"); // open rotation CSV
        fvec = $fopen("results/vectoring_results.csv", "w"); // open vectoring CSV

        $fdisplay(frot, "x_in,y_in,angle_in,x_out,y_out,angle_left"); // write rotation header
        $fdisplay(fvec, "x_in,y_in,mag_out,angle_out,y_left");        // write vectoring header

        test_rot(1.0, 0.0, 0.000000);    // no rotation case
        test_rot(1.0, 0.0, 0.523599);    // about 30 degrees
        test_rot(1.0, 0.0, 0.785398);    // about 45 degrees
        test_rot(0.5, 0.5, -0.523599);   // negative rotation case
        test_rot(0.8, -0.2, 0.349066);   // general input vector case

        test_vec(1.0, 0.0);              // zero angle vector
        test_vec(0.866025, 0.5);         // about 30 degrees vector
        test_vec(0.707107, 0.707107);    // about 45 degrees vector
        test_vec(0.5, -0.5);             // negative angle vector
        test_vec(1.25, 0.75);            // larger magnitude vector

        $fclose(frot);                   // close rotation CSV
        $fclose(fvec);                   // close vectoring CSV
        $display("Q1 tests finished");   // print completion message
        $finish;                         // stop simulation
    end
endmodule
