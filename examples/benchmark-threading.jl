# Benchmark multithreaded solar position calculations
# Run with: julia --threads=auto --project=examples examples/benchmark_threading.jl

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

### output ###
# Benchmarking solar_position with 32 threads
# Number of timestamps: 52699
# ======================================================================

# 🔹 Serial execution (default)
#   6.812 ms (9 allocations: 1.21 MiB)

# 🔹 Parallel with DynamicScheduler
#   562.375 μs (466 allocations: 4.91 MiB)

# 🔹 Parallel with StaticScheduler
#   492.855 μs (402 allocations: 4.91 MiB)

# ======================================================================
# In-place benchmarks (solar_position!)
# ======================================================================

# 🔹 Serial in-place
#   6.827 ms (0 allocations: 0 bytes)

# 🔹 Parallel in-place with DynamicScheduler
#   407.315 μs (284 allocations: 20.47 KiB)

# 🔹 Parallel in-place with StaticScheduler
#   361.754 μs (220 allocations: 15.97 KiB)

# ======================================================================
# Different algorithms (parallel vs serial)
# ======================================================================

# 🔹 NOAA algorithm - Serial
#   15.599 ms (9 allocations: 1.21 MiB)

# 🔹 NOAA algorithm - Parallel (DynamicScheduler)
#   999.830 μs (466 allocations: 4.92 MiB)

# 🔹 SPA algorithm - Serial
#   122.392 ms (18 allocations: 2.41 MiB)

# 🔹 SPA algorithm - Parallel (DynamicScheduler)
#   6.899 ms (507 allocations: 9.80 MiB)
# langestefan@fedora:~/dev/solar/SolarPosition.jl$
