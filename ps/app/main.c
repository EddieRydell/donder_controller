#include <stdint.h>

#include "app_config.h"
#include "ethernet_receiver.h"
#include "frame_pipeline.h"
#include "pl_ingest.h"
#include "sleep.h"
#include "xil_printf.h"

static void fatal(const char *message, int code)
{
    xil_printf("FATAL %s code=%d\r\n", message, code);
    while (1) {
        usleep(100000u);
    }
}

int main(void)
{
    uint32_t last_status_ms;

    xil_printf("\r\ndonder controller starting\r\n");
    xil_printf("max_outputs=%u pin_outputs=%u max_pixels_per_output=%u max_frame_words=%u default_active=%u default_pixels=%u output_invert_mask=0x%08x e131_port=%u first_universe=%u board_ip=%u.%u.%u.%u host_test_ip=%u.%u.%u.%u\r\n",
               (unsigned int)g_app_config.output_count,
               (unsigned int)g_app_config.pin_output_count,
               (unsigned int)g_app_config.pixels_per_output,
               (unsigned int)g_app_config.words_per_frame,
               (unsigned int)g_app_config.default_active_output_count,
               (unsigned int)g_app_config.default_strand_pixel_count,
               (unsigned int)g_app_config.output_invert_mask,
               (unsigned int)g_app_config.e131_port,
               (unsigned int)g_app_config.first_universe,
               g_app_config.ip[0], g_app_config.ip[1], g_app_config.ip[2], g_app_config.ip[3],
               g_app_config.host_test_ip[0], g_app_config.host_test_ip[1],
               g_app_config.host_test_ip[2], g_app_config.host_test_ip[3]);

    pl_ingest_result_t init_result = pl_ingest_init(g_app_config.words_per_frame);
    if (init_result != PL_INGEST_OK) {
        fatal("pl_init", init_result);
    }

    pl_ingest_result_t self_test_result = pl_ingest_self_test();
    if (self_test_result != PL_INGEST_OK) {
        fatal("pl_self_test", self_test_result);
    }
    if (pl_ingest_configure_output_invert_mask(g_app_config.output_invert_mask) != PL_INGEST_OK) {
        fatal("pl_output_invert", -1);
    }

    if (frame_pipeline_init() != 0) {
        fatal("frame_pipeline_config", -1);
    }
    uint32_t expected_universes = ((frame_pipeline_active_pixel_count() * 3u) + DONDER_SLOTS_PER_UNIVERSE - 1u) / DONDER_SLOTS_PER_UNIVERSE;
    xil_printf("strand_config active_outputs=%u first_lengths=[%u,%u,%u,%u] total_pixels=%u e131_channels=%u expected_universes=%u required_commit_words=%u\r\n",
               (unsigned int)frame_pipeline_active_output_count(),
               (unsigned int)frame_pipeline_strand_pixel_count(0u),
               (unsigned int)frame_pipeline_strand_pixel_count(1u),
               (unsigned int)frame_pipeline_strand_pixel_count(2u),
               (unsigned int)frame_pipeline_strand_pixel_count(3u),
               (unsigned int)frame_pipeline_active_pixel_count(),
               (unsigned int)(frame_pipeline_active_pixel_count() * 3u),
               (unsigned int)expected_universes,
               (unsigned int)frame_pipeline_required_words());
    frame_pipeline_clear_all(0u);
    if (frame_pipeline_commit() != 0) {
        fatal("initial_frame_commit", -1);
    }

    if (ethernet_receiver_init() != 0) {
        fatal("ethernet_init", -1);
    }

    pl_ingest_result_t consumer_result = pl_ingest_enable_consumer();
    if (consumer_result != PL_INGEST_OK) {
        fatal("pl_enable_consumer", consumer_result);
    }
    xil_printf("foundation ready source=e131\r\n");
    ethernet_receiver_print_status();
    last_status_ms = ethernet_receiver_now_ms();

    while (1) {
        uint32_t now_ms;

        ethernet_receiver_poll();
        now_ms = ethernet_receiver_now_ms();
        if ((uint32_t)(now_ms - last_status_ms) >= 1000u) {
            ethernet_receiver_print_status();
            last_status_ms = now_ms;
        }
    }
}
