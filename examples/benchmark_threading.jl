# Benchmark multithreaded solar position calculations
# Run with: julia --threads=auto --project=guides guides/benchmark_threading.jl

using OhMyThreads
using SolarPosition
using Dates
using BenchmarkTools
using StructArrays

# Setup
obs = Observer(51.5, -0.18, 15.0)  # London
times = collect(DateTime(2024, 1, 1):Minute(10):DateTime(2024, 12, 31, 23))
n_times = length(times)

println("Benchmarking solar_position with $(Threads.nthreads()) threads")
println("Number of timestamps: $n_times")
println("="^70)

# Serial (default)
println("\n🔹 Serial execution (default)")
@btime solar_position($obs, $times, PSA(), NoRefraction());

# Parallel with DynamicScheduler
println("\n🔹 Parallel with DynamicScheduler")
@btime solar_position($obs, $times, PSA(), NoRefraction(), DynamicScheduler());

# Parallel with StaticScheduler
println("\n🔹 Parallel with StaticScheduler")
@btime solar_position($obs, $times, PSA(), NoRefraction(), StaticScheduler());

# In-place benchmarks
println("\n" * "="^70)
println("In-place benchmarks (solar_position!)")
println("="^70)

pos = StructVector{SolPos{Float64}}(undef, n_times)

println("\n🔹 Serial in-place")
@btime solar_position!($pos, $obs, $times, PSA(), NoRefraction());

println("\n🔹 Parallel in-place with DynamicScheduler")
@btime solar_position!($pos, $obs, $times, PSA(), NoRefraction(), DynamicScheduler());

println("\n🔹 Parallel in-place with StaticScheduler")
@btime solar_position!($pos, $obs, $times, PSA(), NoRefraction(), StaticScheduler());

# Test with different algorithms
println("\n" * "="^70)
println("Different algorithms (parallel vs serial)")
println("="^70)

println("\n🔹 NOAA algorithm - Serial")
@btime solar_position($obs, $times, NOAA(), NoRefraction());

println("\n🔹 NOAA algorithm - Parallel (DynamicScheduler)")
@btime solar_position($obs, $times, NOAA(), NoRefraction(), DynamicScheduler());

println("\n🔹 SPA algorithm - Serial")
@btime solar_position($obs, $times, SPA(), NoRefraction());

println("\n🔹 SPA algorithm - Parallel (DynamicScheduler)")
@btime solar_position($obs, $times, SPA(), NoRefraction(), DynamicScheduler());

## Output for times = collect(DateTime(2024, 1, 1):Second(1):DateTime(2024, 12, 31, 23))

# julia> include("guides/benchmark_threading.jl")
# Benchmarking solar_position with 32 threads
# Number of timestamps: 31618801
# ======================================================================

# 🔹 Serial execution (default)
#   5.409 s (9 allocations: 723.70 MiB)

# 🔹 Parallel with DynamicScheduler
#   1.334 s (461 allocations: 2.78 GiB)

# 🔹 Parallel with StaticScheduler
#   1.380 s (397 allocations: 2.78 GiB)

# ======================================================================
# In-place benchmarks (solar_position!)
# ======================================================================

# 🔹 Serial in-place
#   5.158 s (0 allocations: 0 bytes)

# 🔹 Parallel in-place with DynamicScheduler
#   256.939 ms (284 allocations: 20.47 KiB)

# 🔹 Parallel in-place with StaticScheduler
#   260.609 ms (220 allocations: 15.97 KiB)

# ======================================================================
# Different algorithms (parallel vs serial)
# ======================================================================

# 🔹 NOAA algorithm - Serial
#   10.148 s (9 allocations: 723.70 MiB)

# 🔹 NOAA algorithm - Parallel (DynamicScheduler)
#   1.635 s (461 allocations: 2.78 GiB)

# 🔹 SPA algorithm - Serial
#   83.363 s (31618819 allocations: 1.88 GiB)

# 🔹 SPA algorithm - Parallel (DynamicScheduler)
#   7.110 s (31619294 allocations: 6.04 GiB)
