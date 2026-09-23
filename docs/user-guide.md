# Donder Controller User Guide

This guide assumes you are building the controller from source for a PYNQ-Z2 and using a direct Ethernet link from a host computer to the board.

## Hardware

Required:

- PYNQ-Z2 board.
- MicroSD card that can boot the board.
- USB cable for JTAG/UART.
- Ethernet cable from host to PYNQ-Z2.
- 5 V power supply sized for the LED load.
- WS281x-compatible pixels or downstream line drivers.
- Shared ground between the board-side signal interface and LED power supply.

The PYNQ-Z2 PL pins are 3.3 V LVCMOS outputs. Many WS281x installations need level shifting, buffering, fusing, power injection, and careful grounding. The FPGA pins are signal outputs only; do not power LED strips from the board.

## Software Prerequisites

Install and expose these tools on `PATH`:

- Vivado
- Vitis
- Bootgen
- XSDB
- `hw_server`
- Python 3
- `make`
- A C compiler for host tests, exposed as `gcc` or via `HOST_CC=<compiler>`

Install the PYNQ-Z2 board files before `make hw`. The build script requires board part:

```text
tul.com.tw:pynq-z2:part0:1.0
```

See [PYNQ-Z2 board files](board-files.md) for the expected installation model. Donder does not vendor these files in the repo.

Install Python dependencies:

```sh
python -m pip install -r requirements-regs.txt
```

Using a virtual environment is recommended if you do not want PeakRDL and pyserial installed globally.

## Build

Run the normal source build:

```sh
make clean
make check
make hw
make ps
make boot
```

Outputs:

- `build/vivado/donder_controller.xsa`
- `build/vivado/donder_controller.runs/impl_1/donder_system_wrapper.bit`
- `build/sd/BOOT.BIN`

`BOOT.BIN` contains the FSBL, FPGA bitstream, and bare-metal Donder controller app.

## Run Over JTAG

Connect the USB cable and start the controller:

```sh
make run
```

In a second terminal, stream UART telemetry:

```sh
make serial-ports
make logs
```

If auto-detection selects the wrong port, specify it:

```sh
make logs PORT=COMx
```

Expected startup lines include:

```text
donder controller starting
strand_config active_outputs=30 ... total_pixels=3390 ... expected_universes=20
foundation ready source=e131
e131_status link=...
```

## Boot From SD Card

After `make boot`, copy this file to the FAT partition of the PYNQ-Z2 SD card:

```text
build/sd/BOOT.BIN
```

Insert the SD card, set the board for SD boot, power cycle, and use UART logs to confirm startup.

## Network Setup

Use a direct Ethernet link from the host to the PYNQ-Z2.

Configure the host adapter manually:

```text
IP address: 192.168.7.1
Netmask:    255.255.255.0
Gateway:    blank or 0.0.0.0
```

The board listens at:

```text
IP address: 192.168.7.2
UDP port:   5568
```

These defaults are generated from `hw/regs/pl_control.rdl` into `ps/tools/generated/pl_config.py` and `ps/app/generated/pl_config.h`.

## First Light Test

With the controller running and UART logs open, send a generated E1.31 pattern:

```sh
make e131-send
```

Useful direct sender commands:

```sh
python ps/tools/e131_send.py --pattern bars --packet-count 10 --rate 30
python ps/tools/e131_send.py --pattern chase --duration 20 --rate 30
python ps/tools/e131_send.py --outputs 30 --pixels-per-output 113 --pattern white --packet-count 1
```

The sender is transmit-only. Use UART telemetry as the source of truth.

Successful receive should show these counters increasing:

```text
rx_packets
e131_valid
frames_committed
complete_frames
```

Rejected packets increment `e131_rejected`. Common causes are the wrong destination IP, wrong UDP port, wrong first universe, preview packets, malformed packets, or universes outside the configured active frame.

## Generic sACN/E1.31 Show Setup

Configure show software for unicast E1.31/sACN:

```text
Destination IP: 192.168.7.2
UDP port:       5568
First universe: 1
Color order:    RGB
Universe size:  510 channels
```

The controller consumes a linear output-major RGB stream:

```text
Output 0 pixels first, then output 1, then output 2, and so on.
```

For the default `30` outputs by `113` pixels per output:

```text
Pixels:       3390
RGB channels: 10170
Universes:    20
```

For maximum `30` outputs by `1024` pixels per output:

```text
Pixels:       30720
RGB channels: 92160
Universes:    181
```

The PL frame word format is `0x00RRGGBB`. E1.31 input is normal RGB slot order.

## Troubleshooting

Use `make serial-ports` if UART does not open. Close other serial terminals, Vitis consoles, or Vivado terminals if the port is busy.

If `make run` fails to connect, unplug and reconnect USB, close stale Xilinx tools, then rerun. The wrapper starts `hw_server` and writes logs under `build/jtag/`.

If no packets arrive, verify the host adapter IP, destination IP, UDP port, firewall rules, and direct Ethernet cabling.

If packets arrive but frames do not commit, check `e131_rejected`, `last_error`, `last_universe`, and `expected_universes` in UART logs.

If LEDs flicker or show wrong colors, verify shared ground, level shifting, output mapping, color order, strand length, and whether the physical output needs inversion.
