# [Getting Started](@id getting-started)

In this tutorial, we introduduce the basics of using `SolarPosition.jl` to calculate solar
positions.

First, we need to import the `SolarPosition.jl` package along with some supporting
packages which we need for handling dates and time zones. We also load
[DataFrames.jl](https://dataframes.juliadata.org/stable/) because it makes it easy to
work with tabular data.

!!! info
    The [DateTime](https://docs.julialang.org/en/v1/stdlib/Dates/#Dates.DateTime) type in
    Julia's standard library does not contain time zone information. When using
    `DateTime`, **it is assumed to be in UTC**. Although not necessary, it is safer to
    work with time zone-aware [ZonedDateTime](https://juliatime.github.io/TimeZones.jl/stable/api-public/#ZonedDateTime) from the [TimeZones.jl](https://github.com/JuliaTime/TimeZones.jl)
    package.

```@example getting-started
# mandatory
using SolarPosition
using Dates

# supporting packages
using TimeZones
using DataFrames
```

## Defining a location

We can observe the sun from anywhere on earth. To define an observer location, we use
the `Observer` struct, which takes latitude, longitude, and optionally altitude
(in meters) as arguments.

```@example getting-started
obs = Observer(52.35888, 4.88185, 100.0)  # Van Gogh Museum, Amsterdam
```

## Computing the solar vector

Finally, we can calculate the solar position for a specific date and time using the
[`solar_position`](@ref) function. The time should be provided as a `ZonedDateTime` to ensure
correct handling of time zones.

```@example getting-started
tz = TimeZone("Europe/Brussels")
zdt = ZonedDateTime(2023, 6, 21, 12, 0, 0, tz)  # Summer solstice noon
position = solar_position(obs, zdt)
```

## Choosing a Solar Position Algorithm

By default, [`solar_position`](@ref) uses the [`PSA`](@ref) (Plataforma Solar de
Almería) algorithm, which has a decent tradeoff between complexity and accuracy. You
can choose other algorithms as described in the [Solar Positioning Algorithms](../positioning.md)
section.

!!! info "Performance and Accuracy Benchmarks"
    For detailed performance comparisons and accuracy analysis of all available algorithms,
    see the [Benchmarking Guide](@ref benchmarking).

First, we repeat the previous calculation using the default PSA algorithm:

```@example getting-started
position_psa = solar_position(obs, zdt, PSA())
```

Next, we compute the solar position using the NOAA algorithm:

```@example getting-started
position_noaa = solar_position(obs, zdt, NOAA())
```

As you can see, the results are very similar. With a claimed accuracy of ±0.0083° for
PSA and ±0.0167° for NOAA, the differences should be small:

```@example getting-started
delta_azimuth = abs(position_psa.azimuth - position_noaa.azimuth)
delta_elevation = abs(position_psa.elevation - position_noaa.elevation)
println("Difference in Azimuth: $(round(delta_azimuth, digits=4))°")
println("Difference in Elevation: $(round(delta_elevation, digits=4))°")
```

Whether the differences are significant depends on your application and required
accuracy.

## Computing multiple timestamps simultaneously

For more demanding applications, it is often necessary to compute solar positions for
multiple timestamps at once. `SolarPosition.jl` supports this by passing a vector of
`ZonedDateTime` or `DateTime` objects to the [`solar_position`](@ref) function. Here, we
demonstrate this by calculating solar positions for every hour of a full year.

```@example getting-started
# generate hourly timestamps for a whole year
dts = collect(ZonedDateTime(DateTime(2023), tz):Hour(1):ZonedDateTime(DateTime(2024), tz))
positions = solar_position(obs, dts)
```

!!! info
    The returned datastructure is a [`StructArray`](https://juliaarrays.github.io/StructArrays.jl/stable/reference/#StructArrays.StructArray) from the [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl)
    package, which behaves similarly to a vector of [`SolPos`](@ref)  structs but is
    more convenient to work with.

The returned `StructArray` can be easily converted to a `DataFrame` for inspection:

```@example getting-started
df = DataFrame(positions)
df.datetime = dts  # add datetime information
first(df, 5)  # show first 5 entries
```

## Broadcasting Over Multiple Locations

Thanks to Julia's broadcasting syntax it is trivial to calculate solar positions for
multiple locations simultaneously. This can be useful for example when analyzing solar
irradiance over a geographic region with multiple measurement stations.

```@example getting-started
# Create observers at different latitudes
observers = Observer.([10.0, 20.0, 30.0], 10.0)

# Calculate solar position for all locations at a specific time
dt = DateTime(2020)
positions_broadcast = solar_position.(observers, dt)
```
