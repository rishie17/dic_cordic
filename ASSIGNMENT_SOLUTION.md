# CORDIC Algorithm Assignment

## Section 1: Theory

CORDIC stands for Coordinate Rotation Digital Computer. The main idea is simple: instead of using multipliers, sine/cosine blocks, or division hardware, we break the operation into many small rotations. Each small rotation angle is chosen as `atan(2^-i)`, so multiplying by `tan(angle)` becomes just shifting by `i`.

For this assignment I used:

- Iterations: `16`
- Default word length: `N = 32`
- Fixed point: `Q3.28`
- Scale: real value = integer value / `2^28`

`Q3.28` means 1 sign bit, 3 integer bits, and 28 fractional bits. This is enough for values like radians in the range around `-pi` to `+pi`, and it gives pretty good accuracy for 16 iterations.

The angle lookup table stores:

```text
atan(2^-0), atan(2^-1), atan(2^-2), ... atan(2^-15)
```

The values are stored in fixed-point radians. Example:

```text
atan(1) = pi/4 = 0.785398...
fixed = 0.785398 * 2^28 = 210828714
```

The circular CORDIC gain after many iterations is about:

```text
1 / K = 1.646760...
K     = 0.607252935...
```

So the design uses a shift-add approximation for `K`:

```text
K ~= 1/2 + 1/8 - 1/64 - 1/512 - 1/4096 + 1/16384 + 1/32768
```

This keeps the hardware multiplier-free.

## Section 2: Q1 Verilog Code

The Q1 design files are:

- [rtl/cordic_rotation.v](./rtl/cordic_rotation.v)
- [rtl/cordic_vectoring.v](./rtl/cordic_vectoring.v)

Rotation mode rotates an input vector by a given angle:

```text
x' = x cos(theta) - y sin(theta)
y' = y cos(theta) + x sin(theta)
```

The Verilog does this using the CORDIC recurrence:

```text
if z >= 0:
    x_next = x - (y >>> i)
    y_next = y + (x >>> i)
    z_next = z - atan_table[i]
else:
    x_next = x + (y >>> i)
    y_next = y - (x >>> i)
    z_next = z + atan_table[i]
```

Vectoring mode takes `(x, y)` and tries to rotate the vector onto the x-axis. At the end:

```text
magnitude ~= sqrt(x^2 + y^2)
angle     ~= atan(y/x)
```

The vectoring recurrence used is:

```text
if y >= 0:
    x_next = x + (y >>> i)
    y_next = y - (x >>> i)
    z_next = z + atan_table[i]
else:
    x_next = x - (y >>> i)
    y_next = y + (x >>> i)
    z_next = z - atan_table[i]
```

For this student-level version, vectoring is tested for `x >= 0`, so it gives the normal `atan(y/x)` range. Full `atan2` quadrant correction can be added separately if needed.

## Section 3: Testbenches

The Q1 testbench is:

- [rtl/tb_cordic_q1.v](./rtl/tb_cordic_q1.v)

It tests both modules and writes:

- `results/rotation_results.csv`
- `results/vectoring_results.csv`

ModelSim-style commands are in:

- [rtl/modelsim_commands.do](./rtl/modelsim_commands.do)

Run:

```tcl
do rtl/modelsim_commands.do
```

Or with Icarus Verilog:

```bash
iverilog -o results/q1_check.vvp rtl/cordic_rotation.v rtl/cordic_vectoring.v rtl/tb_cordic_q1.v
vvp results/q1_check.vvp
```

Sample Q1 simulation output:

```text
ROT x=1.000000 y=0.000000 ang=0.523599 -> xo=232476228 yo=134224731
ROT x=1.000000 y=0.000000 ang=0.785398 -> xo=189820587 yo=189814696
VEC x=0.866025 y=0.500000 -> mag=268442589 ang=140556387
VEC x=0.707107 y=0.707107 -> mag=268442767 ang=210832881
Q1 testbench done. CSV files written.
```

## Section 4: Python Verification

The Python checker is:

- [verify/verify_q1.py](./verify/verify_q1.py)

It implements the same fixed-point CORDIC algorithm as the Verilog. It reads the CSV files from simulation and compares:

- Verilog output
- Python fixed-point output
- Absolute error
- Relative error

Run:

```bash
python verify/verify_q1.py
```

Sample output:

```text
Rotation mode check
case | verilog_x python_x abs_err rel_err | verilog_y python_y abs_err rel_err
   1 |  0.86604144  0.86604144 0.000e+00 0.000e+00 |  0.50002609  0.50002609 0.000e+00 0.000e+00
   2 |  0.70713679  0.70713679 0.000e+00 0.000e+00 |  0.70711485  0.70711485 0.000e+00 0.000e+00

Vectoring mode check
case | verilog_mag python_mag abs_err rel_err | verilog_ang python_ang abs_err rel_err
   1 |  1.00002657  1.00002657 0.000e+00 0.000e+00 |  0.52361334  0.52361334 0.000e+00 0.000e+00
   2 |  1.00002724  1.00002724 0.000e+00 0.000e+00 |  0.78541369  0.78541369 0.000e+00 0.000e+00
```

The zero error here means Verilog and Python fixed-point models are matching. There is still a small error compared with exact floating-point math because 16 iterations and fixed-point rounding are not infinite precision.

## Section 5: Q2 Pipelined Design

For Q2 I chose division using linear CORDIC.

Files:

- [rtl/cordic_pipeline.v](./rtl/cordic_pipeline.v)
- [rtl/tb_cordic_pipeline.v](./rtl/tb_cordic_pipeline.v)

The operation is:

```text
quotient ~= numerator / denominator
```

The design assumes:

```text
denominator != 0
|numerator / denominator| < 2
```

This is a normal convergence limit for this simple linear CORDIC divider.

Linear CORDIC division uses:

```text
if y >= 0:
    y_next = y - (x >>> i)
    z_next = z + 2^-i
else:
    y_next = y + (x >>> i)
    z_next = z - 2^-i
```

Here:

- `x` is the denominator
- `y` starts as the numerator
- `z` becomes the quotient

### Pipeline Structure

The simplified version uses one register per CORDIC iteration. That makes the pipeline easier to draw and explain:

```text
pipe[0] -> iteration 0 -> pipe[1] -> iteration 1 -> ... -> pipe[16]
```

The total latency is:

```text
16 CORDIC stages = about 16 clock cycles
```

Throughput is:

```text
1 result per clock after the pipeline is full
```

Conceptually:

```text
cycle 0: input sample 0 enters pipe[0]
cycle 1: sample 0 moves to pipe[1], sample 1 enters pipe[0]
cycle 2: sample 0 moves to pipe[2], sample 1 moves to pipe[1]
...
after the pipe fills: outputs come every clock
```

This is useful in real-time systems because the clock period can be shorter. The answer comes later, but once the pipe is full it keeps producing answers continuously.

## Section 6: Python Verification for Q2

The Q2 Python checker is:

- [verify/verify_pipeline.py](./verify/verify_pipeline.py)

Run:

```bash
python verify/verify_pipeline.py
```

It reads:

- `results/pipeline_results.csv`

Then compares the Verilog quotient with the Python fixed-point CORDIC quotient.

Sample output:

```text
Pipelined division check
case | numerator denominator | verilog_q python_q math_q abs_err rel_err
   0 |  0.5000  1.0000 |  0.50003052  0.50003052  0.50000000 0.000e+00 0.000e+00
   1 |  0.7500  1.2500 |  0.60000610  0.60000610  0.60000000 0.000e+00 0.000e+00
   2 |  1.0000  1.5000 |  0.66665649  0.66665649  0.66666667 0.000e+00 0.000e+00
   3 | -0.6000  1.2000 | -0.49996948 -0.49996948 -0.50000000 0.000e+00 0.000e+00
   4 |  1.4000  1.0000 |  1.39999390  1.39999390  1.40000000 0.000e+00 0.000e+00
   5 |  0.2000  0.8000 |  0.25003052  0.25003052  0.25000000 0.000e+00 0.000e+00
```

## Section 7: Results and Error Analysis

For Q1, the Verilog and Python fixed-point model matched exactly for all tested cases. The output is close to the expected sine/cosine or magnitude/angle values. Example:

```text
cos(30 deg) ~= 0.866025
CORDIC x    ~= 0.866041

sin(30 deg) ~= 0.500000
CORDIC y    ~= 0.500026
```

The small difference is mainly from:

- only 16 iterations
- fixed-point truncation after shifts
- approximate shift-add value of `K`

For Q2 division, the Verilog and Python CORDIC model also matched exactly. Compared to real division, the error is small. Example:

```text
0.75 / 1.25 = 0.600000
CORDIC       = 0.600006
```

That is good enough for a basic fixed-point hardware implementation.

## Section 8: Final Observations

CORDIC is nice for FPGA/digital design because it replaces expensive multipliers with shifts, adds, subtracts, and small lookup tables. Rotation mode is better when we already know the angle and want the rotated vector. Vectoring mode is better when we have a vector and want its magnitude/angle.

The scaling factor is important. If we ignore it, the answer has a gain error of about `1.6467`. In this design I handled it using a shift-add approximation of `K`, so the datapath still stays multiplier-free.

The pipelined divider has more registers than a fully combinational divider, but it can accept a new input every clock. In a real-time system, that is usually useful because throughput matters more than the first result latency.

## HOW THIS CODE WORKS (STUDENT EXPLANATION)

The code is written in a simple way on purpose. The rotation and vectoring modules both use a `for` loop for 16 CORDIC iterations. The variables `x_reg`, `y_reg`, and `z_reg` are the main values being updated.

In one rotation iteration, first I save old `x` and `y` into `x_old` and `y_old`. This is needed because both new values use the old values. Then the sign of `z_reg` decides the direction:

```text
if z is positive:
    x = x - (y >> i)
    y = y + (x >> i)
    z = z - atan_table[i]
else:
    x = x + (y >> i)
    y = y - (x >> i)
    z = z + atan_table[i]
```

The shift `>> i` is the main CORDIC trick. Shifting right by 1 divides by 2, shifting right by 2 divides by 4, and so on. So the circuit avoids multipliers and uses only shifts and add/subtract logic.

Rotation mode and vectoring mode are very similar. Rotation mode checks the angle `z_reg`, because we are trying to use up the required angle. Vectoring mode checks `y_reg`, because we are trying to rotate the vector until the y value becomes almost zero.

The pipeline divider is also kept simple. It has arrays like `x_pipe[0]` to `x_pipe[16]`. Each clock, data moves one stage forward. Every stage does one CORDIC division step and updates `y` and `z`. The `z` value slowly becomes the quotient. The output is delayed by 16 clocks, but once the pipeline is full, it can give one result every clock.
