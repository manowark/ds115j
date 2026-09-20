#!/usr/bin/env python3
"""Minimal ext2 reader for the DS115j DSM initrd rootfs image (blockmap, 128B inodes)."""
import struct, sys, os

IMG = 'initrd-lzma-0.bin'
OUT = 'rootfs-extract'

raw = open(IMG, 'rb').read()
sb = raw[1024:2048]
bs = 1024 << struct.unpack_from('<I', sb, 24)[0]
inodes_n = struct.unpack_from('<I', sb, 0)[0]
first_db = struct.unpack_from('<I', sb, 20)[0]
bpg = struct.unpack_from('<I', sb, 32)[0]
ipg = struct.unpack_from('<I', sb, 40)[0]
inode_size = struct.unpack_from('<H', sb, 88)[0]
ngroups = (inodes_n + ipg - 1) // ipg
gdt_off = (first_db + 1) * bs

def group_info(g):
    e = gdt_off + g * 32
    return struct.unpack_from('<II', raw, e)  # (bb_bitmap, ib_bitmap) ... itable at +8

def inode_raw(ino):
    g = (ino - 1) // ipg
    _, _, itable = struct.unpack_from('<III', raw, gdt_off + g * 32)
    idx = itable * bs + (ino - 1 - g * ipg) * inode_size
    return raw[idx:idx + inode_size]

BLOCK = 0x10000
def block_ptr(ino_blk, level=0):
    if level == 0:
        return ino_blk
    tab = ino_blk * bs
    base = raw[tab:tab + bs]
    return [struct.unpack_from('<I', base, i)[0] for i in range(0, bs, 4) if struct.unpack_from('<I', base, i)[0]]

def file_blocks(ino):
    mode = struct.unpack_from('<H', ino, 0)[0]
    size = struct.unpack_from('<I', ino, 4)[0]
    flags = struct.unpack_from('<I', ino, 32)[0]
    size |= struct.unpack_from('<I', ino, 108)[0] << 32
    blocks = [struct.unpack_from('<I', ino, 40 + 4 * i)[0] for i in range(12)]
    ind = [struct.unpack_from('<I', ino, 40 + 48 + 4 * i)[0] for i in range(3)]  # s,d,t
    return mode, size, flags, blocks, ind

def read_indirect(tab_block, depth):
    if depth == 0:
        yield tab_block
        return
    base = raw[tab_block * bs:(tab_block + 1) * bs]
    for i in range(0, bs, 4):
        b = struct.unpack_from('<I', base, i)[0]
        if b:
            yield from read_indirect(b, depth - 1)

def read_file(ino, limit=40 * 1024 * 1024):
    mode, size, flags, blocks, ind = file_blocks(inode_raw(ino))
    data = bytearray()
    for b in blocks:
        if b: data += raw[b * bs:(b + 1) * bs]
    levels = ((ind[0], 1), (ind[1], 2), (ind[2], 3))
    for tab, depth in levels:
        if tab:
            for b in read_indirect(tab, depth):
                if b: data += raw[b * bs:(b + 1) * bs]
    return bytes(data[:size]), size

def walk(ino, path, out):
    mode, size, flags, blocks, ind = file_blocks(inode_raw(ino))
    ftype = (mode >> 12) & 0xF
    if ftype == 4:  # dir (S_IFDIR>>12)
        data, _ = read_file(ino)
        off = 0
        print(f"DIR  {path}")
        while off + 8 <= len(data):
            i, rec, nl, ft = struct.unpack_from('<IHBB', data, off)
            name = data[off + 8: off + 8 + nl].decode('latin1')
            if i and name not in ('.', '..'):
                walk(i, os.path.join(path, name), out)
            off += rec
    elif ftype == 8:  # regular
        data, size = read_file(ino)
        dst = os.path.join(out, path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, 'wb') as f:
            f.write(data)
        print(f"{size:>10}  {path}")
    elif ftype == 1:  # fifo
        pass

root_ino = raw[gdt_off:gdt_off + 32][8:12]
# root inode 2
walk(2, '', OUT)