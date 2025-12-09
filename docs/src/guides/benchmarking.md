# [Benchmarking](@id benchmarking)

This page provides comprehensive benchmarks of the solar position algorithms available
in `SolarPosition.jl`, comparing their computational performance and accuracy. The
[SPA](@ref SolarPosition.Positioning.SPA) algorithm is used as the reference "gold
standard" due to its high precision (±0.0003°).

```@example benchmarks
using SolarPosition
using CairoMakie
using Dates
using DataFrames
using Statistics
using BenchmarkTools
```

## Algorithm Overview

SolarPosition.jl provides several solar positioning algorithms with different
accuracy/performance trade-offs:

| Algorithm                                             | Claimed Accuracy | Complexity |
| ----------------------------------------------------- | ---------------- | ---------- |
| [`SPA`](@ref SolarPosition.Positioning.SPA)           | ±0.0003°         | High       |
| [`PSA`](@ref SolarPosition.Positioning.PSA)           | ±0.0083°         | Low        |
| [`NOAA`](@ref SolarPosition.Positioning.NOAA)         | ±0.0167°         | Low        |
| [`Walraven`](@ref SolarPosition.Positioning.Walraven) | ±0.0100°         | Low        |
| [`USNO`](@ref SolarPosition.Positioning.USNO)         | ±0.0500°         | Low        |

## Accuracy Analysis

To evaluate accuracy, we compare each algorithm against SPA across a full year of
hourly timestamps at various geographic locations.

```@example benchmarks
# Test locations representing different latitudes
locations = [
    (name = "Equator", obs = Observer(0.0, 0.0, 0.0)),
    (name = "Mid-latitude (London)", obs = Observer(51.5074, -0.1278, 11.0)),
    (name = "High-latitude (Oslo)", obs = Observer(59.9139, 10.7522, 23.0)),
    (name = "Southern hemisphere (Sydney)", obs = Observer(-33.8688, 151.2093, 58.0)),
]

# Generate hourly timestamps for a full year
times = collect(DateTime(2024, 1, 1):Hour(1):DateTime(2024, 12, 31, 23))
println("Testing with $(length(times)) timestamps per location")
```

!!! details "Accuracy comparison"
    ```@example benchmarks
    using Statistics: quantile

    """
    Compare algorithm accuracy against SPA reference.
    Returns DataFrame with error statistics including percentiles.
    """
    function compare_accuracy(obs::Observer, times::Vector{DateTime}, algo)
        # Get SPA reference positions
        spa_pos = solar_position(obs, times, SPA())

        # Get algorithm positions
        algo_pos = solar_position(obs, times, algo)

        # Calculate errors for all positions
        elev_errors = abs.(algo_pos.elevation .- spa_pos.elevation)
        azim_errors = abs.(algo_pos.azimuth .- spa_pos.azimuth)

        # Handle azimuth wraparound (0° and 360° are the same)
        azim_errors = min.(azim_errors, 360.0 .- azim_errors)

        return (
            elevation_mean = mean(elev_errors),
            elevation_p2_5 = quantile(elev_errors, 0.025),
            elevation_p97_5 = quantile(elev_errors, 0.975),
            elevation_max = maximum(elev_errors),
            azimuth_mean = mean(azim_errors),
            azimuth_p2_5 = quantile(azim_errors, 0.025),
            azimuth_p97_5 = quantile(azim_errors, 0.975),
            azimuth_max = maximum(azim_errors),
            n_samples = length(times),
        )
    end

    nothing # hide
    ```

!!! details "Data collection"
    ```@example benchmarks
    # Algorithms to compare (excluding SPA which is the reference)
    algorithms = [
        ("PSA", PSA()),
        ("NOAA", NOAA()),
        ("Walraven", Walraven()),
        ("USNO", USNO()),
    ]

    # Collect accuracy data
    accuracy_results = DataFrame(
        Algorithm = String[],
        Location = String[],
        Elevation_Mean_Error = Float64[],
        Elevation_P2_5 = Float64[],
        Elevation_P97_5 = Float64[],
        Elevation_Max_Error = Float64[],
        Azimuth_Mean_Error = Float64[],
        Azimuth_P2_5 = Float64[],
        Azimuth_P97_5 = Float64[],
        Azimuth_Max_Error = Float64[],
    )

    for (algo_name, algo) in algorithms
        for loc in locations
            stats = compare_accuracy(loc.obs, times, algo)
            push!(accuracy_results, (
                Algorithm = algo_name,
                Location = loc.name,
                Elevation_Mean_Error = stats.elevation_mean,
                Elevation_P2_5 = stats.elevation_p2_5,
                Elevation_P97_5 = stats.elevation_p97_5,
                Elevation_Max_Error = stats.elevation_max,
                Azimuth_Mean_Error = stats.azimuth_mean,
                Azimuth_P2_5 = stats.azimuth_p2_5,
                Azimuth_P97_5 = stats.azimuth_p97_5,
                Azimuth_Max_Error = stats.azimuth_max,
            ))
        end
    end

    accuracy_results
    ```

### Accuracy Visualization

The following plots show the mean error with 95% confidence intervals (2.5th to 97.5th
percentile) for each algorithm compared to SPA.

!!! details "Accuracy visualization"
    ```@example benchmarks
    # Aggregate results by algorithm (mean across all locations)
    algo_stats = combine(
        groupby(accuracy_results, :Algorithm),
        :Elevation_Mean_Error => mean => :Elev_Mean,
        :Elevation_P2_5 => mean => :Elev_P2_5,
        :Elevation_P97_5 => mean => :Elev_P97_5,
        :Azimuth_Mean_Error => mean => :Azim_Mean,
        :Azimuth_P2_5 => mean => :Azim_P2_5,
        :Azimuth_P97_5 => mean => :Azim_P97_5,
    )

    # Sort by algorithm order
    algo_order = ["PSA", "NOAA", "Walraven", "USNO"]
    algo_stats = algo_stats[sortperm([findfirst(==(algo), algo_order) for algo in algo_stats.Algorithm]), :]

    fig = Figure(size = (900, 400), backgroundcolor = :transparent, fontsize = 12, textcolor = "#f5ab35")

    # Elevation error plot with error bars
    ax1 = Axis(fig[1, 1],
        title = "Elevation Error vs SPA (95% CI)",
        xlabel = "Algorithm",
        ylabel = "Error (degrees)",
        xticks = (1:4, algo_stats.Algorithm),
        backgroundcolor = :transparent,
    )

    # Error bars showing 95% interval
    errorbars!(ax1, 1:4, algo_stats.Elev_Mean,
        algo_stats.Elev_Mean .- algo_stats.Elev_P2_5,
        algo_stats.Elev_P97_5 .- algo_stats.Elev_Mean,
        color = :steelblue, linewidth = 2, whiskerwidth = 10)
    scatter!(ax1, 1:4, algo_stats.Elev_Mean, color = :steelblue, markersize = 12)

    # Azimuth error plot with error bars
    ax2 = Axis(fig[1, 2],
        title = "Azimuth Error vs SPA (95% CI)",
        xlabel = "Algorithm",
        ylabel = "Error (degrees)",
        xticks = (1:4, algo_stats.Algorithm),
        backgroundcolor = :transparent,
    )

    errorbars!(ax2, 1:4, algo_stats.Azim_Mean,
        algo_stats.Azim_Mean .- algo_stats.Azim_P2_5,
        algo_stats.Azim_P97_5 .- algo_stats.Azim_Mean,
        color = :coral, linewidth = 2, whiskerwidth = 10)
    scatter!(ax2, 1:4, algo_stats.Azim_Mean, color = :coral, markersize = 12)

    nothing # hide
    ```

```@example benchmarks
fig # hide
```

### PSA Error Over Time

To better understand how errors vary throughout the year, we compare the PSA algorithm
against SPA at hourly resolution for a full year at a single location.

```@example benchmarks
# Generate hourly timestamps for a full year (reduces memory usage vs minute resolution)
hourly_times = collect(DateTime(2024, 1, 1):Hour(1):DateTime(2024, 12, 31, 23))
obs_london = Observer(51.5074, -0.1278, 11.0)

# Calculate positions
spa_positions = solar_position(obs_london, hourly_times, SPA())
psa_positions = solar_position(obs_london, hourly_times, PSA())

# Calculate errors
elev_errors = psa_positions.elevation .- spa_positions.elevation
azim_errors = psa_positions.azimuth .- spa_positions.azimuth

# Handle azimuth wraparound
azim_errors = [abs(e) > 180 ? e - sign(e) * 360 : e for e in azim_errors]

println("PSA vs SPA at hourly resolution ($(length(hourly_times)) samples):")
println("  Elevation: mean=$(round(mean(abs.(elev_errors)), digits=6))°, max=$(round(maximum(abs.(elev_errors)), digits=4))°")
println("  Azimuth: mean=$(round(mean(abs.(azim_errors)), digits=6))°, max=$(round(maximum(abs.(azim_errors)), digits=4))°")
```

!!! details "PSA error visualization"
    ```@example benchmarks
    fig_err = Figure(size = (900, 500), backgroundcolor = :transparent, fontsize = 12, textcolor = "#f5ab35")

    # Convert to day of year for x-axis
    day_of_year = [Dates.dayofyear(t) for t in hourly_times]

    ax1 = Axis(fig_err[1, 1],
        title = "PSA Elevation Error vs SPA (2024, London)",
        xlabel = "Day of Year",
        ylabel = "Error (degrees)",
        backgroundcolor = :transparent,
    )
    scatter!(ax1, day_of_year, elev_errors, markersize = 1.5, color = (:steelblue, 0.5))
    hlines!(ax1, [0.0], color = :gray, linestyle = :dash)

    ax2 = Axis(fig_err[2, 1],
        title = "PSA Azimuth Error vs SPA (2024, London)",
        xlabel = "Day of Year",
        ylabel = "Error (degrees)",
        backgroundcolor = :transparent,
    )
    scatter!(ax2, day_of_year, azim_errors, markersize = 1.5, color = (:coral, 0.5))
    hlines!(ax2, [0.0], color = :gray, linestyle = :dash)

    nothing # hide
    ```

```@example benchmarks
fig_err # hide
```

### Error Distribution by Location

!!! details "Error distribution visualization"
    ```@example benchmarks
    fig2 = Figure(size = (900, 500), backgroundcolor = :transparent, fontsize = 11, textcolor = "#f5ab35")

    for (i, loc) in enumerate(locations)
        row = (i - 1) ÷ 2 + 1
        col = (i - 1) % 2 + 1

        ax = Axis(fig2[row, col],
            title = loc.name,
            xlabel = "Algorithm",
            ylabel = "Mean Elevation Error (°)",
            xticks = (1:4, [a[1] for a in algorithms]),
            backgroundcolor = :transparent,
        )

        loc_data = filter(r -> r.Location == loc.name, accuracy_results)
        barplot!(ax, 1:4, loc_data.Elevation_Mean_Error, color = :teal)
    end

    Label(fig2[0, :], "Elevation Error by Location", fontsize = 14, font = :bold)

    nothing # hide
    ```

```@example benchmarks
fig2 # hide
```

## Performance Benchmarks

We benchmark the computational performance of each algorithm across different input
sizes, from single timestamp calculations to bulk operations with 100,000 timestamps.

!!! details "Single benchmark"
    ```@example benchmarks
    # Single position benchmarks
    obs = Observer(51.5074, -0.1278, 11.0)  # London
    dt = DateTime(2024, 6, 21, 12, 0, 0)

    single_benchmarks = DataFrame(
        Algorithm = String[],
        Time_ns = Float64[],
        Allocations = Int[],
    )

    for (name, algo) in [("PSA", PSA()), ("NOAA", NOAA()), ("Walraven", Walraven()),
                          ("USNO", USNO()), ("SPA", SPA())]
        b = @benchmark solar_position($obs, $dt, $algo) samples=100 evals=10
        push!(single_benchmarks, (
            Algorithm = name,
            Time_ns = median(b.times),
            Allocations = b.allocs,
        ))
    end

    # Add relative timing
    single_benchmarks.Time_μs = single_benchmarks.Time_ns ./ 1000
    single_benchmarks.Relative_to_SPA = single_benchmarks.Time_ns ./
        single_benchmarks[single_benchmarks.Algorithm .== "SPA", :Time_ns][1]

    single_benchmarks[:, [:Algorithm, :Time_μs, :Allocations, :Relative_to_SPA]]
    ```

!!! details "Vector benchmark"
    ```@example benchmarks
    # Vector benchmarks for different sizes
    sizes = [100, 1_000, 10_000, 100_000]

    vector_benchmarks = DataFrame(
        Algorithm = String[],
        N = Int[],
        Time_ms = Float64[],
        Throughput = Float64[],  # positions per second
    )

    for n in sizes
        times_vec = collect(DateTime(2024, 1, 1):Hour(1):(DateTime(2024, 1, 1) + Hour(n-1)))

        for (name, algo) in [("PSA", PSA()), ("NOAA", NOAA()), ("Walraven", Walraven()),
                              ("USNO", USNO()), ("SPA", SPA())]
            b = @benchmark solar_position($obs, $times_vec, $algo) samples=10 evals=1
            time_ms = median(b.times) / 1e6
            push!(vector_benchmarks, (
                Algorithm = name,
                N = n,
                Time_ms = time_ms,
                Throughput = n / (time_ms / 1000),
            ))
        end
    end

    # Pivot for display
    vector_pivot = unstack(vector_benchmarks, :Algorithm, :N, :Time_ms)
    vector_pivot
    ```

### Performance Visualization

!!! details "Performance visualization"
    ```@example benchmarks
    fig3 = Figure(size = (900, 400), backgroundcolor = :transparent, fontsize = 12, textcolor = "#f5ab35")

    # Scaling plot (log-log)
    ax1 = Axis(fig3[1, 1],
        title = "Computation Time vs Input Size",
        xlabel = "Number of Timestamps",
        ylabel = "Time (ms)",
        xscale = log10,
        yscale = log10,
        backgroundcolor = :transparent,
    )

    colors = [:blue, :orange, :green, :purple, :red]
    algo_names = ["PSA", "NOAA", "Walraven", "USNO", "SPA"]

    for (i, algo) in enumerate(algo_names)
        data = filter(r -> r.Algorithm == algo, vector_benchmarks)
        lines!(ax1, data.N, data.Time_ms, label = algo, color = colors[i], linewidth = 2)
        scatter!(ax1, data.N, data.Time_ms, color = colors[i], markersize = 8)
    end
    axislegend(ax1, position = :rb, framevisible = false, labelsize = 10)

    # Throughput plot
    ax2 = Axis(fig3[1, 2],
        title = "Throughput at N=100,000",
        xlabel = "Algorithm",
        ylabel = "Positions per Second",
        xticks = (1:5, algo_names),
        backgroundcolor = :transparent,
    )

    throughput_100k = filter(r -> r.N == 100_000, vector_benchmarks)
    barplot!(ax2, 1:5, throughput_100k.Throughput ./ 1e6, color = colors)
    ax2.ylabel = "Million Positions / Second"

    nothing # hide
    ```

```@example benchmarks
fig3 # hide
```

## Comparison with solposx (Python)

The [solposx](https://github.com/assessingsolar/solposx) package is a Python library
that implements the same solar position algorithms. This section compares the
performance of SolarPosition.jl against solposx to demonstrate the benefits of using
Julia.

!!! note "Benchmarking Methodology"
    The benchmarks below use [PythonCall.jl](https://github.com/JuliaPy/PythonCall.jl)
    to call `solposx` from within Julia. We have also benchmarked `solposx` directly in
    a pure Python environment (without `PythonCall.jl` overhead) and found no significant
    difference in the results.

### Setup

First, we install and import solposx using [PythonCall.jl](https://github.com/JuliaPy/PythonCall.jl) and [CondaPkg.jl](https://github.com/JuliaPy/CondaPkg.jl):

```@example benchmarks
using CondaPkg
CondaPkg.add_pip("solposx")
CondaPkg.add_pip("pandas")

using PythonCall

# Import Python modules
sp = pyimport("solposx.solarposition")
pd = pyimport("pandas")
timeit = pyimport("timeit")
```

### Benchmark Configuration

For fair comparison, we use the same test conditions for both libraries:

- **Observer**: London (51.5074°N, 0.1278°W, 11m elevation)
- **Timestamps**: Hourly data from January 1, 2024
- **Algorithms**: PSA, NOAA, Walraven, USNO, SPA

```@example benchmarks
# Helper function to create pandas DatetimeIndex
function create_pandas_times(n::Int)
    pd.date_range(start="2024-01-01 00:00:00", periods=n, freq="h", tz="UTC")
end

# solposx algorithm mapping - use Symbol keys for kwargs
solposx_algorithms = Dict(
    "PSA" => (sp.psa, (coefficients = 2020,)),
    "NOAA" => (sp.noaa, NamedTuple()),
    "Walraven" => (sp.walraven, NamedTuple()),
    "USNO" => (sp.usno, NamedTuple()),
    "SPA" => (sp.spa, NamedTuple()),
)

lat, lon = 51.5074, -0.1278
```

### Running the Benchmarks

We benchmark both libraries across different input sizes:

!!! details "Benchmark code"
    ```@example benchmarks
    # Benchmark sizes
    sizes = [100, 1_000, 10_000]

    # Results storage
    comparison_results = DataFrame(
        Algorithm = String[],
        N = Int[],
        Julia_ms = Float64[],
        Python_ms = Float64[],
        Speedup = Float64[],
    )

    for n in sizes
        # Create time vectors
        julia_times_vec = collect(DateTime(2024, 1, 1):Hour(1):(DateTime(2024, 1, 1) + Hour(n-1)))
        py_times_idx = create_pandas_times(n)

        for (algo_name, algo) in [("PSA", PSA()), ("NOAA", NOAA()), ("Walraven", Walraven()),
                                   ("USNO", USNO()), ("SPA", SPA())]
            # Julia benchmark
            julia_bench = @benchmark solar_position($obs, $julia_times_vec, $algo) samples=5 evals=1
            julia_time_ms = median(julia_bench.times) / 1e6

            # Python benchmark
            py_func, py_kwargs = solposx_algorithms[algo_name]

            # Benchmark Python function using BenchmarkTools
            if isempty(py_kwargs)
                py_bench = @benchmark $py_func($py_times_idx, $lat, $lon) samples=5 evals=1
            else
                py_bench = @benchmark $py_func($py_times_idx, $lat, $lon; $py_kwargs...) samples=5 evals=1
            end
            python_time_ms = median(py_bench.times) / 1e6

            speedup = python_time_ms / julia_time_ms

            push!(comparison_results, (
                Algorithm = algo_name,
                N = n,
                Julia_ms = round(julia_time_ms, digits=3),
                Python_ms = round(python_time_ms, digits=3),
                Speedup = round(speedup, digits=1),
            ))
        end
    end

    comparison_results
    ```

!!! details "Performance comparison visualization"
    ```@example benchmarks
    fig5 = Figure(size = (600, 750), backgroundcolor = :transparent, fontsize = 12, textcolor = "#f5ab35")

    # Group by algorithm for plotting
    algo_names = ["PSA", "NOAA", "Walraven", "USNO", "SPA"]
    colors_julia = [:blue, :green, :purple, :orange, :red]

    ax1 = Axis(fig5[1, 1],
        title = "Computation Time: Julia vs Python",
        xlabel = "Number of Timestamps",
        ylabel = "Time (ms)",
        xscale = log10,
        yscale = log10,
        backgroundcolor = :transparent,
    )

    # Store line objects for legends
    julia_lines = []
    python_lines = []

    for (i, algo) in enumerate(algo_names)
        data = filter(r -> r.Algorithm == algo, comparison_results)

        # Julia times (solid lines)
        l1 = lines!(ax1, data.N, data.Julia_ms,
            color = colors_julia[i],
            linewidth = 2)
        scatter!(ax1, data.N, data.Julia_ms, color = colors_julia[i], markersize = 6)
        push!(julia_lines, l1)

        # Python times (dashed lines)
        l2 = lines!(ax1, data.N, data.Python_ms,
            color = colors_julia[i],
            linewidth = 2,
            linestyle = :dash)
        scatter!(ax1, data.N, data.Python_ms, color = colors_julia[i], markersize = 6,
            marker = :utriangle)
        push!(python_lines, l2)
    end

    # Algorithm legend (colors)
    leg1 = Legend(fig5[1, 2][1, 1], julia_lines, algo_names, "Algorithm",
        framevisible = true, backgroundcolor = :transparent, labelsize = 10, titlesize = 11)

    # Line style legend (solid vs dashed)
    style_lines = [LineElement(color = :gray, linewidth = 2, linestyle = :solid),
                   LineElement(color = :gray, linewidth = 2, linestyle = :dash)]
    leg2 = Legend(fig5[1, 2][2, 1], style_lines, ["Julia", "Python"], "Library",
        framevisible = true, backgroundcolor = :transparent, labelsize = 10, titlesize = 11)

    # Speedup bar chart
    ax2 = Axis(fig5[2, 1:2],
        title = "Julia vs Python at N=1,000",
        xlabel = "Algorithm",
        ylabel = "Speedup Factor (×)",
        xticks = (1:5, algo_names),
        backgroundcolor = :transparent,
    )

    speedup_1k = filter(r -> r.N == 1_000, comparison_results)
    barplot!(ax2, 1:5, speedup_1k.Speedup, color = colors_julia)
    hlines!(ax2, [1.0], color = :gray, linestyle = :dash)

    nothing # hide
    ```

```@example benchmarks
fig5 # hide
```

### Summary

The benchmarks demonstrate that SolarPosition.jl offers significant performance
advantages over the solposx Python library across all tested algorithms and input sizes.

!!! note "Multi-threading"
    `SolarPosition.jl` can leverage Julia's native multi-threading capabilities (see
    [Parallel Computing](@ref parallel-computing)) for further performance improvements
    on large datasets. The benchmarks above were conducted using a single thread for
    fair comparison with `solposx`, but enabling multi-threading can yield even greater
    speedups in practical applications.

```@example benchmarks
speedup_table = unstack(comparison_results[:, [:Algorithm, :N, :Speedup]], :Algorithm, :N, :Speedup)
speedup_table
```
