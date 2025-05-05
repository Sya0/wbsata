////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bench/cpp/tb_sata.cpp
// {{{
// Project:	A Wishbone SATA controller
//
// Purpose:	Exercise all of the functionality contained within the Verilog
//		core, from bring up through read to write and read-back.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2025, Gisselquist Technology, LLC
// {{{
// This file is part of the WBSATA project.
//
// The WBSATA project is a free software (firmware) project: you may
// redistribute it and/or modify it under the terms of  the GNU General Public
// License as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  If not, please see <http://www.gnu.org/licenses/> for a
// copy.
// }}}
// License:	GPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/gpl.html
//
////////////////////////////////////////////////////////////////////////////////
//
// }}}
// Include files
// {{{
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <Vsata_controller.h>
#include "testb.h"
#include "wb_tb.h"
#include "satasim.h"
// }}}

// MACRO definitions
// {{{
#define	SATA_CMD_ADDR	0
#define	SATA_LBALO_ADDR	1
#define	SATA_LBAHI_ADDR	2
#define	SATA_COUNT_ADDR	3
#define	SATA_PHY_ADDR	5
#define	SATA_DMA_ADDR	6
// }}}

class	SATA_TB : public WB_TB<Vsata_controller> {
	SATASIM	*m_sata;
public:

	SATA_TB(const char *filesystem_image) {
		// {{{
		if (0 != access(filesystem_image, R_OK)) {
			fprintf(stderr, "Cannoot open %s for reading\n", filesystem_image);
			exit(EXIT_FAILURE);
		} if (0 != access(filesystem_image, W_OK)) {
			fprintf(stderr, "Cannot open %s for writing\n", filesystem_image);
			exit(EXIT_FAILURE);
		}

		m_sata = new SATASIM(void);
		m_sata->load(filesystem_image);
		// }}}
	}

	virtual	void	tick(void) {
		// {{{
		TESTB<Vsata_controller>::tick();

		// FIXME!  Need to call some function of m_sata that takes
		//	the ports of the sata_phy, and returns values such as
		//	the sata_phy might return ....
		// core()->i_something = (*m_sata)( ... );
		//
		// Eventually, we might need a tick() function for each of the
		// three clock domains: RX, TX, and WB.
		//
		// }}}
	}

	Vsata_controller *core(void) {
		return m_core;
	}

	void	wait_while_busy(void) {
		// {{{
		// Simply call tick() until we get an interrupt
		while(!core()->o_int)
			tick();
		// }}}
	}

};

int	main(int argc, char **argv) {
	const char	IMG_FILENAME[] = "sdcard.img";
	const char	VCD_FILENAME[] = "trace.vcd";
	SATA_TB	tb(IMG_FILENAME);

	tb.opentrace(VCD_FILENAME);

	// Consider issuing a reset command here.

	//
	// DMA Write
	printf("Issue DMA Write\n");
	tb.dma_write(some_parameters);
	//
	// DMA Read
	printf("Issue DMA Read\n");
	tb.dma_read(some_parameters);
	//
	// Verify read data equals written data.

	if (!failed)
		printf("SUCCESS!\n");
}
