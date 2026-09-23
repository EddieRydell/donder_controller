`timescale 1ns / 1ps

module pl_frame_control #(
    parameter AXIL_ADDR_WIDTH = 12,
    parameter FRAME_WORDS = donder_pl_contract_pkg::FRAME_WORDS,
    parameter OUTPUT_COUNT = donder_pl_contract_pkg::OUTPUT_COUNT,
    parameter PIXELS_PER_OUTPUT = donder_pl_contract_pkg::PIXELS_PER_OUTPUT,
    parameter MASK_WORD_COUNT = donder_pl_contract_pkg::MASK_WORD_COUNT
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input  wire                       aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                       aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_MODE = "Slave" *)
    input  wire [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                 s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                       s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                       s_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                 s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                       s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                       s_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                 s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                       s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                       s_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                 s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                       s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                       s_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]                s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                 s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                       s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                       s_axi_rready,

    output wire                       consumer_enable,
    output logic                      consumer_reset_pulse,
    input  wire                       consumer_busy,
    input  wire                       consumer_reset_low,
    input  wire                       consumer_error_pulse,
    input  wire [31:0]                consumer_sequence,
    input  wire [31:0]                consumer_frame_count,
    input  wire [31:0]                consumer_error_count,
    input  wire [31:0]                consumer_debug,
    input  wire [31:0]                consumer_active_bank,

    output wire [31:0]                active_bank,
    output wire [31:0]                committed_words,
    output wire [31:0]                frame_sequence,
    output logic [$clog2(OUTPUT_COUNT+1)-1:0] runtime_active_output_count,
    output logic [(OUTPUT_COUNT*$clog2(PIXELS_PER_OUTPUT+1))-1:0] runtime_strand_pixel_count,
    output logic [OUTPUT_COUNT-1:0]    runtime_output_invert_mask
);

    import pl_control_regs_pkg::*;

    localparam [31:0] STATUS_READY = donder_pl_contract_pkg::REG_STATUS_ready_MASK;
    localparam [31:0] STATUS_OVERFLOW = donder_pl_contract_pkg::REG_STATUS_overflow_MASK;
    localparam [31:0] STATUS_CONSUMER_ERROR = donder_pl_contract_pkg::REG_STATUS_consumer_error_MASK;
    localparam [31:0] STATUS_COMMIT_REJECTED = donder_pl_contract_pkg::REG_STATUS_commit_rejected_MASK;
    localparam [31:0] FRAME_WORDS_PER_BANK = donder_pl_contract_pkg::FRAME_WORDS_PER_BANK;
    localparam [31:0] NO_BUSY_BANK = 32'hffff_ffff;
    localparam integer ACTIVE_OUTPUT_WIDTH = $clog2(OUTPUT_COUNT + 1);
    localparam integer PIXEL_COUNT_WIDTH = $clog2(PIXELS_PER_OUTPUT + 1);

    pl_control__in_t hwif_in;
    pl_control__out_t hwif_out;

    logic [31:0] status_reg;
    logic [31:0] counter_reg;
    logic [31:0] frame_count_reg;
    logic [31:0] committed_words_reg;
    logic [31:0] committed_first_frame_word_reg;
    logic [31:0] committed_last_frame_word_reg;
    logic [31:0] staged_first_frame_word_reg;
    logic [31:0] staged_last_frame_word_reg;
    logic [31:0] error_count_reg;
    logic [31:0] frame_dropped_reg;
    logic [31:0] frame_rejected_reg;
    logic [31:0] active_bank_reg;
    logic [31:0] frame_sequence_reg;
    logic consumer_error_sticky_reg;
    logic config_invalid_sticky_reg;

    logic frame_commit_swmod_q;
    logic control_clear_swmod_q;
    logic consumer_reset_swmod_q;
    logic first_frame_word_swmod_q;
    logic last_frame_word_swmod_q;
    logic frame_drop_notify_swmod_q;
    logic active_output_count_swmod_q;
    logic strand_pixel_count_swmod_q [0:OUTPUT_COUNT-1];

    wire [31:0] commit_value;
    wire [31:0] write_bank_value;
    wire write_bank_valid_value;
    wire active_output_count_clamped;
    logic [OUTPUT_COUNT-1:0] strand_length_clamped;
    logic config_write_invalid;
    integer output_index_ff;

    assign commit_value = {hwif_out.FRAME_COMMIT.bank.value, hwif_out.FRAME_COMMIT.word_count.value};
    assign write_bank_value = active_bank_reg ^ 32'h0000_0001;
    assign write_bank_valid_value = consumer_active_bank == NO_BUSY_BANK || consumer_active_bank != write_bank_value;
    assign consumer_enable = hwif_out.CONSUMER_CONTROL.enable.value;
    assign active_bank = active_bank_reg;
    assign committed_words = committed_words_reg;
    assign frame_sequence = frame_sequence_reg;
    assign active_output_count_clamped = hwif_out.ACTIVE_OUTPUT_COUNT.value.value > OUTPUT_COUNT;

    always_comb begin
        integer output_index;
        strand_length_clamped = {OUTPUT_COUNT{1'b0}};
        for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
            strand_length_clamped[output_index] = hwif_out.STRAND_PIXEL_COUNT[output_index].value.value > PIXELS_PER_OUTPUT;
        end
    end

    always_comb begin
        integer output_index;
        config_write_invalid = active_output_count_swmod_q && active_output_count_clamped;
        for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
            config_write_invalid = config_write_invalid
                || (strand_pixel_count_swmod_q[output_index] && strand_length_clamped[output_index]);
        end
    end

    assign hwif_in.STATUS.ready.next = status_reg[0];
    assign hwif_in.STATUS.overflow.next = status_reg[1];
    assign hwif_in.STATUS.consumer_error.next = status_reg[2];
    assign hwif_in.STATUS.commit_rejected.next = status_reg[3];
    assign hwif_in.PIN_OUT.value.next = committed_first_frame_word_reg;
    assign hwif_in.COUNTER.value.next = counter_reg;
    assign hwif_in.FRAME_CAPACITY.value.next = FRAME_WORDS;
    assign hwif_in.FRAME_COUNT.value.next = frame_count_reg;
    assign hwif_in.COMMITTED_WORDS.value.next = committed_words_reg;
    assign hwif_in.FIRST_FRAME_WORD.value.next = committed_first_frame_word_reg;
    assign hwif_in.LAST_FRAME_WORD.value.next = committed_last_frame_word_reg;
    assign hwif_in.ERROR_COUNT.value.next = error_count_reg;
    assign hwif_in.FRAME_BANK_WORDS.value.next = FRAME_WORDS_PER_BANK;
    assign hwif_in.ACTIVE_BANK.value.next = active_bank_reg;
    assign hwif_in.WRITE_BANK.value.next = write_bank_value;
    assign hwif_in.FRAME_SEQUENCE.value.next = frame_sequence_reg;
    assign hwif_in.CONSUMER_STATUS.enabled.next = consumer_enable;
    assign hwif_in.CONSUMER_STATUS.busy.next = consumer_busy;
    assign hwif_in.CONSUMER_STATUS.reset_low.next = consumer_reset_low;
    assign hwif_in.CONSUMER_STATUS.error.next = consumer_error_sticky_reg;
    assign hwif_in.CONSUMER_SEQUENCE.value.next = consumer_sequence;
    assign hwif_in.CONSUMER_FRAME_COUNT.value.next = consumer_frame_count;
    assign hwif_in.CONSUMER_ERROR_COUNT.value.next = consumer_error_count;
    assign hwif_in.CONSUMER_DEBUG.value.next = consumer_debug;
    assign hwif_in.WRITE_BANK_VALID.value.next = write_bank_valid_value;
    assign hwif_in.BUSY_BANK.value.next = consumer_active_bank;
    assign hwif_in.FRAME_DROPPED.value.next = frame_dropped_reg;
    assign hwif_in.FRAME_REJECTED.value.next = frame_rejected_reg;
    assign hwif_in.CONFIG_STATUS.config_invalid.next = config_invalid_sticky_reg;
    assign hwif_in.CONFIG_STATUS.active_count_clamped.next = active_output_count_clamped;
    always_comb begin
        integer mask_word_index;
        integer output_index;
        for (mask_word_index = 0; mask_word_index < MASK_WORD_COUNT; mask_word_index = mask_word_index + 1) begin
            hwif_in.STRAND_LENGTH_CLAMPED[mask_word_index].value.next = 32'h0000_0000;
            for (output_index = 0; output_index < 32; output_index = output_index + 1) begin
                if ((mask_word_index * 32 + output_index) < OUTPUT_COUNT) begin
                    hwif_in.STRAND_LENGTH_CLAMPED[mask_word_index].value.next[output_index] =
                        strand_length_clamped[mask_word_index * 32 + output_index];
                end
            end
        end
    end

    pl_control_regs regs (
        .clk(aclk),
        .rst_n(aresetn),
        .s_axil_awready(s_axi_awready),
        .s_axil_awvalid(s_axi_awvalid),
        .s_axil_awaddr(s_axi_awaddr[11:0]),
        .s_axil_awprot(s_axi_awprot),
        .s_axil_wready(s_axi_wready),
        .s_axil_wvalid(s_axi_wvalid),
        .s_axil_wdata(s_axi_wdata),
        .s_axil_wstrb(s_axi_wstrb),
        .s_axil_bready(s_axi_bready),
        .s_axil_bvalid(s_axi_bvalid),
        .s_axil_bresp(s_axi_bresp),
        .s_axil_arready(s_axi_arready),
        .s_axil_arvalid(s_axi_arvalid),
        .s_axil_araddr(s_axi_araddr[11:0]),
        .s_axil_arprot(s_axi_arprot),
        .s_axil_rready(s_axi_rready),
        .s_axil_rvalid(s_axi_rvalid),
        .s_axil_rdata(s_axi_rdata),
        .s_axil_rresp(s_axi_rresp),
        .hwif_in(hwif_in),
        .hwif_out(hwif_out)
    );

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            status_reg <= STATUS_READY;
            counter_reg <= 32'h0000_0000;
            frame_count_reg <= 32'h0000_0000;
            committed_words_reg <= 32'h0000_0000;
            committed_first_frame_word_reg <= 32'h0000_0000;
            committed_last_frame_word_reg <= 32'h0000_0000;
            staged_first_frame_word_reg <= 32'h0000_0000;
            staged_last_frame_word_reg <= 32'h0000_0000;
            error_count_reg <= 32'h0000_0000;
            frame_dropped_reg <= 32'h0000_0000;
            frame_rejected_reg <= 32'h0000_0000;
            active_bank_reg <= 32'h0000_0000;
            frame_sequence_reg <= 32'h0000_0000;
            consumer_error_sticky_reg <= 1'b0;
            config_invalid_sticky_reg <= 1'b0;
            frame_commit_swmod_q <= 1'b0;
            control_clear_swmod_q <= 1'b0;
            consumer_reset_swmod_q <= 1'b0;
            first_frame_word_swmod_q <= 1'b0;
            last_frame_word_swmod_q <= 1'b0;
            frame_drop_notify_swmod_q <= 1'b0;
            active_output_count_swmod_q <= 1'b0;
            consumer_reset_pulse <= 1'b0;
            runtime_active_output_count <= ACTIVE_OUTPUT_WIDTH'(donder_pl_contract_pkg::DEFAULT_ACTIVE_OUTPUT_COUNT);
            runtime_output_invert_mask <= donder_pl_contract_pkg::DEFAULT_OUTPUT_INVERT_MASK[OUTPUT_COUNT-1:0];
            for (output_index_ff = 0; output_index_ff < OUTPUT_COUNT; output_index_ff = output_index_ff + 1) begin
                strand_pixel_count_swmod_q[output_index_ff] <= 1'b0;
                runtime_strand_pixel_count[output_index_ff*PIXEL_COUNT_WIDTH +: PIXEL_COUNT_WIDTH] <= PIXEL_COUNT_WIDTH'(donder_pl_contract_pkg::DEFAULT_STRAND_PIXEL_COUNT);
            end
        end else begin
            counter_reg <= counter_reg + 32'd1;
            consumer_reset_pulse <= 1'b0;
            runtime_active_output_count <= active_output_count_clamped
                ? ACTIVE_OUTPUT_WIDTH'(OUTPUT_COUNT)
                : hwif_out.ACTIVE_OUTPUT_COUNT.value.value[ACTIVE_OUTPUT_WIDTH-1:0];
            for (output_index_ff = 0; output_index_ff < OUTPUT_COUNT; output_index_ff = output_index_ff + 1) begin
                runtime_strand_pixel_count[output_index_ff*PIXEL_COUNT_WIDTH +: PIXEL_COUNT_WIDTH] <= strand_length_clamped[output_index_ff]
                    ? PIXEL_COUNT_WIDTH'(PIXELS_PER_OUTPUT)
                    : hwif_out.STRAND_PIXEL_COUNT[output_index_ff].value.value[PIXEL_COUNT_WIDTH-1:0];
            end
            for (output_index_ff = 0; output_index_ff < OUTPUT_COUNT; output_index_ff = output_index_ff + 1) begin
                runtime_output_invert_mask[output_index_ff] <=
                    hwif_out.OUTPUT_INVERT_MASK[output_index_ff / 32].value.value[output_index_ff % 32];
            end

            frame_commit_swmod_q <= hwif_out.FRAME_COMMIT.word_count.swmod || hwif_out.FRAME_COMMIT.bank.swmod;
            control_clear_swmod_q <= hwif_out.CONTROL.clear_errors.swmod;
            consumer_reset_swmod_q <= hwif_out.CONSUMER_CONTROL.reset_fsm.swmod;
            first_frame_word_swmod_q <= hwif_out.FIRST_FRAME_WORD.value.swmod;
            last_frame_word_swmod_q <= hwif_out.LAST_FRAME_WORD.value.swmod;
            frame_drop_notify_swmod_q <= hwif_out.FRAME_DROP_NOTIFY.value.swmod;
            active_output_count_swmod_q <= hwif_out.ACTIVE_OUTPUT_COUNT.value.swmod;
            for (output_index_ff = 0; output_index_ff < OUTPUT_COUNT; output_index_ff = output_index_ff + 1) begin
                strand_pixel_count_swmod_q[output_index_ff] <= hwif_out.STRAND_PIXEL_COUNT[output_index_ff].value.swmod;
            end

            if (first_frame_word_swmod_q) begin
                staged_first_frame_word_reg <= hwif_out.FIRST_FRAME_WORD.value.value;
            end
            if (last_frame_word_swmod_q) begin
                staged_last_frame_word_reg <= hwif_out.LAST_FRAME_WORD.value.value;
            end

            if (control_clear_swmod_q && hwif_out.CONTROL.clear_errors.value) begin
                status_reg <= STATUS_READY;
                consumer_error_sticky_reg <= 1'b0;
                config_invalid_sticky_reg <= 1'b0;
            end

            if (config_write_invalid) begin
                config_invalid_sticky_reg <= 1'b1;
            end

            if (consumer_error_pulse) begin
                status_reg <= STATUS_READY | STATUS_CONSUMER_ERROR;
                consumer_error_sticky_reg <= 1'b1;
            end

            if (consumer_reset_swmod_q && hwif_out.CONSUMER_CONTROL.reset_fsm.value) begin
                consumer_reset_pulse <= 1'b1;
            end

            if (frame_commit_swmod_q) begin
                if (commit_value[30:0] <= FRAME_WORDS_PER_BANK
                    && commit_value[31] == write_bank_value[0]
                    && write_bank_valid_value) begin
                    frame_count_reg <= frame_count_reg + 32'd1;
                    frame_sequence_reg <= frame_sequence_reg + 32'd1;
                    active_bank_reg <= {31'h0000_0000, commit_value[31]};
                    committed_words_reg <= commit_value[30:0];
                    committed_first_frame_word_reg <= staged_first_frame_word_reg;
                    committed_last_frame_word_reg <= staged_last_frame_word_reg;
                end else begin
                    status_reg <= commit_value[30:0] > FRAME_WORDS_PER_BANK
                        ? (STATUS_READY | STATUS_OVERFLOW)
                        : (STATUS_READY | STATUS_COMMIT_REJECTED);
                    error_count_reg <= error_count_reg + 32'd1;
                    if (commit_value[30:0] <= FRAME_WORDS_PER_BANK) begin
                        frame_rejected_reg <= frame_rejected_reg + 32'd1;
                    end
                end
            end

            if (frame_drop_notify_swmod_q && hwif_out.FRAME_DROP_NOTIFY.value.value) begin
                frame_dropped_reg <= frame_dropped_reg + 32'd1;
            end
        end
    end

endmodule
