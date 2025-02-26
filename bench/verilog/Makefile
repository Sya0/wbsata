# Makefile

# Compiler and simulator commands
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Testbench and source files
SRCS = mdl_oob.v mdl_alignp_transmit.v sata_model.v mdl_srxcomsigs.v mdl_scomfsm.v
OUT = sata_model.out
VCD = waveform.vcd

# Default rule, compile and simulate
all: compile simulate

# Compile the Verilog files
compile:
	$(IVERILOG) -o $(OUT) $(SRCS)

# Run the simulation
simulate: compile
	$(VVP) $(OUT)

# Open GTKWave to view the waveform
view: simulate
	$(GTKWAVE) $(VCD) &

# Clean up generated files
clean:
	rm -f $(OUT) $(VCD) *.vcd

