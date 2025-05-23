################################################################################
##
## Filename:	bench/cpp/Makefile
## {{{
## Project:	SATA controller
##
## Purpose:	Build the verilator simulation environment for the SATA controller
##
## Creator:	Sukru Uzun
##
################################################################################
## }}}
## Copyright (C) 2023-2025
## {{{
## This program is free software (firmware): you can redistribute it and/or
## modify it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
## for more details.
##
## You should have received a copy of the GNU General Public License along
## with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
## target there if the PDF file isn't present.)  If not, see
## <http://www.gnu.org/licenses/> for a copy.
## }}}
## License:	GPL, v3, as defined and found on www.gnu.org,
## {{{
##		http://www.gnu.org/licenses/gpl.html
##
################################################################################
##
## }}}
.PHONY: all
all: tb_sata

CXX := g++
OBJDIR := obj-pc
VTLD := ../../bench/verilog
CPPD := .
RTLD := ../../rtl
VERILATOR_ROOT := $(HOME)/Downloads/oss-cad-suite
VERILATOR_INCLUDE := $(HOME)/Downloads/oss-cad-suite/share/verilator/include

# Verilator setup
ifeq ($(VERILATOR_ROOT),)
VERILATOR := verilator
VERILATOR_ROOT ?= $(shell bash -c '$(VERILATOR) -V|grep VERILATOR_ROOT | head -1 | sed -e " s/^.*=\s*//"')
else
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

# Ensure VERILATOR_ROOT is defined
ifeq ($(VERILATOR_ROOT),)
$(error VERILATOR_ROOT is not set. Please install Verilator or set VERILATOR_ROOT)
endif

# C++ compiler flags
CFLAGS := -Wall -O2 -g -std=c++14
INCS   := -I$(OBJDIR) -I$(VERILATOR_INCLUDE) -I. -I$(CPPD)
LIBS   := -lz

# Source files
SOURCES := tb_sata.cpp satasim.cpp memsim.cpp

# Add verilator infrastructure sources
VROOT := $(VERILATOR_ROOT)
VINCS := -I$(VROOT)/include
VOBJS := $(OBJDIR)/verilated.o $(OBJDIR)/verilated_vcd_c.o $(OBJDIR)/verilated_threads.o

# Check if include directory exists
ifeq ($(wildcard $(VERILATOR_INCLUDE)/verilated.cpp),)
$(error Verilator include files not found at $(VERILATOR_INCLUDE))
endif

# Verilator objects
$(OBJDIR)/%.o: $(VERILATOR_INCLUDE)/%.cpp | $(OBJDIR)
	$(CXX) $(CFLAGS) $(VINCS) -c $< -o $@

# Explicit rules for verilator objects
$(OBJDIR)/verilated.o: $(VERILATOR_INCLUDE)/verilated.cpp | $(OBJDIR)
	$(CXX) $(CFLAGS) $(VINCS) -c $< -o $@

$(OBJDIR)/verilated_vcd_c.o: $(VERILATOR_INCLUDE)/verilated_vcd_c.cpp | $(OBJDIR)
	$(CXX) $(CFLAGS) $(VINCS) -c $< -o $@

$(OBJDIR)/verilated_threads.o: $(VERILATOR_INCLUDE)/verilated_threads.cpp | $(OBJDIR)
	$(CXX) $(CFLAGS) $(VINCS) -c $< -o $@

# Build the testbench executable
tb_sata: $(OBJDIR) $(VOBJS) verilate $(SOURCES)
	$(CXX) $(CFLAGS) $(INCS) $(SOURCES) $(VOBJS) $(OBJDIR)/Vsata_controller__ALL.a $(LIBS) -o $@

## Create output directory if it doesn't exist
$(OBJDIR):
	mkdir -p $(OBJDIR)

## Verilate the sata_controller.v module
## {{{
.PHONY: verilate
verilate: $(OBJDIR)
	@echo "Verilating sata_controller.v and its dependencies..."
	$(VERILATOR) -Wall -cc -DVERILATOR \
		-I$(RTLD) \
		-y $(RTLD) \
		--Wno-fatal \
		--trace \
		$(RTLD)/sata_controller.v \
		-Mdir $(OBJDIR) --top-module sata_controller
	cd $(OBJDIR) && make -f Vsata_controller.mk
	@echo "Verilator model generation completed."
## }}}

## Clean
## {{{
.PHONY: clean
clean:
	rm -rf $(OBJDIR)/ tb_sata *.vcd
## }}}

## Create test disk image
## {{{
sata.img:
	dd if=/dev/zero of=sata.img bs=1M count=128
	@echo "Created empty 128MB disk image: sata.img"
## }}}

## Run the test
## {{{
.PHONY: run
run: tb_sata sata.img
	./tb_sata
## }}}

# Debug target to show build variables
.PHONY: debug
debug:
	@echo "============= Build Environment ============="
	@echo "VERILATOR_ROOT: $(VERILATOR_ROOT)"
	@echo "VERILATOR: $(VERILATOR)"
	@echo "VERILATOR_INCLUDE: $(VERILATOR_INCLUDE)"
	@echo "RTLD: $(RTLD)"
	@echo "OBJDIR: $(OBJDIR)"
	@echo "============= File Checks ============="
	@echo "sata_controller.v exists: $$(test -f $(RTLD)/sata_controller.v && echo Yes || echo No)"
	@echo "verilated.cpp exists: $$(test -f $(VERILATOR_INCLUDE)/verilated.cpp && echo Yes || echo No)"
	@echo "verilated_vcd_c.cpp exists: $$(test -f $(VERILATOR_INCLUDE)/verilated_vcd_c.cpp && echo Yes || echo No)"
	@echo "obj-pc directory exists: $$(test -d $(OBJDIR) && echo Yes || echo No)"
	@echo "============= Build Commands ============="
	@echo "CXX: $(CXX)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "INCS: $(INCS)"
	@echo "============= Source Files ============="
	@echo "SOURCES: $(SOURCES)"
