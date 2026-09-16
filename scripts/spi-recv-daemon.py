#!/usr/bin/env python3
"""Accept SPI dumps on TCP 45151 into /root/ds115j/backups/spi/.

One connection = one file. Stays up for further dumps. Does not write NAS flash.
"""
from __future__ import annotations

import hashlib
import os
import socket
import time

DIR = "/root/ds115j/backups/spi"
PORT = 45151
EXPECT = 8388608


def main() -> None:
    os.makedirs(DIR, exist_ok=True)
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", PORT))
    sock.listen(2)
    print(f"spi-recv on 0.0.0.0:{PORT} -> {DIR}", flush=True)
    while True:
        c, addr = sock.accept()
        stamp = time.strftime("%Y%m%d-%H%M%S")
        path = os.path.join(DIR, f"ds115j-spi-8m-{stamp}.bin")
        print(f"connection {addr} -> {path}", flush=True)
        h = hashlib.sha256()
        n = 0
        with open(path, "wb") as f:
            while True:
                b = c.recv(1024 * 1024)
                if not b:
                    break
                f.write(b)
                h.update(b)
                n += len(b)
        c.close()
        print(f"got {n} bytes sha256={h.hexdigest()}", flush=True)
        if n == EXPECT:
            link = os.path.join(DIR, "ds115j-spi-8m.bin")
            os.symlink(os.path.basename(path), link + ".new")
            os.replace(link + ".new", link)
            with open(path + ".sha256", "w") as s:
                s.write(f"{h.hexdigest()}  {path}\n")
            print("OK 8 MiB — still do not saveenv", flush=True)
        else:
            print("WARNING: not 8 MiB; do not saveenv", flush=True)


if __name__ == "__main__":
    main()
