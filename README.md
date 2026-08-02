# Dawn Controller

Dawn Controller is a PYNQ-Z2 E1.31/sACN to WS281x light-show controller. It receives E1.31 over the board Ethernet port, assembles complete RGB frames on the Zynq PS, commits them into PL frame RAM, and drives 30 parallel WS281x outputs.

## Capabilities

- PYNQ-Z2 target using the onboard Zynq PS Ethernet MAC and PL fabric.
- 30 parallel WS281x data outputs.
- 800 kHz WS281x serialization with one RGB word per pixel.
- Runtime strand sizing up to 1024 pixels per output.
- E1.31/sACN UDP input with static direct-link networking.
- Repeatable host, RTL, and hardware throughput tests.
- SD-card `BOOT.BIN` packaging with FSBL, bitstream, and bare-metal app.

Default generated configuration:

| Setting | Value |
| --- | ---: |
| Board IP | `192.168.7.2` |
| Host/test IP | `192.168.7.1` |
| Netmask | `255.255.255.0` |
| E1.31 UDP port | `5568` |
| First universe | `1` |
| Active outputs at boot | `30` |
| Pixels per output at boot | `113` |
| Max pixels per output | `1024` |
| UART baud | `115200` |

These values are generated from `hw/regs/pl_control.rdl`. Do not edit generated files directly.

## Documentation

- [User guide](docs/user-guide.md): prerequisites, build, run, SD deployment, network setup, and first light.
- [Board-file setup](docs/board-files.md): installing the official PYNQ-Z2 Vivado board files.
- [Wiring guide](docs/wiring.md): the 30 WS281x output pins and connector names.
- [Performance guide](docs/performance.md): benchmark matrix, report generation, and WS281x protocol-limit analysis.
- [Developer notes](docs/developer-notes.md): architecture, generated register contract, tests, and source layout.

## Build From Source

Run from a shell where Vivado, Vitis, Bootgen, XSDB, and `hw_server` are on `PATH`. Install the official PYNQ-Z2 board files before building; the Vivado script requires board part `tul.com.tw:pynq-z2:part0:1.0`. See [Board-file setup](docs/board-files.md).

Use a virtual environment if you do not want the Python dependencies installed globally.

```sh
python -m pip install -r requirements-regs.txt
make clean
make check
make hw
make ps
make boot
```

The deployable boot image is:

```text
build/sd/BOOT.BIN
```

Copy `BOOT.BIN` to the FAT partition of the PYNQ-Z2 SD card to boot without JTAG.

## JTAG Bring-Up

Build hardware and software first, then program and run the controller over JTAG:

```sh
make run
```

Stream UART telemetry in another terminal:

```sh
make logs
```

The app prints `dawn controller starting`, the generated network and strand configuration, then one `e131_status ...` line per second.
`make logs` should automatically discover ports. Use `make serial-ports` and `make logs PORT=COMx` if automatic port discovery fails.

## Network Setup

Connect the host Ethernet adapter directly to the PYNQ-Z2 Ethernet port and configure the host adapter manually:

```text
Host IP:   192.168.7.1
Netmask:   255.255.255.0
Gateway:   blank or 0.0.0.0
Board IP:  192.168.7.2
UDP port:  5568
```

Send a test pattern from the host:

```sh
make e131-send
python ps/tools/e131_send.py --pattern bars --packet-count 10 --rate 30
```

A successful test increments `rx_packets`, `e131_valid`, and `frames_committed` in UART telemetry. Packets outside the configured universe range increment `e131_rejected` and do not commit a frame.

## E1.31 Layout

Dawn accepts RGB data starting at universe `1`. Each E1.31 data slot stream is interpreted as one linear output-major frame:

```text
output 0 pixel 0 RGB
output 0 pixel 1 RGB
...
output 1 pixel 0 RGB
output 1 pixel 1 RGB
...
```

The frame word format inside PL frame RAM is `0x00RRGGBB`. E1.31 packets use 510 RGB data slots per universe, so a 30-output by 113-pixel frame uses 3390 pixels, 10170 RGB slots, and 20 universes.

## Performance

Use the hardware profile flow to profile capability:

```sh
make e131-profile-report
make e131-profile-report E131_PROFILE_DURATION=20 SERIAL_PORT=COMx
```

This writes `E131_PROFILE_RESULTS.md` and links to raw artifacts under `build/bench/`. The report includes pass/fail criteria, observed packet rates, and WS281x protocol-limit calculations.

## Common Commands

```sh
make help                 # list supported targets
make regs                 # regenerate SystemRDL-derived artifacts
make regs-check           # fail if generated artifacts are stale
make check                # run generated, host, RTL syntax, and RTL sim checks
make hw                   # build Vivado bitstream and XSA
make ps                   # build bare-metal controller app
make boot                 # package build/sd/BOOT.BIN
make run                  # program FPGA and run app over JTAG
make logs PORT=COMx       # stream UART telemetry
make e131-send            # send deterministic E1.31 test data
make bench-e131           # run the throughput benchmark
make e131-profile-report  # run repeatable profile and write Markdown report
make clean                # remove generated build output and root log clutter
```
