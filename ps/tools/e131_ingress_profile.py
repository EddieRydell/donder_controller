#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import math
import os
from pathlib import Path
import subprocess
import sys
import time

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import e131_benchmark as bench
from generated import pl_config


CANDIDATES: dict[str, dict[str, int]] = {
    "current": {
        "DONDER_LWIP_MEM_SIZE": pl_config.LWIP_MEM_SIZE,
        "DONDER_LWIP_PBUF_POOL_SIZE": pl_config.LWIP_PBUF_POOL_SIZE,
        "DONDER_LWIP_RX_DESCRIPTORS": pl_config.LWIP_RX_DESCRIPTORS,
    },
    "pool1024": {"DONDER_LWIP_MEM_SIZE": 524288, "DONDER_LWIP_PBUF_POOL_SIZE": 1024, "DONDER_LWIP_RX_DESCRIPTORS": 256},
    "pool1536": {"DONDER_LWIP_MEM_SIZE": 786432, "DONDER_LWIP_PBUF_POOL_SIZE": 1536, "DONDER_LWIP_RX_DESCRIPTORS": 256},
    "pool2048": {"DONDER_LWIP_MEM_SIZE": 1048576, "DONDER_LWIP_PBUF_POOL_SIZE": 2048, "DONDER_LWIP_RX_DESCRIPTORS": 256},
    "desc512": {"DONDER_LWIP_MEM_SIZE": 1048576, "DONDER_LWIP_PBUF_POOL_SIZE": 2048, "DONDER_LWIP_RX_DESCRIPTORS": 512},
    "coalesce8": {
        "DONDER_LWIP_MEM_SIZE": 1048576,
        "DONDER_LWIP_PBUF_POOL_SIZE": 2048,
        "DONDER_LWIP_RX_DESCRIPTORS": 256,
        "DONDER_LWIP_RX_COALESCE": 8,
    },
}

PROFILE_CELLS = ((300, 60.0), (500, 60.0), (1024, 30.0))
GUARD_CELL = (50, 30.0)

ZERO_DELTA_KEYS = (
    "rx_delta_rx_pbuf_alloc_failures",
    "rx_delta_rx_ring_dropped",
    "rx_delta_e131_rejected",
    "rx_delta_frames_dropped",
    "rx_delta_incomplete_sweeps",
    "rx_delta_sequence_anomalies",
    "rx_delta_pl_dropped",
    "rx_delta_pl_rejected",
    "rx_delta_consumer_errors",
)


def run_build(candidate: str, settings: dict[str, int], out_dir: Path) -> tuple[bool, str]:
    stamp = REPO_ROOT / "build" / "vitis" / ".app-built"
    if stamp.exists():
        stamp.unlink()
    env = {**os.environ, **{key: str(value) for key, value in settings.items()}}
    log_path = out_dir / f"{candidate}_make_ps.log"
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        log.write("# environment\n")
        for key, value in sorted(settings.items()):
            log.write(f"{key}={value}\n")
        log.write("\n# build\n")
        process = subprocess.run(
            ["make", "ps"],
            cwd=REPO_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log.write(process.stdout)
    if process.returncode != 0:
        return False, f"unsupported_build_failed_{process.returncode}"
    return True, f"build_seconds={time.monotonic() - started:.1f}"


def strict_classify(row: dict[str, int | float | str]) -> str:
    target = float(row["target_fps"])
    committed_fps = float(row.get("committed_fps", 0.0))
    errors = sum(int(row.get(key, 0) or 0) for key in ZERO_DELTA_KEYS)
    if errors == 0 and committed_fps >= target * 0.99:
        return "pass"
    return "fail"


def run_cell(
    capture: bench.SerialCapture,
    out_dir: Path,
    candidate: str,
    cell_index: int,
    outputs: int,
    pixels: int,
    rate: float,
    args: argparse.Namespace,
) -> dict[str, int | float | str]:
    cell_name = f"{candidate}_{cell_index:02d}_{outputs}x{pixels}_{rate:g}fps"
    total_pixels = outputs * pixels
    universe_count = math.ceil((total_pixels * 3) / pl_config.E131_SLOTS_PER_UNIVERSE)
    uart_start = len(capture.lines)
    capture.drain_pending()
    print(f"{cell_name}: configure outputs={outputs} pixels={pixels} universes={universe_count}", flush=True)

    bench.run_checked(
        [
            sys.executable,
            "ps/scripts/run_xsdb_checked.py",
            "ps/scripts/run_controller.tcl",
            "--active-outputs",
            str(outputs),
            "--pixels-per-output",
            str(pixels),
        ],
        out_dir / f"{cell_name}_jtag_run.log",
    )
    config_line = capture.wait_for(
        rf"strand_config active_outputs={outputs} .*total_pixels={total_pixels} .*expected_universes={universe_count}",
        20.0,
        start_index=uart_start,
    )
    cell_status_start = max(0, len(capture.lines) - 1)
    before_line = capture.wait_for(r"^e131_status .*rx_packets=0 ", 8.0, start_index=cell_status_start)
    before = bench.parse_kv_line(before_line)
    capture.drain_pending()
    print(f"{cell_name}: send duration={args.duration:g}s target_fps={rate:g}", flush=True)
    sender = bench.run_json(
        [
            sys.executable,
            "ps/tools/e131_send.py",
            "--source-ip",
            args.source_ip,
            "--dest-ip",
            args.dest_ip,
            "--port",
            str(args.port),
            "--outputs",
            str(outputs),
            "--pixels-per-output",
            str(pixels),
            "--duration",
            str(args.duration),
            "--rate",
            str(rate),
            "--json",
        ],
        out_dir / f"{cell_name}_sender.log",
    )
    before_packets = bench.number(before.get("rx_packets"))
    expected_packets = int(before_packets if isinstance(before_packets, int) else 0) + int(sender["packets_sent"])
    after = capture.wait_for_status_counter("rx_packets", expected_packets, 2.5, start_index=cell_status_start)
    snapshot_log = out_dir / f"{cell_name}_jtag_snapshot.log"
    bench.run_checked([sys.executable, "ps/scripts/run_xsdb_checked.py", "ps/scripts/pl_snapshot.tcl"], snapshot_log)

    row: dict[str, int | float | str] = {
        "candidate": candidate,
        "cell": cell_name,
        "configured_line": config_line,
        "outputs": outputs,
        "pixels_per_output": pixels,
        "total_pixels": total_pixels,
        "universe_count": universe_count,
        **sender,
        **bench.diff_status(before, after),
        **{f"after_{key}": value for key, value in bench.numeric_status(after).items()},
        **bench.parse_snapshot_log(snapshot_log),
    }
    row["committed_fps"] = float(row.get("rx_delta_frames_committed", 0) or 0) / float(row.get("actual_duration", 1) or 1)
    row["classification"] = strict_classify(row)
    return row


def write_outputs(out_dir: Path, rows: list[dict[str, int | float | str]]) -> None:
    csv_path = out_dir / "results.csv"
    fieldnames = sorted({key for row in rows for key in row.keys()})
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    with (out_dir / "summary.md").open("w", encoding="utf-8") as f:
        f.write("# Non-DMA E1.31 Ingress Profile\n\n")
        f.write(f"Generated: {dt.datetime.now().isoformat(timespec='seconds')}\n\n")
        f.write("| candidate | cell | committed fps | class | pbuf fail | ring drop | seq | input max | poll max drained | budget hits |\n")
        f.write("| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for row in rows:
            if row.get("classification") == "unsupported":
                f.write(f"| {row['candidate']} | build | 0.00 | unsupported |  |  |  |  |  |  |\n")
                continue
            f.write(
                f"| {row['candidate']} | {row['outputs']}x{row['pixels_per_output']} @ {row['target_fps']} | "
                f"{float(row.get('committed_fps', 0.0)):.2f} | {row['classification']} | "
                f"{row.get('rx_delta_rx_pbuf_alloc_failures', 0)} | {row.get('rx_delta_rx_ring_dropped', 0)} | "
                f"{row.get('rx_delta_sequence_anomalies', 0)} | {row.get('after_rx_input_max_packets', 0)} | "
                f"{row.get('after_rx_poll_max_drained', 0)} | {row.get('rx_delta_rx_poll_budget_hits', 0)} |\n"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Profile non-DMA E1.31 ingress across lwIP candidate settings.")
    parser.add_argument("--source-ip", default=pl_config.HOST_IP_STRING)
    parser.add_argument("--dest-ip", default=pl_config.BOARD_IP_STRING)
    parser.add_argument("--port", type=int, default=pl_config.E131_PORT)
    parser.add_argument("--serial-port", default="")
    parser.add_argument("--baud", type=int, default=pl_config.UART_BAUD)
    parser.add_argument("--duration", type=float, default=20.0)
    parser.add_argument("--outputs", type=int, default=pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT)
    parser.add_argument("--candidates", nargs="*", default=list(CANDIDATES.keys()))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = REPO_ROOT / "build" / "bench" / f"{timestamp}-ingress-profile"
    out_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, int | float | str]] = []

    capture = bench.SerialCapture(args.serial_port, args.baud, out_dir / "uart.log")
    capture.start()
    try:
        guard_done = False
        for candidate in args.candidates:
            if candidate not in CANDIDATES:
                raise SystemExit(f"Unknown candidate: {candidate}")
            ok, note = run_build(candidate, CANDIDATES[candidate], out_dir)
            if not ok:
                rows.append({"candidate": candidate, "classification": "unsupported", "note": note})
                write_outputs(out_dir, rows)
                print(f"{candidate}: {note}", flush=True)
                continue

            cells = []
            if not guard_done:
                cells.append(GUARD_CELL)
                guard_done = True
            cells.extend(PROFILE_CELLS)

            for index, (pixels, rate) in enumerate(cells):
                row = run_cell(capture, out_dir, candidate, index, args.outputs, pixels, rate, args)
                row["build_note"] = note
                rows.append(row)
                write_outputs(out_dir, rows)
                print(
                    f"{row['cell']}: {row['classification']} committed_fps={float(row['committed_fps']):.2f} "
                    f"pbuf={row.get('rx_delta_rx_pbuf_alloc_failures', 0)} "
                    f"ring={row.get('rx_delta_rx_ring_dropped', 0)} seq={row.get('rx_delta_sequence_anomalies', 0)}",
                    flush=True,
                )
    finally:
        capture.stop()

    print(f"wrote {out_dir / 'results.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
