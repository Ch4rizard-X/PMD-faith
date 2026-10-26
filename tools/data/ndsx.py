import struct, os, sys
d = open(sys.argv[1],'rb').read()
out = sys.argv[2]
print(d[0:12], d[12:16])
fnt_off, fnt_sz, fat_off, fat_sz = struct.unpack_from('<IIII', d, 0x40)
arm9_off, _, _, arm9_sz = struct.unpack_from('<IIII', d, 0x20)
ov9_off, ov9_sz = struct.unpack_from('<II', d, 0x50)
open(os.path.join(out,'arm9.bin'),'wb').write(d[arm9_off:arm9_off+arm9_sz])
def fat(i):
    s,e = struct.unpack_from('<II', d, fat_off+8*i); return d[s:e]
# overlays
for k in range(ov9_sz//32):
    ovid, ram, size, bss, sinit_s, sinit_e, fid, flags = struct.unpack_from('<8I', d, ov9_off+32*k)
    open(os.path.join(out,f'overlay_{ovid:04d}.bin'),'wb').write(fat(fid))
def walk(dir_id, path):
    off, first, _ = struct.unpack_from('<IHH', d, fnt_off + 8*(dir_id & 0xFFF))
    p = fnt_off + off; fid = first
    while True:
        t = d[p]; p += 1
        if t == 0: break
        ln = t & 0x7F; name = d[p:p+ln].decode('latin1'); p += ln
        if t & 0x80:
            sub, = struct.unpack_from('<H', d, p); p += 2
            walk(sub, os.path.join(path, name))
        else:
            fp = os.path.join(out, 'fs', path, name)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            open(fp,'wb').write(fat(fid)); fid += 1
walk(0xF000, '')
