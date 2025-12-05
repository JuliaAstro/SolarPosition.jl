
# ============================================================================
# Single Position Benchmarks
# ============================================================================

SUITE["single"] = BenchmarkGroup()

for (name, algo) in POSITION_ALGORITHMS
    SUITE["single"][name] = @benchmarkable(solar_position($OBSERVER, $TEST_DT, $algo))
end

# ============================================================================
# Vector Position Benchmarks
# ============================================================================

SUITE["ours"] = BenchmarkGroup()

for n in [100, 1_000, 10_000, 100_000]
    times = generate_times(n)
    for (name, algo) in POSITION_ALGORITHMS
        SUITE["ours"]["n=$n"][name] =
            @benchmarkable(solar_position($OBSERVER, $times, $algo))
    end
end

# ============================================================================
# Refraction Algorithm Benchmarks
# ============================================================================

SUITE["refraction"] = BenchmarkGroup()

for (name, algo) in REFRACTION_ALGORITHMS
    SUITE["refraction"][name] =
        @benchmarkable(solar_position($OBSERVER, $TEST_DT, PSA(), $algo))
end
