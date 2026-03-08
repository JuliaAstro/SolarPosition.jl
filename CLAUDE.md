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
ext/                     # Weak dependency extensions
  SolarPositionMakieExt.jl          # Sun path plotting
  SolarPositionOhMyThreadsExt.jl    # Parallel solar position computation
  SolarPositionModelingToolkitExt.jl # Symbolic models for MTK
```

**Core API pattern:** `solar_position(algorithm, observer, datetime)` returns a `SolPos` or `ApparentSolPos` (if refraction is included). The `Observer` struct holds location (lat/lon/altitude) and optional atmospheric parameters (pressure, temperature).

**Test discovery:** Test files matching `test-*.jl` under `test/` are automatically discovered and wrapped in `@testset`. Reference values live in `expected-values.jl` files alongside algorithm tests.

## Code Style

- Formatter: **Runic.jl** (enforced via pre-commit). Run before committing.
- Imports: All used symbols must be explicitly imported (checked by ExplicitImports.jl).
- Package quality is checked with **Aqua.jl** and type inference with **JET.jl** (Julia 1.12 only).
