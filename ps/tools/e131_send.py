#!/usr/bin/env python3
import argparse
import math
import socket
import struct
import time
import uuid

from generated import pl_config


SLOTS_PER_UNIVERSE = pl_config.E131_SLOTS_PER_UNIVERSE
DEFAULT_CID = uuid.UUID("d06d0ead-beef-4000-8000-000000000001")
DEFAULT_SYNC_ADDRESS = pl_config.E131_DEFAULT_SYNC_ADDRESS


def rgb_for_pixel(pattern, pixel, frame, pixels_per_output):
    output = pixel // pixels_per_output
    index = pixel % pixels_per_output
    if pattern == "red":
        return 255, 0, 0
    if pattern == "green":
        return 0, 255, 0
    if pattern == "blue":
        return 0, 0, 255
    if pattern == "white":
        return 64, 64, 64
    if pattern == "bars":
        colors = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (64, 64, 64))
        return colors[output % len(colors)]
    if pattern == "chase":
        return (255, 128, 16) if ((index + frame * 4 + output * 32) % 128) < 16 else (0, 0, 0)
    phase = (index + frame + output * 64) & 0xFF
    return phase, 255 - phase, (frame + output * 32) & 0xFF


def build_slots(pattern, first_slot, slot_count, frame, pixels_per_output, total_pixels):
    slots = bytearray()
    for slot in range(first_slot, first_slot + slot_count, 3):
        pixel = slot // 3
        if pixel < total_pixels:
            slots.extend(rgb_for_pixel(pattern, pixel, frame, pixels_per_output))
        else:
            slots.extend((0, 0, 0))
    return bytes(slots[:slot_count])


def flags_and_length(length):
    return 0x7000 | length


def build_packet(universe, sequence, slots, cid, priority, sync_address, options):
    prop_count = len(slots) + 1
    total_len = 126 + len(slots)
    packet = bytearray(total_len)
    packet[0:2] = struct.pack(">H", 0x0010)
    packet[2:4] = struct.pack(">H", 0x0000)
    packet[4:16] = b"ASC-E1.17\x00\x00\x00"
    packet[16:18] = struct.pack(">H", flags_and_length(total_len - 16))
    packet[18:22] = struct.pack(">I", 0x00000004)
    packet[22:38] = cid.bytes
    packet[38:40] = struct.pack(">H", flags_and_length(total_len - 38))
    packet[40:44] = struct.pack(">I", 0x00000002)
    source = b"donder e131 sender"
    packet[44:44 + len(source)] = source
    packet[108] = priority
    packet[109:111] = struct.pack(">H", sync_address)
    packet[111] = sequence & 0xFF
    packet[112] = options
    packet[113:115] = struct.pack(">H", universe)
    packet[115:117] = struct.pack(">H", flags_and_length(total_len - 115))
    packet[117] = 0x02
    packet[118] = 0xA1
    packet[119:121] = struct.pack(">H", 0)
    packet[121:123] = struct.pack(">H", 1)
    packet[123:125] = struct.pack(">H", prop_count)
    packet[125] = 0
    packet[126:] = slots
    return bytes(packet)


def build_sync_packet(sequence, cid, sync_address):
    total_len = 49
    packet = bytearray(total_len)
    packet[0:2] = struct.pack(">H", 0x0010)
    packet[2:4] = struct.pack(">H", 0x0000)
    packet[4:16] = b"ASC-E1.17\x00\x00\x00"
    packet[16:18] = struct.pack(">H", flags_and_length(total_len - 16))
    packet[18:22] = struct.pack(">I", 0x00000008)
    packet[22:38] = cid.bytes
    packet[38:40] = struct.pack(">H", flags_and_length(total_len - 38))
    packet[40:44] = struct.pack(">I", 0x00000001)
    packet[44] = sequence & 0xFF
    packet[45:47] = struct.pack(">H", sync_address)
    packet[47:49] = struct.pack(">H", 0)
    return bytes(packet)


def parse_args():
    parser = argparse.ArgumentParser(description="Send deterministic E1.31/sACN data packets.")
    parser.add_argument("--dest-ip", default=pl_config.BOARD_IP_STRING)
    parser.add_argument("--source-ip", default="", help="Optional local source IP/interface to bind before sending.")
    parser.add_argument("--port", type=int, default=pl_config.E131_PORT)
    parser.add_argument("--first-universe", type=int, default=pl_config.E131_FIRST_UNIVERSE)
    parser.add_argument("--universe-count", type=int, default=0, help="0 derives the count from outputs and pixels per output.")
    parser.add_argument("--outputs", type=int, default=pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT)
    parser.add_argument("--pixels-per-output", type=int, default=pl_config.DEFAULT_STRAND_PIXEL_COUNT)
    parser.add_argument("--pattern", choices=("gradient", "bars", "chase", "red", "green", "blue", "white"), default="gradient")
    parser.add_argument("--packet-count", type=int, default=0, help="Frame count to send; 0 means run until Ctrl+C.")
    parser.add_argument("--duration", type=float, default=0.0, help="Run for this many seconds; 0 means use --packet-count.")
    parser.add_argument("--rate", type=float, default=30.0, help="Frame rate in complete universe sweeps per second.")
    parser.add_argument("--priority", type=int, default=100)
    parser.add_argument("--source-cid", default=str(DEFAULT_CID))
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--stream-terminate", action="store_true")
    parser.add_argument("--sync-address", type=int, default=0, help="0 sends unsynced data packets.")
    parser.add_argument("--send-sync", action="store_true", help=f"Emit an E1.31 sync packet after each sweep. Defaults to sync universe {DEFAULT_SYNC_ADDRESS} when --sync-address is omitted.")
    parser.add_argument("--json", action="store_true", help="Print one JSON result object.")
    parser.add_argument("--csv", action="store_true", help="Print one CSV result row with a header.")
    return parser.parse_args()


def main():
    args = parse_args()
    total_pixels = args.outputs * args.pixels_per_output
    total_slots = total_pixels * 3
    universe_count = args.universe_count
    if universe_count <= 0:
        universe_count = math.ceil(total_slots / SLOTS_PER_UNIVERSE)
    delay = 0.0 if args.rate <= 0 else 1.0 / args.rate
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.source_ip:
        sock.bind((args.source_ip, 0))
    cid = uuid.UUID(args.source_cid)
    sync_address = args.sync_address
    if args.send_sync and sync_address == 0:
        sync_address = DEFAULT_SYNC_ADDRESS
    data_options = 0
    if args.preview:
        data_options |= 0x80
    if args.stream_terminate:
        data_options |= 0x40
    frame = 0
    sequence = 0
    sync_sequence = 0
    packets_sent = 0
    bytes_sent = 0
    start = time.monotonic()
    next_frame_time = start
    deadline = start + args.duration if args.duration > 0 else None
    try:
        while (args.packet_count == 0 or frame < args.packet_count) and (deadline is None or time.monotonic() < deadline):
            for offset in range(universe_count):
                first_slot = offset * SLOTS_PER_UNIVERSE
                slot_count = min(SLOTS_PER_UNIVERSE, max(0, total_slots - first_slot))
                if slot_count <= 0:
                    break
                slots = build_slots(args.pattern, first_slot, slot_count, frame, args.pixels_per_output, total_pixels)
                packet = build_packet(args.first_universe + offset, sequence, slots, cid, args.priority, sync_address, data_options)
                bytes_sent += sock.sendto(packet, (args.dest_ip, args.port))
                packets_sent += 1
                sequence = (sequence + 1) & 0xFF
            if args.send_sync:
                packet = build_sync_packet(sync_sequence, cid, sync_address)
                bytes_sent += sock.sendto(packet, (args.dest_ip, args.port))
                packets_sent += 1
                sync_sequence = (sync_sequence + 1) & 0xFF
            frame += 1
            more_frames = args.packet_count == 0 or frame < args.packet_count
            more_time = deadline is None or time.monotonic() < deadline
            if delay > 0 and more_frames and more_time:
                next_frame_time += delay
                sleep_until = next_frame_time
                if deadline is not None and deadline < sleep_until:
                    sleep_until = deadline
                sleep_time = sleep_until - time.monotonic()
                if sleep_time > 0:
                    time.sleep(sleep_time)
    except KeyboardInterrupt:
        pass
    actual_duration = time.monotonic() - start
    result = {
        "dest": f"{args.dest_ip}:{args.port}",
        "source_ip": args.source_ip,
        "first_universe": args.first_universe,
        "universe_count": universe_count,
        "outputs": args.outputs,
        "pixels_per_output": args.pixels_per_output,
        "total_pixels": total_pixels,
        "target_fps": args.rate,
        "actual_duration": actual_duration,
        "frames_sent": frame,
        "packets_sent": packets_sent,
        "bytes_sent": bytes_sent,
        "packet_rate": packets_sent / actual_duration if actual_duration > 0 else 0.0,
        "mbps": (bytes_sent * 8.0) / (actual_duration * 1000000.0) if actual_duration > 0 else 0.0,
        "pattern": args.pattern,
        "priority": args.priority,
        "cid": str(cid),
        "sync_address": sync_address,
        "send_sync": args.send_sync,
    }
    if args.json:
        import json
        print(json.dumps(result, sort_keys=True))
    elif args.csv:
        import csv
        import sys
        writer = csv.DictWriter(sys.stdout, fieldnames=list(result.keys()))
        writer.writeheader()
        writer.writerow(result)
    else:
        print(" ".join(f"{key}={value}" for key, value in result.items()))


if __name__ == "__main__":
    main()
