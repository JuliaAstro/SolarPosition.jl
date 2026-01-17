module SolarPosition

using DocStringExtensions: TYPEDSIGNATURES
using Reexport: @reexport

include("Refraction/Refraction.jl")
include("Positioning/Positioning.jl")
include("Utilities/Utilities.jl")

@reexport using .Positioning
@reexport using .Refraction
@reexport using .Utilities

# to make the makie extension work
export analemmas!

"""
    $(TYPEDSIGNATURES)

Plot analemmas (figure-8 patterns showing the sun's position at each hour throughout the
year) for a given observer location and year.

# Arguments
- `ax`: A Makie [`Axis`](https://docs.makie.org/dev/reference/blocks/axis) or [`PolarAxis`](https://docs.makie.org/dev/reference/blocks/polaraxis) to plot on
- `observer::Observer`: [`Observer`](@ref SolarPosition.Positioning.Observer) location (latitude, longitude, altitude)
- `year::Int`: Year for which to generate the analemmas
- `hour_labels::Bool=true`: Whether to add hour labels to the plot
- `colorscheme::Symbol=:twilight`: Color scheme for the analemma points (any [Makie colormap](https://docs.makie.org/dev/explanations/colors))

# Description
This function automatically generates solar position data for all 24 hours of each day
throughout the specified year and plots them as analemmas. The plot specializes to
either [`PolarAxis`](https://docs.makie.org/dev/reference/blocks/polaraxis) or regular
[`Axis`](https://docs.makie.org/dev/reference/blocks/axis) and adjusts the plot
accordingly:

- [`PolarAxis`](https://docs.makie.org/dev/reference/blocks/polaraxis): Plots in polar coordinates with azimuth as the angle and zenith as the radius
- [`Axis`](https://docs.makie.org/dev/reference/blocks/axis): Plots in cartesian coordinates with azimuth on the x-axis and elevation on the y-axis

The analemmas are colored by day of year. The default colorscheme is `:twilight`, but this
can be customized using the `colorscheme` keyword argument.

# Examples
```julia
using SolarPosition
using CairoMakie

# Define observer location (New Delhi, India)
obs = Observer(28.6, 77.2, 0.0)
year = 2019

# Plot in cartesian coordinates
fig = Figure()
ax = Axis(fig[1, 1], title="Sun Path - Cartesian")
analemmas!(ax, obs, year)
fig

# Plot in polar coordinates
fig2 = Figure()
ax2 = PolarAxis(fig2[1, 1], title="Sun Path - Polar")
analemmas!(ax2, obs, year, hour_labels=true)
fig2

# Use a custom colorscheme
fig3 = Figure()
ax3 = Axis(fig3[1, 1], title="Sun Path - Custom Colors")
analemmas!(ax3, obs, year, colorscheme=:viridis)
fig3
```

See also: [`Observer`](@ref), [`solar_position`](@ref)
"""
function analemmas! end

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
