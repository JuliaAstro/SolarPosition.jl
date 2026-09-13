# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Run tests:**

```bash
julia --project -e "using Pkg; Pkg.test()"
```

**Fast test iteration:** test files are not standalone, they rely on imports and the
`expected-values.jl` helpers loaded by `runtests.jl`. For a fast loop, activate the
`test/` workspace project in a long-lived REPL once, then include the files you are
working on. Iterations take seconds. Keep the full `Pkg.test()` as the pre-push gate
and let CI run the full matrix.

```julia
using Pkg; Pkg.activate("test")
using Test, Dates, SolarPosition
include("test/positioning/expected-values.jl")
@testset "targeted" begin
    include("test/positioning/test-psa.jl")
end
```

**Format code (Runic.jl):**

```bash
pre-commit run runic --all-files
```

**Run all linting/formatting checks:**

```bash
pre-commit run -a
```

**Build docs:**

```bash
julia --project=docs docs/make.jl
```

**Run benchmarks** (AirspeedVelocity.jl: `benchpkg SolarPosition --rev=main,dirty`, or include `benchmark/benchmarks.jl` and `run(SUITE)` with BenchmarkTools).

Note: the pre-commit `no-commit-to-branch` hook blocks commits to `main` — always work on a branch. `test/`, `docs/`, `benchmark/`, and `examples/` are workspace subprojects (root `Project.toml` `[workspace]`) with their own `Project.toml` that depends on the package via `[sources]` path — no `Pkg.develop` needed. CI (`enforce-changelog.yml`) requires every PR to touch `CHANGELOG.md` unless it carries the `skip-changelog` label.

## Architecture

The package provides a unified interface to multiple solar position algorithms. Structure:

```text
src/
  SolarPosition.jl       # Main module, re-exports all submodules; holds the docstrings
                         # and `function ... end` stubs that extensions fill in
                         # (analemmas!, SolarPositionBlock)
  Positioning/           # Solar position algorithms
    Positioning.jl       # Observer struct, SolPos/ApparentSolPos types, solar_position() API
    psa.jl               # PSA algorithm (default, ±0.0083°)
    noaa.jl, spa.jl,     # Other algorithms (NOAA, SPA + spa_coefficients.jl tables,
    walraven.jl,         # Walraven, USNO, Iqbal, Michalsky)
    usno.jl, iqbal.jl,
    michalsky.jl
    interpolated.jl      # Interpolated{SPA} wrapper + solar_rate (needs Interpolations ext
                         # to construct; the struct and query path live here)
    deltat.jl            # Delta T / leap seconds
    timebase.jl          # Magnitude-safe day/century counts since J2000, at precision T
    utils.jl             # unit_clamp for inverse trig, EMR/AU constants
  Refraction/            # Atmospheric refraction correction models
    Refraction.jl        # Abstract base + interface
    hughes.jl, bennett.jl, sg2.jl, spa.jl, archer.jl, michalsky.jl
  Utilities/             # Sunrise/sunset/transit calculations
    srt.jl, spa.jl
ext/                     # Weak dependency extensions (auto-load on `using` of the trigger pkg)
  SolarPositionTimeZonesExt.jl      # TimeZones → ZonedDateTime input, zoned sunrise/sunset
  SolarPositionInterpolationsExt.jl # Interpolations → Interpolated(SPA(); tspan, step) ctor
  SolarPositionMakieExt.jl          # Makie → analemmas!() sun-path plotting (PolarAxis/Axis)
  SolarPositionOhMyThreadsExt.jl    # OhMyThreads → solar_position[!] with an extra ::Scheduler arg
  SolarPositionModelingToolkitExt.jl # ModelingToolkit/Symbolics → SolarPositionBlock() (t in SECONDS)
dyad/solarpositionblock.dyad        # Dyad component declaration mirroring SolarPositionBlock
lib/                     # Python bindings: juliac --trim + JuliaLibWrapping (see lib/README.md)
  src/libsolarposition.jl # the @api surface; enums for algorithm/refraction selection
  build.jl               # default and --threads=N builds
  python/_extras.py      # hand-maintained façade additions
  test/                  # pytest suite + Julia fixture generator
```

Minimum Julia: **1.10** (LTS); CI runs `lts` and `1` on Linux/macOS/Windows. Extensions only activate once their trigger package is loaded; don't `import` them directly. `TimeZones` is a weak dependency: `ZonedDateTime` methods only exist once TimeZones is loaded, which is unavoidable anyway since constructing a `ZonedDateTime` requires it.

**Core API pattern:** `solar_position(obs, dt, alg=PSA(), refraction=DefaultRefraction())` — observer first, then datetime, then algorithm/refraction (both default-able). `dt` may be a single `DateTime`/`ZonedDateTime` or an `AbstractVector` of them (returns a `StructArray`). Also:

- `solar_position!(pos, obs, dts, alg, refraction)` fills a preallocated `StructVector`.
- Table interface: `solar_position!(table, obs, alg, refraction; dt_col=:datetime)` **mutates** the table by adding `azimuth`/`elevation`/`zenith` (plus the apparent columns when refraction applies); `solar_position(table, obs, ...)` copies first. Note the observer is the *second* positional argument and `dt_col` is a keyword.
- The `Utilities` module exports `transit_sunrise_sunset`, `transit_sunrise_sunset_seconds` (seconds since UTC midnight at the observer's element type — use this when a `DateTime`'s whole-second rounding would discard an uncertainty or derivative), and `next_`/`previous_` variants of `sunrise`/`sunset`/`solar_noon`.

Key invariants:

- **Algorithms and refraction models are dispatch types, most carrying options** — `Walraven()`, `Iqbal()`, `ARCHER()`, `MICHALSKY()`, `NoRefraction()` and `DefaultRefraction()` are singletons; the rest have fields: `PSA(coeffs)`, `NOAA(delta_t)`, `USNO(delta_t, gmst_option)`, `SPA(delta_t, pressure, temperature, atmos_refract)`, `Michalsky(spencer_correction, julian_date::Symbol)`, and the parametric `HUGHES/BENNETT/SG2{T}(pressure, temperature)` and `SPARefraction{T}(pressure, temperature, atmos_refract)`. New algorithms are added by defining a struct `<: SolarAlgorithm` (or `<: RefractionAlgorithm`) plus a `_solar_position` method and a `result_type` method on it. See `docs/src/guides/new-algorithm.md`.
- **Return type is resolved at compile time by `result_type(AlgType, RefrType, T)`:** `SolPos{T}` for `NoRefraction`, `ApparentSolPos{T}` (adds `apparent_elevation`/`apparent_zenith`) for an explicit refraction model. `DefaultRefraction()` is resolved *per algorithm*: PSA, Walraven, Iqbal and USNO apply none and return `SolPos`; NOAA (HUGHES), Michalsky (MICHALSKY) and SPA (SPARefraction) return `ApparentSolPos`. Adding an algorithm means adding its `DefaultRefraction` `result_type` too, or the batch path allocates the wrong eltype.
- **Angle convention:** all degrees. Azimuth 0°=North, +clockwise, normalized to [0°, 360°) by every algorithm (the `SolPos`/`ApparentSolPos` field docstrings in `Positioning.jl` still say [-180°, 180°] — the code is authoritative); elevation [-90°, 90°]; zenith = 90° − elevation. Refraction parameters (pressure, temperature) live on the refraction algorithm structs (e.g. `HUGHES(pressure, temperature)`), not on `Observer`, and promote against the observer's element type.
- `Observer(lat, lon; altitude=0, horizon=0)` — also positional `Observer(lat, lon, alt[, horizon])` — precomputes lat/lon trig (`sin_lat`, `cos_lat`) for performance. The element type promotes over the arguments, so integer and mixed inputs work; `Observer{T}(lat, lon, ...)` converts any `Real` arguments to precision `T`. `horizon` (degrees, or a `deg=>arcmin` pair like `0=>34`) is *documented* as the horizon depression for sunrise/sunset but is currently **inert** — it is stored, converted and shown, and never read by any computation in `src/`; `src/Utilities/spa.jl:89` hardcodes `h0 = T(-0.8333)` instead.
- **Type-generic precision:** `Observer{T<:Real}` — deliberately `Real`, not `AbstractFloat`, so `ForwardDiff.Dual` and `Measurements.Measurement` flow through unchanged (no extension needed; see `test/positioning/test-autodiff.jl`, `test-measurements.jl`). Every algorithm computes at the observer's element type: `Float32`, `Float64`, `Float128` (Quadmath, a docs/benchmark-only dep) and `BigFloat` are supported; `Float16` overflows to `NaN`. Inside algorithms always take time via `julian_day_j2000(T, dt)`, `julian_century(T, dt)`, or `fractional_hour(T, dt)` from `timebase.jl`, never `datetime2julian`, so the ~2.45e6 Julian Date magnitude is not materialized at `T`. Guard `asin`/`acos` arguments with `unit_clamp`. ΔT is always evaluated in `Float64`. See `docs/src/guides/precision.md` for measured accuracy and speed.

**Test discovery:** test files matching `test-*.jl` under `test/` are discovered recursively by `runtests.jl` and wrapped in a `@testset` named after the filename — don't edit `runtests.jl` to add tests. `test/positioning/expected-values.jl` is loaded once by `runtests.jl`; `test/utilities/expected-values.jl` is included by `test-srt.jl` itself. `test/linting.jl` runs Aqua.jl always and JET.jl only on Julia 1.12.

**Reference values:** the tables in `test/positioning/expected-values.jl` are exact Float64 outputs of the Python package solposx, generated at timestamps whose offset from noon UTC is a multiple of 84.375 s so the full Julian Date is exactly representable in Float64. This makes the references artifact-free and lets tests compare at `atol = 1e-10` (`1e-8` for SPA). When regenerating: keep timestamps on that grid, use whole seconds only because solposx `usno()` mishandles sub-second times, and paste full round-trip digits.

## Code Style

- Formatter: **Runic.jl** (enforced via pre-commit). Run before committing. Runic has no configuration.
- Imports: All used symbols must be explicitly imported (checked by ExplicitImports.jl).
- Package quality is checked with **Aqua.jl** and type inference with **JET.jl** (Julia 1.12 only) — both run as part of `Pkg.test()` via `test/linting.jl`.
- Docstrings use **DocStringExtensions** macros: `$(TYPEDEF)` + `$(TYPEDFIELDS)` for structs, `$(TYPEDSIGNATURES)` for functions. Doctests run against the setup in `docs/make.jl`, which predefines `obs` and `dt`.
- Public API changes should update the matching page under `docs/src/` and add a `CHANGELOG.md` entry under `## unreleased`.
