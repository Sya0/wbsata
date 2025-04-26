`default_nettype none
`timescale	1ns/1ps
module	satatrn_txarb #(
		parameter	LGAFIFO = 4,
		parameter [0:0]	OPT_LOWPOWER = 1'b0
	) (
		// {{{
		input	wire		i_clk, i_reset,
`ifndef	FORMAL
		input	wire		i_phy_clk, i_phy_reset_n,
`endif
		//
		input	wire		i_reg_valid,
		output	wire		o_reg_ready,
		input	wire	[31:0]	i_reg_data,
		input	wire		i_reg_last,
		//
		input	wire		i_txgate,
		//
		input	wire		i_data_valid,
		output	wire		o_data_ready,
		input	wire	[31:0]	i_data_data,
		input	wire		i_data_last,
		//
		output	reg		o_valid,
		input	wire		i_ready,
		output	reg	[31:0]	o_data,
		output	reg		o_last
		// }}}
	);

	// Local declarations
	// {{{
	localparam	FIS_DATA = 8'h46;

	reg		mid_data_packet, mid_reg_packet;
	(* keep *) wire	regfifo_full, regfifo_empty, regfifo_last,regfifo_ready;
	wire	[31:0]	regfifo_data;
	reg		txgate_phy, txgate_xpipe;
`ifdef	FORMAL
	wire		i_phy_clk, i_phy_reset_n;

	assign	i_phy_clk = i_clk;
	assign	i_phy_reset_n = !i_reset;
`endif
	// }}}

	// txgate_phy, txgate_xpipe
	// {{{
	initial	{ txgate_phy, txgate_xpipe } = 0;
	always @(posedge i_phy_clk or negedge i_phy_reset_n)
	if (!i_phy_reset_n)
		{ txgate_phy, txgate_xpipe } <= 0;
	else
		{ txgate_phy, txgate_xpipe } <= { txgate_xpipe, i_txgate };
`ifdef	FORMAL
	always @(posedge i_phy_clk)
	if ({ txgate_phy, txgate_xpipe } != 0 && {txgate_phy, txgate_xpipe } != 2'b11)
	begin
		assume($stable(i_txgate));
	end
`endif
	// }}}

	// Move the FIS data to the PHY clock
	// {{{
`ifdef	FORMAL
	assign	{ regfifo_last, regfifo_data } = { i_reg_last, i_reg_data };
	assign	regfifo_full  = i_reg_valid && !regfifo_ready;
	assign	regfifo_empty = !i_reg_valid;
`else
	sata_afifo #(
		.WIDTH(1+32), .LGFIFO(LGAFIFO)
	) u_reg_afifo (
		.i_wclk(i_clk), .i_wr_reset_n(!i_reset),
		.i_wr(i_reg_valid), .i_wr_data({ i_reg_last, i_reg_data }),
		.o_wr_full(regfifo_full),
		//
		.i_rclk(i_phy_clk), .i_rd_reset_n(i_phy_reset_n),
		.i_rd(regfifo_ready),.o_rd_data({ regfifo_last, regfifo_data }),
		.o_rd_empty(regfifo_empty)
	);
`endif

	assign	o_reg_ready = !regfifo_full;
	// }}}

	// mid_data_packet
	// {{{
	always @(posedge i_phy_clk or negedge i_phy_reset_n)
	if (!i_phy_reset_n)
		mid_data_packet <= 1'b0;
	else if (i_data_valid && o_data_ready)
		mid_data_packet <= !i_data_last;
	else if (!mid_reg_packet && !mid_data_packet && (!o_valid || i_ready)
				&& txgate_phy && i_data_valid)
		mid_data_packet <= 1'b1;
	// }}}

	// mid_reg_packet
	// {{{
	always @(posedge i_phy_clk or negedge i_phy_reset_n)
	if (!i_phy_reset_n)
		mid_reg_packet <= 1'b0;
	else if (!regfifo_empty && regfifo_ready)
		mid_reg_packet <= !regfifo_last;
	// }}}

	// o_valid
	// {{{
	always @(posedge i_phy_clk or negedge i_phy_reset_n)
	if (!i_phy_reset_n)
		o_valid <= 1'b0;
	else if (!o_valid || i_ready)
	begin
		if (mid_reg_packet)
			o_valid <= !regfifo_empty;
		else if (mid_data_packet)
			o_valid <= i_data_valid;
		else if (txgate_phy && i_data_valid)
			o_valid <= 1'b1;
		else if (!regfifo_empty)
			o_valid <= 1'b1;
		else
			o_valid <= 1'b0;
	end
	// }}}

	// o_data, o_last
	// {{{
	always @(posedge i_phy_clk)
	if (!o_valid || i_ready)
	begin
		if (mid_data_packet)
			{ o_last, o_data } <= { i_data_last, i_data_data };
		else if (mid_reg_packet)
			{ o_last, o_data } <= { regfifo_last, regfifo_data };
		else if (txgate_phy && i_data_valid)
			{ o_last, o_data } <= { 1'b0, FIS_DATA, 24'h0 };
		else if (!regfifo_empty || !OPT_LOWPOWER)
			{ o_last, o_data } <= { regfifo_last, regfifo_data };
		else
			{ o_last, o_data } <= 33'h0;
	end
	// }}}

	assign	regfifo_ready  = (!o_valid || i_ready) && (mid_reg_packet
				|| (!mid_data_packet
				&& (!txgate_phy || !i_data_valid)));
	assign	o_data_ready = mid_data_packet && (!o_valid || i_ready);
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
// Formal properties
// {{{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifdef	FORMAL
	reg	f_past_valid;
	reg	[11:0]	fd_word, fr_word, fo_word;
	(* anyconst *) reg	[32:0]	fnvr_data, fnvr_reg;

	initial	f_past_valid = 0;
	always @(posedge i_clk)
		f_past_valid <= 1;

	always @(*)
	if (!f_past_valid)
		assume(i_reset);
	////////////////////////////////////////////////////////////////////////
	//
	// Stream properties
	// {{{
	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
		assume(!i_reg_valid);
	else if ($past(i_reg_valid && !o_reg_ready))
	begin
		assume(i_reg_valid);
		assume($stable(i_reg_data));
		assume($stable(i_reg_last));
	end

	always @(*)
	if (i_reg_valid)
		assume({ i_reg_last, i_reg_data } != fnvr_reg);

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset))
		assume(!i_data_valid);
	else if ($past(i_data_valid && !o_data_ready))
	begin
		assume(i_data_valid);
		assume($stable(i_data_data));
		assume($stable(i_data_last));
	end

	always @(*)
	begin
		assume(fnvr_data != { 1'b0, FIS_DATA, 24'h0 });
		assume(fnvr_data != 33'h0);
	end

	always @(*)
	if (i_data_valid)
		assume({ i_data_last, i_data_data } != fnvr_data);

	always @(posedge i_clk)
	if (!f_past_valid || $past(i_reset) || i_reset)
		assert(!o_valid);
	else if ($past(o_valid && !i_ready))
	begin
		assert(o_valid);
		assert($stable(o_data));
		assert($stable(o_last));
	end

	always @(posedge i_clk)
	if (i_reset)
		fr_word <= 0;
	else if (i_reg_valid && o_reg_ready)
	begin
		fr_word <= fr_word + 1;
		if (i_reg_last)
			fr_word <= 0;
	end

	always @(*)
		assume(fr_word < 12'h08);
	always @(*)
	if (fr_word == 0)
		assume(!i_reg_valid || !i_reg_last);

	always @(posedge i_clk)
	if (i_reset)
		fd_word <= 0;
	else if (i_data_valid && o_data_ready)
	begin
		fd_word <= fd_word + 1;
		if (i_data_last)
			fd_word <= 0;
	end

	always @(*)
		assume(fd_word < 12'hff8);

	always @(posedge i_clk)
	if (i_reset)
		fo_word <= 0;
	else if (o_valid && i_ready)
	begin
		fo_word <= fo_word + 1;
		if (o_last)
			fo_word <= 0;
	end
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Arbiter properties
	// {{{

	always @(*)
	if (!i_reset)
	begin
		if (fr_word > 0)
			assert(mid_reg_packet);
		if (fd_word > 0)
			assert(mid_data_packet);

		assert(!mid_reg_packet || !mid_data_packet);

		if (mid_reg_packet)
		begin
			assert(!o_valid || fr_word > 0);
			assert(fr_word == fo_word + (o_valid ? 1:0));
			assert(!o_valid || !o_last);
			assert(!o_valid || { o_last, o_data } != fnvr_reg);
		end

		if (o_valid && !o_last)
			assert(mid_reg_packet || mid_data_packet);

		if (mid_data_packet)
		begin
			if (fo_word == 0)
			begin
				assert(fd_word == 0);
				assert(o_valid);
				assert(i_data_valid);
				assert({ o_last, o_data } <= { 1'b0, FIS_DATA, 24'h0 });
			end

			assert(fd_word + 1 == fo_word + (o_valid ? 1:0));
			assert(!o_valid || !o_last);
			assert(!o_valid || { o_last, o_data } != fnvr_data);
		end

		if (!mid_data_packet && !mid_reg_packet)
			assert((!o_valid && fo_word == 0) || (o_valid && o_last));
	end

	// always @(posedge i_phy_clk)
	// if (i_phy_reset_n 
	
	// }}}
	////////////////////////////////////////////////////////////////////////
	//
	// Cover properties
	// {{{
	reg	[11:0]	fr_pkts, fd_pkts, fo_pkts;
	always @(posedge i_phy_clk)
	if (!i_phy_reset_n)
	begin
		fr_pkts <= 0;
		fd_pkts <= 0;
		fo_pkts <= 0;
	end else begin
		if (i_reg_valid && o_reg_ready && i_reg_last)
			fr_pkts <= fr_pkts + 1;
		if (i_data_valid && o_data_ready && i_data_last)
			fd_pkts <= fd_pkts + 1;
		if (o_valid && i_ready && o_last)
			fo_pkts <= fo_pkts + 1;
	end

	always @(posedge i_phy_clk)
	if (i_phy_reset_n)
	begin
		cover(fr_pkts > 0 && fo_pkts > 0);
		cover(fd_pkts > 0 && fo_pkts > 0);
		cover(fr_pkts > 1 && fd_pkts > 0 && fo_pkts > 2);
	end
	// }}}
`endif
// }}}
endmodule
