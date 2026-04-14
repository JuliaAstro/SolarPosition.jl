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
  SolarPosition.jl       # Main module, re-exports all submodules via @reexport
  Positioning/           # Solar position algorithms
    Positioning.jl       # Observer, SolPos/ApparentSolPos types, solar_position() dispatch
    psa.jl               # PSA algorithm (default, ±0.0083°)
    noaa.jl, spa.jl,     # Other algorithms (NOAA, SPA, Walraven, USNO)
    walraven.jl, usno.jl
    deltat.jl            # Delta T / leap seconds
  Refraction/            # Atmospheric refraction correction models
    Refraction.jl        # RefractionAlgorithm abstract type + refraction() interface
    hughes.jl, archer.jl, bennett.jl, michalsky.jl, sg2.jl, spa.jl
  Utilities/             # Sunrise/sunset/transit calculations
    srt.jl               # transit_sunrise_sunset(), next_sunrise/sunset/solar_noon, etc.
    spa.jl               # SPA-based utility helpers
ext/                     # Weak dependency extensions (loaded via [weakdeps] in Project.toml)
  SolarPositionMakieExt.jl          # analemmas!() sun path plotting
  SolarPositionOhMyThreadsExt.jl    # Parallel solar_position via OhMyThreads
  SolarPositionModelingToolkitExt.jl # SolarPositionBlock for MTK symbolic models
```

**Core API pattern:** `solar_position(observer, datetime, algorithm, refraction)` returns a `SolPos` or `ApparentSolPos` (if refraction model is provided). Also accepts vectors of datetimes (returns `StructVector`) and Tables.jl-compatible tables (adds columns in-place).

**Adding a new algorithm:** Subtype `SolarAlgorithm`, implement `_solar_position(obs, dt, alg::YourAlg)::SolPos`, and the dispatch in `Positioning.jl` handles refraction wrapping automatically. Same pattern for refraction: subtype `RefractionAlgorithm` and implement `_refraction(model, elevation)`.

**Test discovery:** Test files matching `test-*.jl` under `test/` are automatically discovered and wrapped in `@testset`. Don't add tests to `runtests.jl` directly. Reference values live in `expected-values.jl` files alongside algorithm tests.

## Code Style

- Formatter: **Runic.jl** (enforced via pre-commit). Run `pre-commit run runic --all-files` before committing.
- Imports: All used symbols must be explicitly imported (checked by ExplicitImports.jl pre-commit hook).
- Spelling: **typos** is enforced via pre-commit. If a false positive occurs, add it to `_typos.toml`.
- Package quality is checked with **Aqua.jl** and type inference with **JET.jl** (Julia 1.12 only).
- Pre-commit `no-commit-to-branch` blocks direct commits to `main`; work on feature branches.
