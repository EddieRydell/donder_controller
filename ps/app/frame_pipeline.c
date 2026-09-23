#include "frame_pipeline.h"

#include "pl_ingest.h"

static uint32_t g_frame_words[DONDER_PL_FRAME_BANKS][DONDER_WORDS_PER_FRAME];
static uint32_t g_write_bank;
static uint32_t g_active_output_count;
static uint32_t g_strand_pixel_count[DONDER_OUTPUT_COUNT];
static uint32_t g_output_base_word[DONDER_OUTPUT_COUNT];
static uint32_t g_linear_pixel_word_index[DONDER_WORDS_PER_FRAME];
static uint32_t g_required_words;
static uint32_t g_active_pixel_count;

static uint32_t clamp_u32(uint32_t value, uint32_t max_value)
{
    return value < max_value ? value : max_value;
}

static uint32_t required_words_for(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    uint32_t required_words = 0u;

    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        if (output < active_count && lengths[output] > 0u) {
            uint32_t required = g_output_base_word[output] + lengths[output];
            if (required > required_words) {
                required_words = required;
            }
        }
    }

    return required_words;
}

static void apply_local_config(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    g_active_output_count = clamp_u32(active_count, DONDER_OUTPUT_COUNT);
    g_active_pixel_count = 0u;
    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        g_output_base_word[output] = output == 0u ? 0u : (g_output_base_word[output - 1u] + DONDER_PIXELS_PER_OUTPUT);
        g_strand_pixel_count[output] = clamp_u32(lengths[output], DONDER_PIXELS_PER_OUTPUT);
        if (output < g_active_output_count) {
            for (uint32_t pixel = 0u; pixel < g_strand_pixel_count[output]; ++pixel) {
                g_linear_pixel_word_index[g_active_pixel_count] = g_output_base_word[output] + pixel;
                g_active_pixel_count++;
            }
        }
    }
    g_required_words = required_words_for(g_active_output_count, g_strand_pixel_count);
}

static void clear_inactive_frame(void)
{
    uint32_t *words = frame_pipeline_inactive_words();

    for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
        words[word] = 0u;
    }
}

int frame_pipeline_init(void)
{
    pl_ingest_config_t config;

    g_write_bank = 0u;
    for (uint32_t bank = 0u; bank < DONDER_PL_FRAME_BANKS; ++bank) {
        for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
            g_frame_words[bank][word] = 0u;
        }
    }

    if (pl_ingest_get_config(&config) != PL_INGEST_OK) {
        return -1;
    }
    apply_local_config(config.effective_active_output_count, config.effective_strand_pixel_count);
    return 0;
}

uint32_t *frame_pipeline_inactive_words(void)
{
    return g_frame_words[g_write_bank];
}

uint32_t frame_pipeline_active_output_count(void)
{
    return g_active_output_count;
}

uint32_t frame_pipeline_active_pixel_count(void)
{
    return g_active_pixel_count;
}

uint32_t frame_pipeline_required_words(void)
{
    return g_required_words;
}

uint32_t frame_pipeline_strand_pixel_count(uint32_t output)
{
    if (output >= DONDER_OUTPUT_COUNT) {
        return 0u;
    }
    return g_strand_pixel_count[output];
}

void frame_pipeline_clear_all(uint32_t rgb_word)
{
    uint32_t *words = frame_pipeline_inactive_words();

    rgb_word &= 0x00ffffffu;
    for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
        words[word] = rgb_word;
    }
}

int frame_pipeline_write_linear_rgb(uint32_t first_pixel, const uint8_t *rgb_slots, uint32_t rgb_pixel_count)
{
    if (rgb_slots == 0) {
        return -1;
    }

    for (uint32_t pixel = 0u; pixel < rgb_pixel_count; ++pixel) {
        uint32_t linear_pixel = first_pixel + pixel;
        uint32_t word_index;
        uint32_t word;

        if (linear_pixel >= g_active_pixel_count) {
            break;
        }
        word_index = g_linear_pixel_word_index[linear_pixel];

        word = ((uint32_t)rgb_slots[(pixel * 3u) + 0u] << 16)
             | ((uint32_t)rgb_slots[(pixel * 3u) + 1u] << 8)
             | ((uint32_t)rgb_slots[(pixel * 3u) + 2u] << 0);

        frame_pipeline_inactive_words()[word_index] = word;
    }

    return 0;
}

int frame_pipeline_commit(void)
{
    pl_ingest_result_t result = pl_ingest_write_frame_strands(frame_pipeline_inactive_words(),
                                                              g_active_output_count,
                                                              g_strand_pixel_count,
                                                              DONDER_PIXELS_PER_OUTPUT,
                                                              g_required_words);

    if (result == PL_INGEST_NO_FREE_BANK) {
        return 1;
    }
    if (result != PL_INGEST_OK) {
        return -1;
    }

    g_write_bank ^= 1u;
    return 0;
}

int frame_pipeline_configure(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    uint32_t new_active_count;
    uint32_t new_lengths[DONDER_OUTPUT_COUNT];
    int needs_black_frame = 0;

    if (lengths == 0) {
        return -1;
    }

    new_active_count = clamp_u32(active_count, DONDER_OUTPUT_COUNT);
    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        new_lengths[output] = clamp_u32(lengths[output], DONDER_PIXELS_PER_OUTPUT);
        if (output >= new_active_count) {
            new_lengths[output] = 0u;
        }
        if (output < g_active_output_count
            && (output >= new_active_count || new_lengths[output] < g_strand_pixel_count[output])) {
            needs_black_frame = 1;
        }
    }

    if (needs_black_frame) {
        int commit_result;
        clear_inactive_frame();
        commit_result = frame_pipeline_commit();
        if (commit_result != 0) {
            return commit_result;
        }
    }

    if (pl_ingest_configure_strands(active_count, lengths) != PL_INGEST_OK) {
        return -1;
    }

    apply_local_config(new_active_count, new_lengths);
    return 0;
}
