`timescale 1ns / 1ps

module tb_ws281x_consumer;
    localparam AXIL_ADDR_WIDTH = donder_pl_contract_pkg::CONTROL_ADDR_WIDTH;
    localparam FRAME_ADDR_WIDTH = 10;
    localparam OUTPUT_COUNT = donder_pl_contract_pkg::OUTPUT_COUNT;
    localparam PIXELS_PER_OUTPUT = 2;
    localparam FRAME_WORDS = 160;
    localparam [31:0] PL_CONTROL_ID_VALUE = donder_pl_contract_pkg::REG_ID_RESET;
    localparam [31:0] PL_CONTROL_VERSION_VALUE = donder_pl_contract_pkg::REG_VERSION_RESET;
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_ID_OFFSET = donder_pl_contract_pkg::REG_ID_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_VERSION_OFFSET = donder_pl_contract_pkg::REG_VERSION_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONTROL_OFFSET = donder_pl_contract_pkg::REG_CONTROL_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_STATUS_OFFSET = donder_pl_contract_pkg::REG_STATUS_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_COMMIT_OFFSET = donder_pl_contract_pkg::REG_FRAME_COMMIT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_COUNT_OFFSET = donder_pl_contract_pkg::REG_FRAME_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_COMMITTED_WORDS_OFFSET = donder_pl_contract_pkg::REG_COMMITTED_WORDS_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_ERROR_COUNT_OFFSET = donder_pl_contract_pkg::REG_ERROR_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_BANK_WORDS_OFFSET = donder_pl_contract_pkg::REG_FRAME_BANK_WORDS_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_ACTIVE_BANK_OFFSET = donder_pl_contract_pkg::REG_ACTIVE_BANK_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_WRITE_BANK_OFFSET = donder_pl_contract_pkg::REG_WRITE_BANK_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_SEQUENCE_OFFSET = donder_pl_contract_pkg::REG_FRAME_SEQUENCE_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_CONTROL_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_CONTROL_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_STATUS_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_STATUS_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_SEQUENCE_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_SEQUENCE_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_FRAME_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_ERROR_COUNT_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_ERROR_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONSUMER_DEBUG_OFFSET = donder_pl_contract_pkg::REG_CONSUMER_DEBUG_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_WRITE_BANK_VALID_OFFSET = donder_pl_contract_pkg::REG_WRITE_BANK_VALID_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_BUSY_BANK_OFFSET = donder_pl_contract_pkg::REG_BUSY_BANK_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_DROPPED_OFFSET = donder_pl_contract_pkg::REG_FRAME_DROPPED_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_REJECTED_OFFSET = donder_pl_contract_pkg::REG_FRAME_REJECTED_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_FRAME_DROP_NOTIFY_OFFSET = donder_pl_contract_pkg::REG_FRAME_DROP_NOTIFY_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET = donder_pl_contract_pkg::REG_ACTIVE_OUTPUT_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET = donder_pl_contract_pkg::REG_STRAND_PIXEL_COUNT_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_CONFIG_STATUS_OFFSET = donder_pl_contract_pkg::REG_CONFIG_STATUS_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_STRAND_LENGTH_CLAMPED_OFFSET = donder_pl_contract_pkg::REG_STRAND_LENGTH_CLAMPED_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [AXIL_ADDR_WIDTH-1:0] PL_CONTROL_OUTPUT_INVERT_MASK_OFFSET = donder_pl_contract_pkg::REG_OUTPUT_INVERT_MASK_OFFSET[AXIL_ADDR_WIDTH-1:0];
    localparam [31:0] PL_CONTROL_STATUS_READY = donder_pl_contract_pkg::REG_STATUS_ready_MASK;
    localparam [31:0] PL_CONTROL_STATUS_OVERFLOW = donder_pl_contract_pkg::REG_STATUS_overflow_MASK;
    localparam [31:0] PL_CONTROL_STATUS_COMMIT_REJECTED = donder_pl_contract_pkg::REG_STATUS_commit_rejected_MASK;
    localparam [31:0] PL_CONTROL_CONTROL_CLEAR_ERRORS = donder_pl_contract_pkg::REG_CONTROL_clear_errors_MASK;
    localparam [31:0] PL_CONTROL_CONSUMER_ENABLE = donder_pl_contract_pkg::REG_CONSUMER_CONTROL_enable_MASK;
    localparam [31:0] PL_CONTROL_CONSUMER_RESET = donder_pl_contract_pkg::REG_CONSUMER_CONTROL_reset_fsm_MASK;
    localparam [31:0] PL_CONTROL_CONSUMER_BUSY = donder_pl_contract_pkg::REG_CONSUMER_STATUS_busy_MASK;

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg [AXIL_ADDR_WIDTH-1:0] ctl_awaddr = {AXIL_ADDR_WIDTH{1'b0}};
    reg [2:0] ctl_awprot = 3'b000;
    reg ctl_awvalid = 1'b0;
    wire ctl_awready;
    reg [31:0] ctl_wdata = 32'h0000_0000;
    reg [3:0] ctl_wstrb = 4'hf;
    reg ctl_wvalid = 1'b0;
    wire ctl_wready;
    wire [1:0] ctl_bresp;
    wire ctl_bvalid;
    reg ctl_bready = 1'b1;
    reg [AXIL_ADDR_WIDTH-1:0] ctl_araddr = {AXIL_ADDR_WIDTH{1'b0}};
    reg [2:0] ctl_arprot = 3'b000;
    reg ctl_arvalid = 1'b0;
    wire ctl_arready;
    wire [31:0] ctl_rdata;
    wire [1:0] ctl_rresp;
    wire ctl_rvalid;
    reg ctl_rready = 1'b1;

    reg [FRAME_ADDR_WIDTH-1:0] ram_awaddr = {FRAME_ADDR_WIDTH{1'b0}};
    reg [2:0] ram_awprot = 3'b000;
    reg ram_awvalid = 1'b0;
    wire ram_awready;
    reg [31:0] ram_wdata = 32'h0000_0000;
    reg [3:0] ram_wstrb = 4'hf;
    reg ram_wvalid = 1'b0;
    wire ram_wready;
    wire [1:0] ram_bresp;
    wire ram_bvalid;
    reg ram_bready = 1'b1;
    reg [FRAME_ADDR_WIDTH-1:0] ram_araddr = {FRAME_ADDR_WIDTH{1'b0}};
    reg [2:0] ram_arprot = 3'b000;
    reg ram_arvalid = 1'b0;
    wire ram_arready;
    wire [31:0] ram_rdata;
    wire [1:0] ram_rresp;
    wire ram_rvalid;
    reg ram_rready = 1'b1;

    wire [OUTPUT_COUNT-1:0] ws281x_data;
    wire [FRAME_ADDR_WIDTH-1:0] frame_araddr;
    wire frame_arvalid;
    wire frame_arready;
    wire [31:0] frame_rdata;
    wire [1:0] frame_rresp;
    wire frame_rvalid;
    wire frame_rready;

    integer i;
    integer word_addr;
    integer frame_read_word;
    integer frame_read_in_bank_word;
    integer frame_read_output;
    integer frame_read_pixel;
    reg [31:0] write_bank;
    reg [31:0] second_write_bank;
    reg [31:0] bank_words;
    reg [31:0] read_data;
    reg monitor_runtime_config_reads = 1'b0;
    reg monitor_no_frame_reads = 1'b0;
    reg monitor_expected_reads = 1'b0;
    reg [OUTPUT_COUNT-1:0] expected_read_mask [0:PIXELS_PER_OUTPUT-1];
    reg [OUTPUT_COUNT-1:0] seen_read_mask [0:PIXELS_PER_OUTPUT-1];

    always #5 aclk = ~aclk;

    always @(posedge aclk) begin
        if (aresetn && monitor_runtime_config_reads && frame_arvalid && frame_arready) begin
            if (monitor_no_frame_reads) begin
                $fatal(1, "consumer read frame RAM with zero active runtime config");
            end
            frame_read_word = frame_araddr >> 2;
            frame_read_in_bank_word = frame_read_word % bank_words;
            if ((frame_read_in_bank_word % 2) != 0 && frame_read_in_bank_word != 3) begin
                $fatal(1, "consumer read inactive runtime-config word %0d", frame_read_in_bank_word);
            end
            if (monitor_expected_reads) begin
                frame_read_output = frame_read_in_bank_word / PIXELS_PER_OUTPUT;
                frame_read_pixel = frame_read_in_bank_word % PIXELS_PER_OUTPUT;
                if (frame_read_output >= OUTPUT_COUNT
                    || frame_read_pixel >= PIXELS_PER_OUTPUT
                    || !expected_read_mask[frame_read_pixel][frame_read_output]) begin
                    $fatal(1, "consumer unexpected frame read word %0d output %0d pixel %0d",
                        frame_read_in_bank_word, frame_read_output, frame_read_pixel);
                end
                seen_read_mask[frame_read_pixel][frame_read_output] <= 1'b1;
            end
        end
    end

    ws281x_controller_core #(
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .FRAME_WORDS(FRAME_WORDS),
        .FRAME_ADDR_WIDTH(FRAME_ADDR_WIDTH),
        .OUTPUT_COUNT(OUTPUT_COUNT),
        .PIXELS_PER_OUTPUT(PIXELS_PER_OUTPUT),
        .CLK_HZ(100000000),
        .WS281X_BIT_RATE(donder_pl_contract_pkg::WS281X_BIT_RATE)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(ctl_awaddr),
        .s_axi_awprot(ctl_awprot),
        .s_axi_awvalid(ctl_awvalid),
        .s_axi_awready(ctl_awready),
        .s_axi_wdata(ctl_wdata),
        .s_axi_wstrb(ctl_wstrb),
        .s_axi_wvalid(ctl_wvalid),
        .s_axi_wready(ctl_wready),
        .s_axi_bresp(ctl_bresp),
        .s_axi_bvalid(ctl_bvalid),
        .s_axi_bready(ctl_bready),
        .s_axi_araddr(ctl_araddr),
        .s_axi_arprot(ctl_arprot),
        .s_axi_arvalid(ctl_arvalid),
        .s_axi_arready(ctl_arready),
        .s_axi_rdata(ctl_rdata),
        .s_axi_rresp(ctl_rresp),
        .s_axi_rvalid(ctl_rvalid),
        .s_axi_rready(ctl_rready),
        .ws281x_data(ws281x_data),
        .m_frame_araddr(frame_araddr),
        .m_frame_arvalid(frame_arvalid),
        .m_frame_arready(frame_arready),
        .m_frame_rdata(frame_rdata),
        .m_frame_rresp(frame_rresp),
        .m_frame_rvalid(frame_rvalid),
        .m_frame_rready(frame_rready)
    );

    axil_frame_ram #(
        .AXIL_ADDR_WIDTH(FRAME_ADDR_WIDTH),
        .FRAME_WORDS(FRAME_WORDS)
    ) frame_ram (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(ram_awaddr),
        .s_axi_awprot(ram_awprot),
        .s_axi_awvalid(ram_awvalid),
        .s_axi_awready(ram_awready),
        .s_axi_wdata(ram_wdata),
        .s_axi_wstrb(ram_wstrb),
        .s_axi_wvalid(ram_wvalid),
        .s_axi_wready(ram_wready),
        .s_axi_bresp(ram_bresp),
        .s_axi_bvalid(ram_bvalid),
        .s_axi_bready(ram_bready),
        .s_axi_araddr(ram_araddr),
        .s_axi_arprot(ram_arprot),
        .s_axi_arvalid(ram_arvalid),
        .s_axi_arready(ram_arready),
        .s_axi_rdata(ram_rdata),
        .s_axi_rresp(ram_rresp),
        .s_axi_rvalid(ram_rvalid),
        .s_axi_rready(ram_rready),
        .rd_araddr(frame_araddr),
        .rd_arvalid(frame_arvalid),
        .rd_arready(frame_arready),
        .rd_rdata(frame_rdata),
        .rd_rresp(frame_rresp),
        .rd_rvalid(frame_rvalid),
        .rd_rready(frame_rready)
    );

    task ctl_write;
        input [AXIL_ADDR_WIDTH-1:0] addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            ctl_awaddr <= addr;
            ctl_wdata <= data;
            ctl_awvalid <= 1'b1;
            ctl_wvalid <= 1'b1;
            wait (ctl_awready && ctl_wready);
            @(posedge aclk);
            ctl_awvalid <= 1'b0;
            ctl_wvalid <= 1'b0;
            wait (ctl_bvalid);
            @(posedge aclk);
        end
    endtask

    task ctl_read;
        input [AXIL_ADDR_WIDTH-1:0] addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            ctl_araddr <= addr;
            ctl_arvalid <= 1'b1;
            wait (ctl_arready);
            @(posedge aclk);
            ctl_arvalid <= 1'b0;
            wait (ctl_rvalid);
            data = ctl_rdata;
            @(posedge aclk);
        end
    endtask

    task ram_write;
        input [FRAME_ADDR_WIDTH-1:0] addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            ram_awaddr <= addr;
            ram_wdata <= data;
            ram_awvalid <= 1'b1;
            ram_wvalid <= 1'b1;
            wait (ram_awready && ram_wready);
            @(posedge aclk);
            ram_awvalid <= 1'b0;
            ram_wvalid <= 1'b0;
            wait (ram_bvalid);
            @(posedge aclk);
        end
    endtask

    task clear_expected_reads;
        integer pixel;
        begin
            for (pixel = 0; pixel < PIXELS_PER_OUTPUT; pixel = pixel + 1) begin
                expected_read_mask[pixel] = {OUTPUT_COUNT{1'b0}};
                seen_read_mask[pixel] = {OUTPUT_COUNT{1'b0}};
            end
            monitor_expected_reads = 1'b1;
        end
    endtask

    task expect_output_length;
        input integer output_num;
        input integer pixel_count;
        integer pixel;
        begin
            for (pixel = 0; pixel < pixel_count; pixel = pixel + 1) begin
                expected_read_mask[pixel][output_num] = 1'b1;
            end
        end
    endtask

    task check_expected_reads;
        input [8*64-1:0] scenario;
        integer pixel;
        begin
            for (pixel = 0; pixel < PIXELS_PER_OUTPUT; pixel = pixel + 1) begin
                if (seen_read_mask[pixel] != expected_read_mask[pixel]) begin
                    $fatal(1, "%0s read mask mismatch for pixel %0d: seen %08x expected %08x",
                        scenario, pixel, seen_read_mask[pixel], expected_read_mask[pixel]);
                end
            end
            monitor_expected_reads = 1'b0;
        end
    endtask

    initial begin
        repeat (8) @(posedge aclk);
        aresetn <= 1'b1;
        repeat (8) @(posedge aclk);

        ctl_read(PL_CONTROL_ID_OFFSET, read_data);
        if (read_data != PL_CONTROL_ID_VALUE) begin
            $fatal(1, "core ID is %08x", read_data);
        end
        ctl_read(PL_CONTROL_VERSION_OFFSET, read_data);
        if (read_data != PL_CONTROL_VERSION_VALUE) begin
            $fatal(1, "core version is %08x", read_data);
        end

        ctl_read(PL_CONTROL_FRAME_BANK_WORDS_OFFSET, bank_words);
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, write_bank);
        if (write_bank > 1) begin
            $fatal(1, "write bank is %08x", write_bank);
        end

        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, bank_words + 1);
        ctl_read(PL_CONTROL_STATUS_OFFSET, read_data);
        if ((read_data & PL_CONTROL_STATUS_OVERFLOW) == 0) begin
            $fatal(1, "oversized commit did not set overflow: %08x", read_data);
        end
        ctl_read(PL_CONTROL_ERROR_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0001) begin
            $fatal(1, "oversized commit error count is %08x", read_data);
        end
        ctl_write(PL_CONTROL_CONTROL_OFFSET, PL_CONTROL_CONTROL_CLEAR_ERRORS);
        ctl_read(PL_CONTROL_STATUS_OFFSET, read_data);
        if (read_data != PL_CONTROL_STATUS_READY) begin
            $fatal(1, "clear errors left status %08x", read_data);
        end

        ctl_read(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, read_data);
        if (read_data != donder_pl_contract_pkg::DEFAULT_ACTIVE_OUTPUT_COUNT) begin
            $fatal(1, "default active output count is %08x", read_data);
        end
        ctl_read(PL_CONTROL_OUTPUT_INVERT_MASK_OFFSET, read_data);
        if (read_data != donder_pl_contract_pkg::DEFAULT_OUTPUT_INVERT_MASK) begin
            $fatal(1, "default output invert mask is %08x", read_data);
        end
        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, 32'h0000_0004);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h000, 32'h0000_0001);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h004, 32'h0000_0002);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h008, 32'h0000_0001);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h00c, 32'h0000_0000);
        ctl_read(PL_CONTROL_CONFIG_STATUS_OFFSET, read_data);
        if ((read_data & 32'h0000_0001) != 0) begin
            $fatal(1, "valid runtime config set sticky invalid: %08x", read_data);
        end
        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, 32'h0000_0029);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h000, 32'h0000_0003);
        ctl_read(PL_CONTROL_CONFIG_STATUS_OFFSET, read_data);
        if ((read_data & 32'h0000_0003) != 32'h0000_0003) begin
            $fatal(1, "invalid runtime config did not report clamp/sticky status: %08x", read_data);
        end
        ctl_read(PL_CONTROL_STRAND_LENGTH_CLAMPED_OFFSET, read_data);
        if ((read_data & 32'h0000_0001) == 0) begin
            $fatal(1, "invalid runtime config did not report strand clamp mask: %08x", read_data);
        end
        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, 32'h0000_0004);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h000, 32'h0000_0001);
        ctl_write(PL_CONTROL_CONTROL_OFFSET, PL_CONTROL_CONTROL_CLEAR_ERRORS);
        ctl_read(PL_CONTROL_CONFIG_STATUS_OFFSET, read_data);
        if ((read_data & 32'h0000_0001) != 0) begin
            $fatal(1, "clear/valid runtime config left sticky invalid: %08x", read_data);
        end

        for (i = 0; i < OUTPUT_COUNT * PIXELS_PER_OUTPUT; i = i + 1) begin
            word_addr = (write_bank * bank_words) + i;
            ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0001_0203 + i);
        end

        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (write_bank << 31) | 32'h0000_0005);
        ctl_read(PL_CONTROL_ACTIVE_BANK_OFFSET, read_data);
        if (read_data != write_bank) begin
            $fatal(1, "active bank is %08x expected %08x", read_data, write_bank);
        end
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        if (read_data != (write_bank ^ 32'h0000_0001)) begin
            $fatal(1, "next write bank is %08x", read_data);
        end

        ctl_write(PL_CONTROL_CONSUMER_CONTROL_OFFSET, PL_CONTROL_CONSUMER_RESET);
        ctl_write(PL_CONTROL_CONTROL_OFFSET, PL_CONTROL_CONTROL_CLEAR_ERRORS);
        monitor_runtime_config_reads <= 1'b1;
        clear_expected_reads();
        expect_output_length(0, 1);
        expect_output_length(1, 2);
        expect_output_length(2, 1);
        ctl_write(PL_CONTROL_CONSUMER_CONTROL_OFFSET, PL_CONTROL_CONSUMER_ENABLE);

        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_STATUS_OFFSET, read_data);
            if ((read_data & PL_CONTROL_CONSUMER_BUSY) != 0) begin
                i = 200000;
            end
        end
        ctl_read(PL_CONTROL_CONSUMER_STATUS_OFFSET, read_data);
        if ((read_data & PL_CONTROL_CONSUMER_BUSY) == 0) begin
            $fatal(1, "consumer did not become busy");
        end

        ctl_read(PL_CONTROL_WRITE_BANK_VALID_OFFSET, read_data);
        if (read_data != 32'h0000_0001) begin
            $fatal(1, "write bank should be valid while only active bank is busy: %08x", read_data);
        end
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, second_write_bank);
        for (i = 0; i < OUTPUT_COUNT * PIXELS_PER_OUTPUT; i = i + 1) begin
            word_addr = (second_write_bank * bank_words) + i;
            ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0102_0304 + i);
        end
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (second_write_bank << 31) | 32'h0000_0005);
        ctl_read(PL_CONTROL_FRAME_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0002) begin
            $fatal(1, "second valid commit left frame count %08x", read_data);
        end
        ctl_read(PL_CONTROL_WRITE_BANK_VALID_OFFSET, read_data);
        if (read_data != 32'h0000_0000) begin
            $fatal(1, "write bank should be invalid after both banks are owned: %08x", read_data);
        end
        ctl_read(PL_CONTROL_BUSY_BANK_OFFSET, read_data);
        if (read_data != write_bank) begin
            $fatal(1, "busy bank is %08x expected %08x", read_data, write_bank);
        end

        ctl_write(PL_CONTROL_FRAME_DROP_NOTIFY_OFFSET, 32'h0000_0001);
        ctl_read(PL_CONTROL_FRAME_DROPPED_OFFSET, read_data);
        if (read_data != 32'h0000_0001) begin
            $fatal(1, "frame dropped count is %08x", read_data);
        end

        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (read_data << 31) | 32'h0000_0005);
        ctl_read(PL_CONTROL_STATUS_OFFSET, read_data);
        if ((read_data & PL_CONTROL_STATUS_COMMIT_REJECTED) == 0) begin
            $fatal(1, "invalid commit did not set commit rejected: %08x", read_data);
        end
        ctl_read(PL_CONTROL_FRAME_REJECTED_OFFSET, read_data);
        if (read_data != 32'h0000_0001) begin
            $fatal(1, "frame rejected count is %08x", read_data);
        end
        ctl_read(PL_CONTROL_FRAME_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0002) begin
            $fatal(1, "rejected commit changed frame count to %08x", read_data);
        end
        ctl_write(PL_CONTROL_CONTROL_OFFSET, PL_CONTROL_CONTROL_CLEAR_ERRORS);
        ctl_read(PL_CONTROL_STATUS_OFFSET, read_data);
        if (read_data != PL_CONTROL_STATUS_READY) begin
            $fatal(1, "clear after rejected commit left status %08x", read_data);
        end

        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
            if (read_data == 32'h0000_0002) begin
                ctl_read(PL_CONTROL_CONSUMER_ERROR_COUNT_OFFSET, read_data);
                if (read_data != 32'h0000_0000) begin
                    $fatal(1, "consumer error count is %08x", read_data);
                end
                ctl_read(PL_CONTROL_CONSUMER_SEQUENCE_OFFSET, read_data);
                if (read_data != 32'h0000_0002) begin
                    $fatal(1, "consumer sequence is %08x", read_data);
                end
                check_expected_reads("mixed-length 4-output");
                i = 200000;
            end
        end

        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, OUTPUT_COUNT);
        for (i = 0; i < OUTPUT_COUNT; i = i + 1) begin
            ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + (i[AXIL_ADDR_WIDTH-1:0] << 2), 32'h0000_0001);
        end
        clear_expected_reads();
        for (i = 0; i < OUTPUT_COUNT; i = i + 1) begin
            expect_output_length(i, 1);
        end
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        for (i = 0; i < OUTPUT_COUNT * PIXELS_PER_OUTPUT; i = i + 1) begin
            word_addr = (read_data * bank_words) + i;
            ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0203_0405 + i);
        end
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (read_data << 31) | 32'h0000_003b);
        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
            if (read_data == 32'h0000_0003) begin
                i = 200000;
            end
        end
        ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0003) begin
            $fatal(1, "30-output consumer frame did not complete");
        end
        check_expected_reads("30-output length-1");

        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, OUTPUT_COUNT);
        for (i = 0; i < OUTPUT_COUNT; i = i + 1) begin
            ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + (i[AXIL_ADDR_WIDTH-1:0] << 2), 32'h0000_0000);
        end
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h000, 32'h0000_0001);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + 12'h008, 32'h0000_0001);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + ((OUTPUT_COUNT - 1) << 2), 32'h0000_0001);
        clear_expected_reads();
        expect_output_length(0, 1);
        expect_output_length(2, 1);
        expect_output_length(OUTPUT_COUNT - 1, 1);
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        for (i = 0; i < OUTPUT_COUNT * PIXELS_PER_OUTPUT; i = i + 1) begin
            word_addr = (read_data * bank_words) + i;
            ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0405_0607 + i);
        end
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (read_data << 31) | 32'h0000_003b);
        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
            if (read_data == 32'h0000_0004) begin
                i = 200000;
            end
        end
        ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0004) begin
            $fatal(1, "30-output sparse consumer frame did not complete");
        end
        check_expected_reads("30-output sparse");

        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, 32'h0000_0001);
        ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET, 32'h0000_0001);
        clear_expected_reads();
        expect_output_length(0, 1);
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        word_addr = read_data * bank_words;
        ram_write(word_addr[FRAME_ADDR_WIDTH-3:0] << 2, 32'h0304_0506);
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (read_data << 31) | 32'h0000_0001);
        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
            if (read_data == 32'h0000_0005) begin
                i = 200000;
            end
        end
        ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
        if (read_data != 32'h0000_0005) begin
            $fatal(1, "1-output consumer frame did not complete");
        end
        check_expected_reads("1-output");

        ctl_write(PL_CONTROL_ACTIVE_OUTPUT_COUNT_OFFSET, 32'h0000_0000);
        for (i = 0; i < OUTPUT_COUNT; i = i + 1) begin
            ctl_write(PL_CONTROL_STRAND_PIXEL_COUNT_OFFSET + (i[AXIL_ADDR_WIDTH-1:0] << 2), 32'h0000_0000);
        end
        monitor_no_frame_reads <= 1'b1;
        monitor_expected_reads <= 1'b0;
        ctl_read(PL_CONTROL_WRITE_BANK_OFFSET, read_data);
        ctl_write(PL_CONTROL_FRAME_COMMIT_OFFSET, (read_data << 31));
        ctl_read(PL_CONTROL_COMMITTED_WORDS_OFFSET, read_data);
        if (read_data != 32'h0000_0000) begin
            $fatal(1, "zero-active commit words is %08x", read_data);
        end

        for (i = 0; i < 200000; i = i + 1) begin
            ctl_read(PL_CONTROL_CONSUMER_FRAME_COUNT_OFFSET, read_data);
            if (read_data == 32'h0000_0006) begin
                ctl_read(PL_CONTROL_CONSUMER_ERROR_COUNT_OFFSET, read_data);
                if (read_data != 32'h0000_0000) begin
                    $fatal(1, "zero-active consumer error count is %08x", read_data);
                end
                $display("WS281x consumer simulation passed");
                $finish;
            end
        end

        ctl_read(PL_CONTROL_CONSUMER_STATUS_OFFSET, read_data);
        $display("CONSUMER_STATUS=%08x", read_data);
        ctl_read(PL_CONTROL_CONSUMER_DEBUG_OFFSET, read_data);
        $display("CONSUMER_DEBUG=%08x", read_data);
        ctl_read(PL_CONTROL_FRAME_COUNT_OFFSET, read_data);
        $display("FRAME_COUNT=%08x", read_data);
        ctl_read(PL_CONTROL_COMMITTED_WORDS_OFFSET, read_data);
        $display("COMMITTED_WORDS=%08x", read_data);
        ctl_read(PL_CONTROL_ACTIVE_BANK_OFFSET, read_data);
        $display("ACTIVE_BANK=%08x", read_data);
        ctl_read(PL_CONTROL_FRAME_SEQUENCE_OFFSET, read_data);
        $display("FRAME_SEQUENCE=%08x", read_data);
        $fatal(1, "consumer did not complete");
    end
endmodule
