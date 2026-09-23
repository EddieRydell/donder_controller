import argparse
import filecmp
import re
import shutil
import subprocess
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path

from systemrdl import RDLCompiler
from systemrdl.node import AddrmapNode, MemNode, RegNode


REPO_ROOT = Path(__file__).resolve().parents[2]
RDL = REPO_ROOT / "hw" / "regs" / "pl_control.rdl"
PS_HEADER = REPO_ROOT / "ps" / "app" / "pl_control.h"
PS_CONFIG_HEADER = REPO_ROOT / "ps" / "app" / "generated" / "pl_config.h"
PY_CONFIG = REPO_ROOT / "ps" / "tools" / "generated" / "pl_config.py"
RTL_DIR = REPO_ROOT / "hw" / "rtl" / "generated"
RTL_CONFIG = RTL_DIR / "donder_pl_contract_pkg.sv"
TCL_CONFIG = REPO_ROOT / "hw" / "scripts" / "generated" / "pl_config.tcl"
DOCS_DIR = REPO_ROOT / "build" / "docs" / "regs" / "pl_control"
PL_CONTROL_TOP = "pl_control"
SYSTEM_TOP = "donder_pl"
CONTROL_INST = "control"
FRAME_RAM_INST = "frame_ram"

PARAM_TO_CONFIG = OrderedDict([
    ("P_OUTPUT_COUNT", "OUTPUT_COUNT"),
    ("P_PIN_OUTPUT_COUNT", "PIN_OUTPUT_COUNT"),
    ("P_PIXELS_PER_OUTPUT", "PIXELS_PER_OUTPUT"),
    ("P_DEFAULT_ACTIVE_OUTPUT_COUNT", "DEFAULT_ACTIVE_OUTPUT_COUNT"),
    ("P_DEFAULT_STRAND_PIXEL_COUNT", "DEFAULT_STRAND_PIXEL_COUNT"),
    ("P_DEFAULT_OUTPUT_INVERT_MASK", "DEFAULT_OUTPUT_INVERT_MASK"),
    ("P_WS281X_BIT_RATE", "WS281X_BIT_RATE"),
    ("P_FRAME_BANKS", "FRAME_BANKS"),
    ("P_CONTROL_RANGE_BYTES", "CONTROL_RANGE_BYTES"),
    ("P_E131_PORT", "E131_PORT"),
    ("P_E131_FIRST_UNIVERSE", "E131_FIRST_UNIVERSE"),
    ("P_E131_SLOTS_PER_UNIVERSE", "E131_SLOTS_PER_UNIVERSE"),
    ("P_E131_BLACKOUT_TIMEOUT_MS", "E131_BLACKOUT_TIMEOUT_MS"),
    ("P_E131_ACCEPT_PREVIEW", "E131_ACCEPT_PREVIEW"),
    ("P_E131_DEFAULT_SYNC_ADDRESS", "E131_DEFAULT_SYNC_ADDRESS"),
    ("P_BOARD_IP0", "BOARD_IP0"),
    ("P_BOARD_IP1", "BOARD_IP1"),
    ("P_BOARD_IP2", "BOARD_IP2"),
    ("P_BOARD_IP3", "BOARD_IP3"),
    ("P_HOST_IP0", "HOST_IP0"),
    ("P_HOST_IP1", "HOST_IP1"),
    ("P_HOST_IP2", "HOST_IP2"),
    ("P_HOST_IP3", "HOST_IP3"),
    ("P_NETMASK_IP0", "NETMASK_IP0"),
    ("P_NETMASK_IP1", "NETMASK_IP1"),
    ("P_NETMASK_IP2", "NETMASK_IP2"),
    ("P_NETMASK_IP3", "NETMASK_IP3"),
    ("P_GATEWAY_IP0", "GATEWAY_IP0"),
    ("P_GATEWAY_IP1", "GATEWAY_IP1"),
    ("P_GATEWAY_IP2", "GATEWAY_IP2"),
    ("P_GATEWAY_IP3", "GATEWAY_IP3"),
    ("P_MAC0", "MAC0"),
    ("P_MAC1", "MAC1"),
    ("P_MAC2", "MAC2"),
    ("P_MAC3", "MAC3"),
    ("P_MAC4", "MAC4"),
    ("P_MAC5", "MAC5"),
    ("P_UART_BAUD", "UART_BAUD"),
    ("P_JTAG_HW_SERVER_PORT", "JTAG_HW_SERVER_PORT"),
    ("P_RX_PACKET_RING_DEPTH", "RX_PACKET_RING_DEPTH"),
    ("P_E131_MAX_PACKET_BYTES", "E131_MAX_PACKET_BYTES"),
    ("P_LWIP_MEM_SIZE", "LWIP_MEM_SIZE"),
    ("P_LWIP_PBUF_POOL_SIZE", "LWIP_PBUF_POOL_SIZE"),
    ("P_LWIP_RX_DESCRIPTORS", "LWIP_RX_DESCRIPTORS"),
])

REQUIRED_REGS = [
    "ID",
    "VERSION",
    "CONTROL",
    "STATUS",
    "PIN_OUT",
    "COUNTER",
    "FRAME_CAPACITY",
    "FRAME_COMMIT",
    "FRAME_COUNT",
    "COMMITTED_WORDS",
    "FIRST_FRAME_WORD",
    "LAST_FRAME_WORD",
    "ERROR_COUNT",
    "FRAME_BANK_WORDS",
    "ACTIVE_BANK",
    "WRITE_BANK",
    "FRAME_SEQUENCE",
    "CONSUMER_CONTROL",
    "CONSUMER_STATUS",
    "CONSUMER_SEQUENCE",
    "CONSUMER_FRAME_COUNT",
    "CONSUMER_ERROR_COUNT",
    "WS281X_BIT_RATE",
    "WS281X_OUTPUT_COUNT",
    "WS281X_PIXELS_PER_OUTPUT",
    "CONSUMER_DEBUG",
    "WRITE_BANK_VALID",
    "BUSY_BANK",
    "FRAME_DROPPED",
    "FRAME_REJECTED",
    "FRAME_DROP_NOTIFY",
    "ACTIVE_OUTPUT_COUNT",
    "STRAND_PIXEL_COUNT",
    "CONFIG_STATUS",
    "STRAND_LENGTH_CLAMPED",
    "OUTPUT_INVERT_MASK",
]


def run(cmd):
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def ceil_log2(value):
    width = 0
    limit = 1
    while limit < value:
        width += 1
        limit <<= 1
    return width


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sv_int(value):
    return f"32'h{int(value) & 0xffffffff:08x}"


def c_uint(value):
    return f"{int(value)}u"


def elaborate_system():
    rdlc = RDLCompiler()
    rdlc.compile_file(str(RDL))
    root = rdlc.elaborate(top_def_name=SYSTEM_TOP)
    top = root.children()[0]
    require(top.inst_name == SYSTEM_TOP, f"Expected top addrmap {SYSTEM_TOP}, got {top.inst_name}")
    return top


def child_by_name(parent, name, cls):
    child = parent.get_child_by_name(name)
    require(child is not None, f"Missing {name} in {parent.get_path()}")
    require(isinstance(child, cls), f"{name} in {parent.get_path()} is {type(child).__name__}, expected {cls.__name__}")
    return child


def read_config_and_regs():
    top = elaborate_system()
    control = child_by_name(top, CONTROL_INST, AddrmapNode)
    frame_ram = child_by_name(top, FRAME_RAM_INST, MemNode)

    config = OrderedDict()
    for param_name, config_name in PARAM_TO_CONFIG.items():
        require(param_name in control.parameters, f"Missing RDL parameter {param_name} on {control.get_path()}")
        config[config_name] = int(control.parameters[param_name])

    config["FRAME_WORDS_PER_BANK"] = config["OUTPUT_COUNT"] * config["PIXELS_PER_OUTPUT"]
    config["FRAME_WORDS"] = config["FRAME_BANKS"] * config["FRAME_WORDS_PER_BANK"]
    config["FRAME_RAM_WORDS"] = config["FRAME_WORDS"]
    config["FRAME_BYTES"] = config["FRAME_WORDS"] * 4
    config["CONTROL_BASEADDR"] = int(control.absolute_address)
    config["FRAME_RAM_BASEADDR"] = int(frame_ram.absolute_address)
    config["FRAME_RAM_RANGE_BYTES"] = int(frame_ram.size)
    config["FRAME_RANGE_BYTES"] = config["FRAME_RAM_RANGE_BYTES"]
    config["CONTROL_ADDR_WIDTH"] = ceil_log2(config["CONTROL_RANGE_BYTES"])
    config["FRAME_ADDR_WIDTH"] = ceil_log2(config["FRAME_RAM_RANGE_BYTES"])
    config["MASK_WORD_COUNT"] = (config["OUTPUT_COUNT"] + 31) // 32
    config["OUTPUT_INDEX_WIDTH"] = ceil_log2(config["OUTPUT_COUNT"])
    config["ACTIVE_OUTPUT_WIDTH"] = ceil_log2(config["OUTPUT_COUNT"] + 1)
    config["PIXEL_COUNT_WIDTH"] = ceil_log2(config["PIXELS_PER_OUTPUT"] + 1)

    require(config["CONTROL_RANGE_BYTES"] > 0, "CONTROL_RANGE_BYTES must be positive")
    require(control.size <= config["CONTROL_RANGE_BYTES"], "pl_control registers exceed CONTROL_RANGE_BYTES")
    require(config["FRAME_RAM_RANGE_BYTES"] >= config["FRAME_BYTES"], "frame RAM aperture is smaller than frame storage")
    require(frame_ram.get_property("memwidth") == 32, "frame_ram memwidth must be 32")
    require(frame_ram.get_property("mementries") * 4 == config["FRAME_RAM_RANGE_BYTES"], "frame_ram size metadata is inconsistent")

    regs = OrderedDict()
    for reg in control.registers(unroll=False):
        require(isinstance(reg, RegNode), f"{reg.get_path()} is not a register")
        try:
            offset = int(reg.address_offset)
        except ValueError:
            offset = int(reg.raw_address_offset)
        count = 1
        arrayed = reg.array_dimensions is not None
        if reg.array_dimensions is not None:
            require(len(reg.array_dimensions) == 1, f"{reg.inst_name} must be a one-dimensional array")
            count = int(reg.array_dimensions[0])
            require(reg.array_stride is not None, f"{reg.inst_name} missing array stride")
        reset = 0
        fields = OrderedDict()
        for field in reg.fields():
            field_mask = ((1 << int(field.width)) - 1) << int(field.low)
            field_reset = int(field.get_property("reset") or 0) << int(field.low)
            reset |= field_reset & field_mask
            fields[field.inst_name] = {
                "low": int(field.low),
                "high": int(field.high),
                "width": int(field.width),
                "mask": field_mask,
                "reset": field_reset & field_mask,
            }
        regs[reg.inst_name] = {
            "offset": offset,
            "count": count,
            "stride": int(reg.array_stride or 0),
            "arrayed": arrayed,
            "reset": reset,
            "fields": fields,
        }

    missing_regs = [name for name in REQUIRED_REGS if name not in regs]
    require(not missing_regs, f"Missing required registers: {', '.join(missing_regs)}")
    require(regs["STRAND_PIXEL_COUNT"]["count"] == config["OUTPUT_COUNT"], "STRAND_PIXEL_COUNT count must match OUTPUT_COUNT")
    require(regs["STRAND_PIXEL_COUNT"]["stride"] == 4, "STRAND_PIXEL_COUNT stride must be 4")
    require(regs["OUTPUT_INVERT_MASK"]["count"] == config["MASK_WORD_COUNT"], "OUTPUT_INVERT_MASK count must match MASK_WORD_COUNT")
    require(regs["STRAND_LENGTH_CLAMPED"]["count"] == config["MASK_WORD_COUNT"], "STRAND_LENGTH_CLAMPED count must match MASK_WORD_COUNT")

    return config, regs


def write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, newline="")


def emit_config_artifacts(out_root, config, regs):
    ps_config = out_root / "ps" / "app" / "generated" / "pl_config.h"
    rtl_config = out_root / "hw" / "rtl" / "generated" / "donder_pl_contract_pkg.sv"
    tcl_config = out_root / "hw" / "scripts" / "generated" / "pl_config.tcl"
    py_config = out_root / "ps" / "tools" / "generated" / "pl_config.py"

    c_lines = [
        "/* Generated from hw/regs/pl_control.rdl. Do not edit. */",
        "#ifndef PL_CONFIG_H",
        "#define PL_CONFIG_H",
        "",
    ]
    for name, value in config.items():
        c_lines.append(f"#define DONDER_PL_{name} {c_uint(value)}")
    c_lines.extend(["", "#endif", ""])
    write_if_changed(ps_config, "\n".join(c_lines))

    sv_lines = [
        "`timescale 1ns / 1ps",
        "package donder_pl_contract_pkg;",
    ]
    for name, value in config.items():
        sv_lines.append(f"    localparam int {name} = {value};")
    sv_lines.append("")
    for name, metadata in regs.items():
        sv_lines.append(f"    localparam int unsigned REG_{name}_OFFSET = 32'h{metadata['offset']:08x};")
        sv_lines.append(f"    localparam logic [31:0] REG_{name}_RESET = {sv_int(metadata['reset'])};")
        if metadata["arrayed"]:
            sv_lines.append(f"    localparam int unsigned REG_{name}_COUNT = {metadata['count']};")
            sv_lines.append(f"    localparam int unsigned REG_{name}_STRIDE = {metadata['stride']};")
        for field_name, field in metadata["fields"].items():
            sv_lines.append(f"    localparam logic [31:0] REG_{name}_{field_name}_MASK = {sv_int(field['mask'])};")
            sv_lines.append(f"    localparam int unsigned REG_{name}_{field_name}_BP = {field['low']};")
    sv_lines.extend(["endpackage", ""])
    write_if_changed(rtl_config, "\n".join(sv_lines))

    tcl_lines = ["# Generated from hw/regs/pl_control.rdl. Do not edit."]
    for name, value in config.items():
        tcl_lines.append(f"set donder_pl_{name.lower()} {value}")
    tcl_lines.append("")
    for name, metadata in regs.items():
        tcl_lines.append(f"set donder_pl_reg_offset({name}) {metadata['offset']}")
    tcl_lines.append("")
    for name, metadata in regs.items():
        if metadata["arrayed"]:
            tcl_lines.append(f"set donder_pl_reg_count({name}) {metadata['count']}")
            tcl_lines.append(f"set donder_pl_reg_stride({name}) {metadata['stride']}")
    tcl_lines.append("")
    write_if_changed(tcl_config, "\n".join(tcl_lines))

    py_lines = ["# Generated from hw/regs/pl_control.rdl. Do not edit."]
    for name, value in config.items():
        py_lines.append(f"{name} = {value}")
    py_lines.extend([
        "",
        "BOARD_IP = (BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3)",
        "HOST_IP = (HOST_IP0, HOST_IP1, HOST_IP2, HOST_IP3)",
        "NETMASK_IP = (NETMASK_IP0, NETMASK_IP1, NETMASK_IP2, NETMASK_IP3)",
        "GATEWAY_IP = (GATEWAY_IP0, GATEWAY_IP1, GATEWAY_IP2, GATEWAY_IP3)",
        "MAC = (MAC0, MAC1, MAC2, MAC3, MAC4, MAC5)",
        "",
        "",
        "def ip_string(octets):",
        "    return \".\".join(str(octet) for octet in octets)",
        "",
        "",
        "BOARD_IP_STRING = ip_string(BOARD_IP)",
        "HOST_IP_STRING = ip_string(HOST_IP)",
        "NETMASK_IP_STRING = ip_string(NETMASK_IP)",
        "GATEWAY_IP_STRING = ip_string(GATEWAY_IP)",
    ])
    py_lines.append("")
    write_if_changed(py_config, "\n".join(py_lines))


def generate(out_root, include_docs=True):
    config, regs = read_config_and_regs()
    out_root.mkdir(parents=True, exist_ok=True)
    ps_header = out_root / "ps" / "app" / "pl_control.h"
    rtl_dir = out_root / "hw" / "rtl" / "generated"
    ps_header.parent.mkdir(parents=True, exist_ok=True)
    rtl_dir.mkdir(parents=True, exist_ok=True)

    run(["peakrdl", "c-header", "-t", PL_CONTROL_TOP, "-o", str(ps_header), str(RDL)])
    run([
        "peakrdl",
        "regblock",
        "-t",
        PL_CONTROL_TOP,
        "--cpuif",
        "axi4-lite-flat",
        "--addr-width",
        "12",
        "--default-reset",
        "rst_n",
        "--module-name",
        "pl_control_regs",
        "-o",
        str(rtl_dir),
        str(RDL),
    ])
    for sv in rtl_dir.glob("*.sv"):
        text = sv.read_text()
        if not text.startswith("`timescale"):
            sv.write_text("`timescale 1ns / 1ps\n" + text, newline="")
    emit_config_artifacts(out_root, config, regs)
    if not include_docs:
        return

    docs_dir = out_root / "docs" / "regs" / "pl_control"
    docs_dir.parent.mkdir(parents=True, exist_ok=True)
    run([
        "peakrdl",
        "html",
        "-t",
        PL_CONTROL_TOP,
        "-o",
        str(docs_dir),
        "--title",
        "Donder Controller PL Control Registers",
        str(RDL),
    ])
    index_html = docs_dir / "index.html"
    index_html.write_text(
        re.sub(r"BUILD_TS = \d+|ts=\d+", lambda m: "BUILD_TS = 0" if m.group(0).startswith("BUILD_TS") else "ts=0", index_html.read_text()),
        newline="",
    )


def copy_generated(src_root):
    PS_CONFIG_HEADER.parent.mkdir(parents=True, exist_ok=True)
    PY_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    TCL_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_root / "ps" / "app" / "pl_control.h", PS_HEADER)
    shutil.copy2(src_root / "ps" / "app" / "generated" / "pl_config.h", PS_CONFIG_HEADER)
    shutil.copy2(src_root / "ps" / "tools" / "generated" / "pl_config.py", PY_CONFIG)
    shutil.copy2(src_root / "hw" / "scripts" / "generated" / "pl_config.tcl", TCL_CONFIG)
    RTL_DIR.mkdir(parents=True, exist_ok=True)
    for path in RTL_DIR.glob("*"):
        if path.is_file():
            path.unlink()
    for path in (src_root / "hw" / "rtl" / "generated").glob("*"):
        shutil.copy2(path, RTL_DIR / path.name)
    if DOCS_DIR.exists():
        shutil.rmtree(DOCS_DIR)
    DOCS_DIR.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src_root / "docs" / "regs" / "pl_control", DOCS_DIR)


def compare_dirs(expected, actual):
    if not actual.exists():
        return [str(actual.relative_to(REPO_ROOT))]

    differences = []
    cmp = filecmp.dircmp(expected, actual)
    for name in cmp.left_only:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name in cmp.right_only:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name in cmp.diff_files:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name, subcmp in cmp.subdirs.items():
        differences.extend(compare_dirs(expected / name, actual / name))
    return differences


def check_generated(src_root):
    differences = []
    if not PS_HEADER.exists() or not filecmp.cmp(src_root / "ps" / "app" / "pl_control.h", PS_HEADER, shallow=False):
        differences.append(str(PS_HEADER.relative_to(REPO_ROOT)))
    for src, dst in [
        (src_root / "ps" / "app" / "generated" / "pl_config.h", PS_CONFIG_HEADER),
        (src_root / "ps" / "tools" / "generated" / "pl_config.py", PY_CONFIG),
        (src_root / "hw" / "scripts" / "generated" / "pl_config.tcl", TCL_CONFIG),
    ]:
        if not dst.exists() or not filecmp.cmp(src, dst, shallow=False):
            differences.append(str(dst.relative_to(REPO_ROOT)))
    differences.extend(compare_dirs(src_root / "hw" / "rtl" / "generated", RTL_DIR))
    return differences


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            generate(tmp_root, include_docs=False)
            differences = check_generated(tmp_root)
            if differences:
                print("Generated register artifacts are stale:", file=sys.stderr)
                for path in differences:
                    print(f"  {path}", file=sys.stderr)
                return 1
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp)
        generate(tmp_root)
        copy_generated(tmp_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
