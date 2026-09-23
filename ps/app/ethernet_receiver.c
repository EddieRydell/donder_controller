#include "ethernet_receiver.h"

#include "app_config.h"
#include "e131_receiver.h"
#include "frame_pipeline.h"
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/memp.h"
#include "lwip/opt.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/stats.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "pl_ingest.h"
#include "rx_packet_ring.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtimer_config.h"

#include <string.h>

#if !(LWIP_STATS && MEMP_STATS)
#error "lwIP MEMP stats must be enabled for E1.31 ingress telemetry"
#endif

#if defined(XPAR_XEMACPS_0_BASEADDR)
#define DONDER_EMAC_BASEADDR XPAR_XEMACPS_0_BASEADDR
#elif defined(XPAR_PS7_ETHERNET_0_BASEADDR)
#define DONDER_EMAC_BASEADDR XPAR_PS7_ETHERNET_0_BASEADDR
#else
#error "Missing PS ENET0 base address in xparameters.h"
#endif

#define DONDER_GT_COUNTER_LOWER_OFFSET 0x00u
#define DONDER_GT_COUNTER_UPPER_OFFSET 0x04u
#define DONDER_GT_CONTROL_OFFSET 0x08u
#define DONDER_GT_CONTROL_ENABLE 0x01u
#define RX_INPUT_ROUNDS_PER_POLL 8u
#define RX_DRAIN_PER_INPUT_ROUND 64u

static struct netif g_netif;
static struct udp_pcb *g_udp;
static ethernet_receiver_counters_t g_counters;
static uint32_t g_poll_now_ms;
static uint32_t g_input_packets_this_call;

static ip_addr_t make_ip(const uint8_t octets[4])
{
    ip_addr_t ip;
    IP4_ADDR(&ip, octets[0], octets[1], octets[2], octets[3]);
    return ip;
}

static uint32_t monotonic_ms(void)
{
    uint32_t high;
    uint32_t low;
    uint32_t control;
    uint64_t ticks;

    control = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DONDER_GT_CONTROL_OFFSET);
    if ((control & DONDER_GT_CONTROL_ENABLE) == 0u) {
        Xil_Out32(XPAR_GLOBAL_TIMER_BASEADDR + DONDER_GT_CONTROL_OFFSET, control | DONDER_GT_CONTROL_ENABLE);
    }

    do {
        high = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DONDER_GT_COUNTER_UPPER_OFFSET);
        low = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DONDER_GT_COUNTER_LOWER_OFFSET);
    } while (Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DONDER_GT_COUNTER_UPPER_OFFSET) != high);

    ticks = ((uint64_t)high << 32) | low;
    return (uint32_t)((ticks * 1000u) / COUNTS_PER_SECOND);
}

static void copy_receiver_status(void)
{
    const e131_receiver_status_t *status = e131_receiver_status();
    rx_packet_ring_status_t ring = rx_packet_ring_status();

    g_counters.rx_ring_depth = ring.depth;
    g_counters.rx_ring_high_water = ring.high_water;
    g_counters.rx_ring_dropped = ring.dropped;
    g_counters.rx_ring_processed = ring.processed;
    g_counters.e131_valid = status->e131_valid;
    g_counters.e131_rejected = status->e131_rejected;
    g_counters.universes_seen = status->universes_seen;
    g_counters.frames_committed = status->frames_committed;
    g_counters.frames_dropped = status->frames_dropped;
    g_counters.complete_frames = status->complete_frames;
    g_counters.incomplete_sweeps = status->incomplete_sweeps;
    g_counters.ignored_sources = status->ignored_sources;
    g_counters.sequence_anomalies = status->sequence_anomalies;
    g_counters.preview_rejects = status->preview_rejects;
    g_counters.sync_waits = status->sync_waits;
    g_counters.sync_timeouts = status->sync_timeouts;
    g_counters.blackouts = status->blackouts;
    g_counters.last_packet_gap_ms = status->last_packet_gap_ms;
    g_counters.max_packet_gap_ms = status->max_packet_gap_ms;
    g_counters.last_frame_commit_gap_ms = status->last_frame_commit_gap_ms;
    g_counters.max_frame_commit_gap_ms = status->max_frame_commit_gap_ms;
    g_counters.last_universe = status->last_universe;
    g_counters.last_sequence = status->last_sequence;
    g_counters.last_error = status->last_error;
}

static void copy_lwip_pbuf_pool_stats(void)
{
    if (lwip_stats.memp[MEMP_PBUF_POOL] != NULL) {
        g_counters.rx_pbuf_alloc_failures = lwip_stats.memp[MEMP_PBUF_POOL]->err;
        g_counters.rx_pbuf_pool_used = lwip_stats.memp[MEMP_PBUF_POOL]->used;
        g_counters.rx_pbuf_pool_max = lwip_stats.memp[MEMP_PBUF_POOL]->max;
        g_counters.rx_pbuf_pool_avail = lwip_stats.memp[MEMP_PBUF_POOL]->avail;
    } else {
        g_counters.rx_pbuf_alloc_failures = UINT32_MAX;
        g_counters.rx_pbuf_pool_used = UINT32_MAX;
        g_counters.rx_pbuf_pool_max = UINT32_MAX;
        g_counters.rx_pbuf_pool_avail = UINT32_MAX;
        g_counters.last_error = "pbuf_stats_unavailable";
    }
}

static void receive_udp(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    uint8_t source_ip[4] = {0u, 0u, 0u, 0u};
    rx_packet_t *slot;
    int commit_result;

    (void)arg;
    (void)pcb;
    (void)port;

    if (p == NULL) {
        return;
    }

    g_counters.rx_packets++;
    g_input_packets_this_call++;
    g_counters.rx_bytes += p->tot_len;

    if (p->tot_len > RX_PACKET_RING_PAYLOAD_BYTES) {
        g_counters.rx_oversized++;
        g_counters.last_error = "too_large";
        pbuf_free(p);
        return;
    }

    slot = rx_packet_ring_reserve();
    if (slot == NULL) {
        g_counters.last_error = "rx_ring_full";
        pbuf_free(p);
        return;
    }

    if (p->len == p->tot_len) {
        memcpy(slot->payload, p->payload, p->tot_len);
    } else {
        pbuf_copy_partial(p, slot->payload, p->tot_len, 0u);
    }

    if (addr != NULL) {
#if LWIP_IPV6
        if (IP_IS_V4(addr)) {
            const ip4_addr_t *ip4 = ip_2_ip4(addr);
            source_ip[0] = ip4_addr1(ip4);
            source_ip[1] = ip4_addr2(ip4);
            source_ip[2] = ip4_addr3(ip4);
            source_ip[3] = ip4_addr4(ip4);
        }
#else
        source_ip[0] = ip4_addr1(addr);
        source_ip[1] = ip4_addr2(addr);
        source_ip[2] = ip4_addr3(addr);
        source_ip[3] = ip4_addr4(addr);
#endif
    }
    commit_result = rx_packet_ring_commit_reserved(slot, (uint16_t)p->tot_len, source_ip, g_poll_now_ms);
    if (commit_result != 0) {
        g_counters.last_error = "rx_ring_full";
    }

    pbuf_free(p);
}

int ethernet_receiver_init(void)
{
    ip_addr_t ip = make_ip(g_app_config.ip);
    ip_addr_t netmask = make_ip(g_app_config.netmask);
    ip_addr_t gateway = make_ip(g_app_config.gateway);

    g_counters = (ethernet_receiver_counters_t){0};
    g_counters.last_error = "init";
    rx_packet_ring_init();
    e131_receiver_init();
    lwip_init();

    if (xemac_add(&g_netif, &ip, &netmask, &gateway, (unsigned char *)g_app_config.mac, DONDER_EMAC_BASEADDR) == 0) {
        g_counters.last_error = "xemac_add";
        return -1;
    }

    netif_set_default(&g_netif);
    netif_set_up(&g_netif);
    g_counters.link_up = netif_is_link_up(&g_netif) ? 1u : 0u;

    g_udp = udp_new();
    if (g_udp == NULL) {
        g_counters.last_error = "udp_new";
        return -1;
    }
    if (udp_bind(g_udp, IP_ADDR_ANY, g_app_config.e131_port) != ERR_OK) {
        udp_remove(g_udp);
        g_udp = NULL;
        g_counters.last_error = "udp_bind";
        return -1;
    }
    udp_recv(g_udp, receive_udp, NULL);
    g_counters.last_error = "ok";

    xil_printf("net status=ready mac=%02x:%02x:%02x:%02x:%02x:%02x ip=%u.%u.%u.%u netmask=%u.%u.%u.%u gateway=%u.%u.%u.%u udp_port=%u emac=0x%08x link=%u\r\n",
               g_app_config.mac[0], g_app_config.mac[1], g_app_config.mac[2],
               g_app_config.mac[3], g_app_config.mac[4], g_app_config.mac[5],
               g_app_config.ip[0], g_app_config.ip[1], g_app_config.ip[2], g_app_config.ip[3],
               g_app_config.netmask[0], g_app_config.netmask[1], g_app_config.netmask[2], g_app_config.netmask[3],
               g_app_config.gateway[0], g_app_config.gateway[1], g_app_config.gateway[2], g_app_config.gateway[3],
               (unsigned int)g_app_config.e131_port,
               (unsigned int)DONDER_EMAC_BASEADDR,
               (unsigned int)g_counters.link_up);
    return 0;
}

void ethernet_receiver_poll(void)
{
    rx_packet_t packet;
    uint32_t poll_drained = 0u;
    uint32_t rounds_run = 0u;
    uint32_t last_round_packets = 0u;

    g_counters.link_up = netif_is_link_up(&g_netif) ? 1u : 0u;
    g_poll_now_ms = monotonic_ms();
    for (uint32_t round = 0u; round < RX_INPUT_ROUNDS_PER_POLL; ++round) {
        uint32_t round_drained = 0u;

        g_input_packets_this_call = 0u;
        g_counters.rx_input_calls++;
        xemacif_input(&g_netif);
        rounds_run++;
        last_round_packets = g_input_packets_this_call;
        if (g_input_packets_this_call > 0u) {
            g_counters.rx_input_active_calls++;
            if (g_input_packets_this_call > g_counters.rx_input_max_packets) {
                g_counters.rx_input_max_packets = g_input_packets_this_call;
            }
        }

        while (round_drained < RX_DRAIN_PER_INPUT_ROUND && rx_packet_ring_dequeue(&packet)) {
            e131_receiver_handle_packet(packet.payload, packet.length, packet.source_ip, packet.received_ms);
            round_drained++;
            poll_drained++;
        }

        if (g_input_packets_this_call == 0u && rx_packet_ring_status().depth == 0u) {
            break;
        }
    }
    if (poll_drained > g_counters.rx_poll_max_drained) {
        g_counters.rx_poll_max_drained = poll_drained;
    }
    if (rx_packet_ring_status().depth > 0u || (rounds_run == RX_INPUT_ROUNDS_PER_POLL && last_round_packets > 0u)) {
        g_counters.rx_poll_budget_hits++;
    }
    copy_lwip_pbuf_pool_stats();
    e131_receiver_poll(g_poll_now_ms);
    copy_receiver_status();
}

uint32_t ethernet_receiver_now_ms(void)
{
    return monotonic_ms();
}

const ethernet_receiver_counters_t *ethernet_receiver_counters(void)
{
    return &g_counters;
}

void ethernet_receiver_print_status(void)
{
    pl_ingest_snapshot_t snapshot;
    const pl_ingest_write_stats_t *write_stats = pl_ingest_write_stats();

    pl_ingest_snapshot(&snapshot);
    const e131_receiver_status_t *rx = e131_receiver_status();
    uint32_t total_pixels = frame_pipeline_active_pixel_count();
    uint32_t expected_universes = ((total_pixels * 3u) + DONDER_SLOTS_PER_UNIVERSE - 1u) / DONDER_SLOTS_PER_UNIVERSE;

    copy_lwip_pbuf_pool_stats();
    copy_receiver_status();

    xil_printf("e131_status link=%u ip=%u.%u.%u.%u port=%u active_outputs=%u pixels_per_output=%u total_pixels=%u expected_universes=%u required_commit_words=%u rx_packets=%u rx_bytes=%u rx_oversized=%u rx_ring_depth=%u rx_ring_high_water=%u rx_ring_dropped=%u rx_ring_processed=%u rx_pbuf_alloc_failures=%u rx_pbuf_pool_used=%u rx_pbuf_pool_max=%u rx_pbuf_pool_avail=%u rx_input_calls=%u rx_input_active_calls=%u rx_input_max_packets=%u rx_poll_max_drained=%u rx_poll_budget_hits=%u e131_valid=%u e131_rejected=%u universes_seen=%u frames_committed=%u frames_dropped=%u complete_frames=%u incomplete_sweeps=%u ignored_sources=%u sequence_anomalies=%u preview_rejects=%u sync_mode=%u sync_address=%u sync_waits=%u sync_timeouts=%u blackouts=%u packet_gap_ms=%u max_packet_gap_ms=%u commit_gap_ms=%u max_commit_gap_ms=%u ps_write_last_us=%u ps_write_max_us=%u ps_write_active_words=%u ps_write_required_words=%u ps_no_free_bank_waits=%u ps_no_free_bank_drops=%u source_locked=%u active_priority=%u source_ip=%u.%u.%u.%u last_universe=%u last_sequence=%u last_error=%s pl_frame_count=%u pl_committed_words=%u pl_error_count=%u pl_dropped=%u pl_rejected=%u consumer_frames=%u consumer_errors=%u pl_status=0x%08x consumer_status=0x%08x config_status=0x%08x\r\n",
               (unsigned int)g_counters.link_up,
               g_app_config.ip[0], g_app_config.ip[1], g_app_config.ip[2], g_app_config.ip[3],
               (unsigned int)g_app_config.e131_port,
               (unsigned int)frame_pipeline_active_output_count(),
               (unsigned int)frame_pipeline_strand_pixel_count(0u),
               (unsigned int)total_pixels,
               (unsigned int)expected_universes,
               (unsigned int)frame_pipeline_required_words(),
               (unsigned int)g_counters.rx_packets,
               (unsigned int)g_counters.rx_bytes,
               (unsigned int)g_counters.rx_oversized,
               (unsigned int)g_counters.rx_ring_depth,
               (unsigned int)g_counters.rx_ring_high_water,
               (unsigned int)g_counters.rx_ring_dropped,
               (unsigned int)g_counters.rx_ring_processed,
               (unsigned int)g_counters.rx_pbuf_alloc_failures,
               (unsigned int)g_counters.rx_pbuf_pool_used,
               (unsigned int)g_counters.rx_pbuf_pool_max,
               (unsigned int)g_counters.rx_pbuf_pool_avail,
               (unsigned int)g_counters.rx_input_calls,
               (unsigned int)g_counters.rx_input_active_calls,
               (unsigned int)g_counters.rx_input_max_packets,
               (unsigned int)g_counters.rx_poll_max_drained,
               (unsigned int)g_counters.rx_poll_budget_hits,
               (unsigned int)g_counters.e131_valid,
               (unsigned int)g_counters.e131_rejected,
               (unsigned int)g_counters.universes_seen,
               (unsigned int)g_counters.frames_committed,
               (unsigned int)g_counters.frames_dropped,
               (unsigned int)g_counters.complete_frames,
               (unsigned int)g_counters.incomplete_sweeps,
               (unsigned int)g_counters.ignored_sources,
               (unsigned int)g_counters.sequence_anomalies,
               (unsigned int)g_counters.preview_rejects,
               (unsigned int)rx->sync_mode,
               (unsigned int)rx->sync_address,
               (unsigned int)g_counters.sync_waits,
               (unsigned int)g_counters.sync_timeouts,
               (unsigned int)g_counters.blackouts,
               (unsigned int)g_counters.last_packet_gap_ms,
               (unsigned int)g_counters.max_packet_gap_ms,
               (unsigned int)g_counters.last_frame_commit_gap_ms,
               (unsigned int)g_counters.max_frame_commit_gap_ms,
               (unsigned int)write_stats->last_write_us,
               (unsigned int)write_stats->max_write_us,
               (unsigned int)write_stats->last_active_words,
               (unsigned int)write_stats->last_required_words,
               (unsigned int)write_stats->no_free_bank_waits,
               (unsigned int)write_stats->no_free_bank_drops,
               (unsigned int)rx->source_locked,
               (unsigned int)rx->active_priority,
               rx->source_ip[0], rx->source_ip[1], rx->source_ip[2], rx->source_ip[3],
               (unsigned int)g_counters.last_universe,
               (unsigned int)g_counters.last_sequence,
               g_counters.last_error,
               (unsigned int)snapshot.frame_count,
               (unsigned int)snapshot.committed_words,
               (unsigned int)snapshot.error_count,
               (unsigned int)snapshot.frame_dropped,
               (unsigned int)snapshot.frame_rejected,
               (unsigned int)snapshot.consumer_frame_count,
               (unsigned int)snapshot.consumer_error_count,
               (unsigned int)snapshot.status,
               (unsigned int)snapshot.consumer_status,
               (unsigned int)snapshot.config_status);
}
