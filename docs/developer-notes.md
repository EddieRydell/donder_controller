# Developer Notes

Donder has one runtime path:

```text
Zynq PS bare-metal app
  -> onboard PS ENET0 + lwIP UDP E1.31 receive
  -> frame assembly in PS memory
  -> M_AXI_GP0 AXI-Lite writes
  -> pl_frame_control control/status
  -> double-buffered axil_frame_ram window
  -> deterministic PL WS281x serializer
```

Ethernet receive, frame assembly, PS-to-PL commit, and WS281x serialization all use the same contract. There are no alternate Python runtime modes for light output.

## Source Layout

Important paths:

| Path | Purpose |
| --- | --- |
| `hw/regs/pl_control.rdl` | SystemRDL source of truth for generated config, register docs, PS headers, Tcl, and RTL packages. |
| `hw/rtl/pl_frame_control.sv` | AXI-Lite control/status and frame commit logic. |
| `hw/rtl/ws281x_frame_consumer.sv` | WS281x frame reader and serializer. |
| `hw/rtl/ws281x_controller_core.v` | Light-controller wrapper. |
| `hw/rtl/axil_frame_ram.v` | PS-writable frame RAM with PL read port. |
| `hw/scripts/build.tcl` | Vivado batch hardware build. |
| `hw/scripts/ps_bd.tcl` | Zynq PS and PL block design wiring. |
| `hw/constraints/pynq_z2.xdc` | PYNQ-Z2 WS281x output constraints. |
| `ps/app/` | Bare-metal controller app. |
| `ps/tools/` | Host-side E1.31 sender, benchmark, and profile tools. |
| `ps/scripts/` | Vitis app creation, JTAG run, PL snapshot, and boot packaging. |
| `Makefile` | Primary workflow entrypoint. |

The repo intentionally does not track vendor PYNQ-Z2 board files. Vivado must discover `tul.com.tw:pynq-z2:part0:1.0` from the user's installed board repository. See [PYNQ-Z2 board files](board-files.md).

## Generated Contract

`hw/regs/pl_control.rdl` owns hardware/software constants such as:

- output count
- max pixels per output
- E1.31 port and first universe
- board, host, netmask, gateway, and MAC defaults
- UART baud
- lwIP profile defaults
- PL address ranges
- register offsets and fields

Regenerate derived files with:

```sh
make regs
```

Check that committed generated files are fresh:

```sh
make regs-check
```

The committed generated outputs include:

- `ps/app/generated/pl_config.h`
- `ps/tools/generated/pl_config.py`
- `hw/scripts/generated/pl_config.tcl`
- `hw/rtl/generated/donder_pl_contract_pkg.sv`
- `hw/rtl/generated/pl_control_regs_pkg.sv`
- `hw/rtl/generated/pl_control_regs.sv`

Local HTML register docs are generated under:

```text
build/docs/regs/pl_control/index.html
```

## Frame Contract

The PS writes only the current `WRITE_BANK`. It commits a completed frame atomically through the control register block. The PL WS281x consumer reads only committed frames from `ACTIVE_BANK`.

Frame storage is output-major:

```text
word 0 = output 0 pixel 0
word 1 = output 0 pixel 1
...
```

Each word is:

```text
0x00RRGGBB
```

The runtime active output count and per-output strand lengths are clamped to synthesized maxima.

## Checks

Use the aggregate check before changing behavior:

```sh
make check
```

It runs:

- `make regs-check`
- `make ssot-check`
- Python compile checks for host scripts
- host-side PS protocol tests
- Vivado RTL syntax checks
- focused WS281x consumer RTL simulation

Individual useful checks:

```sh
make ps-host-test
make rtl-check
make rtl-sim
python -m py_compile ps/tools/e131_send.py ps/tools/e131_benchmark.py ps/tools/e131_ingress_profile.py ps/tools/e131_profile_report.py
```

## Build and Run Targets

```sh
make hw      # build bitstream and XSA
make ps      # build bare-metal controller app
make boot    # package build/sd/BOOT.BIN
make run     # program FPGA and run app over JTAG
make logs    # stream UART telemetry
```

The JTAG wrapper starts `hw_server`, runs XSDB, captures logs under `build/jtag/`, and fails if XSDB output contains common error signatures.

## Profiling

Use `make e131-profile-report` for hardware evidence. It records pass/fail criteria and saves raw artifacts under `build/bench/`.

Use `make bench-e131` or `python ps/tools/e131_benchmark.py` for focused sweeps while developing ingress or frame handoff behavior.
