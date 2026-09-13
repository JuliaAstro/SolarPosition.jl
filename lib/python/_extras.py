"""Hand-maintained additions to the generated façade.

`build.jl` copies this module into the generated Python package and appends an import to
`_facade.py` so these definitions override the generated ones.

Why this file exists: three entrypoints must be declared with all-positional arguments
on the Julia side, because reached through `@api`'s keyword-argument wrapper the
`juliac --trim` verifier cannot resolve the call ("unresolved call from statement
Core.kwcall(...)") and the build fails.

- ``solar_position_inplace_threaded`` and ``solar_position_threaded`` —
  ``Threads.@threads`` builds a closure.
- ``transit_sunrise_sunset`` — the seconds-returning sunrise/sunset path takes a
  different ``_frac_to_event`` specialisation than the ``DateTime`` one, and only the
  former trips the verifier. ``sun_event`` goes through the ``DateTime`` path and keeps
  its keywords, so it needs no wrapper for this reason.

Declaring those arguments positionally keeps the entrypoints trimmable, and the
wrappers here restore the keyword-only signatures the rest of the API has.

``solar_position`` is here for a second reason: the generated binding for it is
miscompiled by some builds of libffi. See its docstring — ``solar_position_threaded``
has the same signature shape and takes the same detour.

Every entrypoint that takes a time accepts datetimes as well as Unix seconds — see
``_unix_seconds``. The C side takes only ``Float64``, so that conversion has to happen
in Python, and it is the sole reason ``solar_position_single``,
``solar_position_inplace`` and ``sun_event`` are wrapped here at all.
"""

import ctypes
import datetime

import numpy as np

from . import _lowlevel
from ._lowlevel import (
    COpt_Float64,
    CVector_borrowed_Float64,
    Algorithm,
    EventDirection,
    JulianDateMode,
    RefractionModel,
    SunEvent,
    _enum_coerce,
)

__all__ = [
    "set_num_threads",
    "solar_position",
    "solar_position_inplace",
    "solar_position_inplace_threaded",
    "solar_position_single",
    "solar_position_threaded",
    "sun_event",
    "transit_sunrise_sunset",
]


def _unix_seconds(when):
    """One instant as seconds since the Unix epoch, UTC.

    Accepts a ``datetime.datetime`` (including a pandas ``Timestamp``), a
    ``datetime.date`` or a ``numpy.datetime64``. Anything else — a plain number above
    all — is returned untouched, so this only ever adds accepted input.

    A naive ``datetime`` is read as UTC, not as local time. That differs from
    ``datetime.timestamp()``, deliberately: every time this library takes or returns is
    UTC, and ``numpy.datetime64`` carries no zone to read, so treating naive input as
    UTC is the only rule that stays consistent across all the accepted types. Attach
    ``tzinfo=datetime.timezone.utc`` when you want to be explicit, or any other
    ``tzinfo`` to have the offset applied.
    """
    if isinstance(when, datetime.datetime):
        if when.tzinfo is None:
            when = when.replace(tzinfo=datetime.timezone.utc)
        return when.timestamp()
    if isinstance(when, datetime.date):
        # A bare date means midnight UTC. `datetime` is a subclass of `date`, so this
        # is reached only by a real `date`.
        midnight = datetime.datetime(
            when.year, when.month, when.day, tzinfo=datetime.timezone.utc
        )
        return midnight.timestamp()
    if isinstance(when, np.datetime64):
        return np.datetime64(when, "us").astype(np.int64) / 1e6
    return when


def _unix_seconds_each(times):
    """Unix seconds for a sequence of instants, one element at a time."""
    return np.array([_unix_seconds(t) for t in times], dtype=np.float64)


def _holds_datetimes(times):
    """Whether ``times`` starts with a datetime, taking the rest to match."""
    for first in times:
        return isinstance(first, (datetime.date, np.datetime64))
    return False


def _unix_seconds_array(times):
    """A sequence of instants as a ``float64`` array of Unix seconds.

    Converts ``datetime64`` arrays, pandas ``DatetimeIndex`` and ``Series`` (tz-aware
    or not) and lists of ``datetime`` objects, by the rules in ``_unix_seconds``.
    Anything else is passed through untouched, so numeric input still has to arrive as
    a contiguous ``float64`` array rather than being silently reinterpreted.
    """
    dtype = getattr(times, "dtype", None)
    if getattr(dtype, "tz", None) is not None:
        # A tz-aware pandas container. What numpy sees of one — UTC or local wall time
        # — has varied across pandas versions, so read each Timestamp's own offset
        # instead of converting the block.
        return _unix_seconds_each(times)
    kind = getattr(dtype, "kind", None)
    if kind == "M":
        # Microseconds, because that is as fine as a float64 Unix second resolves at
        # present-day magnitudes; going through int64 keeps the conversion exact.
        return np.asarray(times, dtype="datetime64[us]").astype(np.int64) / 1e6
    if (kind == "O" or isinstance(times, (list, tuple))) and _holds_datetimes(times):
        return _unix_seconds_each(times)
    return times


def set_num_threads(n: int) -> int:
    """Choose how many Julia threads to use. Starts the Julia runtime.

    Must be called before any solar position call, because the thread count is fixed
    once
    the runtime is running. Returns the number of threads actually configured, and
    raises
    ``RuntimeError`` if that does not match what you asked for — which is what happens
    if
    the runtime was already started, whether by an earlier computation or an earlier
    call
    to this function.

    The default build starts single-threaded with Julia's signal handling disabled,
    which
    is the right mode for a library embedded in Python: Ctrl-C keeps working normally.
    Asking for more than one thread necessarily switches Julia's own SIGINT/SIGSEGV
    handlers on, because on Julia >= 1.12 a multi-threaded library with signal handling
    off segfaults during shutdown. That trade-off is why this is an explicit call rather
    than something the library does for you. See
    https://github.com/JuliaLang/julia/issues/61319

    >>> import solarposition as sp
    >>> sp.set_num_threads(8)        # doctest: +SKIP
    8
    """
    if n < 1:
        raise ValueError(f"n must be >= 1, got {n}")

    fn = _lowlevel._lib.solarposition_set_num_threads
    fn.argtypes = [ctypes.c_int]
    fn.restype = ctypes.c_int
    if fn(int(n)) < 0:
        raise ValueError(f"could not request {n} threads")

    # Start the runtime now and report what it actually came up with. There is no
    # reliable way to ask whether the runtime is already running from here —
    # `jl_is_initialized()` reads 0 even after a call in an AOT-compiled library — so
    # verifying the outcome is what makes a late call an error rather than a silent no-
    # op.
    actual = _lowlevel.libsolarposition_julia_nthreads().value
    if actual != n:
        raise RuntimeError(
            f"asked for {n} Julia threads but got {actual}; the runtime was already "
            "running. Call set_num_threads() before any solar position call."
        )
    return actual


def solar_position_single(
    latitude,
    longitude,
    unix_seconds,
    *,
    altitude=0.0,
    algorithm=Algorithm.PSA,
    refraction=RefractionModel.DEFAULT,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
    refraction_limit=-0.5667,
    psa_coeffs=2020,
    gmst_option=1,
    spencer_correction=True,
    julian_date=JulianDateMode.ORIGINAL,
):
    """Solar position for one instant.

    ``unix_seconds`` is seconds since the Unix epoch, UTC, or any of the datetime types
    ``_unix_seconds`` accepts::

        >>> import datetime as dt, solarposition as sp
        >>> when = dt.datetime(2023, 6, 21, 3, 45, tzinfo=dt.timezone.utc)
        >>> sp.solar_position_single(40.0, -105.0, when)     # doctest: +SKIP

    A naive datetime is read as UTC. ``latitude`` is positive north and ``longitude``
    positive east, both in degrees, and ``altitude`` is metres above mean sea level.

    ``pressure`` [Pa] and ``temperature`` [°C] feed the refraction models that take
    them, and the SPA algorithm. ``delta_t`` [s] is the difference between terrestrial
    time and UT1; pass ``None`` to have it computed from the date. The remaining
    keywords are algorithm options: ``atmos_refract`` and ``psa_coeffs`` for SPA and
    PSA, ``gmst_option`` for USNO, and ``spencer_correction`` and ``julian_date`` for
    Michalsky. ``refraction_limit`` is SPARefraction's own refraction limit.
    """
    _r = _lowlevel.libsolarposition_solar_position_single(
        latitude,
        longitude,
        _unix_seconds(unix_seconds),
        altitude,
        _enum_coerce(Algorithm, algorithm),
        _enum_coerce(RefractionModel, refraction),
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
        refraction_limit,
        psa_coeffs,
        gmst_option,
        spencer_correction,
        _enum_coerce(JulianDateMode, julian_date),
    )
    return _r.value


def transit_sunrise_sunset(
    latitude,
    longitude,
    unix_seconds,
    *,
    altitude=0.0,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
):
    """Solar transit, sunrise and sunset for the UTC day containing ``unix_seconds``.

    Returns a ``SunEvents`` with ``transit``, ``sunrise`` and ``sunset`` as seconds
    since
    midnight UTC of that day. Any of them can fall outside ``[0, 86400)`` when the event
    lands outside that UTC day.

    ``unix_seconds`` may be given as a datetime; see ``solar_position_single``.

    Computed with SPA, so ``delta_t``, ``pressure``, ``temperature`` and
    ``atmos_refract`` are SPA's options. There is deliberately no ``horizon`` parameter:
    the package hardcodes the horizon depression and ignores ``Observer.horizon``.

    In polar day or polar night there is no sunrise or sunset. The underlying Julia
    package warns on stderr and returns zero for all three fields.
    """
    _r = _lowlevel.libsolarposition_transit_sunrise_sunset(
        latitude,
        longitude,
        _unix_seconds(unix_seconds),
        altitude,
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
    )
    return _r.value


def sun_event(
    latitude,
    longitude,
    unix_seconds,
    event,
    direction,
    *,
    altitude=0.0,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
):
    """The next or previous sunrise, sunset or solar noon, as Unix seconds.

    ``event`` selects sunrise, sunset or solar noon and ``direction`` selects whether to
    search forward or backward from ``unix_seconds``, which may be given as a datetime;
    see ``solar_position_single``. The result is rounded to a whole second, because the
    underlying package returns a ``DateTime``; use ``transit_sunrise_sunset`` when the
    sub-second part matters. See it also for the keyword arguments.
    """
    _r = _lowlevel.libsolarposition_sun_event(
        latitude,
        longitude,
        _unix_seconds(unix_seconds),
        _enum_coerce(SunEvent, event),
        _enum_coerce(EventDirection, direction),
        altitude,
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
    )
    return _r.value


def solar_position_inplace(
    latitude,
    longitude,
    unix_seconds,
    azimuth,
    elevation,
    zenith,
    apparent_elevation,
    apparent_zenith,
    *,
    altitude=0.0,
    algorithm=Algorithm.PSA,
    refraction=RefractionModel.DEFAULT,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
    refraction_limit=-0.5667,
    psa_coeffs=2020,
    gmst_option=1,
    spencer_correction=True,
    julian_date=JulianDateMode.ORIGINAL,
):
    """Solar position for many instants, written into caller-allocated output buffers.

    The five output arrays must each hold at least ``len(unix_seconds)`` elements. They
    are borrowed, so the writes land directly in the caller's numpy arrays and nothing
    is allocated. The observer is built once and only read, so this is also the form the
    threaded entrypoint parallelises.

    ``unix_seconds`` may be a sequence of datetimes instead of a ``float64`` array; see
    ``solar_position_single``. Converting one allocates, so pass Unix seconds when the
    point of this entrypoint is to allocate nothing.

    See ``solar_position_single`` for the keyword arguments.
    """
    return _lowlevel.libsolarposition_solar_position_inplace(
        latitude,
        longitude,
        CVector_borrowed_Float64.from_numpy(_unix_seconds_array(unix_seconds)),
        CVector_borrowed_Float64.from_numpy(azimuth),
        CVector_borrowed_Float64.from_numpy(elevation),
        CVector_borrowed_Float64.from_numpy(zenith),
        CVector_borrowed_Float64.from_numpy(apparent_elevation),
        CVector_borrowed_Float64.from_numpy(apparent_zenith),
        altitude,
        _enum_coerce(Algorithm, algorithm),
        _enum_coerce(RefractionModel, refraction),
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
        refraction_limit,
        psa_coeffs,
        gmst_option,
        spencer_correction,
        _enum_coerce(JulianDateMode, julian_date),
    )


def solar_position_inplace_threaded(
    latitude,
    longitude,
    unix_seconds,
    azimuth,
    elevation,
    zenith,
    apparent_elevation,
    apparent_zenith,
    *,
    altitude=0.0,
    algorithm=Algorithm.PSA,
    refraction=RefractionModel.DEFAULT,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
    refraction_limit=-0.5667,
    psa_coeffs=2020,
    gmst_option=1,
    spencer_correction=True,
    julian_date=JulianDateMode.ORIGINAL,
):
    """Solar position for many instants, computed in parallel into caller-held buffers.

    Identical to ``solar_position_inplace`` except that the loop runs across the
    Julia
    threads the library was compiled with. Call ``julia_nthreads()`` to find out how
    many
    that is; a single-threaded build runs this serially and gives the same answers.

    The five output arrays must each hold at least ``len(unix_seconds)`` elements and
    are
    written in place. See ``solar_position_single`` for the keyword arguments.
    """
    return _lowlevel.libsolarposition_solar_position_inplace_threaded(
        latitude,
        longitude,
        CVector_borrowed_Float64.from_numpy(_unix_seconds_array(unix_seconds)),
        CVector_borrowed_Float64.from_numpy(azimuth),
        CVector_borrowed_Float64.from_numpy(elevation),
        CVector_borrowed_Float64.from_numpy(zenith),
        CVector_borrowed_Float64.from_numpy(apparent_elevation),
        CVector_borrowed_Float64.from_numpy(apparent_zenith),
        altitude,
        _enum_coerce(Algorithm, algorithm),
        _enum_coerce(RefractionModel, refraction),
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
        refraction_limit,
        psa_coeffs,
        gmst_option,
        spencer_correction,
        _enum_coerce(JulianDateMode, julian_date),
    )


def solar_position(
    latitude,
    longitude,
    unix_seconds,
    *,
    altitude=0.0,
    algorithm=Algorithm.PSA,
    refraction=RefractionModel.DEFAULT,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
    refraction_limit=-0.5667,
    psa_coeffs=2020,
    gmst_option=1,
    spencer_correction=True,
    julian_date=JulianDateMode.ORIGINAL,
):
    """Solar position for many instants, returned as an ``n x 5`` array.

    The columns are azimuth, elevation, zenith, apparent elevation and apparent zenith.
    This allocates the result for you; use ``solar_position_inplace`` when you
    already hold the output buffers. See ``solar_position_single`` for the keyword
    arguments.

    ``unix_seconds`` may be a ``float64`` array of Unix seconds, a ``datetime64`` array,
    a pandas ``DatetimeIndex`` or ``Series``, or a list of ``datetime`` objects::

        >>> import pandas as pd, solarposition as sp
        >>> t = pd.date_range("2023-06-21", periods=24, freq="h", tz="UTC")
        >>> sp.solar_position(40.0, -105.0, t).shape   # doctest: +SKIP
        (24, 5)

    Why this overrides the generated binding: the C entrypoint that returns an owning
    matrix is called correctly from C, but some builds of libffi marshal that particular
    signature wrongly and silently pass ``delta_t`` where ``latitude`` belongs. The
    trigger is a struct argument split across classes (``COpt_Float64`` is an integer
    flag plus a double) whose integer half lands in the last available general-purpose
    register; libffi then puts its double half in ``xmm0``, on top of the first
    floating-point argument. Only this entrypoint has that shape — every other one
    either passes ``delta_t`` on the stack or leaves a register spare. Observed with the
    libffi bundled in python-build-standalone 3.13.7 (what ``uv`` installs by default)
    and not with Fedora's libffi 3.5.2, so it cannot be avoided by a version check.

    Routing through ``solar_position_inplace``, whose signature is unaffected, makes
    the answer independent of the host libffi. It is also the faster path, since the
    result is written straight into the returned array.
    """
    times = _unix_seconds_array(unix_seconds)
    n = len(times)
    # Column-major, so each column below is a contiguous 1-D view that the C side can
    # write into directly. The layout matches what the generated binding returned.
    out = np.empty((n, 5), dtype=np.float64, order="F")
    _lowlevel.libsolarposition_solar_position_inplace(
        latitude,
        longitude,
        CVector_borrowed_Float64.from_numpy(times),
        CVector_borrowed_Float64.from_numpy(out[:, 0]),
        CVector_borrowed_Float64.from_numpy(out[:, 1]),
        CVector_borrowed_Float64.from_numpy(out[:, 2]),
        CVector_borrowed_Float64.from_numpy(out[:, 3]),
        CVector_borrowed_Float64.from_numpy(out[:, 4]),
        altitude,
        _enum_coerce(Algorithm, algorithm),
        _enum_coerce(RefractionModel, refraction),
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
        refraction_limit,
        psa_coeffs,
        gmst_option,
        spencer_correction,
        _enum_coerce(JulianDateMode, julian_date),
    )
    return out


def solar_position_threaded(
    latitude,
    longitude,
    unix_seconds,
    *,
    altitude=0.0,
    algorithm=Algorithm.PSA,
    refraction=RefractionModel.DEFAULT,
    pressure=101325.0,
    temperature=12.0,
    delta_t=67.0,
    atmos_refract=0.5667,
    refraction_limit=-0.5667,
    psa_coeffs=2020,
    gmst_option=1,
    spencer_correction=True,
    julian_date=JulianDateMode.ORIGINAL,
):
    """Solar position for many instants, computed in parallel into a new array.

    ``solar_position`` and ``solar_position_inplace_threaded`` in one: the columns are
    azimuth, elevation, zenith, apparent elevation and apparent zenith, the result is
    allocated for you, and the loop runs across the Julia threads the library was
    compiled with. Call ``julia_nthreads()`` to find out how many that is; a
    single-threaded build runs this serially and gives the same answers.

    ``unix_seconds`` accepts the same datetime types as ``solar_position``, and the
    keyword arguments are ``solar_position_single``'s.

    Like ``solar_position``, this routes through the in-place entrypoint rather than the
    generated binding for the allocating one, because that signature is miscompiled by
    some builds of libffi. See ``solar_position`` for the details.
    """
    times = _unix_seconds_array(unix_seconds)
    n = len(times)
    out = np.empty((n, 5), dtype=np.float64, order="F")
    _lowlevel.libsolarposition_solar_position_inplace_threaded(
        latitude,
        longitude,
        CVector_borrowed_Float64.from_numpy(times),
        CVector_borrowed_Float64.from_numpy(out[:, 0]),
        CVector_borrowed_Float64.from_numpy(out[:, 1]),
        CVector_borrowed_Float64.from_numpy(out[:, 2]),
        CVector_borrowed_Float64.from_numpy(out[:, 3]),
        CVector_borrowed_Float64.from_numpy(out[:, 4]),
        altitude,
        _enum_coerce(Algorithm, algorithm),
        _enum_coerce(RefractionModel, refraction),
        pressure,
        temperature,
        COpt_Float64.from_optional(delta_t),
        atmos_refract,
        refraction_limit,
        psa_coeffs,
        gmst_option,
        spencer_correction,
        _enum_coerce(JulianDateMode, julian_date),
    )
    return out
