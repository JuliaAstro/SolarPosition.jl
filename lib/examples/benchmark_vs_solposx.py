#!/usr/bin/env python3
"""Benchmark the wrapped Julia library against solposx, the Python reference package.

    pip install ./lib/out solposx
    python lib/examples/benchmark_vs_solposx.py
    python lib/examples/benchmark_vs_solposx.py --sizes 1,1000,100000 --repeats 7

solposx is the package this library's reference values were generated from, and it
implements the same seven algorithms, so this is a like-for-like comparison of the same
maths in two languages.

Method notes, because they decide whether the numbers mean anything:

* Inputs are prepared in each library's native form *before* timing — a pandas
  ``DatetimeIndex`` for solposx, a float64 array of Unix seconds for this library. The
  conversion between them is measured separately and reported, so you can see whether it
  would swamp the difference.
* solposx is fully vectorised over numpy/pandas, so this is not a Python-loop straw man.
* Refraction is switched off on both sides and only the geometric ``elevation`` and
  ``azimuth`` are compared, because each algorithm has a different refraction default.
* Every configuration is checked for agreement before it is timed. A disagreement is
  reported and that row is skipped rather than producing a meaningless speed number.
* The Julia runtime initialises on first call, so there is a warm-up call outside the
  timed region. Best-of-N is reported, not the mean, to suppress scheduler noise.
"""

from __future__ import annotations

import argparse
import time

import numpy as np
import pandas as pd

import solarposition as sp
from solposx import solarposition as sx

LATITUDE, LONGITUDE, ALTITUDE = 52.35888, 4.88185, 100.0

# Each entry: our enum, the solposx callable, and the kwargs that make the two agree.
# Options are pinned explicitly on both sides rather than relying on matching defaults.
ALGORITHMS = [
    (
        "PSA",
        sp.Algorithm.PSA,
        lambda times: sx.psa(times, LATITUDE, LONGITUDE, coefficients=2020),
        dict(psa_coeffs=2020),
    ),
    (
        "NOAA",
        sp.Algorithm.NOAA,
        lambda times: sx.noaa(times, LATITUDE, LONGITUDE, delta_t=67.0),
        dict(delta_t=67.0),
    ),
    (
        "SPA",
        sp.Algorithm.SPA,
        lambda times: sx.spa(
            times, LATITUDE, LONGITUDE, ALTITUDE,
            air_pressure=101325.0, temperature=12.0, delta_t=67.0,
        ),
        dict(altitude=ALTITUDE, pressure=101325.0, temperature=12.0, delta_t=67.0),
    ),
    (
        "WALRAVEN",
        sp.Algorithm.WALRAVEN,
        lambda times: sx.walraven(times, LATITUDE, LONGITUDE),
        dict(),
    ),
    (
        "USNO",
        sp.Algorithm.USNO,
        lambda times: sx.usno(times, LATITUDE, LONGITUDE, delta_t=67.0, gmst_option=1),
        dict(delta_t=67.0, gmst_option=1),
    ),
    (
        "IQBAL",
        sp.Algorithm.IQBAL,
        lambda times: sx.iqbal(times, LATITUDE, LONGITUDE),
        dict(),
    ),
    (
        "MICHALSKY",
        sp.Algorithm.MICHALSKY,
        lambda times: sx.michalsky(
            times, LATITUDE, LONGITUDE,
            spencer_correction=True, julian_date="original",
        ),
        dict(spencer_correction=True, julian_date=sp.JulianDateMode.ORIGINAL),
    ),
]


def best_of(fn, repeats: int) -> float:
    """Shortest wall time over `repeats` runs, in seconds."""
    timings = []
    for _ in range(repeats):
        start = time.perf_counter()
        fn()
        timings.append(time.perf_counter() - start)
    return min(timings)


# Divisor per pandas datetime resolution. `asi8` is the index's raw int64 array in its
# own unit, so the unit must be consulted: pandas >= 2 keeps non-nanosecond units
# and `date_range` here yields microseconds. Dividing by a hardcoded 1e9 is a silent
# 1000x error. Going via `.astype("datetime64[ns]")` on the tz-aware index is correct
# but ~6000x slower (3.9 s vs 0.6 ms for a million instants).
_UNIT_PER_SECOND = {"s": 1.0, "ms": 1e3, "us": 1e6, "ns": 1e9}


def to_unix_seconds(index: pd.DatetimeIndex) -> np.ndarray:
    """DatetimeIndex -> float64 Unix seconds, at the index's own resolution."""
    return index.asi8 / _UNIT_PER_SECOND[index.unit]


def make_inputs(n: int):
    """The same instants in each library's native input form."""
    index = pd.date_range("2024-01-01", periods=n, freq="1min", tz="UTC")
    return index, to_unix_seconds(index)


def agreement(name, our_enum, sx_call, our_kwargs, index, unix):
    """Max absolute elevation/azimuth difference between the two implementations."""
    ref = sx_call(index)
    ours = sp.solar_position(
        LATITUDE, LONGITUDE, unix,
        algorithm=our_enum, refraction=sp.RefractionModel.NONE, **our_kwargs,
    )
    d_elev = np.max(np.abs(ours[:, 1] - ref["elevation"].to_numpy()))
    d_azim = np.max(np.abs(ours[:, 0] - ref["azimuth"].to_numpy()))
    return max(d_elev, d_azim)


def run(sizes, repeats, tolerance, threads):
    if threads > 1:
        # Must happen before anything else touches the Julia runtime.
        sp.set_num_threads(threads)
    nthreads = sp.julia_nthreads()
    print("Benchmark: wrapped SolarPosition.jl vs solposx")
    print(f"  julia_nthreads()   {nthreads}"
          f"{'   (single-threaded build)' if nthreads == 1 else ''}")
    print(f"  numpy {np.__version__}, pandas {pd.__version__}")
    print(f"  best of {repeats} runs; site {LATITUDE}N {LONGITUDE}E {ALTITUDE:.0f} m")

    # --- agreement, checked once on a decent sample --------------------------------
    print("\nAgreement (max |diff| in elevation/azimuth, degrees, 10k instants)")
    index, unix = make_inputs(10_000)
    skip = set()
    for name, our_enum, sx_call, our_kwargs in ALGORITHMS:
        try:
            diff = agreement(name, our_enum, sx_call, our_kwargs, index, unix)
        except Exception as err:  # pragma: no cover - defensive
            print(f"  {name:<10} could not compare: {type(err).__name__}: {err}")
            skip.add(name)
            continue
        verdict = "ok" if diff <= tolerance else "DISAGREES"
        print(f"  {name:<10} {diff:.3e}   {verdict}")
        if diff > tolerance:
            skip.add(name)
    if skip:
        print(f"  -> skipping timings for: {', '.join(sorted(skip))}")

    # --- conversion cost, so it can be judged separately ---------------------------
    print("\nInput conversion (excluded from the timings below)")
    for n in sizes:
        index, _ = make_inputs(n)
        conv = best_of(lambda: to_unix_seconds(index), repeats)
        print(f"  n={n:<9,} DatetimeIndex -> Unix seconds: {conv * 1e3:9.4f} ms")

    # --- timings --------------------------------------------------------------------
    for n in sizes:
        index, unix = make_inputs(n)
        bufs = [np.empty(n) for _ in range(5)]

        print(f"\nn = {n:,} instants")
        print(f"  {'algorithm':<10} {'solposx':>12} {'julia':>12} "
              f"{'julia(inplace)':>15} {'speedup':>9} {'inplace':>9}")
        for name, our_enum, sx_call, our_kwargs in ALGORITHMS:
            if name in skip:
                continue

            def do_sx():
                sx_call(index)

            def do_ours():
                sp.solar_position(
                    LATITUDE, LONGITUDE, unix, algorithm=our_enum,
                    refraction=sp.RefractionModel.NONE, **our_kwargs,
                )

            def do_ours_inplace():
                sp.solar_position_inplace(
                    LATITUDE, LONGITUDE, unix, *bufs, algorithm=our_enum,
                    refraction=sp.RefractionModel.NONE, **our_kwargs,
                )

            do_sx(); do_ours(); do_ours_inplace()   # warm up both sides

            t_sx = best_of(do_sx, repeats)
            t_ours = best_of(do_ours, repeats)
            t_inplace = best_of(do_ours_inplace, repeats)

            print(f"  {name:<10} {t_sx * 1e3:10.4f}ms {t_ours * 1e3:10.4f}ms "
                  f"{t_inplace * 1e3:13.4f}ms {t_sx / t_ours:8.1f}x "
                  f"{t_sx / t_inplace:8.1f}x")

    # --- threaded entrypoint --------------------------------------------------------
    if nthreads > 1:
        n = max(sizes)
        _, unix = make_inputs(n)
        bufs = [np.empty(n) for _ in range(5)]
        index, _ = make_inputs(n)
        print(f"\nThreaded entrypoint, n = {n:,}, {nthreads} Julia threads")
        print(f"  {'algorithm':<10} {'serial':>12} {'threaded':>12} {'scaling':>8} "
              f"{'vs solposx':>11}")
        for name, our_enum, sx_call, our_kwargs in ALGORITHMS:
            if name in skip:
                continue
            serial = best_of(lambda: sp.solar_position_inplace(
                LATITUDE, LONGITUDE, unix, *bufs, algorithm=our_enum,
                refraction=sp.RefractionModel.NONE, **our_kwargs), repeats)
            par = best_of(lambda: sp.solar_position_inplace_threaded(
                LATITUDE, LONGITUDE, unix, *bufs, algorithm=our_enum,
                refraction=sp.RefractionModel.NONE, **our_kwargs), repeats)
            t_sx = best_of(lambda: sx_call(index), repeats)
            print(f"  {name:<10} {serial * 1e3:10.2f}ms {par * 1e3:10.2f}ms "
                  f"{serial / par:6.2f}x {t_sx / par:9.1f}x")
    else:
        print("\nThreaded entrypoint skipped: pass --threads=N to measure it.")

    # --- per-call latency -----------------------------------------------------------
    print("\nSingle-instant latency (one position, no arrays)")
    one_index, one_unix = make_inputs(1)
    for name, our_enum, sx_call, our_kwargs in ALGORITHMS:
        if name in skip:
            continue
        t_sx = best_of(lambda: sx_call(one_index), repeats)
        t_ours = best_of(lambda: sp.solar_position_single(
            LATITUDE, LONGITUDE, float(one_unix[0]), algorithm=our_enum,
            refraction=sp.RefractionModel.NONE, **our_kwargs), repeats)
        print(f"  {name:<10} solposx {t_sx * 1e6:9.1f}us   "
              f"julia {t_ours * 1e6:8.2f}us   {t_sx / t_ours:7.0f}x")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sizes", default="1000,100000,1000000",
                        help="comma-separated instant counts")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--tolerance", type=float, default=1e-6,
                        help="max allowed deg difference before a row is skipped")
    parser.add_argument("--threads", type=int, default=1,
                        help="Julia threads to request before the first call")
    args = parser.parse_args()
    sizes = [int(s) for s in args.sizes.split(",")]
    run(sizes, args.repeats, args.tolerance, args.threads)


if __name__ == "__main__":
    main()
