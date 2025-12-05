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

# Test observer location: London (51.5074°N, 0.1278°W, 11m elevation)
const OBSERVER = Observer(51.5074, -0.1278, 11.0)

# Standard test datetime for single-point benchmarks
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
# SolarPosition.jl Benchmarks (ours)
# ============================================================================

include("algorithms.jl")

# ============================================================================
# Python solposx Benchmarks (reference)
# ============================================================================

include("python.jl")
