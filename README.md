## Wishbone SATA Host Controller

Several projects of mine require a WB SATA controller.  The [10Gb Ethernet
switch](https://github.com/ZipCPU/eth10g) project is an example of one of these
projects.  This repository is intended to be a common IP repository shared by
those projects, and encapsulating the test bench(es) specific to the SATA
controller.

A couple quick features of this controller:

1. Since the [ZipCPU](https://github.com/ZipCPU/zipcpu) that will control
   this IP is big-endian, this controller will need to handle both
   little-endian commands (per spec) and big-endian data.

   There will be an option to be make the IP fully little-endian.

2. My initial goal will be Gen1 (1500Mb/s) compliance.  Later versions may
   move on to Gen2 or Gen3 compliance.

## Hardware

I have two test setups presently.

1. The first is an [Enclustra
   Mercury+ST1](https://www.enclustra.com/en/products/base-boards/mercury-st1/)
   board with an [Enclustra Kintex-7
   160T](https://www.enclustra.com/en/products/fpga-modules/mercury-kx2/)
   daughter board, connected to an
   [Ospero FPGA Drive FMC](https://opsero.com/product/fpga-drive-fmc-dual/).
   My [Kimos](https://github.com/ZipCPU/kimos) project uses this hardware, and
   so I have plans to integrate the WBSATA project into it for testing.  Sadly,
   the [Ospero FPGA Drive
   FMC](https://opsero.com/product/fpga-drive-fmc-dual/) only contains a 100MHz
   reference, whereas SATA on a Series-7 Xilinx device requires either a 150MHz
   or a 200MHz reference.  While the Enclustra board does offer a 200MHz
   reference, I've been using it for other purposes, and Xilinx won't let me
   distribute it via BUFG's to get it to the SATA controller.  This is currently
   requiring a bit of a redesign of my [Kimos](https://github.com/ZipCPU/kimos)
   project.

2. My second test hardware is the [KlusterLab, also known as my 10Gb Ethernet
   switch](https://github.com/ZipCPU/eth10g).  This is currently the board
   I am moving towards testing with.

## Status

While fully funded, this project continues to be a
[work in progress](doc/prjstatus.png).  It is now fully drafted, and ready
for hardware testing.

1. Simulation tests that include out of band signaling now pass.

2. Initial, but very limited, simulation tests that interact with hardware
   also pass.

3. The project is currently being tested as part of the [10Gb Ethernet
   project](https://github.com/ZipCPU/eth10g/tree/sata).  As part of testing,
   three compressed [Wishbone scope](https://github.com/ZipCPU/wbscope)s have
   been fitted to it.

The design (at present) is currently limited to 1500Mb/s, and requires a 150MHz
reference oscillator.  Work integrating this design into my [Kimos
project](https://github.com/ZipCPU/kimos) will require that it can be built
with a 200MHz reference oscillator.  That work remains ongoing, as (apparently)
the reference oscillator cannot be driven from a BUFG.

I'll update these notes further as more development takes place.

## License

The project is currently licensed under GPLv3.

