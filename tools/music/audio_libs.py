"""Audio without the ffmpeg program: the same libraries ffmpeg uses for our music, called from Python (ctypes).
For the APK's on-phone build, where an app can't start programs it carries outside its native library folder and
ffmpeg would bring ~100 libraries along; tools/music/audio_util.py uses this when ffmpeg isn't there.

  resample(st, sr_in, sr_out)          libsoxr (soxr_oneshot, high quality), float (N, 2)
  encode_ogg(pcm16, sr, path)          libvorbisenc + libogg: Vorbis VBR quality 0 (what ffmpeg's -q:a 0 asks for)
  encode_mp3(pcm16, sr, path, kbps)    libmp3lame: CBR, joint stereo (ffmpeg's -b:a 128k)

Libraries are found by name (the APK puts its lib folder on LD_LIBRARY_PATH; on a computer, the system ones)."""
import ctypes
import os

import numpy as np

_libs = {}


def _lib(*names):
    key = names[0]
    if key not in _libs:
        err = None
        for n in names:
            try:
                _libs[key] = ctypes.CDLL(n)
                break
            except OSError as e:
                err = e
        else:
            raise OSError("audio library not found: %s (%s)" % (", ".join(names), err))
    return _libs[key]


def available():
    try:
        _ogg(); _vorbis(); _vorbisenc(); _lame(); _soxr()
        return True
    except OSError:
        return False


def _ogg():
    return _lib("libogg.so", "libogg.so.0")


def _vorbis():
    return _lib("libvorbis.so", "libvorbis.so.0")


def _vorbisenc():
    return _lib("libvorbisenc.so", "libvorbisenc.so.2")


def _lame():
    return _lib("libmp3lame.so", "libmp3lame.so.0")


def _soxr():
    return _lib("libsoxr.so", "libsoxr.so.0")


# ------------------------------------------------------------------ resampling
def resample(st, sr_in, sr_out):
    st = np.ascontiguousarray(st, dtype=np.float32)
    if sr_in == sr_out:
        return st.astype(np.float64)
    ch = st.shape[1] if st.ndim == 2 else 1
    n_in = st.shape[0]
    n_out = int(n_in * sr_out / sr_in + 0.5)
    out = np.zeros((n_out + 64, ch), np.float32)
    s = _soxr()
    s.soxr_oneshot.restype = ctypes.c_char_p
    s.soxr_oneshot.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_uint, ctypes.c_void_p, ctypes.c_size_t,
                               ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t,
                               ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    idone, odone = ctypes.c_size_t(0), ctypes.c_size_t(0)
    err = s.soxr_oneshot(float(sr_in), float(sr_out), ch, ctypes.c_void_p(st.ctypes.data), n_in, ctypes.byref(idone),
                         ctypes.c_void_p(out.ctypes.data), out.shape[0], ctypes.byref(odone), None, None, None)
    if err:
        raise RuntimeError("soxr: " + err.decode())
    return out[:odone.value].astype(np.float64)


# ------------------------------------------------------------------ Ogg Vorbis
class _OggPage(ctypes.Structure):
    _fields_ = [("header", ctypes.c_void_p), ("header_len", ctypes.c_long),
                ("body", ctypes.c_void_p), ("body_len", ctypes.c_long)]


def _buf(n=65536):      # opaque libogg / libvorbis state structs (far smaller than this on any platform)
    return ctypes.create_string_buffer(n)


def encode_ogg(pcm16, sr, path, quality=0.0, chunk=4096):
    """pcm16: int16 (N, 2) interleaved stereo -> path (.ogg)."""
    ogg, vb, ve = _ogg(), _vorbis(), _vorbisenc()
    pcm = np.asarray(pcm16, np.int16).reshape(-1, 2)
    vi, vc, vd, vblk, os_, op = _buf(), _buf(), _buf(), _buf(), _buf(1 << 17), _buf(256)
    hdr, hdr_comm, hdr_code = _buf(256), _buf(256), _buf(256)
    vb.vorbis_info_init(vi)
    ve.vorbis_encode_init_vbr.argtypes = [ctypes.c_void_p, ctypes.c_long, ctypes.c_long, ctypes.c_float]
    if ve.vorbis_encode_init_vbr(vi, 2, int(sr), ctypes.c_float(quality)) != 0:
        raise RuntimeError("vorbis_encode_init_vbr failed")
    vb.vorbis_comment_init(vc)
    vb.vorbis_comment_add_tag(vc, b"ENCODER", b"md-recomp (libvorbis)")
    vb.vorbis_analysis_init(vd, vi)
    vb.vorbis_block_init(vd, vblk)
    ogg.ogg_stream_init(os_, 0x4D445243)
    vb.vorbis_analysis_headerout(vd, vc, hdr, hdr_comm, hdr_code)
    for h in (hdr, hdr_comm, hdr_code):
        ogg.ogg_stream_packetin(os_, h)
    page = _OggPage()
    out = open(path + ".part", "wb")

    def write_page():
        out.write(ctypes.string_at(page.header, page.header_len))
        out.write(ctypes.string_at(page.body, page.body_len))

    while ogg.ogg_stream_flush(os_, ctypes.byref(page)):
        write_page()
    vb.vorbis_analysis_buffer.restype = ctypes.POINTER(ctypes.POINTER(ctypes.c_float))
    f = (pcm.astype(np.float32) * np.float32(1.0 / 32768.0)).astype(np.float32)
    pos = 0
    while True:
        n = min(chunk, len(f) - pos)
        if n > 0:
            bufs = vb.vorbis_analysis_buffer(vd, n)
            for c in range(2):
                part = np.ascontiguousarray(f[pos:pos + n, c], dtype=np.float32)   # kept alive across the copy
                ctypes.memmove(bufs[c], ctypes.c_void_p(part.ctypes.data), n * 4)
            vb.vorbis_analysis_wrote(vd, n)
            pos += n
        else:
            vb.vorbis_analysis_wrote(vd, 0)            # end of stream
        while vb.vorbis_analysis_blockout(vd, vblk) == 1:
            vb.vorbis_analysis(vblk, None)
            vb.vorbis_bitrate_addblock(vblk)
            while vb.vorbis_bitrate_flushpacket(vd, op):
                ogg.ogg_stream_packetin(os_, op)
                while ogg.ogg_stream_pageout(os_, ctypes.byref(page)):
                    write_page()
        if n <= 0:
            break
    while ogg.ogg_stream_flush(os_, ctypes.byref(page)):
        write_page()
    out.close()
    ogg.ogg_stream_clear(os_)
    vb.vorbis_block_clear(vblk)
    vb.vorbis_dsp_clear(vd)
    vb.vorbis_comment_clear(vc)
    vb.vorbis_info_clear(vi)
    os.replace(path + ".part", path)


# ------------------------------------------------------------------ MP3
def encode_mp3(pcm16, sr, path, kbps=128):
    lm = _lame()
    pcm = np.ascontiguousarray(np.asarray(pcm16, np.int16).reshape(-1, 2))
    # every argument typed: an untyped Python int goes to C as a 32-bit int, which cuts a 64-bit address short
    # (on Android, where heap addresses carry a tag in the top byte, always)
    vp, i = ctypes.c_void_p, ctypes.c_int
    lm.lame_init.restype = vp
    lm.lame_init.argtypes = []
    for fn in ("lame_set_in_samplerate", "lame_set_num_channels", "lame_set_brate", "lame_set_mode", "lame_set_quality"):
        getattr(lm, fn).argtypes = [vp, i]
    lm.lame_init_params.argtypes = [vp]
    lm.lame_encode_buffer_interleaved.argtypes = [vp, vp, i, ctypes.c_char_p, i]
    lm.lame_encode_flush.argtypes = [vp, ctypes.c_char_p, i]
    lm.lame_close.argtypes = [vp]
    g = ctypes.c_void_p(lm.lame_init())
    lm.lame_set_in_samplerate(g, int(sr))
    lm.lame_set_num_channels(g, 2)
    lm.lame_set_brate(g, int(kbps))
    lm.lame_set_mode(g, 1)                              # JOINT_STEREO
    lm.lame_set_quality(g, 3)
    if lm.lame_init_params(g) < 0:
        raise RuntimeError("lame_init_params failed")
    n = len(pcm)
    cap = int(1.25 * n + 7200)
    mp3 = ctypes.create_string_buffer(cap)
    w = lm.lame_encode_buffer_interleaved(g, ctypes.c_void_p(pcm.ctypes.data), n, mp3, cap)
    if w < 0:
        raise RuntimeError("lame_encode_buffer_interleaved failed (%d)" % w)
    tail = ctypes.create_string_buffer(7200)
    w2 = lm.lame_encode_flush(g, tail, 7200)
    with open(path + ".part", "wb") as f:
        f.write(mp3.raw[:w])
        f.write(tail.raw[:max(0, w2)])
    lm.lame_close(g)
    os.replace(path + ".part", path)
