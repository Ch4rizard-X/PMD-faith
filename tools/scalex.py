"""Stand-in for the xBRZ scaler where the compiled library can't be had (the APK's on-phone build without a packed
libxbrz): Scale2x / Scale3x (EPX family, Andrea Mazzoleni's AdvMAME rules) in NumPy. Same interface as xbrz.py's
scale_pillow(img, factor) for factors 2..6 (4 = 2x then 2x, 6 = 2x then 3x, 5 = 3x then 2x and a resize)."""
import numpy as np
from PIL import Image


def _pad(a):
    return np.pad(a, 1, mode="edge")


def scale2x(a):
    """a: (h, w) uint32 colours -> (2h, 2w)."""
    p = _pad(a)
    B, D, E, F, H = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:], p[2:, 1:-1]
    ok = (B != H) & (D != F)
    e0 = np.where(ok & (D == B), D, E)
    e1 = np.where(ok & (B == F), F, E)
    e2 = np.where(ok & (D == H), D, E)
    e3 = np.where(ok & (H == F), F, E)
    h, w = a.shape
    out = np.empty((2 * h, 2 * w), a.dtype)
    out[0::2, 0::2], out[0::2, 1::2], out[1::2, 0::2], out[1::2, 1::2] = e0, e1, e2, e3
    return out


def scale3x(a):
    p = _pad(a)
    A, B, C = p[:-2, :-2], p[:-2, 1:-1], p[:-2, 2:]
    D, E, F = p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:]
    G, H, I = p[2:, :-2], p[2:, 1:-1], p[2:, 2:]
    ok = (B != H) & (D != F)
    e = [None] * 9
    e[0] = np.where(ok & (D == B), D, E)
    e[1] = np.where(ok & (((D == B) & (E != C)) | ((B == F) & (E != A))), B, E)
    e[2] = np.where(ok & (B == F), F, E)
    e[3] = np.where(ok & (((D == B) & (E != G)) | ((D == H) & (E != A))), D, E)
    e[4] = E
    e[5] = np.where(ok & (((B == F) & (E != I)) | ((H == F) & (E != C))), F, E)
    e[6] = np.where(ok & (D == H), D, E)
    e[7] = np.where(ok & (((D == H) & (E != I)) | ((H == F) & (E != G))), H, E)
    e[8] = np.where(ok & (H == F), F, E)
    h, w = a.shape
    out = np.empty((3 * h, 3 * w), a.dtype)
    for k in range(9):
        out[k // 3::3, k % 3::3] = e[k]
    return out


def scale_pillow(img, factor):
    img = img.convert("RGBA")
    a = np.ascontiguousarray(np.asarray(img, np.uint8)).view(np.uint32)[:, :, 0]
    if factor == 2:
        r = scale2x(a)
    elif factor == 3:
        r = scale3x(a)
    elif factor == 4:
        r = scale2x(scale2x(a))
    elif factor == 6:
        r = scale3x(scale2x(a))
    elif factor == 5:
        big = scale2x(scale3x(a))
        out = Image.fromarray(big.view(np.uint8).reshape(big.shape + (4,)), "RGBA")
        return out.resize((img.width * 5, img.height * 5), Image.NEAREST)
    else:
        raise ValueError("invalid scale factor")
    return Image.fromarray(np.ascontiguousarray(r).view(np.uint8).reshape(r.shape + (4,)), "RGBA")
