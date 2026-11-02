"""Compile and run the small C "dumpers" a few build steps use to read data tables out of the pret decompilation
(data/gen_fixed_rooms.py, ground/gen_ground_scripts.py, ground/gen_ground_extra.py).

  run(units, cflags, cwd)  -> what the program printed (bytes); files it writes land in cwd

On a computer: gcc compiles a program and runs it, as before. On a phone (the APK's on-phone build) an app may
not start programs it made, so the C is compiled into a shared library instead (TinyCC, MDR_TCC, or any compiler
named in MDR_CC_SO) and its main() is called inside this Python process, with its output caught from file
descriptor 1. MDR_CDUMP_SO=1 forces that way on a computer too (tests).
"""
import ctypes
import os
import shutil
import subprocess
import sys
import tempfile


def _so_compiler():
    tcc = os.environ.get("MDR_TCC")
    if tcc:
        return [tcc] + os.environ.get("MDR_TCC_FLAGS", "").split()
    cc = os.environ.get("MDR_CC_SO") or shutil.which("gcc") or shutil.which("cc") or shutil.which("clang")
    return [cc] if cc else None


def _tcc_flags(cflags):
    """GCC options TinyCC doesn't know, in its terms (-iquote DIR: an include folder for "..." -> -I DIR)."""
    out, it = [], iter(cflags)
    for f in it:
        if f == "-iquote":
            out += ["-I", next(it)]
        elif f.startswith("-iquote"):
            out.append("-I" + f[len("-iquote"):])
        else:
            out.append(f)
    return out


def use_so():
    return bool(os.environ.get("MDR_CDUMP_SO") or os.environ.get("MDR_TCC") or not (shutil.which("gcc") or shutil.which("cc")))


def run(units, cflags, cwd=None, label="dump"):
    cwd = cwd or os.getcwd()
    with tempfile.TemporaryDirectory() as td:
        if not use_so():
            cc = shutil.which("gcc") or shutil.which("cc")
            objs = []
            for i, u in enumerate(units):
                o = os.path.join(td, "u%d.o" % i)
                r = subprocess.run([cc, "-c"] + cflags + [u, "-o", o], capture_output=True, text=True)
                if r.returncode:
                    sys.exit("%s: compile failed %s\n%s" % (label, u, r.stderr[:3000]))
                objs.append(o)
            exe = os.path.join(td, label)
            r = subprocess.run([cc] + objs + ["-o", exe], capture_output=True, text=True)
            if r.returncode:
                sys.exit("%s: link failed\n%s" % (label, r.stderr[:3000]))
            return subprocess.run([exe], cwd=cwd, capture_output=True, check=True).stdout
        cc = _so_compiler()
        if not cc:
            sys.exit("%s: no C compiler (MDR_TCC / MDR_CC_SO / gcc)" % label)
        so = os.path.join(td, "lib%s.so" % label)
        # MDR_TCC_LIBS: what TinyCC links after the code (on Android: libc, its runtime, the closing crt object)
        if os.environ.get("MDR_TCC"):
            cflags = _tcc_flags(cflags)
        cmd = cc + ["-shared", "-fPIC"] + cflags + list(units) + os.environ.get("MDR_TCC_LIBS", "").split() + ["-o", so]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            sys.exit("%s: compile failed\n%s\n%s" % (label, " ".join(cmd[:3]), (r.stderr or r.stdout)[:3000]))
        return _call_main(so, cwd)


def _call_main(so, cwd):
    """main() of a shared library, its stdout (fd 1) caught in a file, run in cwd."""
    lib = ctypes.CDLL(so)
    libc = ctypes.CDLL(None)
    sys.stdout.flush()
    out = tempfile.TemporaryFile()
    saved = os.dup(1)
    old = os.getcwd()
    try:
        os.dup2(out.fileno(), 1)
        os.chdir(cwd)
        lib.main.restype = ctypes.c_int
        rc = lib.main()
        libc.fflush(None)
    finally:
        os.chdir(old)
        os.dup2(saved, 1)
        os.close(saved)
    if rc:
        sys.exit("dumper ended with %d" % rc)
    out.seek(0)
    return out.read()
