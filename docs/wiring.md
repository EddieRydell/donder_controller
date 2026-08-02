# Wiring Guide

Dawn exposes `ws281x_data[0]` through `ws281x_data[29]` as 30 parallel WS281x data outputs.

The pins are configured as 3.3 V `LVCMOS33` outputs with drive strength 8 and slow slew in `hw/constraints/pynq_z2.xdc`.

Use level shifting or buffering when the LED hardware requires 5 V data. Keep LED power separate from the board and share ground between the controller signal interface and LED power supply.

## Output Map

| Output | PYNQ-Z2 connector signal | FPGA package pin |
| ---: | --- | --- |
| 0 | Arduino A0-A13 bus bit 0 | `T14` |
| 1 | Arduino A0-A13 bus bit 1 | `U12` |
| 2 | Arduino A0-A13 bus bit 2 | `U13` |
| 3 | Arduino A0-A13 bus bit 3 | `V13` |
| 4 | Arduino A0-A13 bus bit 4 | `V15` |
| 5 | Arduino A0-A13 bus bit 5 | `T15` |
| 6 | Arduino A0-A13 bus bit 6 | `R16` |
| 7 | Arduino A0-A13 bus bit 7 | `U17` |
| 8 | Arduino A0-A13 bus bit 8 | `V17` |
| 9 | Arduino A0-A13 bus bit 9 | `V18` |
| 10 | Arduino A0-A13 bus bit 10 | `F16` |
| 11 | Arduino A0-A13 bus bit 11 | `R17` |
| 12 | Arduino A0-A13 bus bit 12 | `P18` |
| 13 | Arduino A0-A13 bus bit 13 | `N17` |
| 14 | Arduino A0 | `Y11` |
| 15 | Arduino A1 | `Y12` |
| 16 | Arduino A2 | `W11` |
| 17 | Arduino A3 | `V11` |
| 18 | Arduino A4 | `T5` |
| 19 | Arduino A5 | `U10` |
| 20 | Raspberry Pi header signal 6 | `F19` |
| 21 | Raspberry Pi header signal 7 | `V10` |
| 22 | PMOD JB1 | `W14` |
| 23 | PMOD JB2 | `Y14` |
| 24 | PMOD JB3 | `T11` |
| 25 | PMOD JB4 | `T10` |
| 26 | PMOD JB7 | `V16` |
| 27 | PMOD JB8 | `W16` |
| 28 | PMOD JB9 | `V12` |
| 29 | PMOD JB10 | `W13` |

## Frame-to-Output Mapping

E1.31 data is output-major. The first configured pixels drive output 0, the next configured pixels drive output 1, and so on.

For the default boot configuration:

```text
Output 0: pixels 0-112
Output 1: pixels 113-225
...
Output 29: pixels 3277-3389
```

If runtime configuration changes the active output count or strand length, the mapping remains output-major within the active outputs.

## Signal Inversion

The default output inversion mask is generated as `DAWN_PL_DEFAULT_OUTPUT_INVERT_MASK`, currently all 30 outputs inverted. The firmware applies this generated default during startup. Change the value in `hw/regs/pl_control.rdl` and regenerate with `make regs` if the downstream hardware needs non-inverted outputs.
