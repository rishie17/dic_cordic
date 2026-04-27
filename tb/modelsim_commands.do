vlib work
vlog cordic_rotation.v cordic_vectoring.v tb_cordic_q1.v
vsim -c tb_cordic_q1 -do "run -all; quit"
vlog cordic_pipeline.v tb_cordic_pipeline.v
vsim -c tb_cordic_pipeline -do "run -all; quit"
