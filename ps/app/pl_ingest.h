#ifndef PL_INGEST_H
#define PL_INGEST_H

#include <stddef.h>
#include <stdint.h>

#include "generated/pl_config.h"
#include "pl_control.h"

typedef enum {
    PL_INGEST_OK = 0,
    PL_INGEST_BAD_ID = -1,
    PL_INGEST_BAD_VERSION = -2,
    PL_INGEST_BAD_STATUS = -3,
    PL_INGEST_CAPACITY_TOO_SMALL = -4,
    PL_INGEST_READBACK_FAILED = -5,
    PL_INGEST_COMMIT_FAILED = -7,
    PL_INGEST_CONSUMER_FAILED = -8,
    PL_INGEST_BAD_ARGUMENT = -9,
    PL_INGEST_NO_FREE_BANK = -10,
} pl_ingest_result_t;

typedef struct {
    uint32_t id;
    uint32_t version;
    uint32_t status;
    uint32_t capacity_words;
    uint32_t bank_words;
    uint32_t active_bank;
    uint32_t write_bank;
    uint32_t write_bank_valid;
    uint32_t busy_bank;
    uint32_t frame_sequence;
    uint32_t frame_count;
    uint32_t committed_words;
    uint32_t error_count;
    uint32_t frame_dropped;
    uint32_t frame_rejected;
    uint32_t consumer_status;
    uint32_t consumer_sequence;
    uint32_t consumer_frame_count;
    uint32_t consumer_error_count;
    uint32_t active_output_count;
    uint32_t strand_pixel_count[DONDER_PL_OUTPUT_COUNT];
    uint32_t config_status;
    uint32_t strand_length_clamped[DONDER_PL_MASK_WORD_COUNT];
    uint32_t output_invert_mask[DONDER_PL_MASK_WORD_COUNT];
} pl_ingest_snapshot_t;

typedef struct {
    uint32_t max_output_count;
    uint32_t max_pixels_per_output;
    uint32_t active_output_count;
    uint32_t strand_pixel_count[DONDER_PL_OUTPUT_COUNT];
    uint32_t effective_active_output_count;
    uint32_t effective_strand_pixel_count[DONDER_PL_OUTPUT_COUNT];
    uint32_t required_words;
    uint32_t config_status;
    uint32_t strand_length_clamped[DONDER_PL_MASK_WORD_COUNT];
    uint32_t output_invert_mask[DONDER_PL_MASK_WORD_COUNT];
} pl_ingest_config_t;

typedef struct {
    uint32_t last_write_us;
    uint32_t max_write_us;
    uint32_t last_active_words;
    uint32_t last_required_words;
    uint32_t no_free_bank_waits;
    uint32_t no_free_bank_drops;
} pl_ingest_write_stats_t;

uint32_t pl_ingest_read(uint32_t offset);
void pl_ingest_write(uint32_t offset, uint32_t value);
void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot);
const pl_ingest_write_stats_t *pl_ingest_write_stats(void);
pl_ingest_result_t pl_ingest_init(uint32_t required_words);
pl_ingest_result_t pl_ingest_self_test(void);
pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count);
pl_ingest_result_t pl_ingest_write_frame_strands(const uint32_t *words,
                                                 uint32_t active_count,
                                                 const uint32_t lengths[DONDER_PL_OUTPUT_COUNT],
                                                 uint32_t pixels_per_output,
                                                 uint32_t required_words);
pl_ingest_result_t pl_ingest_configure_strands(uint32_t active_count, const uint32_t lengths[DONDER_PL_OUTPUT_COUNT]);
pl_ingest_result_t pl_ingest_configure_output_invert_mask(uint32_t invert_mask);
pl_ingest_result_t pl_ingest_get_config(pl_ingest_config_t *config);
pl_ingest_result_t pl_ingest_enable_consumer(void);
void pl_ingest_drive_pins(uint32_t value);

#endif
