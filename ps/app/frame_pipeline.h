#ifndef FRAME_PIPELINE_H
#define FRAME_PIPELINE_H

#include <stdint.h>

#include "app_config.h"

int frame_pipeline_init(void);
uint32_t *frame_pipeline_inactive_words(void);
uint32_t frame_pipeline_active_output_count(void);
uint32_t frame_pipeline_active_pixel_count(void);
uint32_t frame_pipeline_required_words(void);
uint32_t frame_pipeline_strand_pixel_count(uint32_t output);
void frame_pipeline_clear_all(uint32_t rgb_word);
int frame_pipeline_write_linear_rgb(uint32_t first_pixel, const uint8_t *rgb_slots, uint32_t rgb_pixel_count);
int frame_pipeline_commit(void);
int frame_pipeline_configure(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT]);

#endif
