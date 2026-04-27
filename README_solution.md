# CORDIC Assignment Solution

This folder contains a complete small CORDIC project:

- `cordic_rotation.v` - Q1 rotation mode CORDIC
- `cordic_vectoring.v` - Q1 vectoring mode CORDIC
- `tb_cordic_q1.v` - testbench for both Q1 modules
- `verify_q1.py` - Python checker for Q1 CSV outputs
- `cordic_pipeline.v` - Q2 doubly pipelined linear CORDIC divider
- `tb_cordic_pipeline.v` - testbench for Q2
- `verify_pipeline.py` - Python checker for Q2 CSV output
- `modelsim_commands.do` - basic ModelSim command file

Run in ModelSim:

```tcl
do modelsim_commands.do
```

Then run:

```bash
python verify_q1.py
python verify_pipeline.py
```

Default fixed point is Q3.28 with 32-bit signed words.
