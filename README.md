# SolarPosition.jl

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

```julia
julia> using SolarPosition, Dates, TimeZones

# define observer location (latitude, longitude, altitude in meters)
julia> obs = Observer(52.35888, 4.88185, 100.0)  # Van Gogh Museum, Amsterdam
Observer(latitude=52.35888°, longitude=4.88185°, altitude=100.0m)

julia> tz = TimeZone("Europe/Brussels")
Europe/Brussels (UTC+1/UTC+2)

# a few hours of timestamps
julia> times = collect(DateTime(2023, 6, 21, 10):Hour(1):DateTime(2023, 6, 21, 15));

# compute solar positions for all timestamps
julia> positions = solar_position(obs, times)
6-element StructArray(::Vector{Float64}, ::Vector{Float64}, ::Vector{Float64}) with eltype SolPos{Float64}:
 SolPos(azimuth=136.1908215897601°, elevation=55.13208390809107°, zenith=34.86791609190893°)
 SolPos(azimuth=160.3753655770986°, elevation=59.974081481305134°, zenith=30.025918518694862°)
 SolPos(azimuth=188.3992597996431°, elevation=60.87918930278924°, zenith=29.120810697210757°)
 SolPos(azimuth=214.62987222053295°, elevation=57.493462259959394°, zenith=32.5065377400406°)
 SolPos(azimuth=235.5258846451899°, elevation=50.992647293443966°, zenith=39.007352706556034°)
 SolPos(azimuth=251.77304757136397°, elevation=42.790197455865076°, zenith=47.209802544134924°)
```

### Sunrise and Sunset Calculations

Calculate sunrise, sunset, and solar noon for a specific date with timezone:

```julia
julia> result = transit_sunrise_sunset(obs, ZonedDateTime(2023, 6, 21, tz))
TransitSunriseSunset{ZonedDateTime}(
    transit=2023-06-21T13:42:15+02:00,
    sunrise=2023-06-21T05:18:05+02:00,
    sunset=2023-06-21T22:06:24+02:00
)
```

Find the next sunrise from a specific time in UTC:

```julia
julia> next_sunrise(obs, DateTime(2023, 6, 21, 12, 30))
2023-06-22T03:18:19
```

Find the next sunset in UTC:

```julia
julia> next_sunset(obs, DateTime(2023, 6, 21, 12, 30))
2023-06-21T20:06:24
```

## Solar positioning algorithms

Here we provide an overview of the solar positioning algorithms currently implemented
in SolarPosition.jl. Each algorithm is described with its reference paper, claimed
accuracy and implementation status.

| Algorithm | Reference                                                                                       | Accuracy | Default Refraction | Status |
| --------- | ----------------------------------------------------------------------------------------------- | -------- | ------------------ | ------ |
| PSA       | [Blanco-Muriel et al.](https://www.sciencedirect.com/science/article/abs/pii/S0038092X00001560) | ±0.0083° | None               | ✅     |
| NOAA      | [Global Monitoring Laboratory](https://gml.noaa.gov/grad/solcalc/calcdetails.html)              | ±0.0167° | HUGHES             | ✅     |
| Walraven  | [Walraven, 1978](<https://doi.org/10.1016/0038-092X(78)90155-X>)                                | ±0.0100° | None               | ✅     |
| USNO      | [U.S. Naval Observatory](https://aa.usno.navy.mil/faq/sun_approx)                               | ±0.0500° | None               | ✅     |
| SPA       | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                           | ±0.0003° | Built-in           | ✅     |

## Refraction correction algorithms

Atmospheric refraction correction algorithms available in SolarPosition.jl.

| Algorithm | Reference                                                                                        | Atmospheric Parameters | Status |
| --------- | ------------------------------------------------------------------------------------------------ | ---------------------- | ------ |
| HUGHES    | [Hughes, 1985](https://pvpmc.sandia.gov/app/uploads/sites/243/2022/10/Engineering-Astronomy.pdf) | Pressure, Temperature  | ✅     |
| ARCHER    | Archer et al., 1980                                                                              | None                   | ✅     |
| BENNETT   | [Bennett, 1982](https://doi.org/10.1017/S0373463300022037)                                       | Pressure, Temperature  | ✅     |
| MICHALSKY | [Michalsky, 1988](<https://doi.org/10.1016/0038-092X(88)90045-X>)                                | None                   | ✅     |
| SG2       | [Blanc & Wald, 2012](https://doi.org/10.1016/j.solener.2012.07.018)                              | Pressure, Temperature  | ✅     |
| SPA       | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                            | Pressure, Temperature  | ✅     |

## Extensions

SolarPosition.jl provides optional extensions that are automatically loaded when you
import the corresponding packages:

| Extension       | Trigger Package                                                       | Features                                          |
| --------------- | --------------------------------------------------------------------- | ------------------------------------------------- |
| Makie           | [`Makie.jl`](https://github.com/MakieOrg/Makie.jl)                    | Plotting recipes for solar position visualization |
| OhMyThreads     | [`OhMyThreads.jl`](https://github.com/JuliaFolds2/OhMyThreads.jl)     | Parallel computation of solar positions           |
| ModelingToolkit | [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)   | Symbolic solar position models for simulations    |

## How to Cite

If you use SolarPosition.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/JuliaAstro/SolarPosition.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first that a look into our [contributing guide directly on GitHub](docs/src/contributing.md) or the [contributing page on the website](https://juliaastro.org/SolarPosition/stable/contributing/)
