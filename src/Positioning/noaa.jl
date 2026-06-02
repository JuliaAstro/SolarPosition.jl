using ..Refraction: HUGHES, DefaultRefraction

"""
    $(TYPEDEF)

NOAA (National Oceanic and Atmospheric Administration) solar position algorithm. This
algorithm is based on NOAA's Solar Position Calculator implementation. The algorithm is
from "Astronomical Algorithms" by Jean Meeus.

By default, the NOAA algorithm uses the [`HUGHES`](@ref) atmospheric refraction model
which is in accordance with the NOAA solar position calculator.

# Accuracy
Claimed accuracy: ±0.0167° from years -2000 to +3000 for latitudes within ±72°.
For latitudes outside this range, the accuracy is ±0.167°.

!!! warning "Numerical Instability at Poles"
    The NOAA algorithm experiences numerical instability at exactly ±90° latitude due to
    domain errors in inverse trigonometric functions. Avoid using this algorithm at the
    geographic poles.

# Literature
Based on the NOAA solar position calculator [NOAA](@cite) and the work by
[MEEUS91](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct NOAA <: SolarAlgorithm
    "Difference between terrestrial time and UT1 [seconds]. If `nothing`, uses automatic calculation."
    delta_t::Union{Float64, Nothing}
end

NOAA() = NOAA(67.0)  # default delta_t value (2020 default from pvlib)


function _solar_position(obs::Observer{T}, dt::DateTime, alg::NOAA) where {T}
    δt = if alg.delta_t === nothing
        calculate_deltat(T, dt)
    else
        T(alg.delta_t)
    end

    # Julian century since J2000.0, at precision T
    jc = julian_century(T, dt)

    # mean longitude of the sun [degrees]
    mean_long = mod(T(280.46646) + jc * (T(36000.76983) + jc * T(0.0003032)), 360)

    # mean anomaly [degrees]
    mean_anom = T(357.52911) + jc * (T(35999.05029) - T(0.0001537) * jc)

    # cccentricity of Earth's orbit
    eccent = T(0.016708634) - jc * (T(0.000042037) + T(0.0000001267) * jc)

    # sun equation of center [degrees]
    sun_eq_ctr = (
        sind(mean_anom) * (T(1.914602) - jc * (T(0.004817) + T(0.000014) * jc)) +
            sind(2 * mean_anom) * (T(0.019993) - T(0.000101) * jc) +
            sind(3 * mean_anom) * T(0.000289)
    )

    # sun true/apparent longitude [degrees]
    sun_true_long = mean_long + sun_eq_ctr
    sun_app_long = sun_true_long - T(0.00569) - T(0.00478) * sind(T(125.04) - T(1934.136) * jc)

    # mean obliquity of ecliptic [degrees]
    mean_obliq =
        T(23) +
        (T(26) + (T(21.448) - jc * (T(46.815) + jc * (T(0.00059) - jc * T(0.001813)))) / 60) / 60

    # obliquity correction [degrees]
    obliq_corr = mean_obliq + T(0.00256) * cosd(T(125.04) - T(1934.136) * jc)
    sun_declin = asind(sind(obliq_corr) * sind(sun_app_long))

    # equation of time [minutes]
    var_y = tand(obliq_corr / 2)^2
    eot =
        4 * rad2deg(
        var_y * sind(2 * mean_long) - 2 * eccent * sind(mean_anom) +
            4 * eccent * var_y * sind(mean_anom) * cosd(2 * mean_long) -
            T(0.5) * var_y^2 * sind(4 * mean_long) - T(1.25) * eccent^2 * sind(2 * mean_anom),
    )

    # true solar time [minutes]
    hour_frac = fractional_hour(T, dt)
    minutes = hour_frac * 60
    true_solar_time = mod(minutes + eot + 4 * obs.longitude, 1440)

    # hour angle [degrees]
    # true_solar_time is in [0, 1440) minutes, so true_solar_time/4 is in [0, 360) degrees
    # Convert to standard hour angle range (-180, 180] where 0 is solar noon
    hour_angle = true_solar_time / 4 - 180

    # zenith angle [degrees]
    zenith = acosd(
        obs.sin_lat * sind(sun_declin) + obs.cos_lat * cosd(sun_declin) * cosd(hour_angle),
    )

    # azimuth angle [degrees]
    azimuth_numerator = obs.sin_lat * cosd(zenith) - sind(sun_declin)
    azimuth_denominator = obs.cos_lat * sind(zenith)

    azimuth = if hour_angle > 0
        mod(acosd(azimuth_numerator / azimuth_denominator) + 180, 360)
    else
        mod(540 - acosd(azimuth_numerator / azimuth_denominator), 360)
    end

    return SolPos{T}(azimuth, 90 - zenith, zenith)
end

function _solar_position(obs::Observer{T}, dt, alg::NOAA, ::DefaultRefraction) where {T}
    return _solar_position(obs, dt, alg, HUGHES{T}())
end

# NOAA with DefaultRefraction returns ApparentSolPos (uses HUGHES refraction)
result_type(::Type{NOAA}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    ApparentSolPos{T}
