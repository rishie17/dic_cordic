# Create ModelSim work library.
vlib work

# Compile Q1 rotation/vectoring files.
vlog rtl/cordic_rotation.v rtl/cordic_vectoring.v rtl/tb_cordic_q1.v

# Run Q1 testbench in command line mode.
vsim -c tb_cordic_q1 -do "run -all; quit"

# Compile Q2 rotation + vectoring pipeline files.
vlog rtl/cordic_pipeline.v rtl/tb_cordic_pipeline.v

# Run Q2 testbench in command line mode.
vsim -c tb_cordic_pipeline -do "run -all; quit"
