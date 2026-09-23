.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
XVLOG ?= xvlog
XELAB ?= xelab
XSIM ?= xsim
VITIS ?= vitis
BOOTGEN ?= bootgen
HOST_CC ?= gcc
PORT ?=
BAUD ?= $(shell $(PYTHON) -c "from ps.tools.generated import pl_config; print(pl_config.UART_BAUD)")
SERIAL_PORT ?=
E131_PROFILE_DURATION ?= 10
E131_PROFILE_REPORT ?= E131_PROFILE_RESULTS.md
E131_DEST_IP ?= $(shell $(PYTHON) -c "from ps.tools.generated import pl_config; print(pl_config.BOARD_IP_STRING)")
E131_PORT ?= $(shell $(PYTHON) -c "from ps.tools.generated import pl_config; print(pl_config.E131_PORT)")

XSA := build/vivado/donder_controller.xsa
BITSTREAM := build/vivado/donder_controller.runs/impl_1/donder_system_wrapper.bit
PS_STAMP := build/vitis/.app-built
BOOT_BIN := build/sd/BOOT.BIN
RTL_CHECK_DIR := build/rtl-check
RTL_SIM_DIR := build/rtl-sim
SIDE_EFFECT_DIR := build/tool-side-effects
PS_HOST_E131_TEST_EXE := build/ps-host-test/e131_host_tests.exe
PS_HOST_FRAME_TEST_EXE := build/ps-host-test/frame_pipeline_host_tests.exe
PS_HOST_RX_RING_TEST_EXE := build/ps-host-test/rx_packet_ring_host_tests.exe

define collect_root_side_effects
	$(PYTHON) make_helpers.py collect-root-side-effects $(SIDE_EFFECT_DIR)
endef

.PHONY: help all regs regs-check ssot-check check rtl-check rtl-sim hw ps ps-host-test boot run logs serial-ports e131-send bench-e131 e131-profile-report clean

help:
	@echo Common targets:
	@echo   make hw      Build Vivado hardware and export XSA
	@echo   make regs    Regenerate SystemRDL-derived software, RTL, and local docs
	@echo   make regs-check  Check committed register artifacts are fresh
	@echo   make ssot-check  Check runtime contract literals come from SystemRDL/generated artifacts
	@echo   make check   Run generated, SSOT, compile, host, RTL checks, and focused RTL sim
	@echo   make rtl-check  Run fast Vivado Verilog syntax checks
	@echo   make rtl-sim  Run focused WS281x consumer RTL simulation
	@echo   make ps      Build the bare-metal controller app
	@echo   make ps-host-test  Build and run host-side PS protocol tests
	@echo   make boot    Package deployable SD-card BOOT.BIN
	@echo   make run     Program FPGA and run the controller app over JTAG
	@echo   make logs   Stream UART telemetry at generated default baud
	@echo   make logs PORT=COMx  Stream UART telemetry from an explicit port
	@echo   make serial-ports  List detected serial ports
	@echo   make e131-send  Send deterministic E1.31 UDP to generated board endpoint
	@echo   make bench-e131  Run the 30-output E1.31 throughput benchmark
	@echo   make e131-profile-report  Auto-detect UART, run hardware profile, and write E131_PROFILE_RESULTS.md
	@echo   make all     Run hw, ps, and boot
	@echo   make clean   Remove generated Xilinx output and root log clutter

all: hw ps boot

regs:
	$(PYTHON) hw/regs/generate_regs.py
	$(collect_root_side_effects)

regs-check:
	$(PYTHON) hw/regs/generate_regs.py --check
	$(collect_root_side_effects)

ssot-check:
	$(PYTHON) hw/regs/ssot_check.py
	$(collect_root_side_effects)

check: regs-check ssot-check
	$(PYTHON) -m py_compile ps/tools/e131_send.py ps/tools/e131_benchmark.py ps/tools/e131_ingress_profile.py ps/tools/e131_profile_report.py ps/scripts/create_app_vitis.py ps/scripts/package_boot.py ps/scripts/run_xsdb_checked.py
	$(MAKE) ps-host-test
	$(MAKE) rtl-check
	$(MAKE) rtl-sim

rtl-check: regs-check
	$(PYTHON) make_helpers.py mkdir $(RTL_CHECK_DIR)
	cd $(RTL_CHECK_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/donder_pl_contract_pkg.sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v
	$(collect_root_side_effects)

rtl-sim: regs-check
	$(PYTHON) make_helpers.py mkdir $(RTL_SIM_DIR)
	cd $(RTL_SIM_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/donder_pl_contract_pkg.sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v ../../hw/sim/tb_ws281x_consumer.v
	cd $(RTL_SIM_DIR) && $(XELAB) tb_ws281x_consumer -s tb_ws281x_consumer_sim
	cd $(RTL_SIM_DIR) && $(XSIM) tb_ws281x_consumer_sim -runall
	$(collect_root_side_effects)

hw: $(XSA) $(BITSTREAM)

$(XSA) $(BITSTREAM): hw/rtl/generated/donder_pl_contract_pkg.sv hw/rtl/generated/pl_control_regs_pkg.sv hw/rtl/generated/pl_control_regs.sv hw/rtl/pl_frame_control.sv hw/rtl/ws281x_frame_consumer.sv hw/rtl/ws281x_controller_core.v hw/rtl/axil_frame_ram.v hw/constraints/pynq_z2.xdc hw/scripts/build.tcl hw/scripts/ps_bd.tcl | regs-check
	$(PYTHON) make_helpers.py mkdir build/vivado
	cd build/vivado && $(VIVADO) -mode batch -source ../../hw/scripts/build.tcl
	$(collect_root_side_effects)

ps: $(PS_STAMP)

ps-host-test: $(PS_HOST_E131_TEST_EXE) $(PS_HOST_FRAME_TEST_EXE) $(PS_HOST_RX_RING_TEST_EXE)
	$(PS_HOST_E131_TEST_EXE)
	$(PS_HOST_FRAME_TEST_EXE)
	$(PS_HOST_RX_RING_TEST_EXE)

$(PS_HOST_E131_TEST_EXE): ps/tests/e131_host_tests.c ps/app/e131_parser.c ps/app/e131_parser.h ps/app/e131_receiver.c ps/app/e131_receiver.h ps/app/app_config.c ps/app/app_config.h ps/app/generated/pl_config.h ps/app/frame_pipeline.h Makefile
	$(PYTHON) make_helpers.py mkdir build/ps-host-test
	$(HOST_CC) -std=c99 -Wall -Wextra -Werror -Ips/app -o $(PS_HOST_E131_TEST_EXE) ps/tests/e131_host_tests.c ps/app/e131_parser.c ps/app/e131_receiver.c ps/app/app_config.c

$(PS_HOST_FRAME_TEST_EXE): ps/tests/frame_pipeline_host_tests.c ps/app/frame_pipeline.c ps/app/frame_pipeline.h ps/app/pl_ingest.h ps/app/app_config.h ps/app/generated/pl_config.h Makefile
	$(PYTHON) make_helpers.py mkdir build/ps-host-test
	$(HOST_CC) -std=c11 -Wall -Wextra -Werror -Ips/app -o $(PS_HOST_FRAME_TEST_EXE) ps/tests/frame_pipeline_host_tests.c ps/app/frame_pipeline.c

$(PS_HOST_RX_RING_TEST_EXE): ps/tests/rx_packet_ring_host_tests.c ps/app/rx_packet_ring.c ps/app/rx_packet_ring.h Makefile
	$(PYTHON) make_helpers.py mkdir build/ps-host-test
	$(HOST_CC) -std=c99 -Wall -Wextra -Werror -Ips/app -o $(PS_HOST_RX_RING_TEST_EXE) ps/tests/rx_packet_ring_host_tests.c ps/app/rx_packet_ring.c

$(PS_STAMP): $(XSA) $(BITSTREAM) $(wildcard ps/app/*.c) $(wildcard ps/app/*.h) ps/scripts/create_app_vitis.py Makefile | regs-check
	$(PYTHON) make_helpers.py mkdir build/vitis
	cd build/vitis && $(VITIS) -s ../../ps/scripts/create_app_vitis.py
	$(collect_root_side_effects)

boot: $(BOOT_BIN)

$(BOOT_BIN): $(PS_STAMP) ps/scripts/package_boot.py
	$(PYTHON) ps/scripts/package_boot.py --bootgen $(BOOTGEN)
	$(collect_root_side_effects)

run: $(PS_STAMP)
	$(PYTHON) ps/scripts/run_xsdb_checked.py ps/scripts/run_controller.tcl
	$(collect_root_side_effects)

logs:
	$(PYTHON) make_helpers.py logs --port "$(PORT)" --baud $(BAUD)

serial-ports:
	$(PYTHON) make_helpers.py list-serial-ports

e131-send:
	$(PYTHON) ps/tools/e131_send.py --dest-ip $(E131_DEST_IP) --port $(E131_PORT)

bench-e131:
	$(PYTHON) ps/tools/e131_benchmark.py

e131-profile-report:
	$(PYTHON) ps/tools/e131_profile_report.py --serial-port "$(SERIAL_PORT)" --baud $(BAUD) --duration $(E131_PROFILE_DURATION) --report "$(E131_PROFILE_REPORT)"

clean:
	$(PYTHON) make_helpers.py remove-paths build .Xil NA
	$(PYTHON) make_helpers.py clean-root-files
