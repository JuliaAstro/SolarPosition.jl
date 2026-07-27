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

Note: the pre-commit `no-commit-to-branch` hook blocks commits to `main` — always work on a branch. `test/`, `docs/`, `benchmark/`, and `examples/` are workspace subprojects (root `Project.toml` `[workspace]`) with their own `Project.toml` that depends on the package via `[sources]` path — no `Pkg.develop` needed.

## Architecture

The package provides a unified interface to multiple solar position algorithms. Structure:

```text
src/
  SolarPosition.jl       # Main module, re-exports all submodules
  Positioning/           # Solar position algorithms
    Positioning.jl       # Observer struct, SolPos/ApparentSolPos types, solar_position() API
    psa.jl               # PSA algorithm (default, ±0.0083°)
    noaa.jl, spa.jl,     # Other algorithms (NOAA, SPA, Walraven, USNO)
    walraven.jl, usno.jl
    deltat.jl            # Delta T / leap seconds
    timebase.jl          # Magnitude-safe day/century counts since J2000, at precision T
    utils.jl             # unit_clamp for inverse trig, EMR/AU constants
  Refraction/            # Atmospheric refraction correction models
    Refraction.jl        # Abstract base + interface
    hughes.jl, bennett.jl, sg2.jl, spa.jl, ...
  Utilities/             # Sunrise/sunset/transit calculations
    srt.jl, spa.jl
ext/                     # Weak dependency extensions (auto-load on `using` of the trigger pkg)
  SolarPositionMakieExt.jl          # Makie → analemmas!() sun-path plotting (PolarAxis/Axis)
  SolarPositionOhMyThreadsExt.jl    # OhMyThreads → solar_position[!] with an extra ::Scheduler arg
  SolarPositionModelingToolkitExt.jl # ModelingToolkit/Symbolics → SolarPositionBlock() (t in SECONDS)
```

Minimum Julia: **1.10** (LTS). Extensions only activate once their trigger package is loaded; don't `import` them directly.

**Core API pattern:** `solar_position(obs, dt, alg=PSA(), refraction=DefaultRefraction())` — observer first, then datetime, then algorithm/refraction (both default-able). `dt` may be a single `DateTime`/`ZonedDateTime` or an `AbstractVector` of them (returns a `StructArray`). A table interface (`solar_position(table, obs; dt_col=:datetime)`, mutates the table) and an in-place `solar_position!(pos, obs, dts, alg, refraction)` also exist. The `Utilities` module exports `transit_sunrise_sunset` and `next_`/`previous_` variants of `sunrise`/`sunset`/`solar_noon`.

- **Algorithms and refraction models are singleton dispatch types** — e.g. `PSA()`, `NOAA()`, `SPA()`, `HUGHES(pressure, temperature)`, `NoRefraction()`. New algorithms are added by defining a struct `<: SolarAlgorithm` (or `<: RefractionAlgorithm`) and a `solar_position` method on it.
- **Return type depends on refraction:** `result_type(...)` yields `SolPos{T}` for `NoRefraction`, else `ApparentSolPos{T}` (adds `apparent_elevation`/`apparent_zenith`).
- **Angle convention:** all degrees. Azimuth 0°=North, +clockwise, normalized to [0°, 360°) by every algorithm (some docstrings in `Positioning.jl` still say [-180°, 180°] — the code is authoritative); elevation [-90°, 90°]; zenith = 90° − elevation. Refraction parameters (pressure, temperature) live on the refraction algorithm structs (e.g. `HUGHES(pressure, temperature)`), not on `Observer`.
- `Observer(latitude, longitude; altitude=0.0, horizon=0.0)` precomputes lat/lon trig (`sin_lat`, `cos_lat`) for performance. `horizon` (degrees, or a `deg=>arcmin` pair like `0=>34`) is the horizon depression used for sunrise/sunset. `Observer{T}(lat, lon, ...)` converts any `Real` arguments to precision `T`.
- **Type-generic precision:** every algorithm computes at the `Observer{T}` element type. `Float32`, `Float64`, `Float128`, and `BigFloat` are supported; `Float16` overflows to `NaN`. Inside algorithms always take time via `julian_day_j2000(T, dt)`, `julian_century(T, dt)`, or `fractional_hour(T, dt)` from `timebase.jl`, never `datetime2julian`, so the ~2.45e6 Julian Date magnitude is not materialized at `T`. Guard `asin`/`acos` arguments with `unit_clamp`. ΔT is always evaluated in `Float64`. See `docs/src/guides/precision.md` for measured accuracy and speed.

**Test discovery:** Test files matching `test-*.jl` under `test/` are automatically discovered and wrapped in `@testset`. Reference values live in `expected-values.jl` files alongside algorithm tests.

**Reference values:** the tables in `test/positioning/expected-values.jl` are exact Float64 outputs of the Python package solposx, generated at timestamps whose offset from noon UTC is a multiple of 84.375 s so the full Julian Date is exactly representable in Float64. This makes the references artifact-free and lets tests compare at `atol = 1e-10` (`1e-8` for SPA). When regenerating: keep timestamps on that grid, use whole seconds only because solposx `usno()` mishandles sub-second times, and paste full round-trip digits.

## Code Style

- Formatter: **Runic.jl** (enforced via pre-commit). Run before committing.
- Imports: All used symbols must be explicitly imported (checked by ExplicitImports.jl).
- Package quality is checked with **Aqua.jl** and type inference with **JET.jl** (Julia 1.12 only) — both run as part of `Pkg.test()` via `test/linting.jl`.
- Docstrings use **DocStringExtensions** macros: `$(TYPEDEF)` + `$(TYPEDFIELDS)` for structs, `$(TYPEDSIGNATURES)` for functions.
