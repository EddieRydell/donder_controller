#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
import os
import sys

import vitis


def mark(message):
    print(message, flush=True)


def env_int(name, default=None):
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return int(value, 0)


def replace_exactly_once(path, old, new, label):
    text = path.read_text()
    count = text.count(old)
    if count == 0:
        raise RuntimeError(f"{label}: expected text not found in {path}")
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1))


def replace_or_verify_exactly_once(path, old, new, label):
    text = path.read_text()
    old_count = text.count(old)
    new_count = text.count(new)
    if old_count == 1 and new_count == 0:
        path.write_text(text.replace(old, new, 1))
        return
    if old_count == 0 and new_count == 1:
        return
    raise RuntimeError(
        f"{label}: expected one replaceable or already-updated match in {path}, "
        f"found old={old_count} new={new_count}"
    )


repo_root = Path(__file__).resolve().parents[2]
if str(repo_root) not in sys.path:
    sys.path.insert(0, str(repo_root))

from ps.tools.generated import pl_config

workspace = repo_root / "build" / "vitis" / datetime.now().strftime("%Y%m%d_%H%M%S")
xsa = repo_root / "build" / "vivado" / "donder_controller.xsa"

if not xsa.exists():
    raise SystemExit(f"Missing XSA: {xsa}")

mark("create_client")
client = vitis.create_client()

mark(f"set_workspace {workspace}")
client.set_workspace(str(workspace))

mark("create_platform_component")
platform = client.create_platform_component(
    name="donder_platform",
    hw_design=str(xsa),
    cpu="ps7_cortexa9_0",
    os="standalone",
    domain_name="standalone",
)

mark("set stdout uart0")
for domain_name in ("standalone", "zynq_fsbl"):
    domain = platform.get_domain(domain_name)
    domain.set_config("os", "standalone_stdin", "ps7_uart_0")
    domain.set_config("os", "standalone_stdout", "ps7_uart_0")
    domain.set_config(
        "proc",
        "proc_extra_compiler_flags",
        " -O2 -g -fno-tree-loop-distribute-patterns",
    )

mark("enable lwip")
standalone_domain = platform.get_domain("standalone")
if not any(lib.get("name") == "lwip220" for lib in standalone_domain.get_libs()):
    standalone_domain.set_lib("lwip220")

mark("enable lwip stats")
standalone_domain.set_config("lib", "lwip220_stats", "true", lib_name="lwip220")
for env_name, param_name, default_value in (
    ("DONDER_LWIP_MEM_SIZE", "lwip220_mem_size", pl_config.LWIP_MEM_SIZE),
    ("DONDER_LWIP_MEMP_N_PBUF", "lwip220_memp_n_pbuf", None),
    ("DONDER_LWIP_PBUF_POOL_SIZE", "lwip220_pbuf_pool_size", pl_config.LWIP_PBUF_POOL_SIZE),
    ("DONDER_LWIP_PBUF_POOL_BUFSIZE", "lwip220_pbuf_pool_bufsize", None),
    ("DONDER_LWIP_RX_DESCRIPTORS", "lwip220_n_rx_descriptors", pl_config.LWIP_RX_DESCRIPTORS),
    ("DONDER_LWIP_TX_DESCRIPTORS", "lwip220_n_tx_descriptors", None),
    ("DONDER_LWIP_RX_COALESCE", "lwip220_n_rx_coalesce", None),
):
    value = env_int(env_name, default_value)
    if value is not None:
        mark(f"set {param_name}={value}")
        standalone_domain.set_config("lib", param_name, str(value), lib_name="lwip220")

mark("silence generated fsbl warnings")
fsbl_user_config = workspace / "donder_platform" / "zynq_fsbl" / "UserConfig.cmake"
replace_exactly_once(
    fsbl_user_config,
    "set(USER_COMPILE_WARNINGS_INHIBIT_ALL )",
    "set(USER_COMPILE_WARNINGS_INHIBIT_ALL -w)",
    "FSBL warning suppression",
)

mark("platform build")
platform.build()

mark("find platform")
platform_xpfm = client.find_platform_in_repos("donder_platform")

mark("create app")
app = client.create_app_component(
    name="donder_controller",
    platform=platform_xpfm,
    domain="standalone",
    template="empty_application",
)

mark("import app files")
app.import_files(from_loc=str(repo_root / "ps" / "app"), dest_dir_in_cmp="src")

mark("optimize app build")
app_user_config = workspace / "donder_controller" / "src" / "UserConfig.cmake"
replace_exactly_once(
    app_user_config,
    "set(USER_COMPILE_OPTIMIZATION_LEVEL -O0)",
    "set(USER_COMPILE_OPTIMIZATION_LEVEL -O2)",
    "app optimization level",
)
replace_exactly_once(
    app_user_config,
    "set(USER_COMPILE_DEBUG_LEVEL -g3)",
    "set(USER_COMPILE_DEBUG_LEVEL -g1)",
    "app debug level",
)

mark("link lwip")
app_cmake = workspace / "donder_controller" / "src" / "CMakeLists.txt"
replace_or_verify_exactly_once(
    app_cmake,
    "collect(PROJECT_LIB_DEPS xilstandalone;xiltimer)",
    "collect(PROJECT_LIB_DEPS xilstandalone;xiltimer;lwip220)",
    "app lwIP link dependency",
)

mark("app build")
app.build()

mark("dispose")
vitis.dispose()

app_elf = workspace / "donder_controller" / "build" / "donder_controller.elf"
fsbl_elf = workspace / "donder_platform" / "zynq_fsbl" / "build" / "fsbl.elf"
stamp = repo_root / "build" / "vitis" / ".app-built"
if not app_elf.exists():
    raise SystemExit(f"Missing app ELF: {app_elf}")
if not fsbl_elf.exists():
    raise SystemExit(f"Missing FSBL ELF: {fsbl_elf}")
stamp.parent.mkdir(parents=True, exist_ok=True)
stamp.touch()

mark("complete")
