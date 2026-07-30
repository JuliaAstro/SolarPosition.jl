"""
    Positioning

This module provides the core solar position calculation algorithms, observer location
handling, and result types for SolarPosition.jl. It includes implementations of various
solar position algorithms such as PSA and NOAA, with support for optional atmospheric
refraction corrections.
"""
module Positioning

using Dates: Dates, DateTime, Date, daysinmonth, dayofyear
using Dates: year, month, day
using TimeZones: ZonedDateTime, UTC
using StructArrays: StructArrays
using Tables: Tables
using DocStringExtensions: TYPEDFIELDS, TYPEDEF, TYPEDSIGNATURES
import ..Refraction
using ..Refraction: RefractionAlgorithm, NoRefraction, DefaultRefraction, SPARefraction

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

Abstract base type for Observers.

All concrete observer types must inherit from this type. Most algorithms will use the
default `Observer` struct defined in this module. More specialized observer types can be
defined by inheriting from this abstract type, see for example [`SPAObserver`](@ref).

# Examples
```julia
struct MyObserver <: AbstractObserver{Float64} end
```
"""
abstract type AbstractObserver{T <: Real} end

"""
    $(TYPEDEF)

Represents an observer's geographic location on Earth.

This struct holds the latitude, longitude, and altitude of an observer, along with
pre-calculated trigonometric values used in solar position calculations.

# Fields
$(TYPEDFIELDS)

# Constructors
```julia
Observer(latitude, longitude, altitude=0.0)
Observer(latitude, longitude; altitude=0.0, horizon=0.0)
Observer(latitude, longitude; altitude=0.0, horizon=0=>34)  # 34 arcminutes
Observer{T}(latitude, longitude, altitude=0.0, horizon=0.0)  # compute at precision T
```

The element type `T` is taken from the arguments, so `Observer(45.0f0, 10.0f0)` is an
`Observer{Float32}`. The explicit form `Observer{Float32}(45.0, 10.0)` converts its
arguments and avoids literal suffixes.

The `horizon` parameter represents the angular depression/elevation of the horizon in
degrees. It is commonly used for sunrise/sunset calculations to account for atmospheric
refraction (typically 0=>34 or ~0.5667°) or local terrain elevation that affects the
visible horizon.

The `horizon` parameter can be specified as:
- A number in degrees (e.g., `0.5667`)
- A `degrees=>arcminutes` pair (e.g., `0=>34` for 34 arcminutes = 0.5667°)
"""
struct Observer{T <: Real} <: AbstractObserver{T}
    "Geodetic latitude (+N)"
    latitude::T
    "Longitude (+E)"
    longitude::T        # longitude (+E)
    "Altitude above mean sea level (meters)"
    altitude::T         # altitude above MSL
    "Horizon angle in degrees (e.g., for refraction or sunrise/sunset calculations)"
    horizon::T
    "Latitude in radians"
    latitude_rad::T
    "Longitude in radians"
    longitude_rad::T
    "sin(latitude)"
    sin_lat::T
    "cos(latitude)"
    cos_lat::T

    function Observer{T}(
            lat::T,
            lon::T,
            alt::T = zero(T),
            horiz::T = zero(T),
        ) where {T <: Real}
        lat_rad = deg2rad(lat)
        lon_rad = deg2rad(lon)
        (sin_lat, cos_lat) = sincos(lat_rad)
        return new{T}(lat, lon, alt, horiz, lat_rad, lon_rad, sin_lat, cos_lat)
    end
end

# helper to convert horizon from different formats to degrees
_horizon_to_degrees(h::Pair{<:Real, <:Real}) = h.first + h.second / 60.0
_horizon_to_degrees(h::Real) = h

# converting constructor, so Observer{Float128}(1.0, 2.0) and Observer{Float32}(45, 10)
# work without converting every argument at the call site
Observer{T}(lat::Real, lon::Real, alt::Real = 0.0, horiz = 0.0) where {T <: Real} =
    Observer{T}(T(lat), T(lon), T(alt), T(_horizon_to_degrees(horiz)))

# the element type promotes over lat/lon/alt and maps to a float type, so integer
# arguments and mixed inputs such as a ForwardDiff.Dual latitude with a Float64
# longitude both work
_observer_eltype(args...) = float(promote_type(map(typeof, args)...))

# the Bool default is promotion neutral, so Observer(45.0f0, 10.0f0) stays Float32
Observer(lat::Real, lon::Real; altitude::Real = false, horizon = 0.0) =
    Observer{_observer_eltype(lat, lon, altitude)}(lat, lon, altitude, horizon)
Observer(lat::Real, lon::Real, alt::Real) =
    Observer{_observer_eltype(lat, lon, alt)}(lat, lon, alt)
Observer(lat::Real, lon::Real, alt::Real, horiz::Union{Real, Pair{<:Real, <:Real}}) =
    Observer{_observer_eltype(lat, lon, alt)}(lat, lon, alt, horiz)

Base.show(io::IO, obs::Observer) = print(
    io,
    "Observer(latitude=$(obs.latitude)°, longitude=$(obs.longitude)°, altitude=$(obs.altitude)m, horizon=$(obs.horizon)°)",
)

abstract type AbstractSolPos end
abstract type AbstractApparentSolPos <: AbstractSolPos end

"""
    $(TYPEDEF)

Represents a calculated solar position without atmospheric refraction correction.

This struct holds the azimuth, elevation, and zenith angles of the sun for a specific
observer and time.

# Fields
$(TYPEDFIELDS)
"""
struct SolPos{T} <: AbstractSolPos where {T <: Real}
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

# Fields
$(TYPEDFIELDS)
"""
struct ApparentSolPos{T} <: AbstractApparentSolPos where {T <: Real}
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

# the element type promotes over the fields, so a position whose apparent angles carry a
# ForwardDiff.Dual from a differentiated refraction parameter can still be built from
# geometric angles that do not
SolPos(azimuth::Real, elevation::Real, zenith::Real) =
    SolPos{promote_type(typeof(azimuth), typeof(elevation), typeof(zenith))}(
    azimuth, elevation, zenith,
)

function ApparentSolPos(
        azimuth::Real,
        elevation::Real,
        zenith::Real,
        apparent_elevation::Real,
        apparent_zenith::Real,
    )
    T = promote_type(
        typeof(azimuth), typeof(elevation), typeof(zenith),
        typeof(apparent_elevation), typeof(apparent_zenith),
    )
    return ApparentSolPos{T}(
        azimuth, elevation, zenith, apparent_elevation, apparent_zenith,
    )
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
    $(TYPEDSIGNATURES)

Calculate solar position(s) for given observer location(s) and time(s).

This function computes the solar position (azimuth, elevation, and zenith angles) based on
an observer's geographic location and timestamp(s). It supports multiple input formats and
automatically handles time zone conversions.

# Arguments
- `obs::AbstractObserver`: Observer location with latitude, longitude, and altitude
- `dt::DateTime` or `dt::ZonedDateTime`: Single timestamp
- `dts::AbstractVector`: Vector of timestamps (DateTime or ZonedDateTime)
- `alg::SolarAlgorithm`: Solar positioning algorithm (default: `PSA()`)
- `refraction::RefractionAlgorithm`: Atmospheric refraction correction (default: `NoRefraction()`)

# Returns
- For single timestamps:
  - `SolPos` struct when `refraction = DefaultRefraction()` (default)
  - `ApparentSolPos` struct when a refraction algorithm is provided
- For multiple timestamps: `StructVector` of solar position data

# Angles Convention
All returned angles are in **degrees**:
- **Azimuth**: 0° = North, positive clockwise, range [-180°, 180°]
- **Elevation**: angle above horizon, range [-90°, 90°]
- **Zenith**: angle from zenith (90° - elevation), range [0°, 180°]
- **Apparent Elevation/Zenith**: Only in `ApparentSolPos`, includes atmospheric refraction

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

# Floating-Point Precision
The result element type follows the `Observer{T}` element type `T`, and the computation runs
at that precision:
- **`Float64`**: the default, with reference accuracy for every algorithm.
- **`BigFloat`**: genuine extended precision for every algorithm — use a higher
  `setprecision` for more correct digits. Note that ΔT is only known to about a second and
  is therefore always evaluated in `Float64`, which bounds the achievable absolute accuracy
  regardless of `T`.
- **`Float128`** from Quadmath.jl: quad precision of ~1e-30° for `PSA`, `SPA`, and
  `Walraven`. `NOAA` and `USNO` currently give wrong results at `Float128` because
  Quadmath.jl's `rem` uses round-to-nearest semantics, which breaks Base's `sind`/`cosd`
  degree reduction.
- **`Float32`**: accurate and faster for every algorithm. A magnitude-safe time base keeps
  full intra-day resolution instead of riding on the ~2.45e6 Julian Date.
- **`Float16`**: unusable — algorithm coefficients overflow its range, so results are silently
  `NaN`. Use `Float32` or wider.
- **`ForwardDiff.Dual`** and other `Real` number types work too, so solar positions are
  differentiable with respect to latitude, longitude, and altitude, and with respect to a
  refraction model's parameters such as pressure and temperature.

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
    apparent_zenith_deg = 90 - apparent_elevation_deg

    return ApparentSolPos(
        pos.azimuth,
        pos.elevation,
        pos.zenith,
        apparent_elevation_deg,
        apparent_zenith_deg,
    )
end

function solar_position(
        obs::AbstractObserver{T},
        dt::DateTime,
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    return _solar_position(obs, dt, alg, refraction)
end

function solar_position(
        obs::AbstractObserver{T},
        dt::ZonedDateTime,
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    return solar_position(obs, DateTime(dt, UTC), alg, refraction)
end

function solar_position!(
        pos::StructArrays.StructVector{T},
        obs::AbstractObserver,
        dts::AbstractVector{Union{DateTime, ZonedDateTime}},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position!(
        pos::StructArrays.StructVector{T},
        obs::AbstractObserver,
        dts::AbstractVector{DateTime},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position!(
        pos::StructArrays.StructVector{T},
        obs::AbstractObserver,
        dts::AbstractVector{ZonedDateTime},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function solar_position(
        obs::AbstractObserver{T},
        dts::AbstractVector{Union{DateTime, ZonedDateTime}},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    RetType = result_type(
        typeof(alg), typeof(refraction), _result_eltype(T, refraction),
    )
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    return pos
end

function solar_position(
        obs::AbstractObserver{T},
        dts::AbstractVector{DateTime},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    RetType = result_type(
        typeof(alg), typeof(refraction), _result_eltype(T, refraction),
    )
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    return pos
end

function solar_position(
        obs::AbstractObserver{T},
        dts::AbstractVector{ZonedDateTime},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    RetType = result_type(
        typeof(alg), typeof(refraction), _result_eltype(T, refraction),
    )
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    return pos
end


"""
    $(TYPEDSIGNATURES)

Compute solar positions for all times in a table and add the results as new columns.

# Arguments
- `table` : Table-like object with datetime column (must support Tables.jl interface).
- `obs::AbstractObserver` : Observer location (latitude, longitude, altitude).
- `latitude, longitude, altitude` : Specify observer location directly.
- `dt_col::Symbol` : Name of the datetime column (default: `:datetime`).
- `alg::SolarAlgorithm` : Algorithm to use (default: `PSA()`).
- `refraction::RefractionAlgorithm` : Refraction correction (default: `NoRefraction()`).
- `kwargs...` : Additional keyword arguments forwarded to the algorithm.

# Returns
- Modified table with added columns: `azimuth`, `elevation`, `zenith`.
- If refraction is applied: also adds `apparent_elevation`, `apparent_zenith`.

# Notes
The input table is modified **in-place** by adding new columns.
"""
function solar_position!(
        table,
        obs::AbstractObserver{T},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction();
        dt_col::Symbol = :datetime,
    ) where {T <: Real}
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
    return
end

"""
    $(TYPEDSIGNATURES)

Non-mutating version of [`solar_position!`](@ref) that returns a modified copy of the input table.

See [`solar_position!`](@ref) for detailed documentation of arguments, examples, and usage patterns.
"""
function solar_position(
        table,
        obs::AbstractObserver{T},
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction();
        kwargs...,
    ) where {T <: Real}
    table_copy = copy(table)
    solar_position!(table_copy, obs, alg, refraction; kwargs...)
    return table_copy
end

# helper function to determine return type based on refraction
result_type(::Type{<:SolarAlgorithm}, ::Type{NoRefraction}, ::Type{T}) where {T} = SolPos{T}
result_type(::Type{<:SolarAlgorithm}, ::Type{<:RefractionAlgorithm}, ::Type{T}) where {T} =
    ApparentSolPos{T}

# element type of the container the vector paths preallocate. Differentiating with respect
# to a refraction parameter makes the apparent angles duals while the observer stays
# Float64, so the observer's precision alone would give a container the results cannot
# convert into
_result_eltype(::Type{T}, refraction::RefractionAlgorithm) where {T <: Real} =
    promote_type(T, Refraction.refraction_eltype(typeof(refraction)))

include("utils.jl")
include("timebase.jl")
include("deltat.jl")
include("psa.jl")
include("iqbal.jl")
include("noaa.jl")
include("walraven.jl")
include("usno.jl")
include("spa.jl")
include("interpolated.jl")

export Observer,
    PSA, NOAA, Walraven, USNO, SPA, Iqbal,
    solar_position, solar_position!, SolPos, ApparentSolPos
export Interpolated, solar_rate
export SolarAlgorithm, AbstractSolPos, AbstractApparentSolPos
export calculate_deltat

end
