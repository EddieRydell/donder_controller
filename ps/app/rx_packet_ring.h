#ifndef RX_PACKET_RING_H
#define RX_PACKET_RING_H

#include <stdint.h>

#include "generated/pl_config.h"

#define RX_PACKET_RING_DEPTH DONDER_PL_RX_PACKET_RING_DEPTH
#define RX_PACKET_RING_PAYLOAD_BYTES DONDER_PL_E131_MAX_PACKET_BYTES

typedef struct {
    uint8_t payload[RX_PACKET_RING_PAYLOAD_BYTES];
    uint16_t length;
    uint8_t source_ip[4];
    uint32_t received_ms;
} rx_packet_t;

typedef struct {
    uint32_t depth;
    uint32_t high_water;
    uint32_t dropped;
    uint32_t processed;
} rx_packet_ring_status_t;

void rx_packet_ring_init(void);
rx_packet_t *rx_packet_ring_reserve(void);
int rx_packet_ring_commit_reserved(rx_packet_t *slot,
                                   uint16_t length,
                                   const uint8_t source_ip[4],
                                   uint32_t received_ms);
int rx_packet_ring_enqueue(const uint8_t *payload,
                           uint16_t length,
                           const uint8_t source_ip[4],
                           uint32_t received_ms);
int rx_packet_ring_dequeue(rx_packet_t *packet);
rx_packet_ring_status_t rx_packet_ring_status(void);

#endif
