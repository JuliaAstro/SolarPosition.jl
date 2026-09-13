#!/usr/bin/env python3
"""Worked examples for the `solarposition` Python bindings.

    julia --project=lib lib/build.jl
    pip install ./lib/out
    python lib/examples/getting_started.py

Every entrypoint takes a datetime directly, and Unix seconds in UTC underneath; the
first section shows both, and the conversion back that results still need. Angles are
all in degrees, azimuth measured from north and increasing clockwise.
"""

from __future__ import annotations

import datetime as dt
import os
import time

import numpy as np

import solarposition as sp

try:
    from zoneinfo import ZoneInfo  # Python 3.9+
except ImportError:  # pragma: no cover
    ZoneInfo = None

# Van Gogh Museum, Amsterdam.
LATITUDE, LONGITUDE, ALTITUDE = 52.35888, 4.88185, 100.0


def rule(title: str) -> None:
    print(f"\n{title}\n{'-' * len(title)}")


# --------------------------------------------------------------------------------------
# 1. Times
# --------------------------------------------------------------------------------------
# Wherever a time is taken you may pass a datetime, a date, a numpy datetime64, a
# pandas DatetimeIndex or Series, or plain Unix seconds. A datetime carrying a tzinfo
# has its offset applied; one without is read as UTC, which is what the whole library
# speaks. Results come back as Unix seconds, so only the way back needs a helper.
#
# Unix seconds are still worth holding directly when you build a grid arithmetically,
# as sections 2 and 5 do, or when you are calling in a loop and want no conversion in
# it at all.


def to_unix(when: dt.datetime) -> float:
    if when.tzinfo is None:
        raise ValueError("pass a timezone-aware datetime")
    return when.timestamp()


def from_unix(seconds: float, tz: dt.tzinfo = dt.timezone.utc) -> dt.datetime:
    return dt.datetime.fromtimestamp(seconds, tz)


# Nothing here calls the library, deliberately: section 2 has to run before the
# first computation.


def times_section() -> dt.datetime:
    rule("1. Times")
    noon_utc = dt.datetime(2023, 6, 21, 12, 0, tzinfo=dt.timezone.utc)
    print(f"  {noon_utc.isoformat()}  ->  {to_unix(noon_utc):.1f} Unix seconds")
    print(f"  a naive datetime is read as UTC, so {dt.datetime(2023, 6, 21, 12, 0)} "
          "means the same instant")

    if ZoneInfo is not None:
        local = dt.datetime(2023, 6, 21, 14, 0, tzinfo=ZoneInfo("Europe/Amsterdam"))
        print(f"  {local.isoformat()}  ->  {to_unix(local):.1f}  (same instant)")
    return noon_utc


# --------------------------------------------------------------------------------------
# 2. Threads
# --------------------------------------------------------------------------------------
# The thread count is chosen at run time, but only before the first computation. That
# is why this comes first. No rebuild is involved. Asking for more than one thread
# switches Julia's signal handlers on for the whole process; see lib/README.md.
#
# Try it:   SP_THREADS=8 python lib/examples/getting_started.py


def threaded_section() -> None:
    rule("2. Threads")
    requested = int(os.environ.get("SP_THREADS", "4"))

    # Set it before anything else touches the runtime. Pick the number however you
    # like -- an env var here, but os.cpu_count(), argv or a config file all work.
    sp.set_num_threads(requested)
    print(f"  set_num_threads({requested}) -> julia_nthreads() = {sp.julia_nthreads()}")

    start = to_unix(dt.datetime(2024, 1, 1, tzinfo=dt.timezone.utc))
    times = start + np.arange(0, 500_000, dtype=np.float64) * 60.0
    bufs = [np.empty(len(times)) for _ in range(5)]

    def elapsed(fn) -> float:
        began = time.perf_counter()
        fn()
        return time.perf_counter() - began

    serial = elapsed(lambda: sp.solar_position_inplace(
        LATITUDE, LONGITUDE, times, *bufs,
        altitude=ALTITUDE, algorithm=sp.Algorithm.SPA,
    ))
    parallel = elapsed(lambda: sp.solar_position_inplace_threaded(
        LATITUDE, LONGITUDE, times, *bufs,
        altitude=ALTITUDE, algorithm=sp.Algorithm.SPA,
    ))
    print(f"  {len(times):,} positions, SPA")
    print(f"    serial   {serial * 1e3:8.1f} ms")
    print(f"    threaded {parallel * 1e3:8.1f} ms   ({serial / parallel:.2f}x)")

    # The count is fixed once the runtime is up. A late call raises rather than
    # silently doing nothing, so this mistake is never invisible. To use a different
    # number of threads, start a new process.
    try:
        sp.set_num_threads(requested + 1)
    except RuntimeError as err:
        print(f"\n  changing it afterwards is refused:\n    {err}")


# --------------------------------------------------------------------------------------
# 3. A single position
# --------------------------------------------------------------------------------------


def single_section(when: dt.datetime) -> None:
    rule("3. One instant")
    # The datetime goes straight in. Unix seconds work just as well, and every other
    # section here passes those, because they build their times by arithmetic.
    r = sp.solar_position_single(
        LATITUDE, LONGITUDE, when, altitude=ALTITUDE, algorithm=sp.Algorithm.SPA
    )
    print(f"  {when.isoformat()}")
    print(f"  azimuth            {r.azimuth:10.6f}deg")
    print(f"  elevation          {r.elevation:10.6f}deg")
    print(f"  zenith             {r.zenith:10.6f}deg")
    print(f"  apparent elevation {r.apparent_elevation:10.6f}deg  (refraction applied)")
    print(f"  apparent zenith    {r.apparent_zenith:10.6f}deg")


# --------------------------------------------------------------------------------------
# 4. Choosing an algorithm
# --------------------------------------------------------------------------------------
# SPA is the most accurate and the slowest; PSA is the package default. `RefractionModel
# .DEFAULT` means "whatever this algorithm's own default is", which is no refraction for
# PSA, Walraven, Iqbal and USNO, and a model for NOAA, Michalsky and SPA.


def algorithms_section(t: float) -> None:
    rule("4. Algorithms (true elevation, no refraction)")
    reference = sp.solar_position_single(
        LATITUDE, LONGITUDE, t, altitude=ALTITUDE,
        algorithm=sp.Algorithm.SPA, refraction=sp.RefractionModel.NONE,
    ).elevation

    for alg in sp.Algorithm:
        r = sp.solar_position_single(
            LATITUDE, LONGITUDE, t, altitude=ALTITUDE,
            algorithm=alg, refraction=sp.RefractionModel.NONE,
        )
        delta = r.elevation - reference
        print(f"  {alg.name:<10} {r.elevation:10.6f}deg   vs SPA {delta:+.2e}deg")


# --------------------------------------------------------------------------------------
# 5. Refraction models
# --------------------------------------------------------------------------------------
# Refraction bends light downward, so the sun always appears higher than it truly is.
# The effect is tiny overhead and largest near the horizon, so this uses a low sun.


def refraction_section() -> None:
    rule("5. Refraction models, sun near the horizon")
    # Amsterdam, shortly after sunrise on the solstice.
    t = to_unix(dt.datetime(2023, 6, 21, 3, 45, tzinfo=dt.timezone.utc))

    true_elevation = sp.solar_position_single(
        LATITUDE, LONGITUDE, t, altitude=ALTITUDE,
        refraction=sp.RefractionModel.NONE,
    ).elevation
    print(f"  true elevation {true_elevation:.6f}deg\n")

    for model in sp.RefractionModel:
        if model is sp.RefractionModel.DEFAULT:
            continue
        r = sp.solar_position_single(
            LATITUDE, LONGITUDE, t, altitude=ALTITUDE, refraction=model,
            pressure=101325.0, temperature=12.0,
        )
        bend = r.apparent_elevation - r.elevation
        print(f"  {model.name:<10} apparent {r.apparent_elevation:9.6f}deg"
              f"   bend {bend:+.6f}deg")


# --------------------------------------------------------------------------------------
# 6. Many instants at once
# --------------------------------------------------------------------------------------


def many_section() -> None:
    rule("6. A day of positions")
    start = to_unix(dt.datetime(2023, 6, 21, 0, 0, tzinfo=dt.timezone.utc))
    times = start + np.arange(0, 24, dtype=np.float64) * 3600.0

    # Returns an (n, 5) array: azimuth, elevation, zenith, apparent elevation,
    # apparent zenith.
    m = sp.solar_position(
        LATITUDE, LONGITUDE, times, altitude=ALTITUDE, algorithm=sp.Algorithm.SPA
    )
    azimuth, elevation = m[:, 0], m[:, 1]

    print("  hour(UTC)   azimuth   elevation")
    for hour in (3, 6, 9, 12, 15, 18, 21):
        print(f"     {hour:02d}      {azimuth[hour]:8.3f}  {elevation[hour]:9.3f}")

    daylight = elevation > 0
    print(f"\n  highest elevation {elevation.max():.3f}deg "
          f"at {from_unix(times[elevation.argmax()]).strftime('%H:%M')} UTC")
    print(f"  hours sampled above the horizon: {daylight.sum()} of 24")


# --------------------------------------------------------------------------------------
# 7. Reusing your own buffers
# --------------------------------------------------------------------------------------
# `solar_position` allocates a fresh array per call. In a loop over many sites,
# `..._into` writes straight into arrays you already hold and allocates nothing. The
# arrays must be float64, contiguous, and at least as long as the input.


def inplace_section() -> None:
    rule("7. Writing into preallocated arrays")
    start = to_unix(dt.datetime(2023, 6, 21, tzinfo=dt.timezone.utc))
    times = start + np.arange(0, 1440, dtype=np.float64) * 60.0  # every minute
    n = len(times)

    azimuth = np.empty(n)
    elevation = np.empty(n)
    zenith = np.empty(n)
    apparent_elevation = np.empty(n)
    apparent_zenith = np.empty(n)

    sites = {"Amsterdam": (52.35888, 4.88185), "Nairobi": (-1.2921, 36.8219)}
    for name, (lat, lon) in sites.items():
        sp.solar_position_inplace(
            lat, lon, times,
            azimuth, elevation, zenith, apparent_elevation, apparent_zenith,
            algorithm=sp.Algorithm.SPA,
        )
        print(f"  {name:<10} peak elevation {elevation.max():7.3f}deg  "
              f"minutes of daylight {(elevation > 0).sum()}")


# --------------------------------------------------------------------------------------
# 8. Sunrise, transit and sunset
# --------------------------------------------------------------------------------------
# `transit_sunrise_sunset` returns seconds since midnight UTC of the day containing the
# instant you pass, keeping sub-second precision. Values can fall outside [0, 86400)
# when the event lands outside that UTC day.


def sunrise_section() -> None:
    rule("8. Sunrise, transit, sunset")
    day = dt.datetime(2023, 6, 21, tzinfo=dt.timezone.utc)
    events = sp.transit_sunrise_sunset(
        LATITUDE, LONGITUDE, to_unix(day), altitude=ALTITUDE
    )

    midnight = to_unix(day)
    tz = ZoneInfo("Europe/Amsterdam") if ZoneInfo is not None else dt.timezone.utc
    for name, seconds in (
        ("sunrise", events.sunrise),
        ("transit", events.transit),
        ("sunset", events.sunset),
    ):
        # Round, so the printed clock time matches the whole-second values the Julia
        # API reports; the float carries the sub-second part.
        when = from_unix(midnight + round(seconds), tz)
        print(f"  {name:<8} {when.strftime('%Y-%m-%d %H:%M:%S %Z')}"
              f"   ({seconds:9.3f} s after 00:00 UTC)")

    length = events.sunset - events.sunrise
    print(f"\n  day length {length / 3600:.3f} hours")


# --------------------------------------------------------------------------------------
# 9. The next or previous event
# --------------------------------------------------------------------------------------


def next_previous_section() -> None:
    rule("9. Next and previous events")
    now = to_unix(dt.datetime(2023, 6, 21, 12, 30, tzinfo=dt.timezone.utc))

    for event in sp.SunEvent:
        nxt = sp.sun_event(
            LATITUDE, LONGITUDE, now, event, sp.EventDirection.NEXT, altitude=ALTITUDE
        )
        prv = sp.sun_event(
            LATITUDE, LONGITUDE, now, event, sp.EventDirection.PREVIOUS,
            altitude=ALTITUDE,
        )
        print(f"  {event.name:<11} previous {from_unix(prv):%Y-%m-%d %H:%M:%S}"
              f"   next {from_unix(nxt):%Y-%m-%d %H:%M:%S}  (UTC)")


# --------------------------------------------------------------------------------------
# 10. Options and error handling
# --------------------------------------------------------------------------------------


def options_section(t: float) -> None:
    rule("10. Options and errors")

    # Every option is accepted by every entrypoint, but an algorithm that has no such
    # setting ignores it. delta_t only reaches SPA and USNO: PSA and Iqbal have no
    # delta_t field at all, and NOAA has one that its implementation never reads.
    # So demonstrate it with SPA, and on a date where the model and the 67 s default
    # diverge.
    old = to_unix(dt.datetime(1900, 6, 21, 12, tzinfo=dt.timezone.utc))
    for label, value in (("67.0", 67.0), ("None", None)):
        r = sp.solar_position_single(
            LATITUDE, LONGITUDE, old, algorithm=sp.Algorithm.SPA, delta_t=value
        )
        print(f"  SPA 1900  delta_t={label:<4} elevation {r.elevation:.9f}deg")
    print("  (delta_t is ignored by PSA, Iqbal and NOAA)")

    # PSA ships two coefficient sets.
    for coeffs in (2020, 2001):
        r = sp.solar_position_single(LATITUDE, LONGITUDE, t, psa_coeffs=coeffs)
        print(f"  psa_coeffs={coeffs}  elevation {r.elevation:.6f}deg")

    # Julia exceptions arrive as JLWError with a code: 2 is ArgumentError,
    # 3 is DimensionMismatch.
    try:
        times = np.zeros(10)
        too_short = [np.zeros(3) for _ in range(5)]
        sp.solar_position_inplace(LATITUDE, LONGITUDE, times, *too_short)
    except sp.JLWError as err:
        print(f"\n  JLWError code={err.code}: {err.message}")

    # Invalid enum values are rejected rather than silently falling through.
    try:
        sp.solar_position_single(LATITUDE, LONGITUDE, t, algorithm=99)
    except (ValueError, KeyError, TypeError) as err:
        print(f"  invalid algorithm rejected: {type(err).__name__}")


def main() -> None:
    print(f"solarposition example - Amsterdam ({LATITUDE}N, {LONGITUDE}E, "
          f"{ALTITUDE:.0f} m)")
    when = times_section()
    threaded_section()          # must run before any computation: it sets the threads
    t = to_unix(when)
    single_section(when)
    algorithms_section(t)
    refraction_section()
    many_section()
    inplace_section()
    sunrise_section()
    next_previous_section()
    options_section(t)
    print()


if __name__ == "__main__":
    main()
