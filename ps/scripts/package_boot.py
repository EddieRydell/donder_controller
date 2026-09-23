#!/usr/bin/env python3
import argparse
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VITIS_WORKSPACE = REPO_ROOT / "build" / "vitis"
BITSTREAM = REPO_ROOT / "build" / "vivado" / "donder_controller.runs" / "impl_1" / "donder_system_wrapper.bit"
BOOT_DIR = REPO_ROOT / "build" / "sd"
BOOT_BIF = BOOT_DIR / "boot.bif"
BOOT_BIN = BOOT_DIR / "BOOT.BIN"


def newest(pattern: str) -> Path:
    candidates = sorted(VITIS_WORKSPACE.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    if not candidates:
        raise RuntimeError(f"No file found under {VITIS_WORKSPACE}: {pattern}")
    return candidates[0]


def resolve_tool(name: str) -> str:
    resolved = shutil.which(name)
    if resolved is not None:
        return resolved
    if not name.lower().endswith((".exe", ".bat", ".cmd")):
        for suffix in (".bat", ".cmd", ".exe"):
            resolved = shutil.which(name + suffix)
            if resolved is not None:
                return resolved
    return name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bootgen", default="bootgen")
    args = parser.parse_args()

    fsbl = newest("*/donder_platform/zynq_fsbl/build/fsbl.elf")
    app = newest("*/donder_controller/build/donder_controller.elf")

    if not BITSTREAM.exists():
        raise RuntimeError(f"Missing bitstream: {BITSTREAM}")

    BOOT_DIR.mkdir(parents=True, exist_ok=True)
    BOOT_BIF.write_text(
        "the_ROM_image:\n"
        "{\n"
        f"  [bootloader] {fsbl.as_posix()}\n"
        f"  {BITSTREAM.as_posix()}\n"
        f"  {app.as_posix()}\n"
        "}\n",
        encoding="utf-8",
    )

    command = [
        resolve_tool(args.bootgen),
        "-arch",
        "zynq",
        "-image",
        str(BOOT_BIF),
        "-w",
        "-o",
        str(BOOT_BIN),
    ]
    print(" ".join(command), flush=True)
    subprocess.check_call(command, cwd=BOOT_DIR)

    if not BOOT_BIN.exists():
        raise RuntimeError(f"Missing BOOT.BIN: {BOOT_BIN}")

    print(f"created {BOOT_BIN}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
