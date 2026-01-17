"""Plot solar positions using SolarPosition.jl with hourly labels."""

using Dates
using CairoMakie
using SolarPosition

# define observer location (latitude, longitude, altitude in meters)
obs = Observer(28.6, 77.2, 0.0)  # New Delhi, India
year = 2019

# plot in cartesian coordinates with hourly labels
fig = Figure()
ax = Axis(fig[1, 1], title = "Cartesian Coordinates with Hour Labels")
analemmas!(ax, obs, year, hour_labels = true)
fig

# plot in polar coordinates with hourly labels
fig2 = Figure()
ax2 = PolarAxis(fig2[1, 1], title = "Polar Coordinates with Hour Labels")
analemmas!(ax2, obs, year, hour_labels = true)
fig2

# example without hourly labels for comparison
fig3 = Figure()
ax3 = Axis(fig3[1, 1], title = "Cartesian Coordinates (No Labels)")
analemmas!(ax3, obs, year, hour_labels = false)
fig3
