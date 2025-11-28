# Parallel Computing with OhMyThreads.jl

SolarPosition.jl provides a parallel computing extension using [`OhMyThreads.jl`](https://github.com/JuliaFolds2/OhMyThreads.jl)
for efficient multithreaded solar position calculations across large time series. This
extension is particularly useful when processing thousands of timestamps, where
parallelization can provide significant speedups.

## Installation

The OhMyThreads extension is loaded automatically when both [`SolarPosition.jl`](https://github.com/JuliaAstro/SolarPosition.jl) and [`OhMyThreads.jl`](https://github.com/JuliaFolds2/OhMyThreads.jl)
are loaded:

```julia
using SolarPosition
using OhMyThreads
```

!!! note "Thread Configuration"
    Julia must be started with multiple threads to benefit from parallelization. Use
    `julia --threads=auto` or set the `JULIA_NUM_THREADS` environment variable. Check
    the number of available threads with `Threads.nthreads()`.

## Quick Start

The extension adds new methods to [`solar_position`](@ref) and [`solar_position!`](@ref)
that accept an `OhMyThreads.Scheduler` as the last argument. These methods automatically
parallelize computations across the provided timestamp vector.

```@example parallel
using SolarPosition
using SolarPosition: BENNETT  # Import refraction algorithms
using OhMyThreads
using Dates
using StructArrays

# Create observer location
obs = Observer(51.5, -0.18, 15.0)  # London

# Generate a year of minute timestamps
times = collect(DateTime(2024, 1, 1):Minute(1):DateTime(2025, 1, 1))

# Parallel computation with DynamicScheduler
t0 = time()
positions = solar_position(obs, times, PSA(), NoRefraction(), DynamicScheduler())
dt_parallel = time() - t0
println("Time taken (parallel): $(round(dt_parallel, digits=5)) seconds")
```

Now we compare this to the serial version:

```@example parallel
# Serial computation (no scheduler argument)
t0 = time()
positions_serial = solar_position(obs, times, PSA(), NoRefraction())
dt_serial = time() - t0
println("Time taken (serial): $(round(dt_serial, digits=5)) seconds")
```

We observe a speedup of:

```@example parallel
speedup = dt_serial / dt_parallel
println("Speedup: $(round(speedup, digits=2))×")
```

### Simplified Syntax

You can also use the simplified syntax with the scheduler as the third argument, which
uses the default algorithm (PSA) and no refraction correction:

```@example parallel
# Simplified syntax with default algorithm
positions = solar_position(obs, times, DynamicScheduler())
@show first(positions, 3)
```

## Available Schedulers

OhMyThreads.jl provides different scheduling strategies optimized for various workload
characteristics:

### DynamicScheduler

The [`DynamicScheduler`](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#OhMyThreads.DynamicScheduler)
is the default and recommended scheduler for most workloads. It dynamically balances
tasks among threads, making it suitable for non-uniform workloads where computation
times may vary. Please visit the `OhMyThreads.jl` documentation for more details.

```@example parallel
# Dynamic scheduling (recommended)
positions = solar_position(obs, times, PSA(), NoRefraction(), DynamicScheduler());
nothing # hide
```

### StaticScheduler

The [`StaticScheduler`](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#OhMyThreads.StaticScheduler)
partitions work statically among threads. This can be more efficient for uniform
workloads where all computations take approximately the same time.

```@example parallel
# Static scheduling for uniform workloads
positions = solar_position(obs, times, PSA(), NoRefraction(), StaticScheduler())
nothing # hide
```

## In-Place Computation

For maximum performance and minimal allocations, use the in-place version
[`solar_position!`](@ref) with a pre-allocated [`StructVector`](https://github.com/JuliaArrays/StructArrays.jl):

```@example parallel
using StructArrays

# Pre-allocate output array
positions = StructVector{SolPos{Float64}}(undef, length(times))

# Compute in-place
solar_position!(positions, obs, times, PSA(), NoRefraction(), DynamicScheduler())
nothing # hide
```

The in-place version avoids allocating the output array and minimizes intermediate
allocations, making it ideal for repeated computations or memory-constrained
environments.

## Performance Comparison

Here's a typical performance comparison between serial and parallel execution:

```julia
using BenchmarkTools

### Serial execution (no scheduler argument)
@benchmark solar_position($obs, $times, PSA(), NoRefraction())
# BenchmarkTools.Trial: 57 samples with 1 evaluation per sample.
#  Range (min … max):  83.994 ms … 98.110 ms  ┊ GC (min … max): 0.00% … 12.50%
#  Time  (median):     87.907 ms              ┊ GC (median):    0.66%
#  Time  (mean ± σ):   88.194 ms ±  2.478 ms  ┊ GC (mean ± σ):  1.39% ±  2.23%

#                ▁             █
#   ▆▁▄▁▁▁▇▆▆▁▁▇▄█▄▁▇▆▇▇▄▄▁▄▄▆▆█▆▆▄▁▆▁▁▆▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄ ▁
#   84 ms           Histogram: frequency by time        95.8 ms <

#  Memory estimate: 12.06 MiB, allocs estimate: 9.

### Parallel execution with DynamicScheduler
@benchmark solar_position($obs, $times, PSA(), NoRefraction(), DynamicScheduler())
# BenchmarkTools.Trial: 312 samples with 1 evaluation per sample.
#  Range (min … max):   7.588 ms … 35.575 ms  ┊ GC (min … max):  0.00% … 74.79%
#  Time  (median):     14.718 ms              ┊ GC (median):     6.16%
#  Time  (mean ± σ):   16.026 ms ±  6.387 ms  ┊ GC (mean ± σ):  23.51% ± 19.37%

#     ▆▆█▁▃▂▅ ▁▁▁▄▁▃▅▁  ▁▄ ▁
#   █▇███████▄████████▇▄██▆█▇▆▇█▅▆▅▆▄▄▁▅▄▁▁▄▃▄▅▄▃▃▄▃▄▆▃▃▁▄▄▁▃▁▃ ▄
#   7.59 ms         Histogram: frequency by time        34.4 ms <

#  Memory estimate: 66.59 MiB, allocs estimate: 468.

### In-place parallel execution
pos = StructVector{SolPos{Float64}}(undef, length(times))
@benchmark solar_position!($pos, $obs, $times, PSA(), NoRefraction(), DynamicScheduler())
# BenchmarkTools.Trial: 908 samples with 1 evaluation per sample.
#  Range (min … max):  4.061 ms …   7.846 ms  ┊ GC (min … max): 0.00% … 0.00%
#  Time  (median):     5.532 ms               ┊ GC (median):    0.00%
#  Time  (mean ± σ):   5.501 ms ± 644.881 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

#                                ▃▅█▄▂▂       ▁
#   ▃▄▅▃▄▃▃▅▃▄▃▁▃▂▃▄▂▃▂▂▃▂▂▃▂▅▃▃████████▆▅▅▄▆▅██▅▅▆▄▅▄▃▂▃▃▃▃▃▂▂ ▃
#   4.06 ms         Histogram: frequency by time        6.72 ms <

#  Memory estimate: 20.47 KiB, allocs estimate: 284.

### In-place parallel execution with StaticScheduler
@benchmark solar_position!($pos, $obs, $times, PSA(), NoRefraction(), StaticScheduler())
# BenchmarkTools.Trial: 902 samples with 1 evaluation per sample.
#  Range (min … max):  4.027 ms …   7.228 ms  ┊ GC (min … max): 0.00% … 0.00%
#  Time  (median):     5.842 ms               ┊ GC (median):    0.00%
#  Time  (mean ± σ):   5.537 ms ± 802.636 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

#  ▃▁   ▁▄▃                       ▁      ▁▅▆█▂▄▇▇▅▁▃    ▁
#  ██▃▃▅███▅▆▆▄▄▃▃▃▃▃▂▄▅▂▁▃▆▃▃▂▅▃▅█▇▆▂▃▅▅██████████████▇█▆▇▇▂▂ ▄
#  4.03 ms         Histogram: frequency by time        6.72 ms <

#  Memory estimate: 15.97 KiB, allocs estimate: 220.
```

On a system with 32 threads processing 527,041 timestamps (one year, minutely):

| Method | Time | Speedup | Allocations |
|--------|------|---------|-------------|
| Serial | 87.9 ms | 1.0× | 12.06 MiB |
| Parallel (DynamicScheduler) | 14.7 ms | **6.0×** | 66.59 MiB |
| In-place (DynamicScheduler) | 5.53 ms | **15.9×** | 20.47 KiB |
| In-place (StaticScheduler) | 5.84 ms | **15.0×** | 15.97 KiB |

!!! tip "Performance Tips"
    For the best performance:
    - Use [`solar_position!`](@ref) with pre-allocated output for minimal allocations
    - Use `DynamicScheduler()` for most workloads
    - Ensure Julia is running with multiple threads (e.g., `--threads=auto`)
    - Process larger batches of timestamps to amortize threading overhead

## Working with Different Time Types

The parallel methods work with both [`DateTime`](https://docs.julialang.org/en/v1/stdlib/Dates/#Dates.DateTime) and [`ZonedDateTime`](https://juliatime.github.io/TimeZones.jl/stable/types/#TimeZones.ZonedDateTime):

```@example parallel
using TimeZones

# Using ZonedDateTime (avoiding DST transitions)
tz = tz"Europe/London"
# Use a subset of times to avoid DST transition issues in documentation
summer_times = collect(DateTime(2024, 6, 1):Hour(1):DateTime(2024, 7, 1))
zoned_times = ZonedDateTime.(summer_times, tz)

# Parallel computation with time zone aware timestamps
zoned_positions = solar_position(obs, zoned_times, PSA(), NoRefraction(), DynamicScheduler())

println("Computed $(length(zoned_positions)) positions with time zone awareness")
```

## Algorithm Comparison

The parallel interface works with all solar position algorithms:

```@example parallel
# Test different algorithms in parallel
algorithms = [PSA(), NOAA(), SPA()]

for alg in algorithms
    pos = solar_position(obs, times[1:100], alg, NoRefraction(), DynamicScheduler())
    println("$(typeof(alg).name.name): azimuth=$(round(pos.azimuth[50], digits=5))°")
end
```

## Refraction Correction

Atmospheric refraction corrections can be applied in parallel computations:

```@example parallel
# Parallel computation with Bennett refraction correction
positions_refracted = solar_position(
    obs,
    times,
    PSA(),
    BENNETT(),
    DynamicScheduler()
)

println("First position with refraction:")
println("  Apparent elevation: $(round(positions_refracted.apparent_elevation[1], digits=2))°")
```

## Implementation Details

The extension uses OhMyThreads' [`tmap`](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#OhMyThreads.tmap)
and [`tmap!`](https://juliafolds2.github.io/OhMyThreads.jl/stable/refs/api/#OhMyThreads.tmap!)
for task-based parallelism. Each timestamp is processed independently, making the
computation embarrassingly parallel with no inter-thread communication required.

The results from `tmap` are automatically converted to a [`StructVector`](https://github.com/JuliaArrays/StructArrays.jl)
for efficient columnar storage compatible with the rest of SolarPosition.jl's API.

## See Also

- [Solar Positioning](@ref solar-positioning-algorithms) - Available positioning algorithms
- [Refraction Correction](@ref refraction-correction) - Atmospheric refraction methods
- [OhMyThreads.jl Documentation](https://juliafolds2.github.io/OhMyThreads.jl/stable/) - Task-based parallelism framework
- [Julia Threading Documentation](https://docs.julialang.org/en/v1/manual/multi-threading/) - Julia's threading capabilities
