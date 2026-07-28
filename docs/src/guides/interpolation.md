# [Interpolated Solar Position](@id interpolated-position)

Dense time series are the common case in solar energy work: a year of positions at
one minute resolution is over half a million queries, and [`SPA`](@ref) spends about
2 µs on each. The [`Interpolated`](@ref SolarPosition.Positioning.Interpolated)
algorithm removes almost all of that cost by precomputing the slow part once.

The sun's geocentric coordinates change smoothly on annual and monthly timescales, so
`Interpolated` samples them on a uniform grid and fits cubic B-splines. Everything
fast or observer dependent, sidereal time, the hour angle, parallax, and the
conversion to azimuth and elevation, stays closed form and runs through the exact
same code as `SPA` itself. The interpolation error is around 1e-10 degrees at the
default one hour grid, about seven orders of magnitude below the accuracy of SPA.

Construction requires [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl),
which is a weak dependency, so load it first:

```@example interp
using SolarPosition
using Dates
using Interpolations

alg = Interpolated(SPA(); tspan = (DateTime(2024, 1, 1), DateTime(2025, 1, 1)))
```

The result is a drop in replacement for any other algorithm:

```@example interp
obs = Observer(52.35888, 4.88185; altitude = 100.0)
dt = DateTime(2024, 6, 21, 12, 30)

solar_position(obs, dt, alg)
```

## Accuracy

The interpolant reproduces the wrapped algorithm to well below its own accuracy. One
day of positions at minute resolution against direct `SPA`:

```@example interp
times = collect(DateTime(2024, 6, 21):Minute(1):DateTime(2024, 6, 22))
exact = solar_position(obs, times, SPA(), NoRefraction())
fast = solar_position(obs, times, alg, NoRefraction())

maximum(abs.(fast.elevation .- exact.elevation))
```

## Speed

Construction samples the geocentric state of `SPA` about 8800 times for a one year
span at the default `step = Hour(1)`, a few milliseconds of work that is threaded
over the available Julia threads. Each query afterwards costs a few spline
evaluations plus the closed form reconstruction:

```@example interp
using BenchmarkTools

@btime solar_position($obs, $dt, $(SPA()), $(NoRefraction()));
@btime solar_position($obs, $dt, $alg, $(NoRefraction()));
nothing # hide
```

On the machine that built these docs this is roughly a 10x speedup per query, so the
construction cost is repaid after a few thousand queries. Below that, direct `SPA` is
the better tool. Two properties make the interpolant attractive beyond raw speed:

- It is observer independent. The splines capture the sun as seen from the Earth's
  center, so one instance serves every site in a simulation grid.
- It is immutable, so evaluation is thread safe by construction and composes with the
  [OhMyThreads extension](@ref parallel-computing).

## Rate of change

Because evaluation is cheap, derivatives come almost for free.
[`solar_rate`](@ref SolarPosition.Positioning.solar_rate) returns the rate of change
of azimuth and elevation in degrees per hour, which is what tracker control loops and
slew rate limits need:

```@example interp
solar_rate(obs, dt, alg)
```

## Out of range queries

Queries outside `tspan` throw by default, because silently falling back to the exact
algorithm would be a hard to notice 10x slowdown:

```@example interp
try
    solar_position(obs, DateTime(2026, 1, 1), alg)
catch err
    println(err.msg)
end
```

Pass `out_of_range = :fallback` to get the wrapped algorithm outside the span
instead. This is convenient when a handful of stray timestamps should not fail a
whole pipeline:

```@example interp
alg_fb = Interpolated(
    SPA();
    tspan = (DateTime(2024, 1, 1), DateTime(2025, 1, 1)),
    out_of_range = :fallback,
)
solar_position(obs, DateTime(2026, 1, 1), alg_fb).elevation
```
