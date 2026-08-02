#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../app/frame_pipeline.h"
#include "../app/pl_ingest.h"

#define EXPECT_EQ(a, b) do { uint32_t av = (uint32_t)(a); uint32_t bv = (uint32_t)(b); if (av != bv) return fail_eq(__LINE__, #a, av, #b, bv); } while (0)

static uint32_t g_write_frame_calls;
static uint32_t g_configure_calls;
static uint32_t g_last_frame_active_count;
static uint32_t g_last_frame_lengths[DAWN_OUTPUT_COUNT];
static uint32_t g_last_frame_pixels_per_output;
static uint32_t g_last_frame_required_words;
static uint32_t g_last_frame_first_word;
static uint32_t g_last_frame_last_word;
static uint32_t g_last_configure_active_count;
static uint32_t g_last_configure_lengths[DAWN_OUTPUT_COUNT];

uint32_t pl_ingest_read(uint32_t offset)
{
    (void)offset;
    return 0u;
}

void pl_ingest_write(uint32_t offset, uint32_t value)
{
    (void)offset;
    (void)value;
}

void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot)
{
    memset(snapshot, 0, sizeof(*snapshot));
}

const pl_ingest_write_stats_t *pl_ingest_write_stats(void)
{
    static pl_ingest_write_stats_t stats;
    return &stats;
}

pl_ingest_result_t pl_ingest_get_config(pl_ingest_config_t *config)
{
    config->max_output_count = DAWN_OUTPUT_COUNT;
    config->max_pixels_per_output = DAWN_PIXELS_PER_OUTPUT;
    config->active_output_count = DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT;
    config->effective_active_output_count = DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT;
    config->required_words = 0u;
    config->config_status = 0u;
    for (uint32_t output = 0u; output < DAWN_OUTPUT_COUNT; ++output) {
        uint32_t length = output < DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT ? DAWN_DEFAULT_STRAND_PIXEL_COUNT : 0u;
        config->strand_pixel_count[output] = length;
        config->effective_strand_pixel_count[output] = length;
    }
    for (uint32_t word = 0u; word < DAWN_PL_MASK_WORD_COUNT; ++word) {
        config->strand_length_clamped[word] = 0u;
        config->output_invert_mask[word] = DAWN_OUTPUT_INVERT_MASK;
    }
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame_strands(const uint32_t *words,
                                                 uint32_t active_count,
                                                 const uint32_t lengths[DAWN_OUTPUT_COUNT],
                                                 uint32_t pixels_per_output,
                                                 uint32_t required_words)
{
    g_write_frame_calls++;
    g_last_frame_active_count = active_count;
    g_last_frame_pixels_per_output = pixels_per_output;
    g_last_frame_required_words = required_words;
    memcpy(g_last_frame_lengths, lengths, sizeof(g_last_frame_lengths));
    g_last_frame_first_word = required_words > 0u ? words[0] : 0u;
    g_last_frame_last_word = required_words > 0u ? words[required_words - 1u] : 0u;
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_configure_strands(uint32_t active_count, const uint32_t lengths[DAWN_OUTPUT_COUNT])
{
    g_configure_calls++;
    g_last_configure_active_count = active_count;
    memcpy(g_last_configure_lengths, lengths, sizeof(g_last_configure_lengths));
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_init(uint32_t required_words)
{
    (void)required_words;
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_self_test(void)
{
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count)
{
    (void)words;
    (void)word_count;
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_configure_output_invert_mask(uint32_t invert_mask)
{
    (void)invert_mask;
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_enable_consumer(void)
{
    return PL_INGEST_OK;
}

void pl_ingest_drive_pins(uint32_t value)
{
    (void)value;
}

static int fail_eq(int line, const char *a, uint32_t av, const char *b, uint32_t bv)
{
    printf("FAIL line=%d %s=%u %s=%u\n", line, a, av, b, bv);
    return 1;
}

static int reset_state(void)
{
    g_write_frame_calls = 0u;
    g_configure_calls = 0u;
    g_last_frame_active_count = 0u;
    g_last_frame_pixels_per_output = 0u;
    g_last_frame_required_words = 0u;
    g_last_frame_first_word = 0u;
    g_last_frame_last_word = 0u;
    g_last_configure_active_count = 0u;
    memset(g_last_frame_lengths, 0, sizeof(g_last_frame_lengths));
    memset(g_last_configure_lengths, 0, sizeof(g_last_configure_lengths));
    EXPECT_EQ(frame_pipeline_init(), 0u);
    return 0;
}

static void default_lengths(uint32_t lengths[DAWN_OUTPUT_COUNT])
{
    for (uint32_t output = 0u; output < DAWN_OUTPUT_COUNT; ++output) {
        lengths[output] = DAWN_DEFAULT_STRAND_PIXEL_COUNT;
    }
}

static int test_default_config_commits_default_shape(void)
{
    if (reset_state() != 0) return 1;
    EXPECT_EQ(DAWN_OUTPUT_COUNT, DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT);
    EXPECT_EQ(DAWN_PIN_OUTPUT_COUNT, DAWN_OUTPUT_COUNT);
    EXPECT_EQ(frame_pipeline_active_pixel_count(), DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT * DAWN_DEFAULT_STRAND_PIXEL_COUNT);

    EXPECT_EQ(frame_pipeline_commit(), 0u);
    EXPECT_EQ(g_write_frame_calls, 1u);
    EXPECT_EQ(g_last_frame_active_count, DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT);
    EXPECT_EQ(g_last_frame_pixels_per_output, DAWN_PIXELS_PER_OUTPUT);
    EXPECT_EQ(g_last_frame_required_words, ((DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT - 1u) * DAWN_PIXELS_PER_OUTPUT) + DAWN_DEFAULT_STRAND_PIXEL_COUNT);
    EXPECT_EQ(g_last_frame_lengths[0], DAWN_DEFAULT_STRAND_PIXEL_COUNT);
    EXPECT_EQ(g_last_frame_lengths[DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT - 1u], DAWN_DEFAULT_STRAND_PIXEL_COUNT);
    return 0;
}

static int test_sparse_linear_mapping(void)
{
    uint32_t lengths[DAWN_OUTPUT_COUNT] = {0u};
    uint8_t slots[] = {
        1u, 2u, 3u,
        4u, 5u, 6u,
        7u, 8u, 9u,
        10u, 11u, 12u,
    };
    uint32_t *words;

    if (reset_state() != 0) return 1;
    lengths[0] = 1u;
    lengths[1] = 2u;
    lengths[3] = 1u;
    EXPECT_EQ(frame_pipeline_configure(4u, lengths), 0u);
    EXPECT_EQ(frame_pipeline_active_pixel_count(), 4u);
    EXPECT_EQ(frame_pipeline_write_linear_rgb(0u, slots, 4u), 0u);
    words = frame_pipeline_inactive_words();
    EXPECT_EQ(words[0], 0x00010203u);
    EXPECT_EQ(words[DAWN_PIXELS_PER_OUTPUT], 0x00040506u);
    EXPECT_EQ(words[DAWN_PIXELS_PER_OUTPUT + 1u], 0x00070809u);
    EXPECT_EQ(words[3u * DAWN_PIXELS_PER_OUTPUT], 0x000a0b0cu);
    EXPECT_EQ(frame_pipeline_commit(), 0u);
    EXPECT_EQ(g_last_frame_required_words, 3073u);
    return 0;
}

static int test_writes_only_current_staging_frame(void)
{
    uint8_t slots[] = {
        0x11u, 0x22u, 0x33u,
    };
    uint32_t *words;

    if (reset_state() != 0) return 1;
    EXPECT_EQ(frame_pipeline_write_linear_rgb(0u, slots, 1u), 0u);
    words = frame_pipeline_inactive_words();
    EXPECT_EQ(words[0], 0x00112233u);
    EXPECT_EQ(frame_pipeline_commit(), 0u);
    words = frame_pipeline_inactive_words();
    EXPECT_EQ(words[0], 0u);
    return 0;
}

static int test_shrink_commits_black_frame_before_reconfiguring(void)
{
    uint32_t lengths[DAWN_OUTPUT_COUNT];

    if (reset_state() != 0) return 1;
    default_lengths(lengths);
    EXPECT_EQ(frame_pipeline_configure(30u, lengths), 0u);
    frame_pipeline_clear_all(0x00123456u);

    memset(lengths, 0, sizeof(lengths));
    lengths[0] = 10u;
    lengths[1] = 5u;
    EXPECT_EQ(frame_pipeline_configure(2u, lengths), 0u);
    EXPECT_EQ(g_write_frame_calls, 1u);
    EXPECT_EQ(g_last_frame_active_count, DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT);
    EXPECT_EQ(g_last_frame_required_words, ((DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT - 1u) * DAWN_PIXELS_PER_OUTPUT) + DAWN_DEFAULT_STRAND_PIXEL_COUNT);
    EXPECT_EQ(g_last_frame_first_word, 0u);
    EXPECT_EQ(g_last_frame_last_word, 0u);
    EXPECT_EQ(g_configure_calls, 2u);
    EXPECT_EQ(g_last_configure_active_count, 2u);
    EXPECT_EQ(frame_pipeline_active_pixel_count(), 15u);

    EXPECT_EQ(frame_pipeline_commit(), 0u);
    EXPECT_EQ(g_last_frame_active_count, 2u);
    EXPECT_EQ(g_last_frame_required_words, 1029u);
    return 0;
}

static int test_oversized_config_uses_clamped_local_shape(void)
{
    uint32_t lengths[DAWN_OUTPUT_COUNT];

    if (reset_state() != 0) return 1;
    for (uint32_t output = 0u; output < DAWN_OUTPUT_COUNT; ++output) {
        lengths[output] = DAWN_PIXELS_PER_OUTPUT + 99u;
    }
    EXPECT_EQ(frame_pipeline_configure(DAWN_OUTPUT_COUNT + 7u, lengths), 0u);
    EXPECT_EQ(g_last_configure_active_count, DAWN_OUTPUT_COUNT + 7u);
    EXPECT_EQ(g_last_configure_lengths[0], DAWN_PIXELS_PER_OUTPUT + 99u);
    EXPECT_EQ(frame_pipeline_active_pixel_count(), DAWN_OUTPUT_COUNT * DAWN_PIXELS_PER_OUTPUT);
    EXPECT_EQ(frame_pipeline_commit(), 0u);
    EXPECT_EQ(g_last_frame_active_count, DAWN_OUTPUT_COUNT);
    EXPECT_EQ(g_last_frame_lengths[0], DAWN_PIXELS_PER_OUTPUT);
    EXPECT_EQ(g_last_frame_lengths[29], DAWN_PIXELS_PER_OUTPUT);
    EXPECT_EQ(g_last_frame_required_words, DAWN_OUTPUT_COUNT * DAWN_PIXELS_PER_OUTPUT);
    return 0;
}

typedef int (*test_fn)(void);

typedef struct {
    const char *name;
    test_fn fn;
} test_case_t;

int main(void)
{
    const test_case_t tests[] = {
        {"default_config_commits_default_shape", test_default_config_commits_default_shape},
        {"sparse_linear_mapping", test_sparse_linear_mapping},
        {"writes_only_current_staging_frame", test_writes_only_current_staging_frame},
        {"shrink_commits_black_frame_before_reconfiguring", test_shrink_commits_black_frame_before_reconfiguring},
        {"oversized_config_uses_clamped_local_shape", test_oversized_config_uses_clamped_local_shape},
    };

    for (uint32_t i = 0u; i < sizeof(tests) / sizeof(tests[0]); ++i) {
        if (tests[i].fn() != 0) {
            printf("test=%s status=fail\n", tests[i].name);
            return 1;
        }
        printf("test=%s status=ok\n", tests[i].name);
    }
    printf("frame_pipeline_host_tests=ok count=%u\n", (unsigned int)(sizeof(tests) / sizeof(tests[0])));
    return 0;
}
