import struct
def px_decompress(data, flags):
    out = bytearray(); i = 0; n = len(data)
    while i < n:
        ctrl = data[i]; i += 1
        for b in range(7, -1, -1):
            if i >= n: break
            if ctrl & (1 << b):
                out.append(data[i]); i += 1
            else:
                nx = data[i]; i += 1
                hi = (nx >> 4) & 0xF; lo = nx & 0xF
                if hi in flags:
                    idx = flags.index(hi)
                    if idx == 0:
                        v = (lo << 4) | lo; out += bytes([v, v])
                    else:
                        base = lo
                        if idx == 1: base = (base + 1) & 0xFF
                        elif idx == 5: base = (base - 1) & 0xFF
                        ns = [base] * 4
                        if 1 <= idx <= 4: ns[idx - 1] = (ns[idx - 1] - 1) & 0xFF
                        else: ns[idx - 5] = (ns[idx - 5] + 1) & 0xFF
                        out += bytes([((ns[0] << 4) | ns[1]) & 0xFF, ((ns[2] << 4) | ns[3]) & 0xFF])
                else:
                    off = (-0x1000 + (lo << 8)) | data[i]; i += 1
                    cnt = hi + 3
                    st = len(out) + off
                    for k in range(cnt):
                        out.append(out[st + k])
    return bytes(out)

def unpx(b):
    if b[:5] == b'AT4PX':
        flags = list(b[7:16]); size = struct.unpack_from('<H', b, 16)[0]
        return px_decompress(b[18:], flags)[:size]
    if b[:5] == b'PKDPX':
        flags = list(b[7:16]); size = struct.unpack_from('<I', b, 16)[0]
        return px_decompress(b[20:], flags)[:size]
    return b

def sir0_content(b):
    if b[:4] != b'SIR0': return b, 0
    dp, po = struct.unpack_from('<II', b, 4)
    return b, dp

def pack_entries(d):
    n = struct.unpack_from('<I', d, 4)[0]
    return [d[o:o + l] for o, l in (struct.unpack_from('<II', d, 8 + 8 * i) for i in range(n))]
