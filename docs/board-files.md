# PYNQ-Z2 Board Files

Donder does not vendor the PYNQ-Z2 Vivado board files. Install the official board files into Vivado before running `make hw`.

The build script expects Vivado to find this board part:

```text
tul.com.tw:pynq-z2:part0:1.0
```

## Install

1. Download the PYNQ-Z2 board files from the official TUL/PYNQ-Z2 product resources.
2. Extract the `pynq-z2` board-file directory.
3. Install it into a Vivado board repository path, such as:

```text
<Vivado install>/data/boards/board_files/
```

or another directory configured through Vivado board repository settings.

4. Confirm Vivado can see the part:

```tcl
get_board_parts -quiet tul.com.tw:pynq-z2:part0:1.0
```

`make hw` fails early with a clear error if the board part is missing.

## Why It Is Not Vendored

The PYNQ-Z2 board files are vendor-provided Vivado metadata: board XML, processing-system presets, pin maps, and an image. They are required by Vivado, but they are not source code owned or maintained by this project.

Keeping them outside the repo avoids license ambiguity, stale copied vendor data, and duplicate checked-in artifacts. Donder keeps only the project-specific constraints and documentation needed for the 30 WS281x outputs.

## Project-Owned Pin Constraints

Donder's output mapping is maintained in:

```text
hw/constraints/pynq_z2.xdc
```

The user-facing output table is in:

```text
docs/wiring.md
```

If the output mapping changes, update the XDC first and then update the wiring guide to match.
