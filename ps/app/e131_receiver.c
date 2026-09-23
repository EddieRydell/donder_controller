#include "e131_receiver.h"

#include <stddef.h>

#include "app_config.h"
#include "e131_parser.h"
#include "frame_pipeline.h"

#define E131_OPTION_PREVIEW 0x80u
#define E131_OPTION_STREAM_TERMINATED 0x40u
#define MAX_E131_UNIVERSES ((DONDER_WORDS_PER_FRAME * 3u + DONDER_SLOTS_PER_UNIVERSE - 1u) / DONDER_SLOTS_PER_UNIVERSE)
#define BITMAP_WORDS ((MAX_E131_UNIVERSES + 31u) / 32u)

static e131_receiver_status_t g_status;
static uint32_t g_received_bitmap[BITMAP_WORDS];
static uint8_t g_sequence_seen[MAX_E131_UNIVERSES];
static uint8_t g_last_sequence[MAX_E131_UNIVERSES];
static uint8_t g_locked_cid[16];
static uint32_t g_received_count;
static uint32_t g_last_display_ms;
static uint32_t g_last_packet_ms;
static uint32_t g_last_commit_ms;
static uint8_t g_has_display_time;
static uint8_t g_has_packet_time;
static uint8_t g_has_commit_time;
static uint8_t g_pending_synced_complete;

static uint32_t total_slots(void)
{
    return frame_pipeline_active_pixel_count() * 3u;
}

static uint32_t expected_universe_count(void)
{
    return (total_slots() + DONDER_SLOTS_PER_UNIVERSE - 1u) / DONDER_SLOTS_PER_UNIVERSE;
}

static uint16_t expected_slots_for_offset(uint32_t offset)
{
    uint32_t first_slot = offset * DONDER_SLOTS_PER_UNIVERSE;
    uint32_t remaining = total_slots() - first_slot;

    return (uint16_t)(remaining > DONDER_SLOTS_PER_UNIVERSE ? DONDER_SLOTS_PER_UNIVERSE : remaining);
}

static int cid_equal(const uint8_t *a, const uint8_t *b)
{
    if (a == NULL || b == NULL) {
        return 0;
    }
    for (uint32_t i = 0u; i < 16u; ++i) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

static void copy_cid(uint8_t dst[16], const uint8_t *src)
{
    for (uint32_t i = 0u; i < 16u; ++i) {
        dst[i] = src != NULL ? src[i] : 0u;
    }
}

static void copy_ip(uint8_t dst[4], const uint8_t src[4])
{
    for (uint32_t i = 0u; i < 4u; ++i) {
        dst[i] = src != NULL ? src[i] : 0u;
    }
}

static void clear_assembly(void)
{
    for (uint32_t i = 0u; i < BITMAP_WORDS; ++i) {
        g_received_bitmap[i] = 0u;
    }
    for (uint32_t i = 0u; i < MAX_E131_UNIVERSES; ++i) {
        g_sequence_seen[i] = 0u;
        g_last_sequence[i] = 0u;
    }
    g_received_count = 0u;
    g_pending_synced_complete = 0u;
}

static void release_lock(void)
{
    g_status.source_locked = 0u;
    g_status.active_priority = 0u;
    g_status.sync_mode = 0u;
    g_status.sync_address = 0u;
    for (uint32_t i = 0u; i < 16u; ++i) {
        g_locked_cid[i] = 0u;
    }
    for (uint32_t i = 0u; i < 4u; ++i) {
        g_status.source_ip[i] = 0u;
    }
}

static uint32_t elapsed_ms(uint32_t now_ms, uint32_t then_ms)
{
    return now_ms - then_ms;
}

static void record_packet_timing(uint32_t now_ms)
{
    if (g_has_packet_time) {
        uint32_t gap = elapsed_ms(now_ms, g_last_packet_ms);
        g_status.last_packet_gap_ms = gap;
        if (gap > g_status.max_packet_gap_ms) {
            g_status.max_packet_gap_ms = gap;
        }
    }
    g_last_packet_ms = now_ms;
    g_has_packet_time = 1u;
}

static void record_commit_timing(uint32_t now_ms)
{
    if (g_has_commit_time) {
        uint32_t gap = elapsed_ms(now_ms, g_last_commit_ms);
        g_status.last_frame_commit_gap_ms = gap;
        if (gap > g_status.max_frame_commit_gap_ms) {
            g_status.max_frame_commit_gap_ms = gap;
        }
    }
    g_last_commit_ms = now_ms;
    g_has_commit_time = 1u;
}

static int commit_current(const char *reason, uint32_t now_ms)
{
    int commit_result = frame_pipeline_commit();

    if (commit_result == 0) {
        g_status.frames_committed++;
        g_status.complete_frames++;
        g_status.last_error = reason;
        g_last_display_ms = now_ms;
        g_has_display_time = 1u;
        record_commit_timing(now_ms);
        clear_assembly();
        return 0;
    }
    if (commit_result > 0) {
        g_status.frames_dropped++;
        g_status.last_error = "pl_busy";
        clear_assembly();
        return 1;
    }

    g_status.e131_rejected++;
    g_status.last_error = "commit_failed";
    return -1;
}

static void commit_black(uint32_t now_ms, const char *reason)
{
    frame_pipeline_clear_all(0u);
    if (frame_pipeline_commit() == 0) {
        g_status.frames_committed++;
        g_status.blackouts++;
        g_status.last_error = reason;
        g_last_display_ms = now_ms;
        g_has_display_time = 1u;
        record_commit_timing(now_ms);
    } else {
        g_status.frames_dropped++;
        g_status.last_error = "black_commit_failed";
    }
    clear_assembly();
    release_lock();
}

static int mark_universe(uint32_t offset)
{
    uint32_t index = offset / 32u;
    uint32_t mask = 1u << (offset % 32u);

    if ((g_received_bitmap[index] & mask) == 0u) {
        g_received_bitmap[index] |= mask;
        g_received_count++;
        g_status.universes_seen++;
        return 1;
    }
    return 0;
}

static int sweep_complete(void)
{
    return g_received_count == expected_universe_count();
}

static int accept_source(const e131_data_packet_t *packet, const uint8_t source_ip[4], uint32_t now_ms)
{
    if (!g_status.source_locked) {
        copy_cid(g_locked_cid, packet->cid);
        copy_ip(g_status.source_ip, source_ip);
        g_status.source_locked = 1u;
        g_status.active_priority = packet->priority;
        g_last_display_ms = now_ms;
        g_has_display_time = 1u;
        return 1;
    }

    if (cid_equal(g_locked_cid, packet->cid)) {
        g_status.active_priority = packet->priority;
        return 1;
    }

    if (packet->priority > g_status.active_priority) {
        clear_assembly();
        copy_cid(g_locked_cid, packet->cid);
        copy_ip(g_status.source_ip, source_ip);
        g_status.active_priority = packet->priority;
        g_last_display_ms = now_ms;
        g_has_display_time = 1u;
        g_status.last_error = "source_preempt";
        return 1;
    }

    g_status.ignored_sources++;
    g_status.last_error = "source_ignored";
    return 0;
}

static void process_sync_packet(const e131_sync_packet_t *packet, uint32_t now_ms)
{
    if (!g_status.source_locked || !cid_equal(g_locked_cid, packet->cid)) {
        g_status.ignored_sources++;
        return;
    }
    if (!g_status.sync_mode || packet->sync_address != g_status.sync_address) {
        g_status.last_error = "sync_mismatch";
        return;
    }
    if (g_pending_synced_complete) {
        (void)commit_current("sync_commit", now_ms);
    }
}

static int try_handle_sync_packet(const uint8_t *data, uint16_t length, uint32_t now_ms)
{
    e131_sync_packet_t packet;
    e131_parse_result_t result = e131_parse_sync_packet(data, length, &packet);

    if (result != E131_PARSE_OK) {
        return 0;
    }
    process_sync_packet(&packet, now_ms);
    return 1;
}

void e131_receiver_init(void)
{
    g_status.e131_valid = 0u;
    g_status.e131_rejected = 0u;
    g_status.universes_seen = 0u;
    g_status.frames_committed = 0u;
    g_status.frames_dropped = 0u;
    g_status.complete_frames = 0u;
    g_status.incomplete_sweeps = 0u;
    g_status.ignored_sources = 0u;
    g_status.sequence_anomalies = 0u;
    g_status.preview_rejects = 0u;
    g_status.sync_waits = 0u;
    g_status.sync_timeouts = 0u;
    g_status.blackouts = 0u;
    g_status.last_packet_gap_ms = 0u;
    g_status.max_packet_gap_ms = 0u;
    g_status.last_frame_commit_gap_ms = 0u;
    g_status.max_frame_commit_gap_ms = 0u;
    g_status.last_universe = 0u;
    g_status.last_sequence = 0u;
    g_status.last_error = "init";
    g_last_display_ms = 0u;
    g_last_packet_ms = 0u;
    g_last_commit_ms = 0u;
    g_has_display_time = 0u;
    g_has_packet_time = 0u;
    g_has_commit_time = 0u;
    clear_assembly();
    release_lock();
}

void e131_receiver_handle_packet(const uint8_t *data,
                                 uint16_t length,
                                 const uint8_t source_ip[4],
                                 uint32_t now_ms)
{
    e131_data_packet_t packet;
    e131_parse_result_t result;
    uint32_t offset;

    result = e131_parse_data_packet(data,
                                    length,
                                    g_app_config.first_universe,
                                    frame_pipeline_active_pixel_count(),
                                    &packet);
    if (result != E131_PARSE_OK) {
        if (try_handle_sync_packet(data, length, now_ms)) {
            return;
        }
        g_status.e131_rejected++;
        g_status.last_error = e131_parse_result_name(result);
        return;
    }
    record_packet_timing(now_ms);

    if ((packet.options & E131_OPTION_PREVIEW) != 0u && DONDER_E131_ACCEPT_PREVIEW == 0u) {
        g_status.e131_rejected++;
        g_status.preview_rejects++;
        g_status.last_error = "preview";
        return;
    }
    if (!accept_source(&packet, source_ip, now_ms)) {
        return;
    }
    if ((packet.options & E131_OPTION_STREAM_TERMINATED) != 0u) {
        commit_black(now_ms, "stream_terminated");
        return;
    }

    offset = (uint32_t)(packet.universe - g_app_config.first_universe);
    if (offset >= expected_universe_count() || packet.rgb_slot_count != expected_slots_for_offset(offset)) {
        g_status.e131_rejected++;
        g_status.last_error = "slot_count";
        return;
    }

    if (packet.sync_address == 0u) {
        if (g_status.sync_mode) {
            clear_assembly();
        }
        g_status.sync_mode = 0u;
        g_status.sync_address = 0u;
    } else {
        if (!g_status.sync_mode || g_status.sync_address != packet.sync_address) {
            clear_assembly();
        }
        g_status.sync_mode = 1u;
        g_status.sync_address = packet.sync_address;
    }

    if (g_sequence_seen[offset]) {
        uint8_t expected = (uint8_t)(g_last_sequence[offset] + 1u);
        if (packet.sequence != expected) {
            g_status.sequence_anomalies++;
        }
    }
    g_sequence_seen[offset] = 1u;
    g_last_sequence[offset] = packet.sequence;

    if (frame_pipeline_write_linear_rgb(packet.first_linear_pixel, packet.rgb_slots, packet.rgb_pixel_count) != 0) {
        g_status.e131_rejected++;
        g_status.last_error = "frame_map";
        return;
    }

    (void)mark_universe(offset);
    g_status.e131_valid++;
    g_status.last_universe = packet.universe;
    g_status.last_sequence = packet.sequence;

    if (packet.sync_address == 0u) {
        if (sweep_complete()) {
            (void)commit_current("ok", now_ms);
        } else {
            g_status.last_error = "partial";
        }
    } else {
        if (sweep_complete()) {
            g_pending_synced_complete = 1u;
            g_status.sync_waits++;
            g_status.last_error = "sync_wait";
        } else {
            g_status.last_error = "partial_sync";
        }
    }
}

void e131_receiver_poll(uint32_t now_ms)
{
    if (!g_status.source_locked || !g_has_display_time) {
        return;
    }
    if (elapsed_ms(now_ms, g_last_display_ms) < DONDER_E131_BLACKOUT_TIMEOUT_MS) {
        return;
    }
    if (g_status.sync_mode && g_pending_synced_complete) {
        g_status.sync_timeouts++;
    } else if (g_received_count > 0u) {
        g_status.incomplete_sweeps++;
    }
    commit_black(now_ms, "blackout");
}

const e131_receiver_status_t *e131_receiver_status(void)
{
    return &g_status;
}
