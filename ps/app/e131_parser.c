#include "e131_parser.h"

#include <stddef.h>

#include "app_config.h"

#define E131_MIN_PACKET_BYTES 126u
#define E131_MIN_SYNC_PACKET_BYTES 49u
#define E131_ROOT_VECTOR_DATA 0x00000004u
#define E131_ROOT_VECTOR_EXTENDED 0x00000008u
#define E131_FRAME_VECTOR_DATA 0x00000002u
#define E131_FRAME_VECTOR_SYNC 0x00000001u
#define E131_DMP_VECTOR_DATA 0x02u
#define E131_DMP_ADDRESS_TYPE 0xa1u

static uint16_t read_be16(const uint8_t *data)
{
    return (uint16_t)(((uint16_t)data[0] << 8) | data[1]);
}

static uint32_t read_be32(const uint8_t *data)
{
    return ((uint32_t)data[0] << 24)
         | ((uint32_t)data[1] << 16)
         | ((uint32_t)data[2] << 8)
         | data[3];
}

const char *e131_parse_result_name(e131_parse_result_t result)
{
    switch (result) {
    case E131_PARSE_OK: return "ok";
    case E131_PARSE_SHORT: return "short";
    case E131_PARSE_ACN_ID: return "acn_id";
    case E131_PARSE_ROOT_VECTOR: return "root_vector";
    case E131_PARSE_FRAME_VECTOR: return "frame_vector";
    case E131_PARSE_SYNC_VECTOR: return "sync_vector";
    case E131_PARSE_DMP_VECTOR: return "dmp_vector";
    case E131_PARSE_DMP_ADDRESS: return "dmp_address";
    case E131_PARSE_PROP_COUNT: return "prop_count";
    case E131_PARSE_START_CODE: return "start_code";
    case E131_PARSE_UNIVERSE: return "universe";
    default: return "unknown";
    }
}

static e131_parse_result_t check_acn_id(const uint8_t *data, uint16_t length, uint16_t min_length)
{
    static const uint8_t acn_id[12] = {
        'A', 'S', 'C', '-', 'E', '1', '.', '1', '7', 0x00u, 0x00u, 0x00u,
    };

    if (data == NULL || length < min_length) {
        return E131_PARSE_SHORT;
    }
    for (uint32_t i = 0u; i < sizeof(acn_id); ++i) {
        if (data[4u + i] != acn_id[i]) {
            return E131_PARSE_ACN_ID;
        }
    }
    return E131_PARSE_OK;
}

e131_parse_result_t e131_parse_data_packet(const uint8_t *data,
                                           uint16_t length,
                                           uint16_t first_universe,
                                           uint32_t total_pixels,
                                           e131_data_packet_t *packet)
{
    uint16_t prop_count;
    uint16_t universe;
    uint32_t universe_offset;
    uint32_t first_slot;
    uint32_t available_rgb_slots;
    e131_parse_result_t acn_result;

    if (packet == NULL) {
        return E131_PARSE_SHORT;
    }

    acn_result = check_acn_id(data, length, E131_MIN_PACKET_BYTES);
    if (acn_result != E131_PARSE_OK) {
        return acn_result;
    }
    if (read_be32(&data[18]) != E131_ROOT_VECTOR_DATA) {
        return E131_PARSE_ROOT_VECTOR;
    }
    if (read_be32(&data[40]) != E131_FRAME_VECTOR_DATA) {
        return E131_PARSE_FRAME_VECTOR;
    }
    if (data[117] != E131_DMP_VECTOR_DATA) {
        return E131_PARSE_DMP_VECTOR;
    }
    if (data[118] != E131_DMP_ADDRESS_TYPE || read_be16(&data[119]) != 0u || read_be16(&data[121]) != 1u) {
        return E131_PARSE_DMP_ADDRESS;
    }

    prop_count = read_be16(&data[123]);
    if (prop_count < 1u || prop_count > (DONDER_SLOTS_PER_UNIVERSE + 1u)
        || (uint32_t)E131_MIN_PACKET_BYTES + (uint32_t)prop_count - 1u > length) {
        return E131_PARSE_PROP_COUNT;
    }
    if (data[125] != 0u) {
        return E131_PARSE_START_CODE;
    }

    universe = read_be16(&data[113]);
    if (universe < first_universe) {
        return E131_PARSE_UNIVERSE;
    }
    universe_offset = (uint32_t)(universe - first_universe);
    first_slot = universe_offset * DONDER_SLOTS_PER_UNIVERSE;
    if (first_slot >= total_pixels * 3u) {
        return E131_PARSE_UNIVERSE;
    }

    available_rgb_slots = prop_count - 1u;
    if ((available_rgb_slots % 3u) != 0u) {
        return E131_PARSE_PROP_COUNT;
    }

    packet->cid = &data[22];
    packet->priority = data[108];
    packet->sync_address = read_be16(&data[109]);
    packet->universe = universe;
    packet->sequence = data[111];
    packet->options = data[112];
    packet->rgb_slots = &data[126];
    packet->rgb_slot_count = (uint16_t)available_rgb_slots;
    packet->first_linear_pixel = first_slot / 3u;
    packet->rgb_pixel_count = available_rgb_slots / 3u;
    if (packet->first_linear_pixel + packet->rgb_pixel_count > total_pixels) {
        packet->rgb_pixel_count = total_pixels - packet->first_linear_pixel;
    }

    return E131_PARSE_OK;
}

e131_parse_result_t e131_parse_sync_packet(const uint8_t *data,
                                           uint16_t length,
                                           e131_sync_packet_t *packet)
{
    e131_parse_result_t acn_result;

    if (packet == NULL) {
        return E131_PARSE_SHORT;
    }

    acn_result = check_acn_id(data, length, E131_MIN_SYNC_PACKET_BYTES);
    if (acn_result != E131_PARSE_OK) {
        return acn_result;
    }
    if (read_be32(&data[18]) != E131_ROOT_VECTOR_EXTENDED) {
        return E131_PARSE_ROOT_VECTOR;
    }
    if (read_be32(&data[40]) != E131_FRAME_VECTOR_SYNC) {
        return E131_PARSE_SYNC_VECTOR;
    }

    packet->cid = &data[22];
    packet->sequence = data[44];
    packet->sync_address = read_be16(&data[45]);
    return E131_PARSE_OK;
}
