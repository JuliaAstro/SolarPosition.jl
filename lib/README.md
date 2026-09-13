# libsolarposition — Python bindings for SolarPosition.jl

A C-ABI shared library and Python package compiled from SolarPosition.jl with
[`juliac --trim`](https://github.com/JuliaLang/JuliaC.jl), wrapped by
[JuliaLibWrapping.jl](https://github.com/JuliaInterop/JuliaLibWrapping.jl). No Julia
installation is needed to use the result: the Julia runtime is bundled.

Every positioning algorithm and every refraction model is exposed, plus the
sunrise/sunset utilities. Results are validated to match both the Julia package and the
solposx reference tables — see [Tests](#tests).

## Requirements

- **Julia 1.13+** to build. JuliaLibWrapping's ABI export requires it. The package
  itself still supports Julia 1.10 LTS; this subproject is deliberately *not* part of the
  root `[workspace]` so it cannot drag that requirement into the package's CI.
- Python 3.8+ and NumPy to use.
- A C compiler (`gcc`) — `juliac` compiles a small shim and links the library.

## Build

```bash
julia --project=lib -e 'using Pkg; Pkg.instantiate()'
julia --project=lib/build-env -e 'using Pkg; Pkg.instantiate()'

julia --project=lib lib/build.jl              # default: signal-safe, single-threaded
julia --project=lib lib/build.jl --threads=4  # bake in a default; usually unneeded
julia --project=lib lib/build.jl --verbose    # pass juliac's output through

pip install ./lib/out
```

Output lands in `lib/out/` (gitignored):

| Path | What |
| --- | --- |
| `libsolarposition.h` | C header |
| `libsolarposition.abi.json` | ABI metadata emitted by `juliac` |
| `libsolarposition.jlw.json` | `@api` metadata sidecar |
| `solarposition/` | installable Python package, including a ~80 MB `bundle/` |
| `libsolarposition-bundle/` | the relocatable runtime bundle |

The compiled library is 2.9 MB; the rest of the bundle is the Julia runtime.

## Python API

```python
import datetime as dt
import numpy as np
import solarposition as sp

# One instant, as a datetime or as Unix seconds; both reach the same C double.
when = dt.datetime(2023, 6, 21, 12, tzinfo=dt.timezone.utc)
r = sp.solar_position_single(52.35888, 4.88185, when, altitude=100.0,
                             algorithm=sp.Algorithm.SPA)
r.azimuth, r.elevation, r.zenith, r.apparent_elevation, r.apparent_zenith

# Many instants -> an (n, 5) array of the same five columns.
times = np.array([1687348800.0 + 3600 * i for i in range(24)])
m = sp.solar_position(52.35888, 4.88185, times, algorithm=sp.Algorithm.SPA)

# Or write into buffers you already hold, with no allocation.
az, el, ze, ael, aze = (np.zeros(len(times)) for _ in range(5))
sp.solar_position_inplace(52.35888, 4.88185, times, az, el, ze, ael, aze)

# Sunrise, transit and sunset, as seconds since midnight UTC.
e = sp.transit_sunrise_sunset(52.35888, 4.88185, when, altitude=100.0)
e.transit, e.sunrise, e.sunset

# The next or previous event, as Unix seconds.
sp.sun_event(52.35888, 4.88185, 1687348800.0,
             sp.SunEvent.SUNRISE, sp.EventDirection.NEXT)
```

### Times

Anywhere a time is taken you may pass Unix seconds, a `datetime.datetime`, a
`datetime.date` (meaning midnight), a `numpy.datetime64`, or — for the batch
entrypoints — a `datetime64` array, a list of `datetime` objects, or a pandas
`DatetimeIndex` or `Series`, tz-aware or not.

A `datetime` carrying a `tzinfo` has its offset applied. A naive one is read as **UTC**,
not as local time. That departs from `datetime.timestamp()` on purpose: everything this
library takes and returns is UTC, and `numpy.datetime64` carries no zone to read, so UTC
is the only rule that stays consistent across all the accepted types.

The conversion happens in Python, in `_extras.py` — the C side takes `Float64` only. It
is vectorised for `datetime64` input and falls back to a per-element loop for object
arrays and tz-aware pandas containers, so a large tz-aware index is worth converting
once yourself if you are calling repeatedly. Numeric input is passed through untouched:
a wrong dtype or a non-contiguous array still raises rather than being silently copied
or reinterpreted.

Results come back as Unix seconds; converting those back is
`datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc)`.

### Algorithms and options

`Algorithm` is `PSA NOAA SPA WALRAVEN USNO IQBAL MICHALSKY`; `RefractionModel` is
`DEFAULT NONE HUGHES ARCHER BENNETT MICHALSKY SG2 SPA`. Both are `enum.IntEnum`s and are
validated on the way in — an out-of-range value raises rather than silently selecting an
algorithm. `DEFAULT` means each algorithm's own default, exactly as in Julia: none for
PSA, Walraven, Iqbal and USNO; HUGHES for NOAA, MICHALSKY for Michalsky, SPA for SPA.

Algorithm and refraction options ride along as keyword arguments: `pressure`,
`temperature`, `delta_t` (pass `None` to compute it from the date), `atmos_refract`,
`refraction_limit`, `psa_coeffs`, `gmst_option`, `spencer_correction` and `julian_date`.

Because there is one entrypoint per shape rather than one per algorithm, **every option is
accepted by every call and quietly ignored by algorithms that have no such setting**:

| Option | Reaches |
| --- | --- |
| `pressure`, `temperature` | HUGHES, BENNETT, SG2, SPARefraction; the SPA algorithm |
| `delta_t` | SPA, USNO. *Not* PSA or Iqbal (no such field), and not NOAA (see below) |
| `atmos_refract` | the SPA algorithm |
| `refraction_limit` | SPARefraction |
| `psa_coeffs` | PSA (2001 or 2020) |
| `gmst_option` | USNO (1 or 2) |
| `spencer_correction`, `julian_date` | Michalsky |

`lib/examples/getting_started.py` is a runnable tour of all of this.

Every entrypoint returns all five angles. Where the selected refraction model applies no
correction, `apparent_*` equals the true value. That keeps the ABI return type uniform
across the `SolPos`/`ApparentSolPos` split, which is what lets each dispatch arm stay
inferable under `--trim`.

Errors surface as `JLWError` with `.code` and `.message` — `2` for `ArgumentError`, `3`
for `DimensionMismatch`, and so on.

## Threading

Choose the thread count at run time, before the first computation:

```python
import solarposition as sp

sp.set_num_threads(8)          # must precede any solar position call
sp.julia_nthreads()            # -> 8
sp.solar_position_threaded(lat, lon, times)              # -> a new (n, 5) array
sp.solar_position_inplace_threaded(lat, lon, times, *buffers)   # into your buffers
```

`set_num_threads` returns what it actually configured and raises `RuntimeError` if that
does not match the request, which is what happens when the runtime is already running —
whether from an earlier computation or an earlier call. The count cannot change after
that; start a new process instead. `julia_nthreads()` reports the current value, and
`solar_position_threaded` and `solar_position_inplace_threaded` run the loop across
those threads, giving elementwise identical answers to their serial counterparts
`solar_position` and `solar_position_inplace`.

**The default is one thread, and raising it is a real trade-off.** More than one Julia
thread requires `handle-signals=yes`, because on Julia ≥ 1.12 a library with
`handle-signals=no` and more than one thread segfaults during shutdown (JuliaC's own
validation step rejects that combination). `set_num_threads(n > 1)` therefore turns
Julia's own SIGINT/SIGSEGV handlers on, which changes Ctrl-C behaviour for the whole
Python program. That is why it is an explicit call rather than a default. Upstream
tracking issue: [JuliaLang/julia#61319](https://github.com/JuliaLang/julia/issues/61319),
whose "critical fixes for even basic functionality" are still open.

### How it works, and what does not work

`JULIA_NUM_THREADS` has no effect. `juliac` compiles an `__attribute__((constructor))`
shim that calls `jl_parse_opts` with `--threads=<N>` at `dlopen`, overriding the
environment.

But the Julia runtime does **not** initialise at `dlopen` — it starts on the first call
into a `@ccallable` entrypoint. (Delete `libopenblas64_.so` from the bundle and
`import solarposition` still succeeds; the first computation is what dies.) That leaves a
window, and `lib/c/set_num_threads.c` uses it.

Within that window, one approach works and one does not:

| Attempt | Result |
| --- | --- |
| Assign `jl_options.nthreads` directly | write lands, `Threads.nthreads()` ignores it |
| Re-run `jl_parse_opts`, as JuliaC's own shim does | works |

`jl_is_initialized()` is not usable as a guard here — it reads 0 even after a successful
call in an AOT-compiled library — which is why `set_num_threads` verifies its own outcome
instead of asking whether the runtime has started.

Passing `--threads=N` to `lib/build.jl` still bakes a default in at compile time, which is
useful if you want a multi-threaded library without the caller having to ask.

### Measured

8 threads on a 32-core machine, one million instants, SPA, from the **default**
single-threaded build with `set_num_threads(8)`:

| | time | |
| --- | --- | --- |
| serial | 3412.8 ms | |
| threaded | 430.2 ms | **7.93x** |

Results are elementwise identical, and 20/20 import-compute-exit cycles at 8 threads
exited cleanly.

## Tests

```bash
julia --project=test lib/test/generate_fixtures.jl   # writes lib/test/fixtures.json
julia --project=lib lib/build.jl
pip install ./lib/out
pytest lib/test -v
```

`fixtures.json` is generated (and gitignored) from two independent sources:

- **The solposx reference tables** in `test/positioning/expected-values.jl` — the same
  values the Julia test suite uses, on the 84.375 s grid where the full Julian Date is
  exactly representable in Float64. Compared at the Julia suite's own tolerances
  (`1e-10`, `1e-8` for SPA). Each table carries its call spec as data, because they are
  not uniform: NOAA is validated against HUGHES at temperature 10.0 and skips the poles,
  USNO has two GMST variants, and SPA has a column this API does not expose.
- **This checkout's own Julia output** for all 7 × 8 algorithm/refraction pairs at the
  same 19 instants (poles, years 1800 and 2200 included), plus sunrise/sunset. Compared
  at `1e-12`, which isolates anything `--trim` changed about the numerics.

Both pass. The refraction decoupling described below was verified this way: all 168
algorithm × refraction × instant combinations are bit-identical to
`solar_position(obs, dt, alg, refraction)`.

## Design notes

**Refraction is decoupled.** `Positioning._solar_position(obs, dt, alg, refraction)`
computes the geometric position and then adds `Refraction.refraction(model, elevation)`.
So the 7 × 8 matrix needs 7 geometric arms plus 8 refraction arms rather than 56 compiled
arms. `DEFAULT` is the exception and delegates to the package per algorithm, because
SPA's default path feeds the SPA struct's own pressure, temperature and `atmos_refract`
and cannot be rebuilt from the decoupled form.

**The enums live in nested modules.** `@enum` binds its members in the enclosing module,
and `MICHALSKY` and `SPA` each name both an algorithm and a refraction model. Nesting
avoids the collision while still giving Python the clean `Algorithm.SPA` /
`RefractionModel.SPA` spelling.

**Time crosses as Unix seconds**, not a `DateTime`, so nothing on the compiled path
touches TimeZones.jl. Convert on the Python side.

**No `horizon` parameter.** `src/Utilities/spa.jl` hardcodes the horizon depression to
−0.8333° and never reads `Observer.horizon`; the field is inert throughout `src/`. A
`horizon` keyword here would be silently ignored, which matters most in exactly the case
someone would reach for it (civil twilight). Add one when the package honours the field.

**`Interpolated` and `solar_rate` are not exposed.** They need Interpolations.jl on the
compiled path, which is very unlikely to survive `--trim`.

## Known constraints

Ordered by how much they cost.

1. **The wheel is not publishable as-is.** `auditwheel` reports the wheel as
   `linux_x86_64`, constrained by glibc 2.38 symbols from the build host, and PyPI only
   accepts `manylinux*`. Publishing requires building inside a manylinux container (e.g.
   `quay.io/pypa/manylinux_2_28_x86_64`) with Julia installed. The generated
   `pyproject.toml` also declares `py3-none-any`, which is wrong for a binary wheel, and
   carries a placeholder version. See
   [JuliaLibWrapping#38](https://github.com/JuliaInterop/JuliaLibWrapping.jl/issues/38).
   The built wheel is 72 MB, under PyPI's 100 MB per-file cap but without much headroom.
2. **~103 MB of the bundle is OpenBLAS, and it cannot be removed.** SolarPosition uses no
   linear algebra, but `OpenBLAS_jll.__init__` still runs when the trimmed library
   initialises and hard-fails with `could not load library "libopenblas64_.so"` if the
   file is absent. Deleting libgfortran, libquadmath, libgomp or libblastrampoline hits
   the same error. PackageCompiler also stores each library three times (`libfoo.so`,
   `.so.N`, `.so.N.M`) — in `lib/out` those are links, but `pip install` materialises
   them into 231 MB on disk.
3. **Three entrypoints must take positional arguments.** Reached through `@api`'s
   keyword-argument wrapper, the `--trim` verifier cannot resolve the call
   (`unresolved call from statement Core.kwcall(...)`) for
   `solar_position_threaded` and `solar_position_inplace_threaded`
   (`Threads.@threads` builds a closure) or
   `transit_sunrise_sunset` (the seconds-returning path takes a different
   `_frac_to_event` specialisation than the `DateTime` one, and only that one trips the
   verifier — `sun_event` keeps its keywords). `lib/python/_extras.py` restores the
   keyword-only Python signatures by hand.
4. **The two allocating entrypoints cannot use their generated bindings.** Some builds
   of libffi marshal that signature wrongly and pass `delta_t` where `latitude`
   belongs, so every result is silently for the wrong place. Calling the same `.so`
   from C is correct, and so is every other entrypoint, so this is neither a Julia nor
   a JuliaLibWrapping fault. The trigger is an argument classified across two classes —
   `COpt_Float64` is an `int32` flag plus a `double` — whose integer half lands in the
   *last* free general-purpose register; libffi then puts its `double` half in `xmm0`,
   on top of the first floating-point argument. Only `solar_position` and
   `solar_position_threaded` have that shape: the returned matrix forces a hidden return
   pointer, and with the input vector and the two enums that fills the register file
   exactly. Both are wrong by the same 14.53° here. Seen with the libffi bundled in
   python-build-standalone 3.13.7, which is what `uv` installs by default, and not with
   Fedora's libffi 3.5.2 — so a version check cannot route around it.
   `lib/python/_extras.py` reimplements both over their in-place counterparts, whose
   signatures are unaffected and which are the faster path anyway.
   `test_delta_t_does_not_leak_into_other_arguments` guards the whole
   class: `delta_t` is the only split argument, and three algorithms ignore it, so
   changing it must change nothing.
5. **JuliaLibWrapping forwards neither `jl_options` nor `c_sources`** to
   `JuliaC.ImageRecipe`, so neither the thread defaults nor the load-time thread shim can
   go through `build_library`. `build.jl` therefore runs the normal `standard_build` for
   the wrappers and ABI, then recompiles the library and bundle through `JuliaC`
   directly. Only the `.so` differs between thread configurations, so the wrappers are
   untouched. Delete `rebuild_library` once a passthrough exists upstream.
6. **One wrapped library per process.** The generated `_lowlevel.py` warns if a second
   JuliaLibWrapping-wrapped package is imported into the same process, because the
   dynamic linker would share a single `libjulia` between them.
7. **Keep virtualenvs out of `lib/`.** `juliac` copies the project tree into a temporary
   directory and chokes on the executable bits inside a `.venv`.

## Upstream issues worth filing

- `jl_options` passthrough for JuliaLibWrapping's `build_library` (constraint 5). Small
  change; would delete `build_threaded_library` here.
- `@api` keyword wrappers defeat the `--trim` verifier for callees containing closures
  (constraint 3).
- `juliac --trim` still runs `OpenBLAS_jll.__init__` for a library that uses no BLAS
  (constraint 2) — worth roughly 103 MB per bundle.
- `experiments/julia-issue-handle-signals-threads.md` in this repo is a complete,
  unfiled regression report for the `handle-signals=no` shutdown segfault, with crash
  tables across Julia 1.10–1.13 and a gdb backtrace.
- **libffi mismarshals a split-class struct argument that exhausts the integer
  registers** (constraint 4). Reproduced in twelve lines of C plus `ctypes`, with no
  Julia involved: a callee taking `(double, double, {int64,ptr}, double, int32, int32,
  double, double, {int32,double}, double, double)` receives the struct's `double` half
  in place of its first argument. Correct on Fedora's libffi 3.5.2, wrong on the libffi
  inside python-build-standalone 3.13.7. Removing any one of the integer arguments, or
  making the return small enough not to need a return pointer, makes it correct again —
  which places the fault in the register-exhaustion path of the classifier. Worth
  filing against libffi, and against python-build-standalone so its bundled copy moves.
- **`ARCHER` refraction throws `DomainError` near −2.7° elevation, and is nonsense
  either side of it.** `src/Refraction/archer.jl:55` divides by
  `0.955 + 20.267·cos(Z)`, which crosses zero at an elevation of about −2.70°, so the
  argument to `acosd` leaves `[-1, 1]`: −2.69°, −2.70° and −2.71° all throw, while
  −2.60° and −2.80° return corrections of +13.39° and −13.83° for a quantity that never
  exceeds about 0.6°. Reproduced in plain Julia, so it is not a bindings artefact. The
  package's own rule is to guard inverse trigonometry with `unit_clamp`, and this call
  is unguarded — but clamping alone would convert the throw into those same wrong
  values, so the real question is the elevation below which Archer's fit stops being
  usable. In the Python suite it surfaces as three of the 56 algorithm/refraction pairs
  failing whenever a sampled elevation happens to land near the pole.
- `Observer.horizon` is documented but never used (design note above).
- **`NOAA.delta_t` is ignored by its own implementation.** `src/Positioning/noaa.jl:38-42`
  computes `δt` from the field (or from `calculate_deltat`) and then never reads it — it
  is a dead local. Measured through these bindings, `NOAA(67.0)` and `NOAA(nothing)` agree
  to 0.0e+00 degrees at 1900, 2000 and 2050, where SPA moves by ~1e-4. The Julia test
  that covers this case (`test/positioning/test-noaa.jl:57`) compares at `atol = 1.0`
  *degree*, which is far too loose to notice.
