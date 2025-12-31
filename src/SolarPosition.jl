module SolarPosition

using DocStringExtensions: TYPEDSIGNATURES

include("Refraction/Refraction.jl")
include("Positioning/Positioning.jl")
include("Utilities/Utilities.jl")

using .Positioning:
    Observer, PSA, NOAA, Walraven, USNO, SPA, solar_position, solar_position!
using .Positioning:
    SolPos,
    ApparentSolPos,
    SPASolPos,
    SolarAlgorithm,
    AbstractApparentSolPos,
    AbstractSolPos
using .Refraction: RefractionAlgorithm, NoRefraction
using .Refraction: HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPARefraction

export solar_position, solar_position!, SolarAlgorithm, Observer
export PSA, NOAA, Walraven, USNO, SPA

# refraction algorithms
export RefractionAlgorithm, NoRefraction
export HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPARefraction

export SolPos, ApparentSolPos, SPASolPos
export AbstractSolPos, AbstractApparentSolPos

# utilities
using .Utilities:
    TransitSunriseSunset, transit_sunrise_sunset, next_sunrise, next_sunset, solar_noon

export TransitSunriseSunset, transit_sunrise_sunset, next_sunrise, next_sunset, solar_noon

# to make the makie extension work
export sunpathplot
export sunpathplot!
export sunpathpolarplot
export sunpathpolarplot!

function sunpathplot end
function sunpathplot! end
function sunpathpolarplot end
function sunpathpolarplot! end

# to make the ModelingToolkit extension work
export SolarPositionBlock

"""
    $(TYPEDSIGNATURES)

Return a [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl) component
that computes solar position as a function of time and can be integrated into symbolic
modeling workflows.

The [`SolarPositionBlock`](@ref) is a [`System`](https://docs.sciml.ai/ModelingToolkit/stable/API/System/#ModelingToolkit.System)
which exposes `azimuth`, `elevation`, and `zenith` as output variables computed from the
simulation time `t` (in seconds) relative to a reference time `t0`.

!!! note
    This function requires [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)
    to be loaded. The extension is automatically loaded when both [SolarPosition.jl](https://github.com/JuliaAstro/SolarPosition.jl)
    and [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl) are available.

# Parameters

- `observer::Observer`: location (latitude, longitude, altitude). See [`Observer`](@ref)
- `t0::DateTime`: Reference time (time when simulation time `t = 0`)
- `algorithm::SolarAlgorithm`: Solar positioning algorithm (default: [`PSA`](@ref))
- `refraction::RefractionAlgorithm`: Atmospheric refraction correction (default: [`NoRefraction`](@ref))

# Variables (Outputs)

- `azimuth(t)`: Solar azimuth angle in degrees (0° = North, 90° = East, 180° = South, 270° = West)
- `elevation(t)`: Solar elevation angle in degrees (angle above horizon, positive when sun is visible)
- `zenith(t)`: Solar zenith angle in degrees (angle from vertical, complementary to elevation: `zenith = 90° - elevation`)

# Time Convention

The simulation time `t` (accessed via `t_nounits`) is in **seconds** from the reference time `t0`. For example:
- `t = 0` corresponds to `t0`
- `t = 3600` corresponds to `t0 + 1 hour`
- `t = 86400` corresponds to `t0 + 24 hours`

# Example

```julia
using SolarPosition, ModelingToolkit
using ModelingToolkit: t_nounits as t, @named, mtkcompile
using Dates
using OrdinaryDiffEq: ODEProblem, solve

@named sun = SolarPositionBlock()
obs = Observer(51.5, -0.18, 15.0)
t0 = DateTime(2024, 6, 21, 12, 0, 0)

sys = mtkcompile(sun)
pmap = [
    sys.observer => obs,
    sys.t0 => t0,
    sys.algorithm => PSA(),
    sys.refraction => NoRefraction(),
]

prob = ODEProblem(sys, pmap, (0.0, 86400.0))
sol = solve(prob; saveat = 3600.0)
```
"""
function SolarPositionBlock end

end # module
