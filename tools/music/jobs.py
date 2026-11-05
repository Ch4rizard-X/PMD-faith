"""Render many songs at once: a few worker processes of the same make.py, each taking the next song as soon as
it is free. Rendering a song is pure Python/numpy on one core, so this is what makes the music step fast on a
phone (6-8 cores) and on a PC.

Workers: `make.py ... --worker` reads song ids from stdin (one per line) and answers each with a line
    @@DONE <id> <json result>
after any log lines of its own. The parent prints one progress line per finished song:
    Music 57/330 (Explorers of Sky) - eos 0123 in 41s, about 12 min left

MDR_JOBS=n sets the number of workers (1 = render in this process, like before).
"""
import json
import os
import queue
import subprocess
import sys
import threading
import time

MB = 1 << 20
PER_WORKER = 900 * MB          # what one worker may use: the longest songs peak at about 1.2 GB, most far below
PER_WORKER_PHONE = 1250 * MB   # on a phone a worker that runs out takes the whole app with it: budget the worst song
PHONE_MAX = 3


def _phone():
    return bool(os.environ.get("ANDROID_ROOT") or os.environ.get("ANDROID_DATA") or os.environ.get("PYTHONHOME"))


def py_cmd():
    """The interpreter and flags build.py uses (the APK's Python needs PYTHONHOME, which -I would ignore)."""
    if os.environ.get("PYTHONHOME"):
        return [sys.executable, "-P", "-s", "-X", "utf8"]
    return [sys.executable, "-I", "-X", "utf8"]


def _mem_available():
    try:
        with open("/proc/meminfo") as f:
            for ln in f:
                if ln.startswith("MemAvailable:"):
                    return int(ln.split()[1]) * 1024
    except OSError:
        pass
    return None


def count(n_items):
    env = os.environ.get("MDR_JOBS")
    if env:
        try:
            return max(1, min(int(env), n_items))
        except ValueError:
            pass
    cpus = os.cpu_count() or 1
    j = min(max(1, cpus - 1) if cpus > 2 else cpus, 6)
    mem = _mem_available()
    if _phone():
        # Android closes the whole app (and the build with it) when memory runs short, and its "available" figure
        # is optimistic: at most 3 at once, each with room for the longest song, out of 75% of what is free
        j = min(j, PHONE_MAX)
        if mem:
            j = min(j, max(1, int(mem * 0.75 // PER_WORKER_PHONE)))
        else:
            j = min(j, 2)
    elif mem:
        j = min(j, max(1, int(mem // PER_WORKER)))
    return max(1, min(j, n_items))


def _fmt_left(s):
    if s < 90:
        return "under 2 min left"
    if s < 3600:
        return "about %d min left" % round(s / 60)
    return "about %dh %02dm left" % (s // 3600, (s % 3600) // 60)


def run(script, ids, label, name_fn, extra=(), on_result=None, word="Music"):
    """Render `ids` with workers running `script --worker *extra`. on_result(id, result) is called in this
    process as each song finishes (results are dicts; a failed song gives {"error": ...}).
    Returns ({id: result}, [ids left over if every worker stopped])."""
    ids = list(ids)
    total = len(ids)
    results = {}
    if not total:
        return results, []
    j = count(total)
    print("%s 0/%d (%s) - %d at a time" % (word, total, label, j), flush=True)
    env = dict(os.environ)
    for k in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
        env[k] = "1"                                    # one core per worker
    todo = list(ids)
    events = queue.Queue()
    procs = []

    def reader(w, p):
        for ln in p.stdout:
            events.put((w, ln.rstrip("\n")))
        events.put((w, None))

    current = {}

    def feed(w):
        p = procs[w]
        if todo:
            n = todo.pop(0)
            current[w] = (n, time.time())
            try:
                p.stdin.write("%s\n" % n)
                p.stdin.flush()
                return
            except OSError:
                todo.insert(0, n)
                current.pop(w, None)
        current.pop(w, None)
        try:
            p.stdin.close()
        except OSError:
            pass

    for w in range(j):
        p = subprocess.Popen(py_cmd() + [script] + list(extra) + ["--worker"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                             errors="replace", env=env, bufsize=1)
        procs.append(p)
        threading.Thread(target=reader, args=(w, p), daemon=True).start()
    for w in range(j):
        feed(w)
    t0 = time.time()
    alive = j
    done = 0
    while alive:
        w, ln = events.get()
        if ln is None:                                  # worker exited
            alive -= 1
            procs[w].wait()
            if w in current:                            # died in the middle of a song
                n, _ = current.pop(w)
                results[n] = {"error": "worker stopped (exit %s)" % procs[w].returncode}
                done += 1
                print("%s %d/%d (%s) - %s FAILED: worker stopped" % (word, done, total, label, name_fn(n)), flush=True)
                if on_result:
                    on_result(n, results[n])
            if alive == 0 and todo:                     # every worker gone: finish the rest here, one by one
                print("   (workers stopped; rendering the remaining %d here)" % len(todo), flush=True)
                return results, list(todo)
            continue
        if not ln.startswith("@@DONE "):
            print("   " + ln, flush=True)
            continue
        _, sid, js = ln.split(" ", 2)
        try:
            r = json.loads(js)
        except ValueError:
            r = {"error": "bad result line"}
        n = type(ids[0])(sid) if not isinstance(ids[0], str) else sid
        _, ts = current.pop(w, (n, time.time()))
        results[n] = r
        done += 1
        el = time.time() - t0
        left = el / done * (total - done)
        msg = "%s %d/%d (%s) - %s %s in %.0fs" % (word, done, total, label, name_fn(n),
                                                       "FAILED" if "error" in r else "done", time.time() - ts)
        if done < total:
            msg += ", " + _fmt_left(left)
        print(msg, flush=True)
        if on_result:
            on_result(n, r)
        feed(w)
    return results, []


def worker_loop(render_fn, parse=int):
    """The --worker side: one song id per stdin line -> log lines, then '@@DONE id json'."""
    import traceback
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        n = parse(line)
        try:
            r = render_fn(n)
        except Exception as e:                           # noqa: BLE001 - reported per song, the rest go on
            traceback.print_exc(file=sys.stdout)
            r = {"error": repr(e)}
        if r is None:
            r = {"skipped": "no notes"}
        sys.stdout.write("@@DONE %s %s\n" % (line, json.dumps(r)))
        sys.stdout.flush()
