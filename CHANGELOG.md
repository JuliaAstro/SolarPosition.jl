# Changelog

Notable changes to SolarPosition.jl are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/).

Releases before v0.5.0 predate this file. See the
[GitHub releases](https://github.com/JuliaAstro/SolarPosition.jl/releases) for those.

## unreleased

## v0.5.0 - 2026-07-31

### Added

- `Michalsky` positioning algorithm, covering both the original and the standard Julian date
  and with the Spencer azimuth correction available as an option
  [#120](https://github.com/JuliaAstro/SolarPosition.jl/pull/120)
- `Iqbal` positioning algorithm
  [#118](https://github.com/JuliaAstro/SolarPosition.jl/pull/118)
- `Interpolated`, which precomputes cubic B-splines of SPA's geocentric solar coordinates and
  reconstructs positions analytically, roughly 10x faster per query at matching accuracy. One
  interpolant serves every observer. Added alongside `solar_rate`
  [#117](https://github.com/JuliaAstro/SolarPosition.jl/pull/117)
- Type-generic precision. Every algorithm computes at the `Observer{T}` element type, with
  `Float32`, `Float64`, `Float128` and `BigFloat` supported, and a converting
  `Observer{T}(lat, lon, ...)` constructor
  [#93](https://github.com/JuliaAstro/SolarPosition.jl/pull/93),
  [#94](https://github.com/JuliaAstro/SolarPosition.jl/pull/94)
- Solar positions are differentiable with ForwardDiff.jl, with no extension package needed,
  including with respect to a refraction model's pressure and temperature
  [#116](https://github.com/JuliaAstro/SolarPosition.jl/pull/116),
  [#119](https://github.com/JuliaAstro/SolarPosition.jl/pull/119)
- Uncertainty propagation with Measurements.jl works throughout, and correlations are
  preserved, so quantities sharing an input stay consistent
  [#122](https://github.com/JuliaAstro/SolarPosition.jl/pull/122)
- `transit_sunrise_sunset_seconds`, returning the events as seconds since midnight UTC at the
  observer's element type. `transit_sunrise_sunset` rounds to a whole second to build a
  `DateTime`, which discards the sub-second part along with any uncertainty or derivative the
  element type carries. This variant keeps all three
  [#122](https://github.com/JuliaAstro/SolarPosition.jl/pull/122)

### Changed

- TimeZones.jl moved from a dependency to a package extension. `ZonedDateTime` input and
  zoned sunrise and sunset still work, but only once TimeZones is loaded, which it must be in
  order to construct a `ZonedDateTime` in the first place. Users who only pass a `DateTime`
  no longer pay for TZJData and its download stack
  [#121](https://github.com/JuliaAstro/SolarPosition.jl/pull/121)
- Refraction model parameters promote against the observer's element type, so a model built
  at a wider precision widens the result
  [#119](https://github.com/JuliaAstro/SolarPosition.jl/pull/119)

### Fixed

- Inverse trigonometric arguments are clamped to their valid domain, so low-precision element
  types no longer throw a `DomainError` on rounding
  [#94](https://github.com/JuliaAstro/SolarPosition.jl/pull/94)
- Algorithms take their time base through magnitude-safe day and century counts since J2000
  rather than the full Julian Date, which made `Float32` unusable
  [#93](https://github.com/JuliaAstro/SolarPosition.jl/pull/93),
  [#94](https://github.com/JuliaAstro/SolarPosition.jl/pull/94)
- The `Observer` inner constructor derives its zero defaults from an argument instead of the
  element type, lifting the requirement that `zero` be defined on the bare type
  [#122](https://github.com/JuliaAstro/SolarPosition.jl/pull/122)
- Corrected the `ARCHER` bibliography entry, which pointed at an unrelated 1980 conference
  paper. The model comes from Archer's comment on Walraven's "Calculating the position of the
  sun", now cited with its DOI
  [#123](https://github.com/JuliaAstro/SolarPosition.jl/pull/123)
