#include "pl_ingest.h"

#include <stddef.h>

#include "sleep.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtimer_config.h"

#if defined(XPAR_WS281X_CONTROLLER_CORE_0_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_WS281X_CONTROLLER_CORE_0_BASEADDR
#elif defined(XPAR_WS281X_CONTROLLER_CORE_0_S_AXI_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_WS281X_CONTROLLER_CORE_0_S_AXI_BASEADDR
#else
#error "Missing WS281X_CONTROLLER_CORE_0 base address in xparameters.h"
#endif

#if defined(XPAR_AXIL_FRAME_RAM_0_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_BASEADDR
#elif defined(XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR
#else
#error "Missing AXIL_FRAME_RAM_0 base address in xparameters.h"
#endif

#if PL_CONTROL_BASEADDR != DONDER_PL_CONTROL_BASEADDR
#error "XPAR WS281X_CONTROLLER_CORE_0 base address does not match DONDER_PL_CONTROL_BASEADDR"
#endif

#if PL_FRAME_BASEADDR != DONDER_PL_FRAME_RAM_BASEADDR
#error "XPAR AXIL_FRAME_RAM_0 base address does not match DONDER_PL_FRAME_RAM_BASEADDR"
#endif

#define PL_CONTROL_OFFSET(reg) ((uint32_t)offsetof(pl_control_t, reg))
#define PL_INGEST_BANK_WAIT_TRIES 200u
#define PL_INGEST_BANK_WAIT_US 100u
#if DONDER_PL_PIN_OUTPUT_COUNT >= 32u
#define PL_INGEST_PIN_MASK 0xffffffffu
#else
#define PL_INGEST_PIN_MASK ((1u << DONDER_PL_PIN_OUTPUT_COUNT) - 1u)
#endif

static pl_ingest_write_stats_t g_write_stats;

uint32_t pl_ingest_read(uint32_t offset)
{
    return Xil_In32(PL_CONTROL_BASEADDR + offset);
}

void pl_ingest_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(PL_CONTROL_BASEADDR + offset, value);
}

static uint32_t pl_frame_read_word(size_t index)
{
    return Xil_In32(PL_FRAME_BASEADDR + (uint32_t)(index * sizeof(uint32_t)));
}

static void pl_frame_write_word(size_t index, uint32_t value)
{
    Xil_Out32(PL_FRAME_BASEADDR + (uint32_t)(index * sizeof(uint32_t)), value);
}

static uint32_t expected_next(uint32_t value)
{
    return value + 1u;
}

static uint32_t pl_ingest_now_us(void)
{
#if defined(XPAR_GLOBAL_TIMER_BASEADDR)
    uint32_t high;
    uint32_t low;
    uint32_t control;
    uint64_t ticks;

    control = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + 0x08u);
    if ((control & 0x01u) == 0u) {
        Xil_Out32(XPAR_GLOBAL_TIMER_BASEADDR + 0x08u, control | 0x01u);
    }

    do {
        high = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + 0x04u);
        low = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + 0x00u);
    } while (Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + 0x04u) != high);

    ticks = ((uint64_t)high << 32) | low;
    return (uint32_t)((ticks * 1000000u) / COUNTS_PER_SECOND);
#else
#error "XPAR_GLOBAL_TIMER_BASEADDR is required for PL ingest timing"
#endif
}

static void record_write_stats(uint32_t start_us, uint32_t active_words, uint32_t required_words)
{
    uint32_t elapsed_us = pl_ingest_now_us() - start_us;

    g_write_stats.last_write_us = elapsed_us;
    if (elapsed_us > g_write_stats.max_write_us) {
        g_write_stats.max_write_us = elapsed_us;
    }
    g_write_stats.last_active_words = active_words;
    g_write_stats.last_required_words = required_words;
}

static int wait_for_write_bank(pl_ingest_snapshot_t *snapshot)
{
    for (uint32_t i = 0u; i < PL_INGEST_BANK_WAIT_TRIES; ++i) {
        pl_ingest_snapshot(snapshot);
        if ((snapshot->write_bank_valid & PL_CONTROL__WRITE_BANK_VALID__VALUE_bm) != 0u) {
            return 0;
        }
        usleep(PL_INGEST_BANK_WAIT_US);
    }
    return -1;
}

const pl_ingest_write_stats_t *pl_ingest_write_stats(void)
{
    return &g_write_stats;
}

void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot)
{
    snapshot->id = pl_ingest_read(PL_CONTROL_OFFSET(ID));
    snapshot->version = pl_ingest_read(PL_CONTROL_OFFSET(VERSION));
    snapshot->status = pl_ingest_read(PL_CONTROL_OFFSET(STATUS));
    snapshot->capacity_words = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_CAPACITY));
    snapshot->bank_words = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_BANK_WORDS));
    snapshot->active_bank = pl_ingest_read(PL_CONTROL_OFFSET(ACTIVE_BANK));
    snapshot->write_bank = pl_ingest_read(PL_CONTROL_OFFSET(WRITE_BANK));
    snapshot->write_bank_valid = pl_ingest_read(PL_CONTROL_OFFSET(WRITE_BANK_VALID));
    snapshot->busy_bank = pl_ingest_read(PL_CONTROL_OFFSET(BUSY_BANK));
    snapshot->frame_sequence = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_SEQUENCE));
    snapshot->frame_count = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_COUNT));
    snapshot->committed_words = pl_ingest_read(PL_CONTROL_OFFSET(COMMITTED_WORDS));
    snapshot->error_count = pl_ingest_read(PL_CONTROL_OFFSET(ERROR_COUNT));
    snapshot->frame_dropped = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_DROPPED));
    snapshot->frame_rejected = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_REJECTED));
    snapshot->consumer_status = pl_ingest_read(PL_CONTROL_OFFSET(CONSUMER_STATUS));
    snapshot->consumer_sequence = pl_ingest_read(PL_CONTROL_OFFSET(CONSUMER_SEQUENCE));
    snapshot->consumer_frame_count = pl_ingest_read(PL_CONTROL_OFFSET(CONSUMER_FRAME_COUNT));
    snapshot->consumer_error_count = pl_ingest_read(PL_CONTROL_OFFSET(CONSUMER_ERROR_COUNT));
    snapshot->active_output_count = pl_ingest_read(PL_CONTROL_OFFSET(ACTIVE_OUTPUT_COUNT));
    for (uint32_t output = 0u; output < DONDER_PL_OUTPUT_COUNT; ++output) {
        snapshot->strand_pixel_count[output] = pl_ingest_read(PL_CONTROL_OFFSET(STRAND_PIXEL_COUNT) + (output * sizeof(uint32_t)));
    }
    snapshot->config_status = pl_ingest_read(PL_CONTROL_OFFSET(CONFIG_STATUS));
    for (uint32_t word = 0u; word < DONDER_PL_MASK_WORD_COUNT; ++word) {
        snapshot->strand_length_clamped[word] = pl_ingest_read(PL_CONTROL_OFFSET(STRAND_LENGTH_CLAMPED) + (word * sizeof(uint32_t)));
        snapshot->output_invert_mask[word] = pl_ingest_read(PL_CONTROL_OFFSET(OUTPUT_INVERT_MASK) + (word * sizeof(uint32_t)));
    }
}

static uint32_t min_u32(uint32_t a, uint32_t b)
{
    return a < b ? a : b;
}

static uint32_t config_required_words(uint32_t active_count, const uint32_t lengths[DONDER_PL_OUTPUT_COUNT], uint32_t max_output_count, uint32_t max_pixels_per_output)
{
    uint32_t required_words = 0u;
    uint32_t output_base = 0u;

    for (uint32_t output = 0u; output < max_output_count && output < DONDER_PL_OUTPUT_COUNT; ++output) {
        if (output < active_count && lengths[output] > 0u) {
            uint32_t required = output_base + lengths[output];
            if (required > required_words) {
                required_words = required;
            }
        }
        output_base += max_pixels_per_output;
    }

    return required_words;
}

pl_ingest_result_t pl_ingest_get_config(pl_ingest_config_t *config)
{
    if (config == NULL) {
        return PL_INGEST_BAD_ARGUMENT;
    }

    config->max_output_count = pl_ingest_read(PL_CONTROL_OFFSET(WS281X_OUTPUT_COUNT));
    config->max_pixels_per_output = pl_ingest_read(PL_CONTROL_OFFSET(WS281X_PIXELS_PER_OUTPUT));
    config->active_output_count = pl_ingest_read(PL_CONTROL_OFFSET(ACTIVE_OUTPUT_COUNT));
    for (uint32_t output = 0u; output < DONDER_PL_OUTPUT_COUNT; ++output) {
        config->strand_pixel_count[output] = pl_ingest_read(PL_CONTROL_OFFSET(STRAND_PIXEL_COUNT) + (output * sizeof(uint32_t)));
    }
    config->config_status = pl_ingest_read(PL_CONTROL_OFFSET(CONFIG_STATUS));
    for (uint32_t word = 0u; word < DONDER_PL_MASK_WORD_COUNT; ++word) {
        config->strand_length_clamped[word] = pl_ingest_read(PL_CONTROL_OFFSET(STRAND_LENGTH_CLAMPED) + (word * sizeof(uint32_t)));
        config->output_invert_mask[word] = pl_ingest_read(PL_CONTROL_OFFSET(OUTPUT_INVERT_MASK) + (word * sizeof(uint32_t)));
    }

    config->effective_active_output_count = min_u32(config->active_output_count, config->max_output_count);
    if (config->effective_active_output_count > DONDER_PL_OUTPUT_COUNT) {
        config->effective_active_output_count = DONDER_PL_OUTPUT_COUNT;
    }
    for (uint32_t output = 0u; output < DONDER_PL_OUTPUT_COUNT; ++output) {
        config->effective_strand_pixel_count[output] = min_u32(config->strand_pixel_count[output], config->max_pixels_per_output);
    }
    config->required_words = config_required_words(config->effective_active_output_count,
                                                   config->effective_strand_pixel_count,
                                                   config->max_output_count,
                                                   config->max_pixels_per_output);

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_init(uint32_t required_words)
{
    pl_ingest_snapshot_t snapshot;

    pl_ingest_snapshot(&snapshot);
    xil_printf("pl_control=0x%08x pl_frame=0x%08x id=0x%08x version=0x%08x capacity=%u bank_words=%u active_bank=%u write_bank=%u write_valid=%u busy_bank=0x%08x status=0x%08x consumer_status=0x%08x max_outputs=%u max_pixels=%u active_outputs=%u first_lengths=[%u,%u,%u,%u] output_invert_mask0=0x%08x config_status=0x%08x\r\n",
               (unsigned int)PL_CONTROL_BASEADDR,
               (unsigned int)PL_FRAME_BASEADDR,
               (unsigned int)snapshot.id,
               (unsigned int)snapshot.version,
               (unsigned int)snapshot.capacity_words,
               (unsigned int)snapshot.bank_words,
               (unsigned int)snapshot.active_bank,
               (unsigned int)snapshot.write_bank,
               (unsigned int)snapshot.write_bank_valid,
               (unsigned int)snapshot.busy_bank,
               (unsigned int)snapshot.status,
               (unsigned int)snapshot.consumer_status,
               (unsigned int)pl_ingest_read(PL_CONTROL_OFFSET(WS281X_OUTPUT_COUNT)),
               (unsigned int)pl_ingest_read(PL_CONTROL_OFFSET(WS281X_PIXELS_PER_OUTPUT)),
               (unsigned int)snapshot.active_output_count,
               (unsigned int)snapshot.strand_pixel_count[0],
               (unsigned int)snapshot.strand_pixel_count[1],
               (unsigned int)snapshot.strand_pixel_count[2],
               (unsigned int)snapshot.strand_pixel_count[3],
               (unsigned int)snapshot.output_invert_mask[0],
               (unsigned int)snapshot.config_status);

    if (snapshot.id != PL_CONTROL__ID__VALUE_reset) {
        return PL_INGEST_BAD_ID;
    }
    if (snapshot.version != PL_CONTROL__VERSION__VALUE_reset) {
        return PL_INGEST_BAD_VERSION;
    }
    if ((snapshot.status & PL_CONTROL__STATUS__READY_bm) == 0u
        || (snapshot.status & (PL_CONTROL__STATUS__OVERFLOW_bm
                               | PL_CONTROL__STATUS__CONSUMER_ERROR_bm
                               | PL_CONTROL__STATUS__COMMIT_REJECTED_bm)) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if (snapshot.bank_words < required_words) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    pl_ingest_write(PL_CONTROL_OFFSET(CONTROL), PL_CONTROL__CONTROL__CLEAR_ERRORS_bm);
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_self_test(void)
{
    static const uint32_t frame[] = {
        0x00000001u,
        0x00000002u,
        0x00000004u,
        0x00000008u,
        0xdeadbeefu,
        0x12345678u,
        0x01020304u,
        0x0badc0deu,
    };

    uint32_t before = pl_ingest_read(PL_CONTROL_OFFSET(FRAME_COUNT));

    if (pl_ingest_write_frame(frame, sizeof(frame) / sizeof(frame[0])) != PL_INGEST_OK) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_CONTROL_OFFSET(FRAME_COUNT)) != before + 1u) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_CONTROL_OFFSET(COMMITTED_WORDS)) != sizeof(frame) / sizeof(frame[0])) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_CONTROL_OFFSET(ACTIVE_BANK)) > 1u || pl_ingest_read(PL_CONTROL_OFFSET(WRITE_BANK)) > 1u) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_CONTROL_OFFSET(LAST_FRAME_WORD)) != frame[7]) {
        return PL_INGEST_READBACK_FAILED;
    }

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count)
{
    pl_ingest_snapshot_t before;
    pl_ingest_snapshot_t after;
    uint32_t bank_words;
    uint32_t write_bank;
    size_t bank_offset;
    uint32_t commit_value;
    uint32_t start_us = pl_ingest_now_us();

    if (words == NULL && word_count > 0u) {
        return PL_INGEST_BAD_ARGUMENT;
    }

    pl_ingest_snapshot(&before);

    if ((before.status & PL_CONTROL__STATUS__READY_bm) == 0u
        || (before.status & (PL_CONTROL__STATUS__OVERFLOW_bm
                             | PL_CONTROL__STATUS__CONSUMER_ERROR_bm
                             | PL_CONTROL__STATUS__COMMIT_REJECTED_bm)) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if ((before.write_bank_valid & PL_CONTROL__WRITE_BANK_VALID__VALUE_bm) == 0u) {
        g_write_stats.no_free_bank_waits++;
        if (wait_for_write_bank(&before) != 0) {
            g_write_stats.no_free_bank_drops++;
            pl_ingest_write(PL_CONTROL_OFFSET(FRAME_DROP_NOTIFY), PL_CONTROL__FRAME_DROP_NOTIFY__VALUE_bm);
            return PL_INGEST_NO_FREE_BANK;
        }
    }
    bank_words = before.bank_words;
    write_bank = before.write_bank;
    bank_offset = (size_t)write_bank * (size_t)bank_words;
    if (write_bank >= DONDER_PL_FRAME_BANKS || word_count > bank_words || word_count > PL_CONTROL__FRAME_COMMIT__WORD_COUNT_bm) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    for (size_t i = 0u; i < word_count; ++i) {
        pl_frame_write_word(bank_offset + i, words[i]);
    }

    if (word_count > 0u) {
        pl_ingest_write(PL_CONTROL_OFFSET(FIRST_FRAME_WORD), words[0]);
        pl_ingest_write(PL_CONTROL_OFFSET(LAST_FRAME_WORD), words[word_count - 1u]);
    } else {
        pl_ingest_write(PL_CONTROL_OFFSET(FIRST_FRAME_WORD), 0u);
        pl_ingest_write(PL_CONTROL_OFFSET(LAST_FRAME_WORD), 0u);
    }

    if (word_count > 0u && pl_frame_read_word(bank_offset) != (words[0] & 0x00ffffffu)) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (word_count > 1u && pl_frame_read_word(bank_offset + word_count - 1u) != (words[word_count - 1u] & 0x00ffffffu)) {
        return PL_INGEST_READBACK_FAILED;
    }

    commit_value = (write_bank << PL_CONTROL__FRAME_COMMIT__BANK_bp) | (uint32_t)word_count;
    pl_ingest_write(PL_CONTROL_OFFSET(FRAME_COMMIT), commit_value);

    pl_ingest_snapshot(&after);
    if (after.frame_count != expected_next(before.frame_count)
        || after.frame_sequence != expected_next(before.frame_sequence)
        || after.active_bank != write_bank
        || after.write_bank != (write_bank ^ 1u)
        || after.committed_words != word_count
        || (after.status & PL_CONTROL__STATUS__READY_bm) == 0u
        || (after.status & (PL_CONTROL__STATUS__OVERFLOW_bm
                            | PL_CONTROL__STATUS__CONSUMER_ERROR_bm
                            | PL_CONTROL__STATUS__COMMIT_REJECTED_bm)) != 0u
        || after.frame_rejected != before.frame_rejected) {
        return PL_INGEST_COMMIT_FAILED;
    }

    record_write_stats(start_us, (uint32_t)word_count, (uint32_t)word_count);
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame_strands(const uint32_t *words,
                                                 uint32_t active_count,
                                                 const uint32_t lengths[DONDER_PL_OUTPUT_COUNT],
                                                 uint32_t pixels_per_output,
                                                 uint32_t required_words)
{
    pl_ingest_snapshot_t before;
    pl_ingest_snapshot_t after;
    uint32_t bank_words;
    uint32_t write_bank;
    size_t bank_offset;
    uint32_t commit_value;
    uint32_t first_word = 0u;
    uint32_t last_word = 0u;
    uint32_t have_last = 0u;
    uint32_t active_words = 0u;
    uint32_t start_us = pl_ingest_now_us();

    if (words == NULL && required_words > 0u) {
        return PL_INGEST_BAD_ARGUMENT;
    }
    if (lengths == NULL || active_count > DONDER_PL_OUTPUT_COUNT || pixels_per_output == 0u) {
        return PL_INGEST_BAD_ARGUMENT;
    }

    pl_ingest_snapshot(&before);

    if ((before.status & PL_CONTROL__STATUS__READY_bm) == 0u
        || (before.status & (PL_CONTROL__STATUS__OVERFLOW_bm
                             | PL_CONTROL__STATUS__CONSUMER_ERROR_bm
                             | PL_CONTROL__STATUS__COMMIT_REJECTED_bm)) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if ((before.write_bank_valid & PL_CONTROL__WRITE_BANK_VALID__VALUE_bm) == 0u) {
        g_write_stats.no_free_bank_waits++;
        if (wait_for_write_bank(&before) != 0) {
            g_write_stats.no_free_bank_drops++;
            pl_ingest_write(PL_CONTROL_OFFSET(FRAME_DROP_NOTIFY), PL_CONTROL__FRAME_DROP_NOTIFY__VALUE_bm);
            return PL_INGEST_NO_FREE_BANK;
        }
    }
    bank_words = before.bank_words;
    write_bank = before.write_bank;
    bank_offset = (size_t)write_bank * (size_t)bank_words;
    if (write_bank >= DONDER_PL_FRAME_BANKS || required_words > bank_words || required_words > PL_CONTROL__FRAME_COMMIT__WORD_COUNT_bm) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    uint32_t output_base = 0u;
    for (uint32_t output = 0u; output < active_count; ++output) {
        active_words += lengths[output];
        for (uint32_t pixel = 0u; pixel < lengths[output]; ++pixel) {
            uint32_t word_index = output_base + pixel;
            if (word_index >= required_words) {
                return PL_INGEST_BAD_ARGUMENT;
            }
            pl_frame_write_word(bank_offset + word_index, words[word_index]);
        }
        if (lengths[output] > 0u) {
            last_word = words[output_base + lengths[output] - 1u];
            have_last = 1u;
        }
        output_base += pixels_per_output;
    }

    if (required_words > 0u) {
        first_word = words[0];
    }
    pl_ingest_write(PL_CONTROL_OFFSET(FIRST_FRAME_WORD), first_word);
    pl_ingest_write(PL_CONTROL_OFFSET(LAST_FRAME_WORD), have_last ? last_word : 0u);

    if (required_words > 0u && pl_frame_read_word(bank_offset) != (words[0] & 0x00ffffffu)) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (have_last && pl_frame_read_word(bank_offset + required_words - 1u) != (last_word & 0x00ffffffu)) {
        return PL_INGEST_READBACK_FAILED;
    }

    commit_value = (write_bank << PL_CONTROL__FRAME_COMMIT__BANK_bp) | required_words;
    pl_ingest_write(PL_CONTROL_OFFSET(FRAME_COMMIT), commit_value);

    pl_ingest_snapshot(&after);
    if (after.frame_count != expected_next(before.frame_count)
        || after.frame_sequence != expected_next(before.frame_sequence)
        || after.active_bank != write_bank
        || after.write_bank != (write_bank ^ 1u)
        || after.committed_words != required_words
        || (after.status & PL_CONTROL__STATUS__READY_bm) == 0u
        || (after.status & (PL_CONTROL__STATUS__OVERFLOW_bm
                            | PL_CONTROL__STATUS__CONSUMER_ERROR_bm
                            | PL_CONTROL__STATUS__COMMIT_REJECTED_bm)) != 0u
        || after.frame_rejected != before.frame_rejected) {
        return PL_INGEST_COMMIT_FAILED;
    }

    record_write_stats(start_us, active_words, required_words);
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_configure_strands(uint32_t active_count, const uint32_t lengths[DONDER_PL_OUTPUT_COUNT])
{
    if (lengths == NULL) {
        return PL_INGEST_BAD_ARGUMENT;
    }

    pl_ingest_write(PL_CONTROL_OFFSET(ACTIVE_OUTPUT_COUNT), active_count);
    for (uint32_t output = 0u; output < DONDER_PL_OUTPUT_COUNT; ++output) {
        pl_ingest_write(PL_CONTROL_OFFSET(STRAND_PIXEL_COUNT) + (output * sizeof(uint32_t)), lengths[output]);
    }

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_configure_output_invert_mask(uint32_t invert_mask)
{
    pl_ingest_write(PL_CONTROL_OFFSET(OUTPUT_INVERT_MASK), invert_mask);
    for (uint32_t word = 1u; word < DONDER_PL_MASK_WORD_COUNT; ++word) {
        pl_ingest_write(PL_CONTROL_OFFSET(OUTPUT_INVERT_MASK) + (word * sizeof(uint32_t)), 0u);
    }
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_enable_consumer(void)
{
    uint32_t consumer_status;

    pl_ingest_write(PL_CONTROL_OFFSET(CONSUMER_CONTROL), PL_CONTROL__CONSUMER_CONTROL__RESET_FSM_bm);
    pl_ingest_write(PL_CONTROL_OFFSET(CONTROL), PL_CONTROL__CONTROL__CLEAR_ERRORS_bm);
    pl_ingest_write(PL_CONTROL_OFFSET(CONSUMER_CONTROL), PL_CONTROL__CONSUMER_CONTROL__ENABLE_bm);

    consumer_status = pl_ingest_read(PL_CONTROL_OFFSET(CONSUMER_STATUS));
    if ((consumer_status & PL_CONTROL__CONSUMER_STATUS__ENABLED_bm) == 0u
        || (consumer_status & PL_CONTROL__CONSUMER_STATUS__ERROR_bm) != 0u) {
        return PL_INGEST_CONSUMER_FAILED;
    }

    return PL_INGEST_OK;
}

void pl_ingest_drive_pins(uint32_t value)
{
    pl_ingest_write(PL_CONTROL_OFFSET(PIN_OUT), value & PL_INGEST_PIN_MASK);
}
