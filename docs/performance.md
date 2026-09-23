# Performance Guide

Donder includes hardware-in-the-loop profiling so performance claims can be tied to repeatable runs and saved artifacts.

The useful headline is not just raw packet rate. For WS281x, the output protocol has a hard frame-time limit:

```text
max_fps = 1,000,000 / ((pixels_per_output * 30) + 50)
```

That assumes 1250 ns per WS281x bit, 24 bits per RGB pixel, and a 50 us reset/latch interval. Because Donder drives 30 outputs in parallel, protocol time depends on pixels per output, not total pixel count.

## Profile Report

Run the full repeatable report:

```sh
make e131-profile-report
```

Use explicit UART and longer cells when collecting resume-worthy results:

```sh
make e131-profile-report SERIAL_PORT=COMx E131_PROFILE_DURATION=20
```

The target writes:

```text
E131_PROFILE_RESULTS.md
build/bench/<timestamp>-e131-profile-report/
build/bench/<timestamp>-ingress-profile/
build/bench/<timestamp>/
```

The report includes:

- Host-side protocol tests.
- Python compile checks.
- Non-DMA ingress profile across lwIP candidate settings.
- A `30x500` ceiling sweep using repo-default lwIP settings.
- WS281x protocol-limit calculations.
- Links to raw CSV, UART, sender, JTAG run, and snapshot logs.

## Benchmark Matrix

`make bench-e131` runs `python ps/tools/e131_benchmark.py`.

Default matrix:

| Pixels per output | Target FPS |
| ---: | --- |
| 50 | 30, 60, 120, 240, 480 |
| 100 | 30, 60, 120, 240, 360 |
| 300 | 30, 60, 90, 110, 130 |
| 500 | 30, 50, 60, 70, 90 |
| 750 | 20, 30, 40, 50 |
| 1024 | 20, 25, 30, 35, 40 |

Useful focused runs:

```sh
python ps/tools/e131_benchmark.py --skip-build --sanity-only
python ps/tools/e131_benchmark.py --skip-build --pixels 300 --rates 60
python ps/tools/e131_benchmark.py --skip-build --pixels 500 --rates 61 62 63 64 65
```

Use `--skip-build` only when the app is already built.

## Pass Criteria

The profile report treats a cell as passing when committed FPS is at least 99% of target and these counters stay at zero during the cell:

- pbuf allocation failures
- RX ring drops
- E1.31 rejects
- sequence anomalies
- PL drops or rejects
- consumer errors

For a resume or project summary, cite a specific report artifact and state the tested cell, for example:

```text
30 outputs x 500 pixels/output stable at 60 FPS, with the next ceiling sweep showing the WS281x protocol limit near 64-65 FPS.
```

Only make that exact claim after the local `E131_PROFILE_RESULTS.md` from the current hardware run supports it.

## Protocol Reference Points

The report generator calculates these from the WS281x timing formula:

| Pixels per output | Protocol max FPS | Notes |
| ---: | ---: | --- |
| 300 | 110.50 | 60 FPS should have substantial protocol margin. |
| 500 | 66.45 | 60 FPS has margin; 64-65 FPS is near the hard limit. |
| 1024 | 32.54 | 30 FPS is near the hard limit. |

If a target is at or below the protocol limit and the report still shows drops, rejects, sequence anomalies, or low committed FPS, investigate controller ingress, PS writes, or PL handoff. If a target is above the protocol limit, failure is expected even when the controller is healthy.

## Artifacts

Each benchmark run writes:

- `results.csv`
- `summary.md`
- `uart.log`
- per-cell sender logs
- JTAG run logs
- JTAG snapshot logs

Keep the generated report and raw artifacts together when using results as evidence.
