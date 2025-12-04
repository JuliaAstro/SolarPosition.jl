"""
Benchmarks for SolarPosition.jl

Compatible with AirspeedVelocity.jl for benchmarking across package versions.

Run locally with:
    benchpkg SolarPosition --rev=main,dirty

Or use the Julia API:
    using BenchmarkTools
    include("benchmarks/benchmarks.jl")
    run(SUITE)
"""

using BenchmarkTools
using SolarPosition
using Dates

# ============================================================================
# Benchmark Suite
# ============================================================================

const SUITE = BenchmarkGroup()

# ============================================================================
# Configuration
# ============================================================================

# Test observer location
const OBSERVER = Observer(51.5074, -0.1278, 11.0)  # London

# Standard test datetime
const TEST_DT = DateTime(2024, 6, 21, 12, 0, 0)

# Generate test time vectors of different sizes
function generate_times(n::Int)
    return collect(DateTime(2024, 1, 1):Hour(1):(DateTime(2024, 1, 1)+Hour(n-1)))
end

# Available algorithms to benchmark
const POSITION_ALGORITHMS = Dict(
    "PSA" => PSA(2020),
    "NOAA" => NOAA(),
    "Walraven" => Walraven(),
    "USNO" => USNO(),
    "SPA" => SPA(),
)

const REFRACTION_ALGORITHMS = Dict(
    "NoRefraction" => NoRefraction(),
    "BENNETT" => BENNETT(),
    "ARCHER" => ARCHER(),
    "MICHALSKY" => MICHALSKY(),
    "SG2" => SG2(),
)

# ============================================================================
# Single Position Benchmarks
# ============================================================================

SUITE["single"] = BenchmarkGroup()

for (name, algo) in POSITION_ALGORITHMS
    SUITE["single"][name] = @benchmarkable(solar_position($(OBSERVER), $TEST_DT, $algo))
end

# ============================================================================
# Vector Position Benchmarks (multiple timestamps)
# ============================================================================

SUITE["vector"] = BenchmarkGroup()

for n in [100, 1_000, 10_000, 100_000]
    times = generate_times(n)
    for (name, algo) in POSITION_ALGORITHMS
        SUITE["vector"]["n=$n,$name"] =
            @benchmarkable(solar_position($(OBSERVER), $times, $algo))
    end
end

# ============================================================================
# Refraction Algorithm Benchmarks
# ============================================================================

SUITE["refraction"] = BenchmarkGroup()

for (name, algo) in REFRACTION_ALGORITHMS
    SUITE["refraction"][name] =
        @benchmarkable(solar_position($(OBSERVER), $TEST_DT, PSA(), $algo))
end
