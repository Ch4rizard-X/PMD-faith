"""Small audio helpers shared by the music / sound-effect builders (numpy + the ffmpeg binary only)."""
import os
import subprocess

import numpy as np

FFMPEG = os.environ.get("MDR_FFMPEG") or "ffmpeg"     # (the APK passes its packed ffmpeg)


def _no_ffmpeg():
    """No ffmpeg program here (the APK's on-phone build): use the libraries directly (audio_libs.py)."""
    import shutil
    return not (os.environ.get("MDR_FFMPEG") or shutil.which(FFMPEG))


def resample(st, sr_in, sr_out):
    """Resample a float (N, 2) array with ffmpeg's resampler (swresample, high-quality filter)."""
    if sr_in == sr_out:
        return np.asarray(st, np.float64)
    if _no_ffmpeg():
        import audio_libs
        return audio_libs.resample(st, sr_in, sr_out)
    raw = np.ascontiguousarray(st, dtype="<f4").tobytes()
    r = subprocess.run([FFMPEG, "-nostdin", "-loglevel", "error", "-f", "f32le", "-ar", str(sr_in), "-ac", "2",
                        "-i", "pipe:0", "-af", "aresample=resampler=swr:filter_size=64:phase_shift=10:cutoff=0.97",
                        "-ar", str(sr_out), "-f", "f32le", "pipe:1"], input=raw, capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").reshape(-1, 2).astype(np.float64)


def encode(st, sr, path, codec="ogg", sr_out=None):
    """Write a float (N, 2) array (-1..1) to .ogg (Vorbis q0, like the shipped files) or .mp3."""
    if _no_ffmpeg():
        import audio_libs
        if sr_out and sr_out != sr:
            st, sr = audio_libs.resample(st, sr, sr_out), sr_out
        pcm16 = (np.clip(st, -1, 1) * 32767).astype("<i2")
        if codec == "ogg":
            audio_libs.encode_ogg(pcm16, sr, path)
        else:
            audio_libs.encode_mp3(pcm16, sr, path)
        return
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2").tobytes()
    args = [FFMPEG, "-nostdin", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(sr), "-ac", "2", "-i", "pipe:0"]
    if sr_out and sr_out != sr:
        args += ["-ar", str(sr_out)]
    if codec == "ogg":
        args += ["-c:a", "libvorbis", "-q:a", "0"]
    else:
        args += ["-c:a", "libmp3lame", "-b:a", "128k"]
    subprocess.run(args + [path], input=pcm, check=True)


def decode(path, sr=24000, mono=False):
    """Decode any audio file to float32 (N, 2) (or (N,) mono) at sr."""
    r = subprocess.run([FFMPEG, "-nostdin", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1" if mono else "2",
                        "-ar", str(sr), "pipe:1"], capture_output=True, check=True)
    a = np.frombuffer(r.stdout, "<f4")
    return a if mono else a.reshape(-1, 2)
