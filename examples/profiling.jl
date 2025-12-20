"""Profiling example for SolarPosition.jl using ProfileView."""

using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Dates
using SolarPosition

# define observer location (latitude, longitude, altitude in meters)
obs = Observer(52.358134610343214, 4.881269505489815, 0.0)  # Van Gogh Museum

# a whole year of hourly timestamps for profiling
times = collect(DateTime(2023):Minute(1):DateTime(2024))

# warm up the function to compile
solar_position(obs, times, PSA())

# profile the PSA algorithm with multiple iterations for better sampling
@profview for _ = 1:1000
    solar_position(obs, times, PSA())
end
