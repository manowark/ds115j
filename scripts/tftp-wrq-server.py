#!/usr/bin/env python3
"""One-shot TFTP WRQ listener for U-Boot tftpput.

Conflicts with tftpd-hpa on UDP/69. Only run after:
    systemctl stop tftpd-hpa
and start tftpd-hpa again when the dump is done.

Does not write the NAS. Writes files under --dir only.
"""
from __future__ import annotations

import argparse
import os
import socket
import struct
import sys

RRQ, WRQ, DATA, ACK, ERR = 1, 2, 3, 4, 5
BLK = 512


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--dir",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "backups",
            "spi",
        ),
    )
    p.add_argument("--port", type=int, default=69)
    p.add_argument("--expect", type=int, default=8388608)
    args = p.parse_args()
    os.makedirs(args.dir, exist_ok=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", args.port))
    print(f"TFTP WRQ on :{args.port}, dir={args.dir}", flush=True)
    print("U-Boot: tftpput 0x02000000 0x800000 ds115j-spi-8m.bin", flush=True)

    data, addr = sock.recvfrom(4096)
    if len(data) < 4 or struct.unpack("!H", data[:2])[0] != WRQ:
        print("not a WRQ, exiting", file=sys.stderr)
        return 1
    rest = data[2:].split(b"\x00")
    name = os.path.basename(rest[0].decode("ascii", "replace") or "dump.bin")
    path = os.path.join(args.dir, name)
    print(f"WRQ {name} from {addr} -> {path}", flush=True)

    # ACK block 0 to start
    tsock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tsock.settimeout(30)
    tsock.sendto(struct.pack("!HH", ACK, 0), addr)

    with open(path, "wb") as f:
        expect_block = 1
        while True:
            pkt, src = tsock.recvfrom(4 + BLK + 4)
            opc = struct.unpack("!H", pkt[:2])[0]
            if opc != DATA:
                print("unexpected opcode", opc, file=sys.stderr)
                return 1
            block = struct.unpack("!H", pkt[2:4])[0]
            chunk = pkt[4:]
            if block != expect_block:
                tsock.sendto(struct.pack("!HH", ACK, block), src)
                continue
            f.write(chunk)
            tsock.sendto(struct.pack("!HH", ACK, block), src)
            if len(chunk) < BLK:
                break
            expect_block = (expect_block + 1) & 0xFFFF

    size = os.path.getsize(path)
    print(f"got {size} bytes")
    if size != args.expect:
        print(f"WARNING: expected {args.expect}", file=sys.stderr)
        return 2
    print("OK 8 MiB. Restart: systemctl start tftpd-hpa")
    return 0


if __name__ == "__main__":
    sys.exit(main())
