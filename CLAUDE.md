# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Run tests:**

```bash
julia --project -e "using Pkg; Pkg.test()"
```

**Run a single test file:**

```bash
julia --project test/positioning/test-psa.jl
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

**Core API pattern:** `solar_position(obs, dt, alg=PSA(), refraction=DefaultRefraction())` — observer first, then datetime, then algorithm/refraction (both default-able). `dt` may be a single `DateTime` or an `AbstractVector{DateTime}` (returns a `StructArray`). A table interface (`solar_position(table, obs; dt_col=:datetime)`) and an in-place `solar_position!(pos, obs, dts, alg, refraction)` also exist.

- **Algorithms and refraction models are singleton dispatch types** — e.g. `PSA()`, `NOAA()`, `SPA()`, `HUGHES(pressure, temperature)`, `NoRefraction()`. New algorithms are added by defining a struct `<: SolarAlgorithm` (or `<: RefractionAlgorithm`) and a `solar_position` method on it.
- **Return type depends on refraction:** `result_type(...)` yields `SolPos{T}` for `NoRefraction`, else `ApparentSolPos{T}` (adds `apparent_elevation`/`apparent_zenith`).
- **Angle convention:** all degrees. Azimuth 0°=North, +clockwise, [-180°, 180°]; elevation [-90°, 90°]; zenith = 90° − elevation.
- `Observer(latitude, longitude; altitude=0.0, horizon=0.0)` precomputes lat/lon trig (`sin_lat`, `cos_lat`) for performance; it also holds optional pressure/temperature for refraction.

**Test discovery:** Test files matching `test-*.jl` under `test/` are automatically discovered and wrapped in `@testset`. Reference values live in `expected-values.jl` files alongside algorithm tests.

## Code Style

- Formatter: **Runic.jl** (enforced via pre-commit). Run before committing.
- Imports: All used symbols must be explicitly imported (checked by ExplicitImports.jl).
- Package quality is checked with **Aqua.jl** and type inference with **JET.jl** (Julia 1.12 only).
