#!/usr/bin/env python3
"""Red's sound effects -> game/assets/sfx/<name>.(mp3|ogg), rendered from the decomp with the m4a renderer.

A file named NNN (or evNNN, the copy the ground event scripts used) is Red song NNN of sound/song_table.inc
(SE players 1-6); the game calls Audio.sfx("%03d" % id) with the script / effect sound ids, which are song ids.
The mapping was verified by matching every file of the old sound set against renders of all 509 Red SE songs
(log-band spectrogram similarity; 97 of 121 had their own number as best match, the rest within 0.01 of it).
The set of names (and mp3 44.1 kHz / ogg 22.05 kHz per name) is the one the game shipped with.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "red"))
sys.path.insert(0, os.path.dirname(HERE))
import common  # noqa: E402
import make  # noqa: E402  (tools/music/red/make.py)

MP3 = "200 204 210 301 302 303 304 305 332 333 336 341 342 343 463 606 607 608 610 ev455 ev463 ev468 ev470 ev473"
OGG = ("201 203 205 206 212 213 330 348 400 450 451 453 454 455 457 458 459 460 464 465 466 468 469 470 471 472 473 "
       "474 475 476 477 478 479 480 481 482 483 484 485 486 487 489 491 492 493 497 499 500 501 502 503 504 505 506 "
       "507 508 509 510 511 512 513 514 515 516 517 603 623 631 652 653 661 662 663 664 665 666 672 682 685 686 702 "
       "705 708 726 739 762 774 779 786 787 809 812 831 848 850 862 877 900")
GAIN = 1.22          # renderer output -> level of the old set (median peak ratio over the 117 audible files)


def files():
    out = [(n, n + ".mp3", 44100) for n in MP3.split()] + [(n, n + ".ogg", 22050) for n in OGG.split()]
    return sorted(out)


def main():
    outdir = os.path.join(common.ASSETS, "sfx")
    os.makedirs(outdir, exist_ok=True)
    t0 = time.time()
    for name, fn, sr in files():
        num = int(name.replace("ev", ""))
        d = make.se(num, os.path.join(outdir, fn), sr=sr, gain=GAIN)
        print("%-10s song %3d  %.2fs" % (fn, num, d), flush=True)
    print("sfx: %d files (%.0fs)" % (len(files()), time.time() - t0))


if __name__ == "__main__":
    main()
