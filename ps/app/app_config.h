#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stdint.h>

#include "generated/pl_config.h"

#define DONDER_OUTPUT_COUNT DONDER_PL_OUTPUT_COUNT
#define DONDER_PIN_OUTPUT_COUNT DONDER_PL_PIN_OUTPUT_COUNT
#define DONDER_PIXELS_PER_OUTPUT DONDER_PL_PIXELS_PER_OUTPUT
#define DONDER_WORDS_PER_FRAME DONDER_PL_FRAME_WORDS_PER_BANK
#define DONDER_DEFAULT_ACTIVE_OUTPUT_COUNT DONDER_PL_DEFAULT_ACTIVE_OUTPUT_COUNT
#define DONDER_DEFAULT_STRAND_PIXEL_COUNT DONDER_PL_DEFAULT_STRAND_PIXEL_COUNT
#define DONDER_OUTPUT_INVERT_MASK DONDER_PL_DEFAULT_OUTPUT_INVERT_MASK

#define DONDER_E131_PORT DONDER_PL_E131_PORT
#define DONDER_FIRST_UNIVERSE DONDER_PL_E131_FIRST_UNIVERSE
#define DONDER_SLOTS_PER_UNIVERSE DONDER_PL_E131_SLOTS_PER_UNIVERSE
#define DONDER_E131_BLACKOUT_TIMEOUT_MS DONDER_PL_E131_BLACKOUT_TIMEOUT_MS
#define DONDER_E131_ACCEPT_PREVIEW DONDER_PL_E131_ACCEPT_PREVIEW
#define DONDER_E131_DEFAULT_SYNC_ADDRESS DONDER_PL_E131_DEFAULT_SYNC_ADDRESS
#define DONDER_HOST_TEST_IP0 DONDER_PL_HOST_IP0
#define DONDER_HOST_TEST_IP1 DONDER_PL_HOST_IP1
#define DONDER_HOST_TEST_IP2 DONDER_PL_HOST_IP2
#define DONDER_HOST_TEST_IP3 DONDER_PL_HOST_IP3

typedef struct {
    uint32_t output_count;
    uint32_t pin_output_count;
    uint32_t pixels_per_output;
    uint32_t words_per_frame;
    uint32_t default_active_output_count;
    uint32_t default_strand_pixel_count;
    uint32_t output_invert_mask;
    uint16_t e131_port;
    uint16_t first_universe;
    uint8_t mac[6];
    uint8_t ip[4];
    uint8_t netmask[4];
    uint8_t gateway[4];
    uint8_t host_test_ip[4];
} app_config_t;

extern const app_config_t g_app_config;

#endif
