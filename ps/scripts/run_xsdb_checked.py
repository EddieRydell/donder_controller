from __future__ import annotations

import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time


def terminate_process_tree(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return

    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        process.terminate()


def kill_stale_jtag_processes() -> None:
    if os.environ.get("DONDER_CLEAN_JTAG", "1") == "0":
        return

    if os.name == "nt":
        for image in ("xsdb.exe", "hw_server.exe"):
            subprocess.run(
                ["taskkill", "/IM", image, "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )


def wait_for_port(host: str, port: int, timeout_seconds: float) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex((host, port)) == 0:
                return True
        time.sleep(0.2)
    return False


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: run_xsdb_checked.py <xsdb-script> [args...]", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parents[2]
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))
    from ps.tools.generated import pl_config

    xsdb_script = Path(sys.argv[1])
    if not xsdb_script.is_absolute():
        xsdb_script = repo_root / xsdb_script
    xsdb_args = [str(xsdb_script), *sys.argv[2:]]

    xsdb = os.environ.get("XSDB")
    if xsdb is None:
        xsdb = shutil.which("xsdb.bat") or shutil.which("xsdb") or "xsdb"

    log_dir = repo_root / "build" / "jtag"
    log_dir.mkdir(parents=True, exist_ok=True)
    xsdb_log_path = log_dir / "xsdb_run.log"
    hw_log_path = log_dir / "hw_server_xsdb.log"

    kill_stale_jtag_processes()

    hw_server = shutil.which("hw_server.bat") or shutil.which("hw_server")
    hw_process = None
    hw_log = None
    process = None
    if hw_server is not None:
        hw_log = hw_log_path.open("w")
        hw_process = subprocess.Popen(
            [hw_server, f"-sTCP::{pl_config.JTAG_HW_SERVER_PORT}", "-I60"],
            stdout=hw_log,
            stderr=subprocess.STDOUT,
            cwd=log_dir,
        )
        if not wait_for_port("localhost", pl_config.JTAG_HW_SERVER_PORT, 10):
            print(f"ERROR: hw_server did not open TCP port {pl_config.JTAG_HW_SERVER_PORT}", file=sys.stderr)
            return 1

    saw_error = False
    xsdb_log = xsdb_log_path.open("w", encoding="utf-8")
    try:
        process = subprocess.Popen(
            [xsdb, *xsdb_args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=log_dir,
        )

        assert process.stdout is not None
        try:
            for line in process.stdout:
                print(line, end="")
                xsdb_log.write(line)
                xsdb_log.flush()
                lowered = line.lower()
                if (
                    line.startswith("ERROR:")
                    or line.startswith("Traceback ")
                    or "error:" in lowered
                    or "memory read error" in lowered
                    or "memory write error" in lowered
                    or "invoked from within" in lowered
                ):
                    saw_error = True
        except KeyboardInterrupt:
            terminate_process_tree(process)
            return 130

        return_code = process.wait()
        if return_code != 0:
            return return_code
        return 1 if saw_error else 0
    finally:
        xsdb_log.close()
        terminate_process_tree(process)
        terminate_process_tree(hw_process)
        if hw_log is not None:
            hw_log.close()


if __name__ == "__main__":
    raise SystemExit(main())
