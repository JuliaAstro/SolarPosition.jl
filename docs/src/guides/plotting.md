# [Plotting with Makie.jl](@id plotting-examples)

SolarPosition.jl provides a plotting extension for [Makie.jl](https://makie.juliaplots.org/stable/).

To use it, simply import both the `SolarPosition` and `Makie` packages:

```@example plotting
using SolarPosition
using CairoMakie

# supporting packages
using Dates
using TimeZones
using DataFrames
```

This example notebook is based on the [pvlib sun path example](https://pvlib-python.readthedocs.io/en/stable/gallery/solar-position/plot_sunpath_diagrams.html).

## Basic Sun Path Plotting

Let's start by defining an observer location and calculating solar positions for a whole year:

```@example plotting
# Define observer location (New Delhi, India)
# Parameters: latitude, longitude, altitude in meters
tz = tz"Asia/Kolkata"
obs = Observer(28.6, 77.2, 0.0)

# Generate hourly timestamps for a whole year
times = collect(ZonedDateTime(DateTime(2019), tz):Hour(1):ZonedDateTime(DateTime(2020), tz))

# This returns a StructVector with solar position data
positions = solar_position(obs, times)

# For plotting, we need to create a DataFrame that includes the timestamps
df = DataFrame(positions)
df.datetime = times

# We can inspect the first few entries
first(df, 5)
```

## Simple Sun Path Plot in Cartesian Coordinates

We can visualize solar positions in cartesian coordinates using the `sunpathplot`
function:

```@example plotting
fig = Figure(backgroundcolor = (:white, 0.0), textcolor= "#f5ab35")
ax = Axis(fig[1, 1], backgroundcolor = (:white, 0.0))
sunpathplot!(ax, df, hour_labels = false)
fig
```

## Polar Coordinates with Hour Labels

We can also work directly with a `DataFrame`. Note that for plotting we need to include
the datetime information, so we add it to the DataFrame.

Plotting in polar coordinates with `sunpathpolarplot` may yield a more intuitive
representation of the solar path. Here, we also enable hourly labels for better
readability:

```@example plotting
fig2 = Figure(backgroundcolor = :transparent, textcolor= "#f5ab35", size = (800, 600))
ax2 = PolarAxis(fig2[1, 1], backgroundcolor = "#1f2424")
sunpathpolarplot!(ax2, df, hour_labels = true)

# Draw individual days
line_objects = []
for (date, label) in [(Date("2019-03-21"), "Mar 21"),
                      (Date("2019-06-21"), "Jun 21"),
                      (Date("2019-12-21"), "Dec 21")]
    times = collect(ZonedDateTime(DateTime(date), tz):Minute(5):ZonedDateTime(DateTime(date) + Day(1), tz))
    solpos = solar_position(obs, times)
    above_horizon = solpos.elevation .> 0
    day_df = DataFrame(solpos)
    day_df.datetime = times
    day_filtered = day_df[above_horizon, :]
    line_obj = lines!(ax2, deg2rad.(day_filtered.azimuth), day_filtered.zenith,
                      linewidth = 2, label = label)
    push!(line_objects, line_obj)
end

# Add legend below the plot
fig2[2, 1] = Legend(fig2, line_objects, ["Mar 21", "Jun 21", "Dec 21"],
                    orientation = :horizontal, tellheight = true, backgroundcolor = :transparent)
fig2
```

The figure-8 patterns are known as [analemmas](https://en.wikipedia.org/wiki/Analemma),
which represent the sun's position at the same time of day throughout the year.

Note that in polar coordinates, the radial distance from the center represents the
zenith angle (90° - elevation). Thus, points closer to the center indicate higher
elevations. Conversely, a zenith angle of more than 90° (negative elevation) indicates
that the sun is below the horizon. Tracing a path from right to left corresponds to the
sun's movement from east to west.

It tells us when the sun rises, reaches its highest point, and sets. And hence also the
length of the day. From the figure we can also read that in June the days are longest,
while in December they are shortest.

## Plotting without a custom axis

Finally, we can also create plots without explicitly defining an axis beforehand.
This is a more concise way to create plots, but it offers less customization:

```@example plotting
sunpathpolarplot(df, hour_labels = true, colorbar = true)
```
