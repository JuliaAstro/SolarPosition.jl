"""Tests for the compiled solarposition Python bindings.

Run against an installed build:

    julia --project=test lib/test/generate_fixtures.jl   # refresh fixtures.json
    julia --project=lib lib/build.jl                     # build the library
    pip install ./lib/out
    pytest lib/test -v

The two substantive tests are `test_matches_solposx_reference`, which checks the
compiled library against the solposx tables that also back the Julia test suite, and
`test_matches_julia_package`, which checks it against this checkout's own Julia output
for every algorithm x refraction pair. The first catches a numeric regression anywhere
in the chain; the second isolates whether `juliac --trim` changed anything.
"""

import datetime as dt
import json
import pathlib

import numpy as np
import pytest

import solarposition as sp

FIXTURES = pathlib.Path(__file__).parent / "fixtures.json"

# Column name in a reference table -> attribute on the returned SolarAngles.
_COLUMN_TO_FIELD = {
    "elevation": "elevation",
    "zenith": "zenith",
    "azimuth": "azimuth",
    "apparent_elevation": "apparent_elevation",
    "apparent_zenith": "apparent_zenith",
}


@pytest.fixture(scope="session")
def fx():
    if not FIXTURES.exists():
        pytest.skip(
            f"{FIXTURES} missing; run "
            "`julia --project=test lib/test/generate_fixtures.jl`"
        )
    return json.loads(FIXTURES.read_text())


def _observers(fx):
    return list(
        zip(fx["latitude"], fx["longitude"], fx["altitude"], fx["unix_seconds"])
    )


# --------------------------------------------------------------------------- basics


def test_enums_cover_every_algorithm_and_refraction_model():
    assert set(sp.Algorithm.__members__) == {
        "PSA", "NOAA", "SPA", "WALRAVEN", "USNO", "IQBAL", "MICHALSKY",
    }
    assert set(sp.RefractionModel.__members__) == {
        "DEFAULT", "NONE", "HUGHES", "ARCHER", "BENNETT", "MICHALSKY", "SG2", "SPA",
    }
    assert set(sp.JulianDateMode.__members__) == {"ORIGINAL", "STANDARD"}


def test_single_returns_five_angles():
    r = sp.solar_position_single(52.35888, 4.88185, 1687348800.0, altitude=100.0)
    assert r.zenith == pytest.approx(90.0 - r.elevation, abs=1e-9)
    assert -90.0 <= r.elevation <= 90.0
    assert 0.0 <= r.azimuth < 360.0


def test_refraction_raises_apparent_elevation():
    # Refraction bends light downward, so the sun appears higher than it is.
    args = (40.0, -105.0, 1687348800.0)
    for model in (
        sp.RefractionModel.HUGHES,
        sp.RefractionModel.ARCHER,
        sp.RefractionModel.BENNETT,
        sp.RefractionModel.MICHALSKY,
        sp.RefractionModel.SG2,
        sp.RefractionModel.SPA,
    ):
        r = sp.solar_position_single(*args, refraction=model)
        assert r.apparent_elevation > r.elevation, model
        assert r.apparent_zenith == pytest.approx(90.0 - r.apparent_elevation, abs=1e-9)


def test_no_refraction_leaves_apparent_equal_to_true():
    r = sp.solar_position_single(
        40.0, -105.0, 1687348800.0, refraction=sp.RefractionModel.NONE
    )
    assert r.apparent_elevation == r.elevation
    assert r.apparent_zenith == r.zenith


def test_delta_t_none_is_accepted():
    fixed = sp.solar_position_single(40.0, -105.0, 1687348800.0, delta_t=67.0)
    auto = sp.solar_position_single(40.0, -105.0, 1687348800.0, delta_t=None)
    assert auto.elevation == pytest.approx(fixed.elevation, abs=1e-3)


# ------------------------------------------------------------------- correctness


def test_matches_solposx_reference(fx):
    """The compiled library reproduces the solposx tables the Julia tests use."""
    checked = 0
    for name, spec in fx["reference"].items():
        columns = spec["columns"]
        atol = spec["atol"]
        for (lat, lon, alt, t), row in zip(_observers(fx), spec["rows"]):
            # test-noaa.jl skips the poles, where NOAA is numerically unstable.
            if spec["skip_poles"] and abs(abs(lat) - 90.0) < 1e-9:
                continue
            got = sp.solar_position_single(
                lat,
                lon,
                t,
                altitude=alt,
                algorithm=sp.Algorithm[spec["algorithm"]],
                refraction=sp.RefractionModel[spec["refraction"]],
                pressure=fx["pressure"],
                temperature=spec["temperature"],
                psa_coeffs=spec["psa_coeffs"],
                gmst_option=spec["gmst_option"],
                refraction_limit=fx["refraction_limit"],
            )
            for col, expected in zip(columns, row):
                field = _COLUMN_TO_FIELD.get(col)
                if field is None:
                    continue  # e.g. SPA's equation_of_time, not exposed by this API
                assert getattr(got, field) == pytest.approx(expected, abs=atol), (
                    f"{name} {col} at lat={lat} lon={lon} t={t}"
                )
                checked += 1
    assert checked > 0


def test_matches_julia_package(fx):
    """Every algorithm x refraction pair matches the Julia package exactly."""
    worst = 0.0
    for key, rows in fx["package"].items():
        alg_name, refr_name = key.split("|")
        for (lat, lon, alt, t), row in zip(_observers(fx), rows):
            got = sp.solar_position_single(
                lat,
                lon,
                t,
                altitude=alt,
                algorithm=sp.Algorithm[alg_name],
                refraction=sp.RefractionModel[refr_name],
                pressure=fx["pressure"],
                temperature=fx["temperature"],
                refraction_limit=fx["refraction_limit"],
            )
            mine = [
                got.azimuth,
                got.elevation,
                got.zenith,
                got.apparent_elevation,
                got.apparent_zenith,
            ]
            for a, b in zip(mine, row):
                worst = max(worst, abs(a - b))
            assert mine == pytest.approx(row, abs=1e-12, rel=0), key
    # The compiled library runs the same Float64 code, so agreement is near-exact.
    assert worst < 1e-12, f"worst deviation from the Julia package: {worst}"


# ------------------------------------------------------------------------ batch


def test_many_instants_match_single(fx):
    lat, lon, alt = 52.35888, 4.88185, 100.0
    times = np.array(fx["unix_seconds"], dtype=np.float64)
    for alg in sp.Algorithm:
        m = sp.solar_position(lat, lon, times, altitude=alt, algorithm=alg)
        assert m.shape == (len(times), 5)
        for i, t in enumerate(times):
            r = sp.solar_position_single(
                lat, lon, float(t), altitude=alt, algorithm=alg
            )
            assert list(m[i]) == [
                r.azimuth,
                r.elevation,
                r.zenith,
                r.apparent_elevation,
                r.apparent_zenith,
            ], f"{alg} row {i}"


def test_inplace_matches_allocating(fx):
    lat, lon, alt = 52.35888, 4.88185, 100.0
    times = np.array(fx["unix_seconds"], dtype=np.float64)
    n = len(times)
    bufs = [np.zeros(n) for _ in range(5)]
    sp.solar_position_inplace(lat, lon, times, *bufs, altitude=alt)
    m = sp.solar_position(lat, lon, times, altitude=alt)
    for col, buf in enumerate(bufs):
        np.testing.assert_array_equal(buf, m[:, col])


@pytest.mark.parametrize(
    "algorithm", [sp.Algorithm.PSA, sp.Algorithm.WALRAVEN, sp.Algorithm.IQBAL]
)
def test_delta_t_does_not_leak_into_other_arguments(algorithm):
    """`delta_t` must reach the argument it names, on every entrypoint.

    These three algorithms ignore `delta_t` entirely, so changing it must change
    nothing. That makes this a cheap detector for a whole class of ABI-marshalling
    faults, where a value arrives in the wrong slot: `delta_t` is the only argument
    passed as a struct split across an integer and a floating-point half, which is
    exactly the shape ctypes/libffi is most likely to place wrongly. One such libffi
    bug silently put `delta_t` where `latitude` belongs on `solar_position`;
    see `solar_position` in `lib/python/_extras.py`. `solar_position_threaded` has
    the same signature shape, so it is checked here too.
    """
    lat, lon, alt = 52.35888, 4.88185, 100.0
    times = np.linspace(1687348800.0, 1687435200.0, 64)
    kwargs = dict(altitude=alt, algorithm=algorithm)

    def sample(delta_t):
        one = sp.solar_position_single(lat, lon, float(times[0]),
                                       delta_t=delta_t, **kwargs)
        many = sp.solar_position(lat, lon, times, delta_t=delta_t, **kwargs)
        inplace = [np.empty(len(times)) for _ in range(5)]
        sp.solar_position_inplace(lat, lon, times, *inplace,
                                  delta_t=delta_t, **kwargs)
        threaded = [np.empty(len(times)) for _ in range(5)]
        sp.solar_position_inplace_threaded(lat, lon, times, *threaded,
                                           delta_t=delta_t, **kwargs)
        many_threaded = sp.solar_position_threaded(lat, lon, times,
                                                   delta_t=delta_t, **kwargs)
        return one.azimuth, many, inplace, threaded, many_threaded

    one_a, many_a, inplace_a, threaded_a, many_threaded_a = sample(67.0)
    one_b, many_b, inplace_b, threaded_b, many_threaded_b = sample(0.0)

    assert one_a == one_b, "solar_position_single"
    np.testing.assert_array_equal(many_a, many_b, err_msg="solar_position")
    np.testing.assert_array_equal(many_threaded_a, many_threaded_b,
                                  err_msg="solar_position_threaded")
    for col, (a, b) in enumerate(zip(inplace_a, inplace_b)):
        np.testing.assert_array_equal(a, b, err_msg=f"inplace column {col}")
    for col, (a, b) in enumerate(zip(threaded_a, threaded_b)):
        np.testing.assert_array_equal(a, b, err_msg=f"threaded column {col}")

    # And all of them must agree with each other, not merely be self-consistent.
    np.testing.assert_array_equal(many_a[:, 0], inplace_a[0])
    np.testing.assert_array_equal(many_a[:, 0], threaded_a[0])
    np.testing.assert_array_equal(many_a, many_threaded_a)
    assert many_a[0, 0] == one_a


@pytest.mark.parametrize(
    "entrypoint", [sp.solar_position, sp.solar_position_threaded]
)
def test_allocating_entrypoints_use_the_hand_maintained_wrapper(entrypoint):
    """These must come from `_extras`, not from the generated façade.

    The generated bindings for the two allocating entrypoints are mismarshalled by
    some builds of libffi, so the override is the fix rather than a convenience. If a
    build stops installing it, every result from them silently becomes wrong, and this
    is the tripwire for that.
    """
    assert entrypoint.__module__.endswith("_extras")


def test_inplace_rejects_short_buffers():
    times = np.zeros(10)
    short = [np.zeros(3) for _ in range(5)]
    with pytest.raises(sp.JLWError) as excinfo:
        sp.solar_position_inplace(0.0, 0.0, times, *short)
    # DimensionMismatch maps to status code 3.
    assert excinfo.value.code == 3


def test_inplace_writes_through_to_caller_arrays():
    times = np.array([1687348800.0, 1687352400.0])
    bufs = [np.full(2, np.nan) for _ in range(5)]
    sp.solar_position_inplace(40.0, -105.0, times, *bufs)
    for buf in bufs:
        assert np.all(np.isfinite(buf))


@pytest.mark.parametrize(
    "entrypoint", [sp.solar_position, sp.solar_position_threaded]
)
def test_empty_input_is_allowed(entrypoint):
    m = entrypoint(40.0, -105.0, np.zeros(0))
    assert m.shape == (0, 5)


# ---------------------------------------------------------------- datetime input

UTC_INSTANT = dt.datetime(2023, 6, 21, 3, 45, tzinfo=dt.timezone.utc)
UTC_SECONDS = UTC_INSTANT.timestamp()


def test_single_accepts_a_datetime():
    a = sp.solar_position_single(40.0, -105.0, UTC_INSTANT, algorithm=sp.Algorithm.SPA)
    b = sp.solar_position_single(40.0, -105.0, UTC_SECONDS, algorithm=sp.Algorithm.SPA)
    assert a.elevation == b.elevation
    assert a.azimuth == b.azimuth


@pytest.mark.parametrize(
    "when",
    [
        # A naive datetime is read as UTC, not as the machine's local time. That is a
        # deliberate departure from `datetime.timestamp()`: everything this library
        # takes and returns is UTC, and numpy's datetime64 carries no zone to read.
        dt.datetime(2023, 6, 21, 3, 45),
        dt.datetime(2023, 6, 21, 3, 45, tzinfo=dt.timezone.utc),
        # Same instant written in another zone; the offset must be applied.
        dt.datetime(2023, 6, 21, 5, 45, tzinfo=dt.timezone(dt.timedelta(hours=2))),
        np.datetime64("2023-06-21T03:45"),
    ],
)
def test_every_spelling_of_one_instant_agrees(when):
    got = sp.solar_position_single(40.0, -105.0, when)
    ref = sp.solar_position_single(40.0, -105.0, UTC_SECONDS)
    assert got.elevation == ref.elevation


def test_a_bare_date_means_midnight_utc():
    midnight = dt.datetime(2023, 6, 21, tzinfo=dt.timezone.utc)
    assert (
        sp.solar_position_single(40.0, -105.0, dt.date(2023, 6, 21)).elevation
        == sp.solar_position_single(40.0, -105.0, midnight).elevation
    )


def _hourly(n=5):
    """`n` hourly instants, as Unix seconds and as datetimes."""
    seconds = np.array([UTC_SECONDS + 3600.0 * i for i in range(n)])
    return seconds, [dt.datetime.fromtimestamp(t, dt.timezone.utc) for t in seconds]


@pytest.mark.parametrize(
    "entrypoint", [sp.solar_position, sp.solar_position_threaded]
)
def test_solar_position_accepts_datetime_sequences(entrypoint):
    seconds, datetimes = _hourly()
    ref = entrypoint(40.0, -105.0, seconds)
    for label, times in [
        ("list of datetime", datetimes),
        ("tuple of datetime", tuple(datetimes)),
        # datetime64 has no zone, so strip the (UTC) one rather than let numpy
        # warn about dropping it.
        (
            "datetime64 array",
            np.array([d.replace(tzinfo=None) for d in datetimes], "datetime64[s]"),
        ),
        ("object array", np.array(datetimes, dtype=object)),
    ]:
        got = entrypoint(40.0, -105.0, times)
        np.testing.assert_array_equal(got, ref, err_msg=label)


def test_solar_position_accepts_pandas_datetime_containers():
    """pandas is the common caller, and its tz-aware containers take a separate path."""
    pd = pytest.importorskip("pandas")
    seconds, _ = _hourly()
    ref = sp.solar_position(40.0, -105.0, seconds)
    aware = pd.to_datetime(seconds, unit="s", utc=True)
    for label, times in [
        ("DatetimeIndex utc", aware),
        ("DatetimeIndex naive", aware.tz_localize(None)),
        ("DatetimeIndex offset", aware.tz_convert("Europe/Amsterdam")),
        ("Series utc", pd.Series(aware)),
        ("Series naive", pd.Series(aware.tz_localize(None))),
    ]:
        got = sp.solar_position(40.0, -105.0, times)
        np.testing.assert_array_equal(got, ref, err_msg=label)


@pytest.mark.parametrize(
    "entrypoint",
    [sp.solar_position_inplace, sp.solar_position_inplace_threaded],
)
def test_inplace_accepts_datetimes(entrypoint):
    seconds, datetimes = _hourly()
    ref = sp.solar_position(40.0, -105.0, seconds)
    bufs = [np.zeros(len(seconds)) for _ in range(5)]
    entrypoint(40.0, -105.0, datetimes, *bufs)
    for col, buf in enumerate(bufs):
        np.testing.assert_array_equal(buf, ref[:, col])


def test_sunrise_sunset_entrypoints_accept_datetimes():
    assert (
        sp.transit_sunrise_sunset(52.35888, 4.88185, UTC_INSTANT).sunrise
        == sp.transit_sunrise_sunset(52.35888, 4.88185, UTC_SECONDS).sunrise
    )
    assert sp.sun_event(
        52.35888, 4.88185, UTC_INSTANT, sp.SunEvent.SUNRISE, sp.EventDirection.NEXT
    ) == sp.sun_event(
        52.35888, 4.88185, UTC_SECONDS, sp.SunEvent.SUNRISE, sp.EventDirection.NEXT
    )


# -------------------------------------------------------------------- validation


def test_out_of_range_algorithm_is_rejected():
    """An invalid enum value must raise, not silently fall through to an algorithm."""
    with pytest.raises((ValueError, KeyError, TypeError)):
        sp.solar_position_single(40.0, -105.0, 1687348800.0, algorithm=99)


def test_out_of_range_refraction_is_rejected():
    with pytest.raises((ValueError, KeyError, TypeError)):
        sp.solar_position_single(40.0, -105.0, 1687348800.0, refraction=99)


def test_wrong_dtype_array_is_rejected():
    with pytest.raises((ValueError, TypeError)):
        sp.solar_position(40.0, -105.0, np.array([1, 2, 3], dtype=np.int64))


def test_non_contiguous_array_is_rejected():
    times = np.linspace(1687348800.0, 1687366800.0, 20)[::2]
    assert not times.flags["C_CONTIGUOUS"]
    with pytest.raises((ValueError, TypeError)):
        sp.solar_position(40.0, -105.0, times)


# ------------------------------------------------------------------- consistency


def test_psa_coefficient_sets_differ():
    a = sp.solar_position_single(40.0, -105.0, 1687348800.0, psa_coeffs=2020)
    b = sp.solar_position_single(40.0, -105.0, 1687348800.0, psa_coeffs=2001)
    assert a.elevation != b.elevation


def test_usno_gmst_options_are_both_accepted():
    for opt in (1, 2):
        r = sp.solar_position_single(
            40.0, -105.0, 1687348800.0, algorithm=sp.Algorithm.USNO, gmst_option=opt
        )
        assert np.isfinite(r.elevation)


def test_michalsky_options_are_honoured():
    base = dict(algorithm=sp.Algorithm.MICHALSKY)
    orig = sp.solar_position_single(
        40.0, -105.0, 1687348800.0, julian_date=sp.JulianDateMode.ORIGINAL, **base
    )
    std = sp.solar_position_single(
        40.0, -105.0, 1687348800.0, julian_date=sp.JulianDateMode.STANDARD, **base
    )
    assert np.isfinite(orig.elevation) and np.isfinite(std.elevation)
    no_spencer = sp.solar_position_single(
        40.0, -105.0, 1687348800.0, spencer_correction=False, **base
    )
    assert np.isfinite(no_spencer.azimuth)


# ------------------------------------------------------- sunrise, sunset, transit


def test_transit_sunrise_sunset_matches_julia(fx):
    for (lat, lon, alt, t), row in zip(_observers(fx), fx["sun_events"]):
        got = sp.transit_sunrise_sunset(lat, lon, t, altitude=alt)
        assert [got.transit, got.sunrise, got.sunset] == pytest.approx(
            row, abs=1e-9, rel=0
        ), f"lat={lat} lon={lon} t={t}"


def test_sun_event_matches_julia(fx):
    events = {
        "SUNRISE": sp.SunEvent.SUNRISE,
        "SUNSET": sp.SunEvent.SUNSET,
        "SOLAR_NOON": sp.SunEvent.SOLAR_NOON,
    }
    directions = {"NEXT": sp.EventDirection.NEXT,
                  "PREVIOUS": sp.EventDirection.PREVIOUS}
    for key, expected in fx["sun_event"].items():
        ev, direction = key.split("|")
        for (lat, lon, alt, t), want in zip(_observers(fx), expected):
            got = sp.sun_event(
                lat, lon, t, events[ev], directions[direction], altitude=alt
            )
            # The package returns a DateTime here, so this is whole-second exact.
            assert got == pytest.approx(want, abs=1e-6), f"{key} lat={lat} t={t}"


def test_known_sunrise_sunset_for_amsterdam():
    """Cross-check against the values published in the project README.

    README: transit 2023-06-21T13:42:15+02:00, sunrise 05:18:05+02:00,
    sunset 22:06:24+02:00 — i.e. 11:42:15, 03:18:05 and 20:06:24 UTC.
    """
    e = sp.transit_sunrise_sunset(52.35888, 4.88185, 1687348800.0, altitude=100.0)
    assert round(e.transit) == 11 * 3600 + 42 * 60 + 15
    assert round(e.sunrise) == 3 * 3600 + 18 * 60 + 5
    assert round(e.sunset) == 20 * 3600 + 6 * 60 + 24


def test_sunrise_precedes_transit_precedes_sunset():
    e = sp.transit_sunrise_sunset(40.0, -105.0, 1687348800.0)
    assert e.sunrise < e.transit < e.sunset


def test_next_and_previous_bracket_the_query_time():
    t = 1687348800.0
    nxt = sp.sun_event(40.0, -105.0, t, sp.SunEvent.SUNRISE, sp.EventDirection.NEXT)
    prv = sp.sun_event(40.0, -105.0, t, sp.SunEvent.SUNRISE, sp.EventDirection.PREVIOUS)
    assert prv < t < nxt
    # Consecutive sunrises are one day apart, give or take the equation of time.
    assert 23 * 3600 < nxt - prv < 25 * 3600


def test_polar_night_returns_zeros():
    """The package warns and returns zeros where the sun never rises."""
    # 2023-12-21, near the pole
    e = sp.transit_sunrise_sunset(89.0, 0.0, 1703116800.0)
    assert (e.transit, e.sunrise, e.sunset) == (0.0, 0.0, 0.0)


# -------------------------------------------------------------------- threading


def test_julia_nthreads_is_reported():
    n = sp.julia_nthreads()
    assert isinstance(n, int) and n >= 1


def test_set_num_threads_rejects_bad_input():
    with pytest.raises(ValueError):
        sp.set_num_threads(0)
    with pytest.raises(ValueError):
        sp.set_num_threads(-1)


def test_set_num_threads_after_runtime_start_raises():
    """The thread count is fixed once the runtime is up, so a late call must not pass
    silently. Every other test in this file has already started the runtime, so by the
    time this runs the call is guaranteed to be late."""
    sp.julia_nthreads()  # ensure the runtime is running regardless of test order
    current = sp.julia_nthreads()
    with pytest.raises(RuntimeError, match="already running"):
        sp.set_num_threads(current + 1)


def test_threaded_matches_serial(fx):
    """The parallel loop must agree with the serial one, elementwise, per algorithm.

    This is meaningful on a single-threaded build too: it exercises the separate
    all-positional entrypoint and the hand-maintained keyword wrapper over it.
    """
    lat, lon, alt = 52.35888, 4.88185, 100.0
    times = np.array(fx["unix_seconds"], dtype=np.float64)
    n = len(times)
    for alg in sp.Algorithm:
        bufs = [np.zeros(n) for _ in range(5)]
        sp.solar_position_inplace_threaded(
            lat, lon, times, *bufs, altitude=alt, algorithm=alg
        )
        serial = sp.solar_position(lat, lon, times, altitude=alt, algorithm=alg)
        for col, buf in enumerate(bufs):
            np.testing.assert_array_equal(
                buf, serial[:, col], err_msg=f"{alg} col {col}"
            )
        allocating = sp.solar_position_threaded(
            lat, lon, times, altitude=alt, algorithm=alg
        )
        np.testing.assert_array_equal(allocating, serial, err_msg=str(alg))


def test_threaded_rejects_short_buffers():
    times = np.zeros(10)
    short = [np.zeros(3) for _ in range(5)]
    with pytest.raises(sp.JLWError) as excinfo:
        sp.solar_position_inplace_threaded(0.0, 0.0, times, *short)
    assert excinfo.value.code == 3


def test_threaded_is_repeatable_over_many_calls():
    """A parallel region re-entered many times must stay stable and deterministic."""
    times = np.linspace(1687348800.0, 1687435200.0, 500)
    first = None
    for _ in range(25):
        bufs = [np.zeros(len(times)) for _ in range(5)]
        sp.solar_position_inplace_threaded(
            40.0, -105.0, times, *bufs, algorithm=sp.Algorithm.SPA
        )
        if first is None:
            first = [b.copy() for b in bufs]
        else:
            for a, b in zip(first, bufs):
                np.testing.assert_array_equal(a, b)


# ------------------------------------------------------------------- consistency


def test_extreme_latitudes_and_epochs_are_finite(fx):
    """The fixture conditions include the poles and the years 1800 and 2200."""
    for lat, lon, alt, t in _observers(fx):
        for alg in sp.Algorithm:
            r = sp.solar_position_single(
                lat, lon, t, altitude=alt, algorithm=alg
            )
            assert np.isfinite(r.azimuth) and np.isfinite(r.elevation), (alg, lat, t)
