using ..Refraction: MICHALSKY

"""
    $(TYPEDEF)

Michalsky solar position algorithm.

Implements the Astronomical Almanac's approximate solar position algorithm. By default the
[`MICHALSKY`](@ref) atmospheric refraction model is applied, matching the original
publication.

# Accuracy
Claimed accuracy: ±0.01° between 1950 and 2050 when using the original Julian date
formulation.

# Options
- `spencer_correction`: when `true` (default), applies the azimuth-quadrant correction of
  [Spe89](@cite) so the algorithm is valid at all latitudes. The original formulation
  (`false`) is only valid in the northern hemisphere.
- `julian_date`: `:original` (default) uses the integer-based Julian date from the original
  paper, which guarantees the stated accuracy only between 1950 and 2050; `:standard` uses
  the exact Julian date and remains usable outside that window.

# Literature
Based on the algorithm of [Mic88](@cite) with the azimuth correction of [Spe89](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct Michalsky <: SolarAlgorithm
    "Apply the Spencer (1989) azimuth-quadrant correction (valid for all latitudes)."
    spencer_correction::Bool
    "Julian date formulation: `:original` or `:standard`."
    julian_date::Symbol
end

Michalsky(; spencer_correction::Bool = true, julian_date::Symbol = :original) =
    Michalsky(spencer_correction, julian_date)

function _solar_position(obs::Observer{T}, dt::DateTime, alg::Michalsky) where {T}
    hour = fractional_hour(dt)

    # Julian date
    jd = if alg.julian_date === :original
        delta = year(dt) - 1949
        leap = floor(delta / 4)
        2432916.5 + delta * 365 + leap + dayofyear(dt) + hour / 24
    elseif alg.julian_date === :standard
        datetime2julian(dt)
    else
        throw(
            ArgumentError(
                "`julian_date` must be :original or :standard, got :$(alg.julian_date)",
            ),
        )
    end

    # days since J2000.0
    n = jd - 2451545.0

    # mean longitude, mean anomaly and ecliptic longitude [degrees]
    L = mod(280.46 + 0.9856474 * n, 360)
    g = mod(357.528 + 0.9856003 * n, 360)
    l = mod(L + 1.915 * sind(g) + 0.02 * sind(2 * g), 360)

    # obliquity of the ecliptic [degrees]
    ep = 23.439 - 0.0000004 * n

    # declination and right ascension [degrees]
    dec = asind(sind(ep) * sind(l))
    ra = mod(rad2deg(atan(cosd(ep) * sind(l), cosd(l))), 360)

    # Greenwich and local mean sidereal time [hours]
    gmst = mod(6.697375 + 0.0657098242 * n + hour, 24)
    lmst = mod(gmst + obs.longitude / 15, 24)

    # hour angle [hours], wrapped to [-12, 12)
    ha = mod(lmst - ra / 15 + 12, 24) - 12

    # elevation and azimuth [degrees]
    el = asind(sind(dec) * obs.sin_lat + cosd(dec) * obs.cos_lat * cosd(15 * ha))
    az = asind(-cosd(dec) * sind(15 * ha) / cosd(el))

    if alg.spencer_correction
        # Spencer (1989) quadrant correction
        cos_az = sind(dec) - sind(el) * obs.sin_lat
        if cos_az >= 0 && sind(az) < 0
            az += 360
        end
        if cos_az < 0
            az = 180 - az
        end
    else
        # Original Michalsky quadrant assignment via the critical elevation. The ratio can
        # exceed the asin domain (e.g. at the equator); treat that as undefined so neither
        # correction applies, matching the reference behaviour.
        ratio = sind(dec) / obs.sin_lat
        elc = abs(ratio) <= 1 ? asind(ratio) : T(NaN)
        if el >= elc
            az = 180 - az
        end
        if el <= elc && ha > 0
            az += 360
        end
        az = mod(az, 360)
    end

    return SolPos{T}(az, el, 90 - el)
end

function _solar_position(obs, dt, alg::Michalsky, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, MICHALSKY())
end

# Michalsky with DefaultRefraction returns ApparentSolPos (uses MICHALSKY refraction)
result_type(::Type{Michalsky}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    ApparentSolPos{T}
