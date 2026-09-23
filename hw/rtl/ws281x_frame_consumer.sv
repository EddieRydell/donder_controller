`timescale 1ns / 1ps

module ws281x_frame_consumer #(
    parameter FRAME_WORDS = donder_pl_contract_pkg::FRAME_WORDS,
    parameter FRAME_ADDR_WIDTH = donder_pl_contract_pkg::FRAME_ADDR_WIDTH,
    parameter OUTPUT_COUNT = donder_pl_contract_pkg::OUTPUT_COUNT,
    parameter PIXELS_PER_OUTPUT = donder_pl_contract_pkg::PIXELS_PER_OUTPUT,
    parameter CLK_HZ = 100000000,
    parameter WS281X_BIT_RATE = donder_pl_contract_pkg::WS281X_BIT_RATE
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    input  wire                       enable,
    input  wire                       reset_pulse,
    input  wire [31:0]                active_bank,
    input  wire [31:0]                committed_words,
    input  wire [31:0]                frame_sequence,
    input  wire [$clog2(OUTPUT_COUNT+1)-1:0] runtime_active_output_count,
    input  wire [(OUTPUT_COUNT*$clog2(PIXELS_PER_OUTPUT+1))-1:0] runtime_strand_pixel_count,
    input  wire [OUTPUT_COUNT-1:0]    runtime_output_invert_mask,

    output wire                       busy,
    output wire                       reset_low,
    output logic                      error_pulse,
    output logic [31:0]               consumer_sequence,
    output logic [31:0]               consumer_frame_count,
    output logic [31:0]               consumer_error_count,
    output logic [31:0]               consumer_active_bank,
    output wire [31:0]                consumer_debug,

    output wire [OUTPUT_COUNT-1:0]    ws281x_data,

    output logic [FRAME_ADDR_WIDTH-1:0] m_frame_araddr,
    output logic                       m_frame_arvalid,
    input  wire                       m_frame_arready,
    input  wire [31:0]                m_frame_rdata,
    input  wire [1:0]                 m_frame_rresp,
    input  wire                       m_frame_rvalid,
    output wire                       m_frame_rready
);

    localparam [31:0] FRAME_WORDS_PER_BANK = donder_pl_contract_pkg::FRAME_WORDS_PER_BANK;
    localparam integer WS_BIT_CYCLES = CLK_HZ / WS281X_BIT_RATE;
    localparam integer WS_T0H_CYCLES = 35;
    localparam integer WS_T1H_CYCLES = 70;
    localparam integer WS_RESET_CYCLES = 28000;
    localparam [31:0] NO_BUSY_BANK = 32'hffff_ffff;
    localparam integer ACTIVE_OUTPUT_WIDTH = $clog2(OUTPUT_COUNT + 1);
    localparam integer PIXEL_COUNT_WIDTH = $clog2(PIXELS_PER_OUTPUT + 1);
    localparam integer OUTPUT_INDEX_WIDTH = (OUTPUT_COUNT <= 1) ? 1 : $clog2(OUTPUT_COUNT);

    localparam [2:0] TX_IDLE = 3'd0;
    localparam [2:0] TX_LOAD_FIRST = 3'd1;
    localparam [2:0] TX_SEND = 3'd2;
    localparam [2:0] TX_RESET = 3'd3;
    localparam [2:0] TX_ERROR = 3'd4;
    localparam [2:0] TX_VALIDATE = 3'd5;
    localparam [2:0] TX_COMPUTE_CONFIG = 3'd6;

    localparam [2:0] RD_IDLE = 3'd0;
    localparam [2:0] RD_SCAN = 3'd1;
    localparam [2:0] RD_ADDR_PREP = 3'd2;
    localparam [2:0] RD_ADDR = 3'd3;
    localparam [2:0] RD_DATA = 3'd4;

    logic [2:0] tx_state_reg;
    logic [2:0] rd_state_reg;
    logic [31:0] tx_sequence_reg;
    logic [31:0] tx_active_bank_reg;
    logic [PIXEL_COUNT_WIDTH-1:0] pixel_index_reg;
    logic [PIXEL_COUNT_WIDTH-1:0] read_pixel_index_reg;
    logic [31:0] bit_cycle_reg;
    logic [4:0] bit_index_reg;
    logic [31:0] reset_cycle_reg;
    logic [ACTIVE_OUTPUT_WIDTH-1:0] read_output_reg;
    logic [ACTIVE_OUTPUT_WIDTH-1:0] scan_output_reg;
    logic [31:0] scan_base_word_reg;
    logic [31:0] frame_bank_base_words_reg;
    logic [31:0] selected_output_base_word_reg;
    logic [31:0] current_pixel_reg [0:OUTPUT_COUNT-1];
    logic [31:0] next_pixel_reg [0:OUTPUT_COUNT-1];
    logic [ACTIVE_OUTPUT_WIDTH-1:0] frame_active_output_count_reg;
    logic [PIXEL_COUNT_WIDTH-1:0] frame_strand_pixel_count_reg [0:OUTPUT_COUNT-1];
    logic [PIXEL_COUNT_WIDTH-1:0] frame_max_pixels_reg;
    logic [31:0] frame_required_words_reg;
    logic [31:0] output_frame_base_words_reg [0:OUTPUT_COUNT-1];
    logic [OUTPUT_COUNT-1:0] frame_output_invert_mask_reg;
    logic [OUTPUT_COUNT-1:0] current_active_mask_reg;
    logic [OUTPUT_COUNT-1:0] next_active_mask_reg;
    logic next_pixel_valid_reg;
    logic read_active_reg;
    logic [OUTPUT_COUNT-1:0] ws281x_data_reg;
    logic [ACTIVE_OUTPUT_WIDTH-1:0] config_scan_output_reg;
    logic [31:0] config_next_base_word_reg;

    wire frame_read_address_fire;
    wire frame_read_data_fire;
    wire [9:0] debug_pixel_index;
    integer output_index;

    assign ws281x_data = ws281x_data_reg ^ frame_output_invert_mask_reg;
    assign m_frame_rready = 1'b1;
    assign busy = tx_state_reg != TX_IDLE;
    assign reset_low = tx_state_reg == TX_RESET;
    assign debug_pixel_index = pixel_index_reg;
    assign consumer_debug = {8'h00, tx_state_reg, rd_state_reg, next_pixel_valid_reg, read_active_reg, bit_index_reg, debug_pixel_index};
    assign frame_read_address_fire = rd_state_reg == RD_ADDR && m_frame_arvalid && m_frame_arready;
    assign frame_read_data_fire = m_frame_rvalid && (rd_state_reg == RD_DATA || frame_read_address_fire);

    function automatic [23:0] grb_word(input [31:0] rgb_word);
        grb_word = {rgb_word[15:8], rgb_word[23:16], rgb_word[7:0]};
    endfunction

    function automatic ws_bit_value(input [31:0] rgb_word, input [4:0] bit_index);
        logic [23:0] grb;
        begin
            grb = grb_word(rgb_word);
            ws_bit_value = grb[23 - bit_index];
        end
    endfunction

    always_ff @(posedge aclk) begin
        logic [31:0] next_read_word;

        if (!aresetn) begin
            tx_state_reg <= TX_IDLE;
            rd_state_reg <= RD_IDLE;
            tx_sequence_reg <= 32'h0000_0000;
            tx_active_bank_reg <= 32'h0000_0000;
            pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
            read_pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
            bit_cycle_reg <= 32'h0000_0000;
            bit_index_reg <= 5'd0;
            reset_cycle_reg <= 32'h0000_0000;
            read_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
            scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
            scan_base_word_reg <= 32'h0000_0000;
            frame_bank_base_words_reg <= 32'h0000_0000;
            selected_output_base_word_reg <= 32'h0000_0000;
            frame_active_output_count_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
            frame_max_pixels_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
            frame_required_words_reg <= 32'h0000_0000;
            config_scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
            config_next_base_word_reg <= 32'h0000_0000;
            frame_output_invert_mask_reg <= {OUTPUT_COUNT{1'b0}};
            current_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
            next_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
            next_pixel_valid_reg <= 1'b0;
            read_active_reg <= 1'b0;
            ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
            m_frame_araddr <= {FRAME_ADDR_WIDTH{1'b0}};
            m_frame_arvalid <= 1'b0;
            error_pulse <= 1'b0;
            consumer_sequence <= 32'h0000_0000;
            consumer_frame_count <= 32'h0000_0000;
            consumer_error_count <= 32'h0000_0000;
            consumer_active_bank <= NO_BUSY_BANK;
            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                current_pixel_reg[output_index] <= 32'h0000_0000;
                next_pixel_reg[output_index] <= 32'h0000_0000;
                frame_strand_pixel_count_reg[output_index] <= {PIXEL_COUNT_WIDTH{1'b0}};
                output_frame_base_words_reg[output_index] <= 32'h0000_0000;
            end
        end else begin
            error_pulse <= 1'b0;

            if (reset_pulse) begin
                tx_state_reg <= TX_IDLE;
                rd_state_reg <= RD_IDLE;
                m_frame_arvalid <= 1'b0;
                next_pixel_valid_reg <= 1'b0;
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                consumer_active_bank <= NO_BUSY_BANK;
            end

            if (tx_state_reg == TX_IDLE && enable && frame_sequence != consumer_sequence) begin
                tx_sequence_reg <= frame_sequence;
                tx_active_bank_reg <= active_bank;
                pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                read_pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                read_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                scan_base_word_reg <= 32'h0000_0000;
                frame_bank_base_words_reg <= active_bank[0] ? FRAME_WORDS_PER_BANK : 32'h0000_0000;
                selected_output_base_word_reg <= 32'h0000_0000;
                frame_active_output_count_reg <= runtime_active_output_count;
                frame_max_pixels_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                frame_required_words_reg <= 32'h0000_0000;
                config_scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                config_next_base_word_reg <= 32'h0000_0000;
                frame_output_invert_mask_reg <= runtime_output_invert_mask;
                current_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
                next_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
                next_pixel_valid_reg <= 1'b0;
                read_active_reg <= 1'b0;
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_IDLE;
                tx_state_reg <= TX_COMPUTE_CONFIG;
                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                    current_pixel_reg[output_index] <= 32'h0000_0000;
                    next_pixel_reg[output_index] <= 32'h0000_0000;
                    frame_strand_pixel_count_reg[output_index] <= runtime_strand_pixel_count[output_index*PIXEL_COUNT_WIDTH +: PIXEL_COUNT_WIDTH];
                end
            end

            if (tx_state_reg == TX_COMPUTE_CONFIG) begin
                output_frame_base_words_reg[config_scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]] <= config_next_base_word_reg;
                config_next_base_word_reg <= config_next_base_word_reg + PIXELS_PER_OUTPUT;
                if (config_scan_output_reg < frame_active_output_count_reg
                    && frame_strand_pixel_count_reg[config_scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]] != {PIXEL_COUNT_WIDTH{1'b0}}) begin
                    if (frame_strand_pixel_count_reg[config_scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]] > frame_max_pixels_reg) begin
                        frame_max_pixels_reg <= frame_strand_pixel_count_reg[config_scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]];
                    end
                    frame_required_words_reg <= config_next_base_word_reg
                        + frame_strand_pixel_count_reg[config_scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]];
                end
                if (config_scan_output_reg == ACTIVE_OUTPUT_WIDTH'(OUTPUT_COUNT - 1)) begin
                    tx_state_reg <= TX_VALIDATE;
                end else begin
                    config_scan_output_reg <= config_scan_output_reg + ACTIVE_OUTPUT_WIDTH'(1);
                end
            end

            if (tx_state_reg == TX_VALIDATE) begin
                if (committed_words >= frame_required_words_reg) begin
                    consumer_active_bank <= tx_active_bank_reg;
                    if (frame_max_pixels_reg == {PIXEL_COUNT_WIDTH{1'b0}}) begin
                        reset_cycle_reg <= 32'h0000_0000;
                        tx_state_reg <= TX_RESET;
                        rd_state_reg <= RD_IDLE;
                        m_frame_arvalid <= 1'b0;
                        read_active_reg <= 1'b0;
                    end else begin
                        read_active_reg <= 1'b1;
                        tx_state_reg <= TX_LOAD_FIRST;
                    end
                end else begin
                    consumer_sequence <= tx_sequence_reg;
                    consumer_error_count <= consumer_error_count + 32'd1;
                    error_pulse <= 1'b1;
                    tx_state_reg <= TX_IDLE;
                end
            end

            if (rd_state_reg == RD_SCAN) begin
                if (scan_output_reg == ACTIVE_OUTPUT_WIDTH'(OUTPUT_COUNT)) begin
                    rd_state_reg <= RD_IDLE;
                    if (read_active_reg) begin
                        read_active_reg <= 1'b0;
                    end else begin
                        next_pixel_valid_reg <= 1'b1;
                    end
                end else begin
                    if (scan_output_reg < frame_active_output_count_reg
                        && read_pixel_index_reg < frame_strand_pixel_count_reg[scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]]) begin
                        read_output_reg <= scan_output_reg;
                        selected_output_base_word_reg <= scan_base_word_reg;
                        if (read_active_reg) begin
                            current_active_mask_reg[scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]] <= 1'b1;
                        end else begin
                            next_active_mask_reg[scan_output_reg[OUTPUT_INDEX_WIDTH-1:0]] <= 1'b1;
                        end
                        scan_output_reg <= scan_output_reg + ACTIVE_OUTPUT_WIDTH'(1);
                        scan_base_word_reg <= scan_base_word_reg + PIXELS_PER_OUTPUT;
                        rd_state_reg <= RD_ADDR_PREP;
                    end else begin
                        scan_output_reg <= scan_output_reg + ACTIVE_OUTPUT_WIDTH'(1);
                        scan_base_word_reg <= scan_base_word_reg + PIXELS_PER_OUTPUT;
                    end
                end
            end

            if (rd_state_reg == RD_ADDR_PREP) begin
                next_read_word = frame_bank_base_words_reg + selected_output_base_word_reg + read_pixel_index_reg;
                m_frame_araddr <= next_read_word[FRAME_ADDR_WIDTH-3:0] << 2;
                m_frame_arvalid <= 1'b1;
                rd_state_reg <= RD_ADDR;
            end

            if (frame_read_address_fire) begin
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_DATA;
            end

            if (frame_read_data_fire) begin
                if (m_frame_rresp != 2'b00) begin
                    tx_state_reg <= TX_ERROR;
                    rd_state_reg <= RD_IDLE;
                    consumer_error_count <= consumer_error_count + 32'd1;
                    error_pulse <= 1'b1;
                end else begin
                    if (read_active_reg) begin
                        current_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end else begin
                        next_pixel_reg[read_output_reg] <= m_frame_rdata;
                    end

                    rd_state_reg <= RD_SCAN;
                end
            end

            case (tx_state_reg)
            TX_LOAD_FIRST: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                if (rd_state_reg == RD_IDLE && read_active_reg && !m_frame_arvalid) begin
                    read_pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                    scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                    scan_base_word_reg <= 32'h0000_0000;
                    current_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
                    rd_state_reg <= RD_SCAN;
                end else if (rd_state_reg == RD_IDLE && !read_active_reg) begin
                    pixel_index_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                    bit_index_reg <= 5'd0;
                    bit_cycle_reg <= 32'h0000_0000;
                    tx_state_reg <= TX_SEND;
                    if (frame_max_pixels_reg > PIXEL_COUNT_WIDTH'(1)) begin
                        read_pixel_index_reg <= PIXEL_COUNT_WIDTH'(1);
                        next_pixel_valid_reg <= 1'b0;
                        next_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
                        scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                        scan_base_word_reg <= 32'h0000_0000;
                        for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                            next_pixel_reg[output_index] <= 32'h0000_0000;
                        end
                        rd_state_reg <= RD_SCAN;
                    end
                end
            end
            TX_SEND: begin
                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                    ws281x_data_reg[output_index] <= current_active_mask_reg[output_index]
                        && bit_cycle_reg < (ws_bit_value(current_pixel_reg[output_index], bit_index_reg) ? WS_T1H_CYCLES : WS_T0H_CYCLES);
                end

                if (bit_cycle_reg == WS_BIT_CYCLES - 1) begin
                    bit_cycle_reg <= 32'h0000_0000;
                    if (bit_index_reg == 5'd23) begin
                        bit_index_reg <= 5'd0;
                        ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                        if (pixel_index_reg == frame_max_pixels_reg - PIXEL_COUNT_WIDTH'(1)) begin
                            tx_state_reg <= TX_RESET;
                            reset_cycle_reg <= 32'h0000_0000;
                        end else if (next_pixel_valid_reg) begin
                            for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                                current_pixel_reg[output_index] <= next_pixel_reg[output_index];
                            end
                            current_active_mask_reg <= next_active_mask_reg;
                            pixel_index_reg <= pixel_index_reg + PIXEL_COUNT_WIDTH'(1);
                            next_pixel_valid_reg <= 1'b0;
                            if (pixel_index_reg + PIXEL_COUNT_WIDTH'(2) < frame_max_pixels_reg) begin
                                read_pixel_index_reg <= pixel_index_reg + PIXEL_COUNT_WIDTH'(2);
                                next_active_mask_reg <= {OUTPUT_COUNT{1'b0}};
                                scan_output_reg <= {ACTIVE_OUTPUT_WIDTH{1'b0}};
                                scan_base_word_reg <= 32'h0000_0000;
                                for (output_index = 0; output_index < OUTPUT_COUNT; output_index = output_index + 1) begin
                                    next_pixel_reg[output_index] <= 32'h0000_0000;
                                end
                                rd_state_reg <= RD_SCAN;
                            end
                        end else begin
                            tx_state_reg <= TX_ERROR;
                            consumer_error_count <= consumer_error_count + 32'd1;
                            error_pulse <= 1'b1;
                        end
                    end else begin
                        bit_index_reg <= bit_index_reg + 5'd1;
                    end
                end else begin
                    bit_cycle_reg <= bit_cycle_reg + 32'd1;
                end
            end
            TX_RESET: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                if (reset_cycle_reg == WS_RESET_CYCLES - 1) begin
                    consumer_sequence <= tx_sequence_reg;
                    consumer_frame_count <= consumer_frame_count + 32'd1;
                    consumer_active_bank <= NO_BUSY_BANK;
                    tx_state_reg <= TX_IDLE;
                end else begin
                    reset_cycle_reg <= reset_cycle_reg + 32'd1;
                end
            end
            TX_ERROR: begin
                ws281x_data_reg <= {OUTPUT_COUNT{1'b0}};
                m_frame_arvalid <= 1'b0;
                rd_state_reg <= RD_IDLE;
                consumer_active_bank <= NO_BUSY_BANK;
                tx_state_reg <= TX_IDLE;
            end
            default: begin
            end
            endcase
        end
    end

endmodule
