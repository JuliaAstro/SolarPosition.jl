# ============================================================================
# Python solposx Benchmarks
# ============================================================================
#
# This file benchmarks the Python solposx library for comparison with
# SolarPosition.jl. The Julia benchmarks are in benchmarks.jl (vector section).

using CondaPkg

# install solposx via pip
CondaPkg.add_pip("solposx")
CondaPkg.add_pip("pandas")

using PythonCall

sp = pyimport("solposx.solarposition")
pd = pyimport("pandas")

# Create pandas DatetimeIndex for Python benchmarks (same timestamps as Julia)
function create_pandas_times(n::Int)
    pd.date_range(start = "2024-01-01 00:00:00", periods = n, freq = "h", tz = "UTC")
end

# Map algorithm names to solposx functions
# solposx functions: psa, noaa, walraven, usno, spa
const SOLPOSX_ALGORITHMS = Dict(
    "PSA" => (sp.psa, Dict(:coefficients => 2020)),
    "NOAA" => (sp.noaa, Dict()),
    "Walraven" => (sp.walraven, Dict()),
    "USNO" => (sp.usno, Dict()),
    "SPA" => (sp.spa, Dict()),
)

SUITE["solposx"] = BenchmarkGroup()

# Vector benchmarks for all solposx algorithms
for n in [100, 1_000, 10_000, 100_000]
    py_times = create_pandas_times(n)

    for (name, (py_func, py_kwargs)) in SOLPOSX_ALGORITHMS
        SUITE["solposx"]["n=$n"][name] = @benchmarkable(
            $py_func($py_times, $(OBSERVER.latitude), $(OBSERVER.longitude); $py_kwargs...)
        )
    end
end
