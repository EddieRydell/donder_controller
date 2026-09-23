#!/usr/bin/env python3
from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RDL = REPO_ROOT / "hw" / "regs" / "pl_control.rdl"
PS_CONFIG_HEADER = REPO_ROOT / "ps" / "app" / "generated" / "pl_config.h"
PY_CONFIG = REPO_ROOT / "ps" / "tools" / "generated" / "pl_config.py"
TCL_CONFIG = REPO_ROOT / "hw" / "scripts" / "generated" / "pl_config.tcl"

CONTRACT_SOURCE_PATHS = {
    "hw/regs/pl_control.rdl",
    "hw/regs/generate_regs.py",
    "hw/regs/ssot_check.py",
    "ps/app/pl_control.h",
    "ps/app/generated/pl_config.h",
    "ps/tools/generated/pl_config.py",
    "hw/scripts/generated/pl_config.tcl",
}

ALLOWED_PREFIXES = (
    "hw/rtl/generated/",
    "build/",
)

# These values are intentionally exploratory matrices rather than production
# defaults. Keep the exemption path-based so copied defaults elsewhere fail.
BENCHMARK_MATRIX_PATHS = {
    "ps/tools/e131_benchmark.py",
    "ps/tools/e131_ingress_profile.py",
    "ps/tools/e131_profile_report.py",
    "README.md",
}

CONTRACT_NAME_RE = re.compile(
    r"(?:DEFAULT|BASEADDR|PACKET|BAUD|PORT|JTAG|IP|MAC|LWIP|RING_DEPTH|"
    r"OUTPUT_COUNT|PIXELS_PER_OUTPUT|SLOTS_PER_UNIVERSE|BLACKOUT_TIMEOUT|SYNC_ADDRESS)"
)
STRICT_CONTRACT_NAME_RE = re.compile(
    r"(?:DEFAULT|BASEADDR|E131_PORT|UART_BAUD|JTAG_HW_SERVER_PORT|RX_PACKET_RING_DEPTH|"
    r"E131_MAX_PACKET_BYTES|LWIP|BOARD_IP|HOST_IP|NETMASK_IP|GATEWAY_IP|MAC[0-5])"
)
NUMERIC_LITERAL_RE = re.compile(r"(?<![A-Za-z0-9_])(?:0x[0-9a-fA-F]+|\d+)(?:u|U)?(?![A-Za-z0-9_])")
RDL_DEFINE_RE = re.compile(r"`define\s+([A-Z0-9_]+)\s+(.+)$")
C_DEFINE_RE = re.compile(r"#\s*define\s+DONDER_PL_([A-Z0-9_]+)\s+((?:0x[0-9a-fA-F]+|\d+)(?:u|U)?)\b")
PY_ASSIGN_RE = re.compile(r"^([A-Z][A-Z0-9_]*)\s*=\s*(0x[0-9a-fA-F]+|\d+)\b")
TCL_SET_RE = re.compile(r"^set\s+donder_pl_([a-z0-9_]+)\s+(0x[0-9a-fA-F]+|\d+)\b")
SOURCED_FROM_GENERATED_RE = re.compile(r"\b(?:DONDER_PL_[A-Z0-9_]+|pl_config\.[A-Z0-9_]+|donder_pl_contract_pkg::[A-Z0-9_]+|\$donder_pl_[a-z0-9_]+)\b")
SUSPICIOUS_DEFAULT_RE = re.compile(
    r"(?:env_int\([^,\n]+,\s*(?:0x[0-9a-fA-F]+|\d+)|"
    r"add_argument\(\"--(?:source-ip|dest-ip|port|first-universe|outputs|pixels-per-output|baud)\"[^\n]*default=(?:\"[^\"]+\"|0x[0-9a-fA-F]+|\d+)|"
    r"#\s*define\s+(?:[A-Z0-9_]*DEFAULT[A-Z0-9_]*|[A-Z0-9_]*BASEADDR|[A-Z0-9_]*(?:MAX_PACKET_BYTES|RING_DEPTH|BAUD|PORT|JTAG|IP|MAC|LWIP)[A-Z0-9_]*)\s+(?:0x[0-9a-fA-F]+|\d+))"
)
LEGACY_HARDWARE_NAMES = (
    "ETH_CONTROL_CORE",
    "XPAR_ETH_CONTROL_CORE",
)


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [path for line in result.stdout.splitlines() if line and (path := REPO_ROOT / line).exists()]


def rel_path(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def is_allowed_path(path: Path) -> bool:
    rel = rel_path(path)
    return rel in CONTRACT_SOURCE_PATHS or any(rel.startswith(prefix) for prefix in ALLOWED_PREFIXES)


def is_benchmark_matrix_path(path: Path) -> bool:
    return rel_path(path) in BENCHMARK_MATRIX_PATHS


def text_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return []


def parse_int(text: str) -> int | None:
    cleaned = text.strip().rstrip("uU")
    try:
        return int(cleaned, 0)
    except ValueError:
        return None


def parse_rdl_defines() -> dict[str, int]:
    config: dict[str, int] = {}
    for line in text_lines(RDL):
        match = RDL_DEFINE_RE.match(line.strip())
        if not match:
            continue
        name, value = match.groups()
        value = value.strip()
        if value.startswith("32'h"):
            parsed = int(value[4:], 16)
        elif re.fullmatch(r"\d+", value):
            parsed = int(value)
        else:
            continue
        config[name] = parsed
    return config


def parse_c_config() -> dict[str, int]:
    config: dict[str, int] = {}
    for line in text_lines(PS_CONFIG_HEADER):
        match = C_DEFINE_RE.match(line.strip())
        if match:
            parsed = parse_int(match.group(2))
            if parsed is not None:
                config[match.group(1)] = parsed
    return config


def parse_py_config() -> dict[str, int]:
    config: dict[str, int] = {}
    for line in text_lines(PY_CONFIG):
        match = PY_ASSIGN_RE.match(line.strip())
        if match:
            parsed = parse_int(match.group(2))
            if parsed is not None:
                config[match.group(1)] = parsed
    return config


def parse_tcl_config() -> dict[str, int]:
    config: dict[str, int] = {}
    for line in text_lines(TCL_CONFIG):
        match = TCL_SET_RE.match(line.strip())
        if match:
            parsed = parse_int(match.group(2))
            if parsed is not None:
                config[match.group(1).upper()] = parsed
    return config


def load_generated_contract(findings: list[str]) -> dict[str, int]:
    rdl = parse_rdl_defines()
    c_config = parse_c_config()
    py_config = parse_py_config()
    tcl_config = parse_tcl_config()
    generated_names = set(c_config) | set(py_config) | set(tcl_config)

    for name in sorted(generated_names):
        values = {
            "C": c_config.get(name),
            "Python": py_config.get(name),
            "Tcl": tcl_config.get(name),
        }
        present = {source: value for source, value in values.items() if value is not None}
        if len(present) != 3:
            findings.append(f"generated config missing {name}: {present}")
            continue
        if len(set(present.values())) != 1:
            findings.append(f"generated config mismatch for {name}: {present}")
        if name in rdl and rdl[name] != next(iter(present.values())):
            findings.append(f"generated config {name}={next(iter(present.values()))} does not match RDL {rdl[name]}")

    return py_config


def extract_candidate_dict_line(line: str) -> dict[str, int] | None:
    if "DONDER_LWIP_" not in line or "{" not in line:
        return None
    try:
        candidate = ast.literal_eval(line[line.index("{"):].rstrip(","))
    except (SyntaxError, ValueError):
        return None
    if not isinstance(candidate, dict):
        return None
    parsed: dict[str, int] = {}
    for key, value in candidate.items():
        if isinstance(key, str) and key.startswith("DONDER_LWIP_") and isinstance(value, int):
            parsed[key] = value
    return parsed if parsed else None


def line_uses_generated_config(line: str) -> bool:
    return bool(SOURCED_FROM_GENERATED_RE.search(line))


def line_has_contract_name(line: str) -> bool:
    return bool(CONTRACT_NAME_RE.search(line))


def line_has_strict_contract_name(line: str) -> bool:
    return bool(STRICT_CONTRACT_NAME_RE.search(line))


def scan_for_violations(path: Path, contract: dict[str, int]) -> list[str]:
    findings: list[str] = []
    rel = rel_path(path)
    value_to_names: dict[int, set[str]] = {}
    for name, value in contract.items():
        if line_has_strict_contract_name(name):
            value_to_names.setdefault(value, set()).add(name)

    for line_no, line in enumerate(text_lines(path), start=1):
        stripped = line.strip()
        for legacy in LEGACY_HARDWARE_NAMES:
            if legacy in line:
                findings.append(f"{rel}:{line_no}: legacy hardware name {legacy}: {stripped}")

        if line_uses_generated_config(line):
            continue

        if is_benchmark_matrix_path(path):
            if rel == "ps/tools/e131_ingress_profile.py" and "DONDER_LWIP_" in line:
                continue
            if extract_candidate_dict_line(stripped) is not None:
                continue
            if re.search(r"\bMATRIX\b|\bPROFILE_CELLS\b|\bGUARD_CELL\b|ceiling-rates", line):
                continue

        if SUSPICIOUS_DEFAULT_RE.search(line):
            findings.append(f"{rel}:{line_no}: local default/fallback must use generated config: {stripped}")
            continue

        if not line_has_strict_contract_name(line):
            continue

        for match in NUMERIC_LITERAL_RE.finditer(line):
            parsed = parse_int(match.group(0))
            if parsed is None or parsed <= 16 or parsed not in value_to_names:
                continue
            names = ", ".join(sorted(value_to_names[parsed])[:6])
            findings.append(f"{rel}:{line_no}: contract value {parsed} duplicated for {names}: {stripped}")
            break

    return findings


def main() -> int:
    findings: list[str] = []
    contract = load_generated_contract(findings)

    for path in tracked_files():
        if is_allowed_path(path):
            continue
        findings.extend(scan_for_violations(path, contract))

    if findings:
        print("SSOT contract check failed:", file=sys.stderr)
        for finding in findings:
            print(f"  {finding}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
