# Building models with ModelingToolkit.jl

SolarPosition.jl provides a [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)
extension that enables integration of solar position calculations into symbolic modeling
workflows. This allows you to compose solar position components with other physical
systems for applications like solar energy modeling, building thermal analysis, and
solar tracking systems.

## Installation

The ModelingToolkit extension is loaded automatically when both [`SolarPosition.jl`](https://github.com/JuliaAstro/SolarPosition.jl) and [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)
are loaded:

```julia
using SolarPosition
using ModelingToolkit
```

## Quick Start

The extension provides the [`SolarPositionBlock`](@ref) component, which outputs solar
azimuth, elevation, and zenith angles as time-varying quantities.

```@example mtk
using SolarPosition
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Dates
using OrdinaryDiffEq

# Create a solar position block
@named sun = SolarPositionBlock()

# Define observer location and reference time
obs = Observer(51.50274937708521, -0.17782150375214803, 15.0)  # Natural History Museum
t0 = DateTime(2024, 6, 21, 12, 0, 0)  # Summer solstice noon

# Compile the system
sys = mtkcompile(sun)

# Set parameters using the compiled system's parameter references
pmap = [
    sys.observer => obs,
    sys.t0 => t0,
    sys.algorithm => PSA(),
    sys.refraction => NoRefraction(),
]

# Solve over 24 hours (time in seconds)
tspan = (0.0, 86400.0)
prob = ODEProblem(sys, pmap, tspan)
sol = solve(prob; saveat = 3600.0)  # Save every hour

# Show some results
println("Solar position at noon (t=12 hours):")
println("  Azimuth: ", round(sol[sys.azimuth][1], digits=2), "°")
println("  Elevation: ", round(sol[sys.elevation][1], digits=2), "°")
println("  Zenith: ", round(sol[sys.zenith][1], digits=2), "°")
```

## SolarPositionBlock

The [`SolarPositionBlock`](@ref) is a [`ModelingToolkit.jl`](https://github.com/SciML/ModelingToolkit.jl)  component that computes solar position angles based on time, observer location, and
chosen positioning and refraction algorithms.

```@docs
SolarPositionBlock
```

## Composing with Other Systems

The real power of the ModelingToolkit extension comes from composing solar position with other physical systems.

### Example: Solar Panel Power Model

```@example mtk
using CairoMakie: Figure, Axis, lines!

# Create solar position block
@named sun = SolarPositionBlock()

# Create a simple solar panel model
@parameters begin
    area = 10.0           # Panel area (m²)
    efficiency = 0.2      # Panel efficiency (20%)
    dni_peak = 1000.0     # Peak direct normal irradiance (W/m²)
end

@variables begin
    irradiance(t) = 0.0   # Effective irradiance on panel (W/m²)
    power(t) = 0.0        # Power output (W)
end

# Simplified model: irradiance depends on sun elevation
# In reality, you'd account for panel orientation, azimuth, etc.
eqs = [
    irradiance ~ dni_peak * max(0, sind(sun.elevation)),
    power ~ area * efficiency * irradiance,
]

# Compose the complete system
@named model = System(eqs, t; systems = [sun])
sys_model = mtkcompile(model)

# Set up and solve
obs = Observer(37.7749, -122.4194, 100.0)
t0 = DateTime(2024, 6, 21, 0, 0, 0)

pmap = [
    sys_model.sun.observer => obs,
    sys_model.sun.t0 => t0,
    sys_model.sun.algorithm => PSA(),
    sys_model.sun.refraction => NoRefraction(),
]

prob = ODEProblem(sys_model, pmap, (0.0, 86400.0))
sol = solve(prob; saveat = 600.0)  # Save every 10 minutes

# Plot results
fig = Figure(size = (1000, 400))

ax1 = Axis(fig[1, 1]; xlabel = "Time (hours)", ylabel = "Elevation (°)", title = "Solar Elevation")
lines!(ax1, sol.t ./ 3600, sol[sys_model.sun.elevation])

ax2 = Axis(fig[1, 2]; xlabel = "Time (hours)", ylabel = "Power (W)", title = "Solar Panel Power")
lines!(ax2, sol.t ./ 3600, sol[sys_model.power])

fig
```

### Example: Building Thermal Model with Solar Gain

```@example mtk
using CairoMakie: Figure, Axis, lines!
using ModelingToolkit: D_nounits as D

# Solar position component
@named sun = SolarPositionBlock()

# Building thermal model with solar gain
@parameters begin
    mass = 1000.0         # Thermal mass (kg)
    cp = 1000.0           # Specific heat capacity (J/(kg·K))
    U = 0.5               # Overall heat transfer coefficient (W/(m²·K))
    wall_area = 50.0      # Wall area (m²)
    window_area = 5.0     # Window area (m²)
    window_trans = 0.7    # Window transmittance
    T_outside = 20.0      # Outside temperature (°C)
    dni_peak = 800.0      # Peak solar irradiance (W/m²)
end

@variables begin
    T(t) = 20.0           # Room temperature (°C)
    Q_loss(t)             # Heat loss through walls (W)
    Q_solar(t)            # Solar heat gain (W)
    irradiance(t)         # Solar irradiance (W/m²)
end

eqs = [
    # Solar irradiance based on sun elevation
    irradiance ~ dni_peak * max(0, sind(sun.elevation)),
    # Solar heat gain through windows
    Q_solar ~ window_area * window_trans * irradiance,
    # Heat loss through walls
    Q_loss ~ U * wall_area * (T - T_outside),
    # Energy balance
    D(T) ~ (Q_solar - Q_loss) / (mass * cp),
]

@named building = System(eqs, t; systems = [sun])
sys_building = mtkcompile(building)

# Simulate
obs = Observer(40.7128, -74.0060, 100.0)  # New York City
t0 = DateTime(2024, 6, 21, 0, 0, 0)

pmap = [
    sys_building.sun.observer => obs,
    sys_building.sun.t0 => t0,
    sys_building.sun.algorithm => PSA(),
    sys_building.sun.refraction => NoRefraction(),
]

prob = ODEProblem(sys_building, pmap, (0.0, 86400.0))
sol = solve(prob, Tsit5(); saveat = 600.0)

# Plot temperature evolution
fig = Figure(size = (1200, 400))

ax1 = Axis(fig[1, 1]; xlabel = "Time (hours)", ylabel = "Temperature (°C)", title = "Room Temperature")
lines!(ax1, sol.t ./ 3600, sol[sys_building.T])

ax2 = Axis(fig[1, 2]; xlabel = "Time (hours)", ylabel = "Solar Gain (W)", title = "Solar Heat Gain")
lines!(ax2, sol.t ./ 3600, sol[sys_building.Q_solar])

ax3 = Axis(fig[1, 3]; xlabel = "Time (hours)", ylabel = "Elevation (°)", title = "Sun Elevation")
lines!(ax3, sol.t ./ 3600, sol[sys_building.sun.elevation])

fig
```

## Implementation Details

The extension works by registering the [`solar_position`](@ref) function and helper functions as
symbolic operations in ModelingToolkit. The actual solar position calculation happens
during ODE solving, with the simulation time `t` being converted to a [`DateTime`](https://docs.julialang.org/en/v1/stdlib/Dates/#Dates.DateTime) relative to the reference time `t0`.

## Limitations

The solar position calculation is treated as a black-box function by MTK's symbolic
engine, so its internals cannot be symbolically simplified.

## See Also

- [Solar Positioning](@ref solar-positioning-algorithms) - Available positioning algorithms
- [Refraction Correction](@ref refraction-correction) - Atmospheric refraction methods
- [ModelingToolkit.jl Documentation](https://docs.sciml.ai/ModelingToolkit/stable/) -
MTK framework documentation
