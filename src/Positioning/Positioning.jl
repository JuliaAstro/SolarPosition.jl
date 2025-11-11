"""
    Positioning

This module provides the core solar position calculation algorithms, observer location
handling, and result types for SolarPosition.jl. It includes implementations of various
solar position algorithms such as PSA and NOAA, with support for optional atmospheric
refraction corrections.

# Exported Types
- [`Observer`](@ref): Geographic observer location
- [`SolPos`](@ref): Basic solar position result
- [`ApparentSolPos`](@ref): Solar position with atmospheric corrections
- [`PSA`](@ref): PSA algorithm implementation
- [`NOAA`](@ref): NOAA algorithm implementation
- [`RefractionAlgorithm`](@ref): Base type for refraction algorithms
- [`NoRefraction`](@ref): No refraction correction (default)

# Exported Functions
- [`solar_position`](@ref): Calculate solar positions
- [`solar_position!`](@ref): In-place solar position calculation
"""
module Positioning

using Dates: datetime2julian, DateTime, Date, daysinmonth, dayofyear
using Dates: year, month, day, hour, minute, second, millisecond
using TimeZones: ZonedDateTime, UTC
using StructArrays: StructArrays
using Tables: Tables
using DocStringExtensions: TYPEDFIELDS, TYPEDEF, TYPEDSIGNATURES
import ..Refraction
using ..Refraction: RefractionAlgorithm, NoRefraction, DefaultRefraction

"""
    $(TYPEDEF)

Abstract base type for all solar position algorithms.

All concrete solar position algorithm types must inherit from this type.

# Examples
```julia
struct MyAlgorithm <: SolarAlgorithm end
```
"""
abstract type SolarAlgorithm end

"""
    $(TYPEDEF)

Observer location (deg  rees, meters). Accepts a type parameter `T` for the
floating point type to use (e.g. `Float32`, `Float64`).

---
# Fields
$(TYPEDFIELDS)
"""
struct Observer{T<:AbstractFloat}
    "Geodetic latitude (+N)"
    latitude::T
    "Longitude (+E)"
    longitude::T        # longitude (+E)
    "Altitude above mean sea level (meters)"
    altitude::T         # altitude above MSL
    "Latitude in radians"
    latitude_rad::T
    "Longitude in radians"
    longitude_rad::T
    "sin(latitude)"
    sin_lat::T
    "cos(latitude)"
    cos_lat::T

    function Observer{T}(lat::T, lon::T, alt::T = zero(T)) where {T<:AbstractFloat}
        # apply pole corrections to avoid numerical issues
        if lat == 90.0
            lat -= 1e-6
            @warn "Latitude was 90°. Adjusted to $(lat)° to avoid singularities."
        elseif lat == -90.0
            lat += 1e-6
            @warn "Latitude was -90°. Adjusted to $(lat)° to avoid singularities."
        end

        lat_rad = deg2rad(lat)
        lon_rad = deg2rad(lon)
        sin_lat = sin(lat_rad)
        cos_lat = cos(lat_rad)
        new{T}(lat, lon, alt, lat_rad, lon_rad, sin_lat, cos_lat)
    end
end

Observer(lat::T, lon::T; altitude = 0.0) where {T} = Observer{T}(lat, lon, altitude)
Observer(lat::T, lon::T, alt::T) where {T} = Observer{T}(lat, lon, alt)

Base.show(io::IO, obs::Observer) = print(
    io,
    "Observer(latitude=$(obs.latitude)°, longitude=$(obs.longitude)°, altitude=$(obs.altitude)m)",
)

abstract type AbstractSolPos end
abstract type AbstractApparentSolPos <: AbstractSolPos end

"""
    $(TYPEDEF)

Represents a single solar position calculated for a given observer and time.

---
# Fields
$(TYPEDFIELDS)
"""
struct SolPos{T} <: AbstractSolPos where {T<:AbstractFloat}
    "Azimuth (degrees, 0=N, +clockwise, range [-180, 180])"
    azimuth::T
    "Elevation (degrees, range [-90, 90])"
    elevation::T
    "Zenith = 90 - elevation (degrees, range [0, 180])"
    zenith::T
end

"""
    $(TYPEDEF)

Represents a single solar position calculated for a given observer and time.
Also includes apparent elevation and zenith angles.

---
# Fields
$(TYPEDFIELDS)
"""
struct ApparentSolPos{T} <: AbstractApparentSolPos where {T<:AbstractFloat}
    "Azimuth (degrees, 0=N, +clockwise, range [-180, 180])"
    azimuth::T
    "Elevation (degrees, range [-90, 90])"
    elevation::T
    "Zenith = 90 - elevation (degrees, range [0, 180])"
    zenith::T
    "Apparent elevation (degrees, range [-90, 90])"
    apparent_elevation::T
    "Apparent zenith (degrees, range [0, 180])"
    apparent_zenith::T
end

Base.show(io::IO, obs::SolPos) = print(
    io,
    "SolPos(azimuth=$(obs.azimuth)°, elevation=$(obs.elevation)°, zenith=$(obs.zenith)°)",
)

Base.show(io::IO, obs::ApparentSolPos) = print(
    io,
    "ApparentSolPos(azimuth=$(obs.azimuth)°, elevation=$(obs.elevation)°, zenith=$(obs.zenith)°,
    apparent_elevation=$(obs.apparent_elevation)°, apparent_zenith=$(obs.apparent_zenith)°",
)

"""
    $(TYPEDEF)

Solar position result from SPA algorithm including equation of time.

---
# Fields
$(TYPEDFIELDS)
"""
struct SPASolPos{T} <: AbstractApparentSolPos where {T<:AbstractFloat}
    "Azimuth (degrees, 0=N, +clockwise, range [-180, 180])"
    azimuth::T
    "Elevation (degrees, range [-90, 90])"
    elevation::T
    "Zenith = 90 - elevation (degrees, range [0, 180])"
    zenith::T
    "Apparent elevation (degrees, range [-90, 90])"
    apparent_elevation::T
    "Apparent zenith (degrees, range [0, 180])"
    apparent_zenith::T
    "Equation of time (minutes)"
    equation_of_time::T
end

Base.show(io::IO, obs::SPASolPos) = print(
    io,
    "SPASolPos(azimuth=$(obs.azimuth)°, elevation=$(obs.elevation)°, zenith=$(obs.zenith)°,
    apparent_elevation=$(obs.apparent_elevation)°, apparent_zenith=$(obs.apparent_zenith)°,
    equation_of_time=$(obs.equation_of_time)min",
)

"""
    solar_position(obs::Observer, dt::DateTime, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction())
    solar_position(obs::Observer, dt::ZonedDateTime, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction())
    solar_position(obs::Observer, dts::AbstractVector{DateTime}, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction())
    solar_position(obs::Observer, dts::AbstractVector{ZonedDateTime}, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction())

Calculate solar position(s) for given observer location(s) and time(s).

This function computes the solar position (azimuth, elevation, and zenith angles) based on
an observer's geographic location and timestamp(s). It supports multiple input formats and
automatically handles time zone conversions.

# Arguments
- `obs::Observer`: Observer location with latitude, longitude, and altitude
- `dt::DateTime` or `dt::ZonedDateTime`: Single timestamp
- `dts::AbstractVector`: Vector of timestamps (DateTime or ZonedDateTime)
- `alg::SolarAlgorithm`: Solar positioning algorithm (default: `PSA()`)
- `refraction::RefractionAlgorithm`: Atmospheric refraction correction (default: `NoRefraction()`)

# Returns
- For single timestamps:
  - `SolPos` struct when `refraction = DefaultRefraction()` (default)
  - `ApparentSolPos` struct when a refraction algorithm is provided
- For multiple timestamps: `StructVector` of solar position data

---

# Angles Convention
All returned angles are in **degrees**:
- **Azimuth**: 0° = North, positive clockwise, range [-180°, 180°]
- **Elevation**: angle above horizon, range [-90°, 90°]
- **Zenith**: angle from zenith (90° - elevation), range [0°, 180°]
- **Apparent Elevation/Zenith**: Only in `ApparentSolPos`, includes atmospheric refraction

---

# Examples
## Single timestamp calculation (basic position)
```julia
using SolarPosition, Dates, TimeZones

# Define observer location (San Francisco)
obs = Observer(37.7749, -122.4194, 100.0)

# Calculate position at specific time
dt = ZonedDateTime(2023, 6, 21, 12, 0, 0, tz"America/Los_Angeles")
pos = solar_position(obs, dt)

println("Azimuth: \$(pos.azimuth)°")
println("Elevation: \$(pos.elevation)°")
println("Zenith: \$(pos.zenith)°")
```

## With refraction correction
```julia
# Use a refraction algorithm (when implemented)
# pos_apparent = solar_position(obs, dt, PSA(), MyRefractionAlg())
# println("Apparent Elevation: \$(pos_apparent.apparent_elevation)°")
```

## Multiple timestamps calculation
```julia
# Generate hourly timestamps for a day
times = collect(DateTime(2023, 6, 21):Hour(1):DateTime(2023, 6, 22))
positions = solar_position(obs, times)

# Access as StructVector (acts like array of structs)
println("First position: ", positions[1])
println("All azimuths: ", positions.azimuth)
```

## Using different algorithms
```julia
# Use NOAA algorithm instead of default PSA
pos_noaa = solar_position(obs, dt, NOAA())
```

# Supported Input Types
- **Observer**: `Observer{T}` struct with lat/lon/altitude
- **Single time**: `DateTime`, `ZonedDateTime`
- **Multiple times**: `Vector{DateTime}`, `Vector{ZonedDateTime}`
- **Algorithm**: Any `SolarAlgorithm` subtype
- **Refraction**: Any `RefractionAlgorithm` subtype (default: `NoRefraction()`)

# Time Zone Handling
- `DateTime` inputs are assumed to be in UTC
- `ZonedDateTime` inputs are automatically converted to UTC
- For local solar time calculations, use appropriate time zones

# Performance Notes
- Vectorized operations are optimized for multiple timestamps
- Type-stable implementations for both `Float32` and `Float64`
- Broadcasting-friendly for large datasets

See also: [`solar_position!`](@ref), [`Observer`](@ref), [`PSA`](@ref), [`NOAA`](@ref)
"""
function solar_position end

function _solar_position(obs, dt, alg::SolarAlgorithm, ::NoRefraction)
    return _solar_position(obs, dt, alg)
end

function _solar_position(obs, dt, alg::SolarAlgorithm, refraction::RefractionAlgorithm)
    pos = _solar_position(obs, dt, alg)

    # apply refraction correction
    refraction_correction_deg = Refraction.refraction(refraction, pos.elevation)
    apparent_elevation_deg = pos.elevation + refraction_correction_deg
    apparent_zenith_deg = 90.0 - apparent_elevation_deg

    return ApparentSolPos(
        pos.azimuth,
        pos.elevation,
        pos.zenith,
        apparent_elevation_deg,
        apparent_zenith_deg,
    )
end

function solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractFloat}
    _solar_position(obs, dt, alg, refraction)
end

function solar_position(
    obs::Observer{T},
    dt::ZonedDateTime,
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractFloat}
    solar_position(obs, DateTime(dt, UTC), alg, refraction)
end

function solar_position!(
    pos::StructArrays.StructVector{T},
    obs::Observer,
    dts::AbstractVector{Union{DateTime,ZonedDateTime}},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position!(
    pos::StructArrays.StructVector{T},
    obs::Observer,
    dts::AbstractVector{DateTime},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position!(
    pos::StructArrays.StructVector{T},
    obs::Observer,
    dts::AbstractVector{ZonedDateTime},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position(
    obs::Observer{T},
    dts::AbstractVector{Union{DateTime,ZonedDateTime}},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractFloat}
    RetType = result_type(typeof(alg), typeof(refraction), T)
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    pos
end

function solar_position(
    obs::Observer{T},
    dts::AbstractVector{DateTime},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractFloat}
    RetType = result_type(typeof(alg), typeof(refraction), T)
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    pos
end

function solar_position(
    obs::Observer{T},
    dts::AbstractVector{ZonedDateTime},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction(),
) where {T<:AbstractFloat}
    RetType = result_type(typeof(alg), typeof(refraction), T)
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    pos
end


"""
    solar_position!(table, obs::Observer; dt_col::Symbol=:datetime, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction(), kwargs...)
    solar_position!(table; latitude::AbstractFloat, longitude::AbstractFloat,
                    altitude::AbstractFloat=0.0, alg::SolarAlgorithm=PSA(), refraction::RefractionAlgorithm=NoRefraction(), kwargs...)

Compute solar positions for all times in a table and add the results as new columns.

Arguments
---------
- `table` : Table-like object with datetime column (must support Tables.jl interface).
- `obs::Observer` : Observer location (latitude, longitude, altitude).
- `latitude, longitude, altitude` : Specify observer location directly.
- `dt_col::Symbol` : Name of the datetime column (default: `:datetime`).
- `alg::SolarAlgorithm` : Algorithm to use (default: `PSA()`).
- `refraction::RefractionAlgorithm` : Refraction correction (default: `NoRefraction()`).
- `kwargs...` : Additional keyword arguments forwarded to the algorithm.

Returns
-------
- Modified table with added columns: `azimuth`, `elevation`, `zenith`.
- If refraction is applied: also adds `apparent_elevation`, `apparent_zenith`.

Notes
-----
The input table is modified **in-place** by adding new columns.
"""
function solar_position!(
    table,
    obs::Observer{T},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction();
    dt_col::Symbol = :datetime,
) where {T<:AbstractFloat}
    tbl = Tables.columntable(table)
    if !haskey(tbl, dt_col)
        throw(ArgumentError("Input table must have a $(dt_col) column"))
    end

    dts = tbl[dt_col]
    result = StructArrays.components(solar_position(obs, dts, alg, refraction))

    # add the result columns to the table
    for (key, value) in pairs(result)
        table[!, key] = value
    end
end

"""
    $(TYPEDSIGNATURES)

Non-mutating version of [`solar_position!`](@ref) that returns a modified copy of the input table.

See [`solar_position!`](@ref) for detailed documentation of arguments, examples, and usage patterns.
"""
function solar_position(
    table,
    obs::Observer{T},
    alg::SolarAlgorithm = PSA(),
    refraction::RefractionAlgorithm = DefaultRefraction();
    kwargs...,
) where {T<:AbstractFloat}
    table_copy = copy(table)
    solar_position!(table_copy, obs, alg, refraction; kwargs...)
    return table_copy
end

# helper function to determine return type based on refraction
result_type(::Type{<:SolarAlgorithm}, ::Type{NoRefraction}, ::Type{T}) where {T} = SolPos{T}
result_type(::Type{<:SolarAlgorithm}, ::Type{<:RefractionAlgorithm}, ::Type{T}) where {T} =
    ApparentSolPos{T}

include("utils.jl")
include("deltat.jl")
include("psa.jl")
include("noaa.jl")
include("walraven.jl")
include("usno.jl")
include("spa.jl")

export Observer,
    PSA,
    NOAA,
    Walraven,
    USNO,
    SPA,
    solar_position,
    solar_position!,
    SolPos,
    ApparentSolPos,
    SPASolPos
export calculate_deltat

end
