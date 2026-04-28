# CORDIC Assignment Solution

This folder contains a complete small CORDIC project:

- `rtl/cordic_rotation.v` - Q1 rotation mode CORDIC
- `rtl/cordic_vectoring.v` - Q1 vectoring mode CORDIC
- `rtl/tb_cordic_q1.v` - testbench for both Q1 modules
- `verify/verify_q1.py` - Python checker for Q1 CSV outputs
- `rtl/cordic_pipeline.v` - Q2 pipelined rotation plus vectoring CORDIC
- `rtl/tb_cordic_pipeline.v` - testbench for Q2
- `verify/verify_pipeline.py` - Python checker for Q2 CSV output
- `rtl/modelsim_commands.do` - basic ModelSim command file

Run in ModelSim:

```tcl
do rtl/modelsim_commands.do
```

Then run:

```bash
python verify/verify_q1.py
python verify/verify_pipeline.py
```

Default fixed point is Q3.28 with 32-bit signed words.

## How This Code Works (Student Explanation)

CORDIC is basically a shift-add method for doing rotations and some math functions. Instead of multiplying by sine and cosine directly, the circuit rotates by small fixed angles like `atan(1)`, `atan(1/2)`, `atan(1/4)` and so on. Since those values use powers of two, the multiply part becomes a right shift.

In one rotation-mode iteration, the code checks the sign of `z_reg`, which is the angle still left to rotate. If `z_reg` is positive, it rotates one way and subtracts the current angle table value. If `z_reg` is negative, it rotates the other way and adds the table value back. The update is just:

```text
x = x +/- (y >> i)
y = y -/+ (x >> i)
z = z -/+ atan(2^-i)
```

The important part is `(y >> i)` and `(x >> i)`. A right shift by `i` bits is the same idea as dividing by `2^i`, so the hardware does not need a multiplier.

Vectoring mode is almost the same hardware, but the decision is based on `y_reg` instead of `z_reg`. Here the aim is to push `y_reg` close to zero. When that happens, `x_reg` is the magnitude, after correcting the CORDIC gain, and `z_reg` is the angle.

The pipeline version first rotates the input vector, then sends that rotated vector into a second vectoring pipeline. It has one register per iteration in each part, so the total latency is about 32 clocks, but after the pipe fills, a new result can still come out every clock.
