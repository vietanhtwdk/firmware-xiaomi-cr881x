#!/usr/bin/env python3
"""Unpack Xiaomi router firmware.

  xiaomi_fw.py hdr1 <miwifi_*.bin> <out.ubi>   extract the UBI image (root.ubi blob)
  xiaomi_fw.py ubi  <image.ubi|mtdN.bin> <dir> extract UBI volumes as <id>_<name>.bin
"""
import os
import struct
import sys

PEB = 128 * 1024
UBI_LAYOUT_VOL = 0x7FFFEFFF


def hdr1(src, dst):
    data = open(src, 'rb').read()
    if data[:4] != b'HDR1':
        sys.exit(f'{src}: not a Xiaomi HDR1 image')
    # Blob offsets follow the 16 byte header, terminated by zero
    for i in range(8):
        off = struct.unpack_from('<I', data, 0x10 + 4 * i)[0]
        if not off:
            break
        magic, _, size, _, name = struct.unpack_from('<IIIi32s', data, off)
        name = name.split(b'\0')[0].decode()
        body = data[off + 0x30:off + 0x30 + size]
        print(f'blob {name}: {size} bytes @ {off + 0x30:#x}')
        if name == 'root.ubi':
            if body[:4] != b'UBI#':
                sys.exit('root.ubi does not start with a UBI header')
            open(dst, 'wb').write(body)
            return
    sys.exit('root.ubi blob not found')


def ubi(src, out):
    img = open(src, 'rb').read()
    os.makedirs(out, exist_ok=True)
    vols, names = {}, {}
    for off in range(0, len(img), PEB):
        blk = img[off:off + PEB]
        if blk[:4] != b'UBI#':
            continue
        vid_off, data_off = struct.unpack('>II', blk[16:24])
        vh = blk[vid_off:vid_off + 64]
        if vh[:4] != b'UBI!':
            continue
        vol_type = vh[5]
        vol_id, lnum = struct.unpack('>II', vh[8:16])
        data_size = struct.unpack('>I', vh[20:24])[0]
        sqnum = struct.unpack('>Q', vh[40:48])[0]
        payload = blk[data_off:]
        if vol_type == 2 and data_size:  # static volume
            payload = payload[:data_size]
        prev = vols.setdefault(vol_id, {}).get(lnum)
        if prev is None or prev[0] < sqnum:
            vols[vol_id][lnum] = (sqnum, payload)

    if UBI_LAYOUT_VOL in vols:
        tbl = vols.pop(UBI_LAYOUT_VOL)[0][1]
        for i in range(128):
            rec = tbl[i * 172:(i + 1) * 172]
            if struct.unpack('>I', rec[:4])[0]:
                nlen = struct.unpack('>H', rec[14:16])[0]
                names[i] = rec[16:16 + nlen].decode()

    for vid, lebs in sorted(vols.items()):
        name = names.get(vid, f'vol{vid}')
        data = b''.join(lebs[l][1] for l in sorted(lebs))
        path = os.path.join(out, f'{vid}_{name}.bin')
        open(path, 'wb').write(data)
        print(f'volume {vid} {name}: {len(lebs)} LEBs -> {path}')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('hdr1', 'ubi'):
        sys.exit(__doc__)
    {'hdr1': hdr1, 'ubi': ubi}[sys.argv[1]](sys.argv[2], sys.argv[3])
