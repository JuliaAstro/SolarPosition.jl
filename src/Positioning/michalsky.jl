"""
    $(TYPEDEF)

Michalsky solar position algorithm.

Implements the approximate solar position algorithm of the Astronomical Almanac. The
default refraction model is [`MICHALSKY`](@ref), matching the original publication, so
`solar_position` returns an [`ApparentSolPos`](@ref) unless another model is given.

# Accuracy
±0.01° between 1950 and 2050 with the original Julian date formulation.

# Constructors
```julia
Michalsky()                                   # Spencer correction, original Julian date
Michalsky(; spencer_correction = false)       # original northern hemisphere quadrants
Michalsky(; julian_date = :standard)          # exact Julian date, usable outside 1950-2050
```

# Options
- `spencer_correction`: when `true`, the default, the azimuth quadrant is resolved with the
  correction of [Spe89](@cite), which is valid at all latitudes. The original formulation,
  `false`, is only valid in the northern hemisphere.
- `julian_date`: `:original`, the default, reproduces the integer based Julian date of the
  paper, whose naive leap year count holds the stated accuracy only between 1950 and 2050.
  `:standard` uses the exact Julian date and stays usable outside that window. The two agree
  exactly within it. Other packages call the `:standard` variant the pandas Julian date.

# Literature
Based on [Mic88](@cite), with the azimuth quadrant correction of [Spe89](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct Michalsky <: SolarAlgorithm
    "Apply the Spencer (1989) azimuth quadrant correction, valid at all latitudes"
    spencer_correction::Bool
    "Julian date formulation, `:original` or `:standard`"
    julian_date::Symbol
end

function Michalsky(; spencer_correction::Bool = true, julian_date::Symbol = :original)
    julian_date in (:original, :standard) || throw(
        ArgumentError(
            "`julian_date` must be :original or :standard, got :$julian_date",
        ),
    )
    return Michalsky(spencer_correction, julian_date)
end

# Days since J2000.0 noon, the quantity the almanac series are expressed in.
#
# The paper builds a Julian Date from a naive leap year count since 1949, which would
# materialise the ~2.43e6 Julian Date magnitude at precision T. The constant J2000 offset is
# folded into the integer day count instead, so nothing larger than the day count itself is
# ever represented at T. The half day is the paper's midnight epoch against J2000 noon.
@inline function _michalsky_days(::Type{T}, dt::DateTime, julian_date::Symbol) where {T <: Real}
    julian_date === :original || return julian_day_j2000(T, dt)
    Δyear = year(dt) - 1949
    days = Δyear * 365 + fld(Δyear, 4) + dayofyear(dt) - 18629
    return T(days) + T(0.5) + fractional_hour(T, dt) / 24
end

function _solar_position(obs::Observer{T}, dt::DateTime, alg::Michalsky) where {T <: Real}
    n = _michalsky_days(T, dt, alg.julian_date)

    # mean longitude, mean anomaly and ecliptic longitude in degrees
    mean_longitude = mod(T(280.46) + T(0.9856474) * n, 360)
    mean_anomaly = mod(T(357.528) + T(0.9856003) * n, 360)
    ecliptic_longitude = mod(
        mean_longitude + T(1.915) * sind(mean_anomaly) +
            T(0.02) * sind(2 * mean_anomaly),
        360,
    )

    # obliquity of the ecliptic in degrees
    obliquity = T(23.439) - T(0.0000004) * n

    (sin_λ, cos_λ) = sincosd(ecliptic_longitude)
    (sin_ε, cos_ε) = sincosd(obliquity)

    # declination and right ascension in degrees
    declination = asind(unit_clamp(sin_ε * sin_λ))
    right_ascension = mod(atand(cos_ε * sin_λ, cos_λ), 360)

    # Greenwich and local mean sidereal time in hours
    gmst = mod(T(6.697375) + T(0.0657098242) * n + fractional_hour(T, dt), 24)
    lmst = mod(gmst + obs.longitude / 15, 24)

    # hour angle in hours, wrapped to [-12, 12)
    hour_angle = mod(lmst - right_ascension / 15 + 12, 24) - 12

    (sin_δ, cos_δ) = sincosd(declination)
    (sin_ω, cos_ω) = sincosd(15 * hour_angle)

    elevation = asind(unit_clamp(sin_δ * obs.sin_lat + cos_δ * obs.cos_lat * cos_ω))
    azimuth = asind(unit_clamp(-cos_δ * sin_ω / cosd(elevation)))

    azimuth = if alg.spencer_correction
        _spencer_quadrant(azimuth, elevation, sin_δ, obs.sin_lat)
    else
        _original_quadrant(azimuth, elevation, sin_δ, obs.sin_lat, hour_angle)
    end

    return SolPos{T}(azimuth, elevation, 90 - elevation)
end

# Spencer (1989) quadrant correction. The sign of the azimuth cosine picks the branch, which
# makes the result valid in both hemispheres.
@inline function _spencer_quadrant(azimuth::T, elevation, sin_δ, sin_lat) where {T <: Real}
    cos_azimuth = sin_δ - sind(elevation) * sin_lat
    if cos_azimuth < 0
        azimuth = 180 - azimuth
    elseif sind(azimuth) < 0
        azimuth += 360
    end
    return mod(azimuth, 360)
end

# The original quadrant assignment, which compares the elevation against a critical
# elevation. The ratio can leave the asin domain, at the equator for instance, so that case
# is treated as undefined and neither correction applies, which is what the reference
# implementations do.
@inline function _original_quadrant(
        azimuth::T, elevation, sin_δ, sin_lat, hour_angle,
    ) where {T <: Real}
    ratio = sin_δ / sin_lat
    critical = abs(ratio) <= 1 ? asind(ratio) : T(NaN)
    if elevation >= critical
        azimuth = 180 - azimuth
    end
    if elevation <= critical && hour_angle > 0
        azimuth += 360
    end
    return mod(azimuth, 360)
end

function _solar_position(obs::AbstractObserver, dt, alg::Michalsky, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, MICHALSKY())
end

# Michalsky applies the MICHALSKY refraction model by default, matching the paper, so
# DefaultRefraction returns ApparentSolPos
result_type(::Type{Michalsky}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    ApparentSolPos{T}
