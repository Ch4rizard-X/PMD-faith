"""Small audio helpers shared by the music / sound-effect builders (numpy + the ffmpeg binary only)."""
import subprocess

import numpy as np

FFMPEG = "ffmpeg"


def resample(st, sr_in, sr_out):
    """Resample a float (N, 2) array with ffmpeg's resampler (swresample, high-quality filter)."""
    if sr_in == sr_out:
        return np.asarray(st, np.float64)
    raw = np.ascontiguousarray(st, dtype="<f4").tobytes()
    r = subprocess.run([FFMPEG, "-nostdin", "-loglevel", "error", "-f", "f32le", "-ar", str(sr_in), "-ac", "2",
                        "-i", "pipe:0", "-af", "aresample=resampler=swr:filter_size=64:phase_shift=10:cutoff=0.97",
                        "-ar", str(sr_out), "-f", "f32le", "pipe:1"], input=raw, capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").reshape(-1, 2).astype(np.float64)


def encode(st, sr, path, codec="ogg", sr_out=None):
    """Write a float (N, 2) array (-1..1) to .ogg (Vorbis q0, like the shipped files) or .mp3."""
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
