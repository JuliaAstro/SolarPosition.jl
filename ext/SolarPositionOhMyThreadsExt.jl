module SolarPositionOhMyThreadsExt

using SolarPosition
using SolarPosition: Observer, SolarAlgorithm, RefractionAlgorithm
using SolarPosition: SolPos, ApparentSolPos, AbstractSolPos
using OhMyThreads
using OhMyThreads: tmap, tmap!
using StructArrays: StructArrays
using Dates: DateTime
using TimeZones: ZonedDateTime
using DocStringExtensions: TYPEDSIGNATURES

"""
    $(TYPEDSIGNATURES)

In-place multithreaded computation of solar positions using OhMyThreads.jl.

This method uses OhMyThreads.jl's task-based parallelism to efficiently compute solar
positions across multiple timestamps in parallel. The computation is performed in-place,
writing results directly to the pre-allocated `pos` vector.

# Arguments
- `pos::StructArrays.StructVector`: Pre-allocated output vector for solar positions
- `obs::Observer`: Observer location (latitude, longitude, altitude)
- `dts::AbstractVector{DateTime}`: Vector of timestamps (UTC)
- `alg::SolarAlgorithm`: Solar positioning algorithm (e.g., PSA(), NOAA())
- `refraction::RefractionAlgorithm`: Atmospheric refraction correction
- `executor::OhMyThreads.Scheduler`: OhMyThreads scheduler for parallel execution

# Returns
- `pos`: The input vector with computed solar positions

# Examples
```julia
using SolarPosition, OhMyThreads, Dates, StructArrays

# Setup observer and times
obs = Observer(51.5, -0.18, 15.0)
times = collect(DateTime(2024, 6, 21):Hour(1):DateTime(2024, 6, 22))

# Pre-allocate output
pos = StructVector{SolPos{Float64}}(undef, length(times))

# Compute in parallel with default scheduler
solar_position!(pos, obs, times, PSA(), NoRefraction(), DynamicScheduler())

# Or use a specific scheduler
solar_position!(pos, obs, times, PSA(), NoRefraction(), StaticScheduler())
```

See also: [`solar_position`](@ref), [`OhMyThreads.Scheduler`]
"""
function SolarPosition.solar_position!(
    pos::StructArrays.StructVector{T},
    obs::Observer,
    dts::AbstractVector{Z},
    alg::SolarAlgorithm,
    refraction::RefractionAlgorithm,
    executor::OhMyThreads.Scheduler,
) where {T<:AbstractSolPos,Z<:Union{DateTime,ZonedDateTime}}
    f = dt -> SolarPosition.solar_position(obs, dt, alg, refraction)
    tmap!(f, pos, dts; scheduler = executor)
    return pos
end

"""
    solar_position(obs::Observer, dts::AbstractVector{DateTime}, alg::SolarAlgorithm, refraction::RefractionAlgorithm, executor::OhMyThreads.Scheduler)

Multithreaded computation of solar positions using OhMyThreads.jl.

This method allocates the output vector and uses OhMyThreads.jl's task-based parallelism
to efficiently compute solar positions across multiple timestamps in parallel.

# Arguments
- `obs::Observer`: Observer location (latitude, longitude, altitude)
- `dts::AbstractVector{DateTime}`: Vector of timestamps (UTC)
- `alg::SolarAlgorithm`: Solar positioning algorithm (e.g., PSA(), NOAA())
- `refraction::RefractionAlgorithm`: Atmospheric refraction correction
- `executor::OhMyThreads.Scheduler`: OhMyThreads scheduler for parallel execution

# Returns
- `StructVector` of solar positions

# Examples
```julia
using SolarPosition, OhMyThreads, Dates

# Setup observer and times
obs = Observer(51.5, -0.18, 15.0)
times = collect(DateTime(2024, 6, 21):Hour(1):DateTime(2024, 6, 22))

# Compute in parallel with DynamicScheduler
positions = solar_position(obs, times, PSA(), NoRefraction(), DynamicScheduler())

# Compute with StaticScheduler for better performance on uniform workloads
positions = solar_position(obs, times, PSA(), NoRefraction(), StaticScheduler())
```

# Available Schedulers
- `DynamicScheduler()`: Dynamic load balancing, good for variable workloads
- `StaticScheduler()`: Static partitioning, best for uniform workloads
- `GreedyScheduler()`: Greedy task stealing, adaptive scheduling

See also: [`solar_position!`](@ref), [`OhMyThreads.Scheduler`]
"""
function SolarPosition.solar_position(
    obs::Observer{T},
    dts::AbstractVector{Z},
    alg::SolarAlgorithm,
    refraction::RefractionAlgorithm,
    executor::OhMyThreads.Scheduler,
) where {T<:AbstractFloat,Z<:Union{DateTime,ZonedDateTime}}
    f = dt -> SolarPosition.solar_position(obs, dt, alg, refraction)
    results = tmap(f, dts; scheduler = executor)
    return StructArrays.StructVector(results)
end

function SolarPosition.solar_position(
    obs::Observer{T},
    dts::AbstractVector{Z},
    executor::OhMyThreads.Scheduler,
) where {T<:AbstractFloat,Z<:Union{DateTime,ZonedDateTime}}
    return SolarPosition.solar_position(
        obs,
        dts,
        SolarPosition.PSA(),
        SolarPosition.NoRefraction(),
        executor,
    )
end

end # module
