```@meta
CurrentModule = SolarPosition
```

# Home

## SolarPosition.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliaastro.org/SolarPosition/stable/)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaastro.org/SolarPosition.jl/dev/)

[![Test workflow status](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaAstro/SolarPosition.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaAstro/SolarPosition.jl)
[![Lint workflow Status](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/JuliaAstro/SolarPosition.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![tested with JET.jl](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)

SolarPosition.jl provides a simple, unified interface to a collection of validated solar position
algorithms written in pure, performant julia.

Solar positioning algorithms are commonly used to calculate the solar zenith and
azimuth angles, which are essential for various applications where the sun is important, such as:

- Solar energy systems
- Building design
- Climate studies
- Astronomy

## Acknowledgement

This package is based on the work done by researchers in the field of solar photovoltaics
in the packages [solposx](https://github.com/assessingsolar/solposx) and
[pvlib-python](https://github.com/pvlib/pvlib-python). In particular the positioning and
refraction methods have been adapted from [solposx](https://github.com/assessingsolar/solposx),
while the SPA algorithm and the deltat calculation are ported from [pvlib-python](https://github.com/pvlib/pvlib-python). These packages also provide validation data necessary to ensure
correctness of the algorithm implementations.

## Example Usage

```@example srt
using SolarPosition, Dates, TimeZones

# define observer location (latitude, longitude, altitude in meters)
obs = Observer(52.35888, 4.88185, 100.0)  # Van Gogh Museum, Amsterdam
tz = TimeZone("Europe/Brussels")

# a few hours of timestamps
times = collect(DateTime(2023, 6, 21, 10):Hour(1):DateTime(2023, 6, 21, 15));

# compute solar positions for all timestamps
positions = solar_position(obs, times)
```

### Sunrise and Sunset Calculations

Calculate sunrise, sunset, and solar noon for a specific date with timezone:

```@example srt
result = transit_sunrise_sunset(obs, ZonedDateTime(2023, 6, 21, tz))
```

Find the next sunrise from a specific time in UTC:

```@example srt
next_sunrise(obs, DateTime(2023, 6, 21, 12, 30))
```

Find the next sunset in UTC:

```@example srt
next_sunset(obs, DateTime(2023, 6, 21, 12, 30))
```

## Solar positioning algorithms

Here we provide an overview of the solar positioning algorithms currently implemented
in SolarPosition.jl. Each algorithm is described with its reference paper, claimed
accuracy and implementation status.

| Algorithm                                               | Reference                                                                                       | Accuracy | Default Refraction                                     | Status |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------ | ------ |
| [`PSA`](@ref SolarPosition.Positioning.PSA)             | [Blanco-Muriel et al.](https://www.sciencedirect.com/science/article/abs/pii/S0038092X00001560) | ±0.0083° | None                                                   | ✅     |
| [`NOAA`](@ref SolarPosition.Positioning.NOAA)           | [Global Monitoring Laboratory](https://gml.noaa.gov/grad/solcalc/calcdetails.html)              | ±0.0167° | [`HUGHES`](@ref SolarPosition.Refraction.HUGHES)       | ✅     |
| [`Walraven`](@ref SolarPosition.Positioning.Walraven)   | [Walraven, 1978](https://doi.org/10.1016/0038-092X(78)90155-X)                                  | ±0.0100° | None                                                   | ✅     |
| [`USNO`](@ref SolarPosition.Positioning.USNO)           | [U.S. Naval Observatory](https://aa.usno.navy.mil/faq/sun_approx)                               | ±0.0500° | None                                                   | ✅     |
| [`SPA`](@ref SolarPosition.Positioning.SPA)             | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                           | ±0.0003° | Built-in                                               | ✅     |
| [`Iqbal`](@ref SolarPosition.Positioning.Iqbal)         | [Iqbal, 1983](https://doi.org/10.1016/B978-0-12-373750-2.X5001-0)                               | ±0.0100° | None                                                   | ✅     |
| [`Michalsky`](@ref SolarPosition.Positioning.Michalsky) | [Michalsky, 1988](https://doi.org/10.1016/0038-092X(88)90045-X)                                 | ±0.0100° | [`MICHALSKY`](@ref SolarPosition.Refraction.MICHALSKY) | ✅     |

Pass an algorithm as the third argument to pick one; the default is
[`PSA`](@ref SolarPosition.Positioning.PSA).

```@example srt
solar_position(obs, DateTime(2023, 6, 21, 12), Michalsky())
```

## Fast repeated evaluation

For dense time series, the [`Interpolated`](@ref SolarPosition.Positioning.Interpolated)
wrapper precomputes cubic B-splines of SPA's geocentric solar coordinates and reconstructs
positions analytically, roughly 10× faster per query at matching accuracy. One interpolant
serves every observer. It activates as a package extension when
[Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) is loaded:

```@example srt
using Interpolations

alg = Interpolated(SPA(); tspan = (DateTime(2023, 1, 1), DateTime(2024, 1, 1)))
solar_position(obs, times, alg)
```

See the [Interpolated Solar Position](@ref interpolated-position) guide for accuracy
figures and when the construction cost pays off.

## Automatic differentiation

All algorithms are generic over the number type, so solar positions are differentiable
with [ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl) out of the box, with no
extension package needed:

```@example srt
using ForwardDiff

ForwardDiff.gradient(
    x -> solar_position(Observer(x[1], x[2]), DateTime(2023, 6, 21, 12)).elevation,
    [52.35888, 4.88185],
)
```

The [Automatic Differentiation](@ref automatic-differentiation) guide shows gradients
through refraction models, panel orientation optimization, and a single axis tracker
example.

## Uncertainty propagation

The same genericity makes the algorithms work with
[Measurements.jl](https://github.com/JuliaPhysics/Measurements.jl), again with no
extension package needed:

```@example srt
using Measurements

pos = solar_position(Observer(52.35888 ± 0.01, 4.88185 ± 0.01), DateTime(2023, 6, 21, 12))
```

Correlations are tracked, so results that share an input stay consistent. Zenith is
derived from elevation, and their sum therefore carries no uncertainty at all:

```@example srt
pos.elevation + pos.zenith
```

Refraction parameters take uncertainties in the same way, for example
`HUGHES(101325.0 ± 500.0, 12.0 ± 2.0)`.

!!! note
    [`transit_sunrise_sunset`](@ref) and the `next_`/`previous_` helpers return a
    `DateTime`, which cannot carry an uncertainty. They compute from the nominal
    coordinates and drop it.

## Numeric precision

The computation runs at the precision of the
[`Observer{T}`](@ref SolarPosition.Positioning.Observer) element type. `Float32`,
`Float64`, `Float128`, and `BigFloat` are supported. A refraction model's own parameter
type promotes with the observer's, so build the model at the same precision to keep a
narrow result narrow. See the
[Numeric Precision](@ref numeric-precision) guide for measured accuracy and runtime of
every algorithm at each precision, including multithreaded benchmarks.

## Refraction correction algorithms

Atmospheric refraction correction algorithms available in SolarPosition.jl.

| Algorithm                                                          | Reference                                                                                        | Atmospheric Parameters | Status |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------- | ------ |
| [`HUGHES`](@ref SolarPosition.Refraction.HUGHES)                   | [Hughes, 1985](https://pvpmc.sandia.gov/app/uploads/sites/243/2022/10/Engineering-Astronomy.pdf) | Pressure, Temperature  | ✅     |
| [`ARCHER`](@ref SolarPosition.Refraction.ARCHER)                   | Archer et al., 1980                                                                              | None                   | ✅     |
| [`BENNETT`](@ref SolarPosition.Refraction.BENNETT)                 | [Bennett, 1982](https://doi.org/10.1017/S0373463300022037)                                       | Pressure, Temperature  | ✅     |
| [`MICHALSKY`](@ref SolarPosition.Refraction.MICHALSKY)             | [Michalsky, 1988](https://doi.org/10.1016/0038-092X(88)90045-X)                                  | None                   | ✅     |
| [`SG2`](@ref SolarPosition.Refraction.SG2)                         | [Blanc & Wald, 2012](https://doi.org/10.1016/j.solener.2012.07.018)                              | Pressure, Temperature  | ✅     |
| [`SPARefraction`](@ref SolarPosition.Refraction.SPARefraction)     | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                            | Pressure, Temperature  | ✅     |

## Extensions

SolarPosition.jl provides optional extensions that are automatically loaded when you
import the corresponding packages:

| Extension       | Trigger Package                                                       | Features                                          |
| --------------- | --------------------------------------------------------------------- | ------------------------------------------------- |
| Makie           | [`Makie.jl`](https://github.com/MakieOrg/Makie.jl)                    | Plotting recipes for solar position visualization |
| OhMyThreads     | [`OhMyThreads.jl`](https://github.com/JuliaFolds2/OhMyThreads.jl)     | Parallel computation of solar positions           |
| ModelingToolkit | [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)   | Symbolic solar position models for simulations    |
| Interpolations  | [`Interpolations.jl`](https://github.com/JuliaMath/Interpolations.jl) | Fast `Interpolated` algorithm construction        |
| TimeZones       | [`TimeZones.jl`](https://github.com/JuliaTime/TimeZones.jl)           | `ZonedDateTime` input and zoned sunrise/sunset    |

Loading `TimeZones.jl` is what enables `ZonedDateTime` arguments. In practice this needs
no thought, since a `ZonedDateTime` cannot be constructed without it, and it means users
who only ever pass a `DateTime` do not pay for TZJData and its download stack.

!!! note
    For more details on the extensions, see:
    - [ModelingToolkit Extension](guides/modelingtoolkit.md)
    - [Makie Extension](guides/plotting.md)
    - [OhMyThreads Extension](guides/parallel.md)
    - [Interpolated Solar Position](@ref interpolated-position)

## How to Cite

If you use SolarPosition.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/JuliaAstro/SolarPosition.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first that a look into our [contributing guide directly on GitHub](https://github.com/JuliaAstro/SolarPosition.jl/blob/main/docs/src/contributing.md) or the [contributing page on the website](https://juliaastro.org/SolarPosition/stable/contributing/)
