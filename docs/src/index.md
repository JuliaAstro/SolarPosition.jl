```@meta
CurrentModule = SolarPosition
```

# Home

## SolarPosition.jl

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

This package is based on the work done by readers in the field of solar photovoltaics
in the packages [solposx](https://github.com/assessingsolar/solposx) and
[pvlib-python](https://github.com/pvlib/pvlib-python). In particular the positioning and
refraction methods have been adapted from [solposx](https://github.com/assessingsolar/solposx), while
the SPA algorithm and the deltat calculation are ported from [pvlib-python](https://github.com/pvlib/pvlib-python). These packages also provide validation data necessary to ensure
correctness of the algorithm implementations.

## Example Usage

```@example
using SolarPosition, Dates

# define observer location (latitude, longitude, altitude in meters)
obs = Observer(52.35888, 4.88185, 100.0)  # Van Gogh Museum, Amsterdam

# a few hours of timestamps
times = collect(DateTime(2023, 6, 21, 10):Hour(1):DateTime(2023, 6, 21, 15));

# compute solar positions for all timestamps
positions = solar_position(obs, times)
```

## Solar positioning algorithms

Here we provide an overview of the solar positioning algorithms currently implemented
in SolarPosition.jl. Each algorithm is described with its reference paper, claimed
accuracy and implementation status.

| Algorithm                                             | Reference                                                                                       | Accuracy | Default Refraction | Status |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------- | ------------------ | ------ |
| [`PSA`](@ref SolarPosition.Positioning.PSA)           | [Blanco-Muriel et al.](https://www.sciencedirect.com/science/article/abs/pii/S0038092X00001560) | ±0.0083° | None               | ✅     |
| [`NOAA`](@ref SolarPosition.Positioning.NOAA)         | [Global Monitoring Laboratory](https://gml.noaa.gov/grad/solcalc/calcdetails.html)              | ±0.0167° | [`HUGHES`](@ref SolarPosition.Refraction.HUGHES) | ✅     |
| [`Walraven`](@ref SolarPosition.Positioning.Walraven) | [Walraven, 1978](https://doi.org/10.1016/0038-092X(78)90155-X)                                | ±0.0100° | None               | ✅     |
| [`USNO`](@ref SolarPosition.Positioning.USNO)         | [U.S. Naval Observatory](https://aa.usno.navy.mil/faq/sun_approx)                                | ±0.0500° | None               | ✅     |
| [`SPA`](@ref SolarPosition.Positioning.SPA)           | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                           | ±0.0003° | Built-in           | ✅     |

## Refraction correction algorithms

Atmospheric refraction correction algorithms available in SolarPosition.jl.

| Algorithm                                              | Reference                                                                                        | Atmospheric Parameters | Status |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------- | ------ |
| [`HUGHES`](@ref SolarPosition.Refraction.HUGHES)       | [Hughes, 1985](https://pvpmc.sandia.gov/app/uploads/sites/243/2022/10/Engineering-Astronomy.pdf) | Pressure, Temperature  | ✅     |
| [`ARCHER`](@ref SolarPosition.Refraction.ARCHER)       | Archer et al., 1980                                                                              | None                   | ✅     |
| [`BENNETT`](@ref SolarPosition.Refraction.BENNETT)     | [Bennett, 1982](https://doi.org/10.1017/S0373463300022037)                                       | Pressure, Temperature  | ✅     |
| [`MICHALSKY`](@ref SolarPosition.Refraction.MICHALSKY) | [Michalsky, 1988](https://doi.org/10.1016/0038-092X(88)90045-X)                                | None                   | ✅     |
| [`SG2`](@ref SolarPosition.Refraction.SG2)             | [Blanc & Wald, 2012](https://doi.org/10.1016/j.solener.2012.07.018)                              | Pressure, Temperature  | ✅     |
| [`SPARefraction`](@ref SolarPosition.Refraction.SPARefraction)             | [Reda & Andreas, 2004](https://doi.org/10.1016/j.solener.2003.12.003)                            | Pressure, Temperature  | ✅     |

## How to Cite

If you use SolarPosition.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/JuliaAstro/SolarPosition.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first that a look into our [contributing guide directly on GitHub](https://github.com/JuliaAstro/SolarPosition.jl/blob/main/docs/src/contributing.md) or the [contributing page on the website](https://juliaastro.org/SolarPosition/stable/contributing/)
